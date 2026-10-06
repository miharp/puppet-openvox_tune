# frozen_string_literal: true

require 'spec_helper_container'
require 'time'
require 'fileutils'
require 'tmpdir'
require 'zlib'

describe 'openvox_tune::jruby_load task' do
  # Fixed points relative to now, on 5-minute boundaries so that whole slots
  # are easy to name.
  let(:now) { Time.now.utc }
  let(:slot) { ((now.to_i - 7200) / 300) * 300 } # a whole slot about two hours ago

  let(:log_dir) { Dir.mktmpdir('openvox-tune-logs') }

  after do
    FileUtils.remove_entry(log_dir)
  end

  def write_current(lines)
    File.write(File.join(log_dir, 'puppetserver-access.log'), lines.join)
  end

  def write_rotated(day, lines)
    Zlib::GzipWriter.open(File.join(log_dir, "puppetserver-access-#{day.strftime('%Y-%m-%d')}.0.log.gz")) do |gz|
      gz.write(lines.join)
    end
  end

  def catalog(time, certname, borrow_ms, status: 200)
    access_line(time, "/puppet/v3/catalog/#{certname}?environment=production", borrow_ms: borrow_ms, status: status)
  end

  it 'adds up the JRuby time, catalog requests per node and 503s in the window, rotated logs included' do
    in_slot = Time.at(slot + 60).utc
    write_rotated(now - 86_400, [
                    # Older than the 24 h window: counts only towards how far back the logs go.
                    catalog(now - 90_000, 'old.example.com', 5000),
                    catalog(now - 80_000, 'agent01.example.com', 1500),
                  ])
    write_current([
                    catalog(in_slot, 'agent01.example.com', 1200),
                    access_line(in_slot, '/puppet/v3/file_metadatas/plugins?recurse=true', borrow_ms: 300, method: 'GET'),
                    access_line(in_slot, '/puppet-ca/v1/certificate/ca', borrow_ms: nil, method: 'GET'),
                    catalog(in_slot + 30, 'agent02.example.com', 800),
                    catalog(now - 600, 'agent01.example.com', 1000),
                    catalog(now - 300, 'agent02.example.com', 0, status: 503),
                    "not an access log line\n",
                  ])

    result = jruby_load(log_dir)

    expect(result).to include(
      'access_log' => 'found',
      'files' => 2,
      'window_seconds' => 86_400,
      'requests' => 7,
      'unparsed_lines' => 1,
      'jruby_requests' => 6,
      'jruby_seconds' => 4.8,
      'catalog_requests' => 4,
      'status_503' => 1,
      'bucket_seconds' => 300,
    )
    expect(result['buckets'][slot.to_s]).to eq(2.3)
    expect(result['nodes']['agent01.example.com']).to eq([3, (now - 80_000).to_i, (now - 600).to_i])
    expect(result['nodes']['agent02.example.com']).to eq([1, (in_slot + 30).to_i, (in_slot + 30).to_i])
    expect(result['nodes']).not_to include('old.example.com')
    expect(result['runinterval']).to eq(1800)
  end

  it 'reads only the hours asked for, in the slot length asked for' do
    write_current([catalog(now - 7200, 'agent01.example.com', 1000), catalog(now - 1800, 'agent01.example.com', 2000)])

    result = jruby_load(log_dir, window_hours: 1, bucket_minutes: 10)

    expect(result).to include('requests' => 1, 'jruby_seconds' => 2.0, 'bucket_seconds' => 600)
  end

  it 'reports the window a younger server covers' do
    write_current([catalog(now - 3600, 'agent01.example.com', 1000)])

    expect(jruby_load(log_dir)['window_seconds']).to be_within(5).of(3600)
  end

  it 'reports a missing log' do
    expect(jruby_load(log_dir)).to include('access_log' => 'missing')
  end

  it 'reports a log in a format it does not know' do
    write_current(["#{now.iso8601} GET /puppet/v3/catalog/agent01.example.com 200 1200ms\n"])

    expect(jruby_load(log_dir)).to include('access_log' => 'unrecognized', 'requests' => 0)
  end
end
