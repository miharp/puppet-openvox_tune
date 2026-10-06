# frozen_string_literal: true

# Summarises a benchmark run:
#   ruby analyze.rb <dir>
# where <dir> holds requests.log and levels.log from the load generator and
# cpu.log and puppetserver-access.log (or its rotated .gz files) from the
# server. Prints, in Markdown, a table per label and the average compile time
# per minute of each run, warm-ups included, which shows how long the JRubies
# took to warm up.
require 'time'
require 'zlib'

dir = ARGV.fetch(0)
levels = File.readlines(File.join(dir, 'levels.log')).map(&:split)
requests = File.readlines(File.join(dir, 'requests.log')).map(&:split)
cpu = File.readlines(File.join(dir, 'cpu.log')).map { |l| l.split.map(&:to_i) }

# Each catalog request on the server: [epoch, total ms, JRuby borrow ms]. The
# borrow time is the compile; the rest is mostly waiting for a free JRuby.
ACCESS = %r{\[(?<time>[^\]]+)\] "GET /puppet/v3/catalog/\S+ [^"]*" \d{3} \S+ "[^"]*" "[^"]*" (?<ms>\d+) \S+ (?<borrow>\d+)\s*\z}.freeze
access = Dir[File.join(dir, 'puppetserver-access.log*')].flat_map do |file|
  text = file.end_with?('.gz') ? Zlib::GzipReader.open(file, &:read) : File.read(file)
  text.each_line.filter_map do |l|
    m = ACCESS.match(l) or next
    [Time.strptime(m[:time], '%d/%b/%Y:%H:%M:%S %z').to_i, Integer(m[:ms]), Integer(m[:borrow])]
  end
end

def percentile(sorted, fraction)
  sorted[[(fraction * sorted.size).ceil - 1, 0].max]
end

def average(values)
  values.empty? ? nil : values.sum.to_f / values.size
end

def fmt(value, digits = 1)
  value.nil? ? '-' : format("%.#{digits}f", value)
end

# Leaves out the first and last few seconds of a window, where a level ramps
# up and drains.
def inside(rows, start, finish)
  rows.select { |row| row[0].between?(start + 5, finish - 5) }
end

levels.reject { |l| l[0].start_with?('warmup') }.group_by(&:first).each do |label, rows|
  puts "### #{label}", ''
  puts '| Concurrent requests | Catalogs/min | p50 s | p95 s | Wait for a JRuby s | Compile s | Errors | CPU busy % | Steal % | RSS MB |'
  puts '|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|'
  rows.each do |_, level, start, finish|
    start = start.to_f
    finish = finish.to_f
    mine = requests.select { |r| r[0] == label && r[1] == level }
    times = mine.map { |r| r[3].to_f }.sort
    server = inside(access, start, finish)
    samples = inside(cpu, start, finish)
    row = [
      level,
      fmt(mine.size / ((finish - start) / 60)),
      fmt(percentile(times, 0.5)),
      fmt(percentile(times, 0.95)),
      fmt(average(server.map { |_, ms, borrow| (ms - borrow) / 1000.0 })),
      fmt(average(server.map { |_, _, borrow| borrow / 1000.0 }), 2),
      mine.count { |r| r[4] != '200' },
      fmt(average(samples.map { |s| s[1] }), 0),
      fmt(average(samples.map { |s| s[2] }), 0),
      samples.map { |s| s[3] }.max,
    ].join(' | ')
    puts "| #{row} |"
  end
  puts
end

puts '### Compile time per minute (s)', ''
levels.group_by(&:first).each do |label, rows|
  start = rows.first[2].to_f
  by_minute = access.select { |t, _, _| t.between?(start, rows.last[3].to_f) }.group_by { |t, _, _| ((t - start) / 60).floor }
  puts "- #{label}: " + by_minute.sort.map { |minute, r| "#{minute}: #{fmt(average(r.map { |_, _, b| b / 1000.0 }))}" }.join(', ')
end
