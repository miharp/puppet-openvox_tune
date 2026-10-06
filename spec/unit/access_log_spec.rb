# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'zlib'
require_relative '../../files/access_log'

describe OpenvoxTune::AccessLog do
  # Not on a slot boundary, so the slot holding now is still open.
  let(:now) { Time.utc(2026, 10, 6, 12, 2, 0) }
  let(:log_dir) { Dir.mktmpdir('openvox-tune-logs') }
  # A whole 5-minute slot two hours before now.
  let(:slot) { Time.utc(2026, 10, 6, 10, 0, 0) }

  after do
    FileUtils.remove_entry(log_dir)
  end

  def line(time, path, borrow_ms:, method: 'POST', status: 200)
    stamp = time.utc.strftime('%d/%b/%Y:%H:%M:%S +0000')
    %(10.0.0.5 - - [#{stamp}] "#{method} #{path} HTTP/1.1" #{status} 318 "-" ) +
      %("Puppet/8.29.0 Ruby/3.2.11-p268 (x86_64-linux)" #{borrow_ms.to_i + 8} 16557 #{borrow_ms || '-'}\n)
  end

  def catalog(time, certname, borrow_ms, status: 200)
    line(time, "/puppet/v3/catalog/#{certname}?environment=production", borrow_ms: borrow_ms, status: status)
  end

  def write_current(lines)
    File.write(File.join(log_dir, 'puppetserver-access.log'), lines.join)
  end

  def write_rotated(day, lines)
    Zlib::GzipWriter.open(File.join(log_dir, "puppetserver-access-#{day}.0.log.gz")) { |gz| gz.write(lines.join) }
  end

  def summary(**options)
    described_class.new(log_dir: log_dir, now: now, **options).summary
  end

  it 'adds up the JRuby time, catalog requests per node and 503s in the window, rotated logs included' do
    write_rotated('2026-10-05', [
                    catalog(now - 90_000, 'old.example.com', 5000),
                    catalog(now - 80_000, 'agent01.example.com', 1500),
                  ])
    write_current([
                    catalog(slot + 60, 'agent01.example.com', 1200),
                    line(slot + 60, '/puppet/v3/file_metadatas/plugins?recurse=true', borrow_ms: 300, method: 'GET'),
                    line(slot + 60, '/puppet-ca/v1/certificate/ca', borrow_ms: nil, method: 'GET'),
                    catalog(slot + 90, 'agent02.example.com', 800),
                    catalog(now - 600, 'agent01.example.com', 1000),
                    catalog(now - 300, 'agent02.example.com', 0, status: 503),
                    "not an access log line\n",
                  ])

    result = summary

    expect(result).to include(
      'access_log' => 'found', 'files' => 2, 'window_seconds' => 86_400, 'requests' => 7, 'unparsed_lines' => 1,
      'jruby_requests' => 6, 'jruby_seconds' => 4.8, 'catalog_requests' => 4, 'status_503' => 1, 'bucket_seconds' => 300
    )
    expect(result['buckets'][slot.to_i.to_s]).to eq(2.3)
    expect(result['nodes']).to eq(
      'agent01.example.com' => [3, (now - 80_000).to_i, (now - 600).to_i],
      'agent02.example.com' => [1, (slot + 90).to_i, (slot + 90).to_i],
    )
  end

  it 'skips rotated files from before the window' do
    write_rotated('2026-10-01', [catalog(now - (5 * 86_400), 'old.example.com', 1000)])
    write_current([catalog(now - 60, 'agent01.example.com', 1000)])

    expect(described_class.new(log_dir: log_dir, now: now).files.map { |f| File.basename(f) }).to eq(['puppetserver-access.log'])
  end

  it 'counts only whole time slots inside the window' do
    write_current([catalog(now - 3700, 'agent01.example.com', 1000), catalog(now - 60, 'agent01.example.com', 2000)])

    result = summary(window_hours: 1)

    # The slot holding now - 60 s is still open, and now - 3700 s is before the window.
    expect(result['buckets']).to eq({})
    expect(result).to include('requests' => 1, 'jruby_seconds' => 2.0)
  end

  it 'uses the slot length asked for' do
    write_current([
                    catalog(slot - 3600, 'agent01.example.com', 0),
                    catalog(slot + 30, 'agent01.example.com', 1000),
                    catalog(slot + 400, 'agent01.example.com', 1000),
                  ])

    expect(summary(bucket_minutes: 10)['buckets']).to include(slot.to_i.to_s => 2.0)
  end

  it 'reports the window a younger server covers' do
    write_current([catalog(now - 3600, 'agent01.example.com', 1000)])

    expect(summary['window_seconds']).to eq(3600)
  end

  it 'reports a missing log' do
    expect(summary).to eq('access_log' => 'missing', 'log_dir' => log_dir)
  end

  it 'reports a log in a format it does not know' do
    write_current(["2026-10-06T11:00:00Z GET /puppet/v3/catalog/agent01.example.com 200 1200ms\n"])

    expect(summary).to include('access_log' => 'unrecognized', 'requests' => 0, 'unparsed_lines' => 1)
  end
end
