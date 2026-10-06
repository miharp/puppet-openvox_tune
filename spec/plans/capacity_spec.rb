# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::capacity', :plan do
  # Without the openbolt gem (bundles with OpenVox 9) these are skipped; see spec_helper.rb.
  include BoltSpec::Plans if defined?(BoltSpec::Plans)

  # A slot start on a 5-minute boundary.
  let(:peak_start) { 1_791_244_800 }
  let(:peak_at) { Time.at(peak_start).utc.strftime('%Y-%m-%d %H:%M') }

  def host(installed: true)
    puppetserver = { 'xms_mb' => 2048, 'xmx_mb' => 2048, 'code_cache_mb' => nil, 'ca_enabled' => true,
                     'max_active_instances' => nil, 'max_requests_per_instance' => nil,
                     'max_queued_requests' => nil, 'multithreaded' => nil, 'environment_timeout' => 0, }
    { 'cpus' => 8, 'memory_mb' => 16_000, 'other_services' => [], 'puppetserver' => (installed ? puppetserver : nil) }
  end

  # A day of 300 nodes running every 30 minutes, each run holding JRubies for
  # 2.4 s: 0.4 JRubies busy on average, 0.96 in the busiest slot.
  def day(overrides = {})
    nodes = (1..300).to_h { |i| ["node#{i}.example.com", [48, i, i + (47 * 1800)]] }
    {
      'access_log' => 'found', 'log_dir' => '/var/log/puppetlabs/puppetserver', 'files' => 2,
      'window_seconds' => 86_400, 'requests' => 50_000, 'unparsed_lines' => 0,
      'jruby_requests' => 48_000, 'jruby_seconds' => 34_560.0, 'catalog_requests' => 14_400,
      'status_503' => 0, 'bucket_seconds' => 300,
      'buckets' => { (peak_start - 300).to_s => 100.0, peak_start.to_s => 288.0 },
      'nodes' => nodes, 'runinterval' => 1800,
    }.merge(overrides.transform_keys(&:to_s))
  end

  before do
    allow_out_message
  end

  it 'reports the load and the capacity it implies' do
    expect_task('openvox_tune::host_resources').always_return(host)
    expect_task('openvox_tune::jruby_load')
      .with_params('window_hours' => 24, 'bucket_minutes' => 5, '_catch_errors' => true)
      .always_return(day)
    [
      '# puppet.example.com: 4 JRubies, 50000 requests (48000 held a JRuby); busy 10% on average, 24% at the busiest.',
      '# Capacity over the last 24 h, from the access logs of 1 server:',
      '# 300 nodes requested catalogs, every 30 min (median); each run held JRubies for 2.40 s in total.',
      "# JRubies busy 10% on average, 24% in the busiest 5 minutes (from #{peak_at} UTC).",
      '# At this rate the 4 JRubies can serve about 3000 nodes; the nodes seen need at least 1 JRuby.',
    ].each { |line| expect_out_message.with_params(line) }

    result = run_plan('openvox_tune::capacity', 'targets' => 'puppet.example.com')
    expect(result).to be_ok
    expect(result.value['estimate']).to include('node-capacity' => 3000, 'minimum-jrubies' => 1, 'nodes' => 300)
    expect(result.value['targets'].first).to include('target' => 'puppet.example.com', 'jrubies' => 4, 'access-log' => 'found')
    expect(result.value['targets'].first).not_to include('load')
  end

  it 'leaves out targets without OpenVox Server or a readable access log' do
    expect_task('openvox_tune::host_resources').return_for_targets(
      'puppet.example.com' => host,
      'new.example.com' => host(installed: false),
      'locked.example.com' => host,
    )
    expect_task('openvox_tune::jruby_load').return_for_targets(
      'puppet.example.com' => day,
      'new.example.com' => { 'access_log' => 'missing', 'log_dir' => '/var/log/puppetlabs/puppetserver' },
      'locked.example.com' => { 'access_log' => 'unreadable', 'log_dir' => '/var/log/puppetlabs/puppetserver' },
    )
    expect_out_message.with_params('# new.example.com: OpenVox Server is not installed; left out.')
    expect_out_message.with_params('# locked.example.com: access log unreadable in /var/log/puppetlabs/puppetserver; left out.')
    expect_out_message.with_params('# Capacity over the last 24 h, from the access logs of 1 server:')

    result = run_plan('openvox_tune::capacity', 'targets' => ['puppet.example.com', 'new.example.com', 'locked.example.com'])
    expect(result).to be_ok
  end

  it 'estimates from the compilers, leaving out their server' do
    compiler = host
    compiler['puppetserver'] = compiler['puppetserver'].merge('ca_enabled' => false)
    expect_task('openvox_tune::host_resources').return_for_targets(
      'puppet.example.com' => host,
      'compiler01.example.com' => compiler,
    )
    expect_task('openvox_tune::jruby_load').return_for_targets(
      'puppet.example.com' => day('jruby_seconds' => 999.0, 'catalog_requests' => 10),
      'compiler01.example.com' => day,
    )
    expect_out_message.with_params(
      '# puppet.example.com: the server; left out of the estimate, since its compilers serve the agents.',
    )
    expect_out_message.with_params('# Capacity over the last 24 h, from the access logs of 1 compiler:')

    result = run_plan('openvox_tune::capacity', 'targets' => ['puppet.example.com', 'compiler01.example.com'])
    expect(result).to be_ok
    expect(result.value['estimate']).to include('jrubies' => 4, 'jruby-seconds' => 34_560.0, 'catalog-requests' => 14_400)
    expect(result.value['targets'].to_h { |t| [t['target'], t['role']] }).to eq(
      'puppet.example.com' => 'server-with-compilers',
      'compiler01.example.com' => 'compiler',
    )
  end

  it 'leaves out a target where a task fails' do
    expect_task('openvox_tune::host_resources').always_return(host)
    expect_task('openvox_tune::jruby_load').return_for_targets(
      'puppet.example.com' => day,
      'broken.example.com' => { '_error' => { 'msg' => 'Permission denied', 'kind' => 'openvox_tune/jruby_load-error' } },
    )
    expect_out_message.with_params('# broken.example.com: Permission denied; left out.')
    expect_out_message.with_params('# Capacity over the last 24 h, from the access logs of 1 server:')

    result = run_plan('openvox_tune::capacity', 'targets' => ['puppet.example.com', 'broken.example.com'])
    expect(result).to be_ok
  end

  it 'fails when no target has a log to read' do
    expect_task('openvox_tune::host_resources').always_return(host)
    expect_task('openvox_tune::jruby_load').always_return('access_log' => 'unrecognized', 'log_dir' => '/var/log/puppetlabs/puppetserver')

    result = run_plan('openvox_tune::capacity', 'targets' => 'puppet.example.com')
    expect(result).not_to be_ok
    expect(result.value.message).to match(%r{No target had OpenVox Server with a readable access log})
  end

  it 'points out a nearly full pool, 503 responses and a short window' do
    busy = day('window_seconds' => 7200, 'buckets' => { peak_start.to_s => 1100.0 }, 'status_503' => 12)
    expect_task('openvox_tune::host_resources').always_return(host)
    expect_task('openvox_tune::jruby_load').always_return(busy)
    expect_out_message.with_params('# The logs cover less than the 24 h asked for; the server has not been up that long.')
    expect_out_message.with_params(
      '# Note: the JRubies were nearly all in use at the busiest time; agents checking in together wait for one. ' \
      'splay on the agents spreads their runs out.',
    )
    expect_out_message.with_params(
      '# Note: 12 requests got 503 because the JRuby queue was full (max-queued-requests), so demand was higher than this load shows.',
    )

    result = run_plan('openvox_tune::capacity', 'targets' => 'puppet.example.com')
    expect(result).to be_ok
  end

  it 'falls back to runinterval, and says so' do
    once = (1..10).to_h { |i| ["node#{i}.example.com", [1, i, i]] }
    expect_task('openvox_tune::host_resources').always_return(host)
    expect_task('openvox_tune::jruby_load').always_return(day(nodes: once, catalog_requests: 10, runinterval: 3600))
    expect_out_message.with_params(
      '# 10 nodes requested catalogs, every 60 min (runinterval; no node ran twice in the window); ' \
      'each run held JRubies for 3456.00 s in total.',
    )

    result = run_plan('openvox_tune::capacity', 'targets' => 'puppet.example.com')
    expect(result).to be_ok
  end

  it 'says there is nothing to estimate without agent runs' do
    expect_task('openvox_tune::host_resources').always_return(host)
    expect_task('openvox_tune::jruby_load').always_return(day(catalog_requests: 0, nodes: {}, buckets: {}))
    expect_out_message.with_params('# No agent requested a catalog in that time, so there is nothing to estimate from.')

    result = run_plan('openvox_tune::capacity', 'targets' => 'puppet.example.com')
    expect(result).to be_ok
    expect(result.value['estimate']['node-capacity']).to be_nil
  end
end
