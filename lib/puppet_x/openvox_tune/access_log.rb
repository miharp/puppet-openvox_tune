# frozen_string_literal: true

require 'time'
require 'zlib'

module PuppetX
  module OpenvoxTune
    # Adds up OpenVox Server's access logs over a window. The access log
    # records, for every request, how long it held a JRuby
    # (%mdc{jruby.borrow-time} in request-logging.xml), so the sum measures the
    # JRuby load directly. Used by the jruby_load task.
    class AccessLog
      # The pattern request-logging.xml ships:
      #   %h %l %u [%t] "%r" %s %b "%i{Referer}" "%i{User-Agent}" %D %i{Content-Length} %mdc{jruby.borrow-time:--}
      LINE = %r{
        \A\S+\ \S+\ \S+\ \[(?<time>[^\]]+)\]\ "(?<method>[A-Z]+)\ (?<path>[^\ "]+)[^"]*"\ (?<status>\d{3})\ \S+
        \ "[^"]*"\ "[^"]*"\ \d+\ \S+\ (?<borrow>\d+|-)\s*\z
      }x.freeze
      CATALOG = %r{\A/puppet/v3/catalog/(?<certname>[^/?]+)}.freeze
      CURRENT = 'puppetserver-access.log'

      def initialize(log_dir:, window_hours: 24, bucket_minutes: 5, now: Time.now)
        @log_dir = log_dir
        @now = now
        @cutoff = now - (window_hours * 3600)
        @bucket_seconds = bucket_minutes * 60
      end

      # The current log and the rotated ones that can hold lines from the
      # window; rotated files are named after the day their lines are from.
      def files
        rotated = Dir.glob(File.join(@log_dir, 'puppetserver-access-*.log.gz')).select do |file|
          day = file[%r{puppetserver-access-(\d{4}-\d{2}-\d{2})\.}, 1]
          day && Time.parse("#{day}T23:59:59Z") >= @cutoff - 86_400
        end
        current = File.join(@log_dir, CURRENT)
        rotated.sort + (File.exist?(current) ? [current] : [])
      end

      def summary
        files = self.files
        return { 'access_log' => 'missing', 'log_dir' => @log_dir } if files.empty?
        return { 'access_log' => 'unreadable', 'log_dir' => @log_dir } unless files.all? { |file| File.readable?(file) }

        reset
        files.each { |file| read(file) }
        result(files.size)
      end

      private

      def reset
        @stats = Hash.new(0)
        @buckets = Hash.new(0.0)
        @nodes = {}
        @earliest = nil
        @last_stamp = nil
        @last_time = nil
      end

      def read(file)
        if file.end_with?('.gz')
          Zlib::GzipReader.open(file) { |gz| gz.each_line { |line| add(line) } }
        else
          File.foreach(file) { |line| add(line) }
        end
      end

      def add(line)
        match = LINE.match(line)
        time = match && parse_time(match[:time])
        if time.nil?
          @stats['unparsed_lines'] += 1
          return
        end
        @earliest = time if @earliest.nil? || time < @earliest
        return if time < @cutoff || time > @now

        @stats['requests'] += 1
        @stats['status_503'] += 1 if match[:status] == '503'
        add_jruby_time(time, Integer(match[:borrow]) / 1000.0) unless match[:borrow] == '-'
        certname = CATALOG.match(match[:path])
        add_catalog(certname[:certname], time.to_i) if certname && match[:status] == '200'
      end

      # Many lines share a second, so parse each timestamp once.
      def parse_time(stamp)
        return @last_time if stamp == @last_stamp

        @last_stamp = stamp
        @last_time = begin
          Time.strptime(stamp, '%d/%b/%Y:%H:%M:%S %z')
        rescue ArgumentError
          nil
        end
      end

      def add_jruby_time(time, seconds)
        @stats['jruby_requests'] += 1
        @stats['jruby_seconds'] += seconds
        @buckets[(time.to_i / @bucket_seconds) * @bucket_seconds] += seconds
      end

      def add_catalog(certname, epoch)
        @stats['catalog_requests'] += 1
        seen = @nodes[certname]
        if seen
          seen[0] += 1
          seen[1] = epoch if epoch < seen[1]
          seen[2] = epoch if epoch > seen[2]
        else
          @nodes[certname] = [1, epoch, epoch]
        end
      end

      def result(file_count)
        # The window the logs cover: shorter on a server younger than it.
        covered_from = [@cutoff, @earliest || @now].max
        # Only time slots wholly inside it count; one cut short at either end
        # would understate its rate.
        whole = @buckets.select { |start, _| start >= covered_from.to_i && start + @bucket_seconds <= @now.to_i }
        {
          'access_log' => (@stats['requests'].zero? && @stats['unparsed_lines'].positive?) ? 'unrecognized' : 'found',
          'log_dir' => @log_dir,
          'files' => file_count,
          'from' => covered_from.utc.iso8601,
          'to' => @now.utc.iso8601,
          'window_seconds' => (@now - covered_from).to_i,
          'requests' => @stats['requests'],
          'unparsed_lines' => @stats['unparsed_lines'],
          'jruby_requests' => @stats['jruby_requests'],
          'jruby_seconds' => @stats['jruby_seconds'].round(3),
          'catalog_requests' => @stats['catalog_requests'],
          'status_503' => @stats['status_503'],
          'bucket_seconds' => @bucket_seconds,
          'buckets' => whole.to_h { |start, seconds| [start.to_s, seconds.round(3)] },
          'nodes' => @nodes,
        }
      end
    end
  end
end
