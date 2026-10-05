# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::tune' do
  include BoltSpec::Plans

  def host_resources(cpus, memory_mb, other_services = [], puppetserver: nil)
    { 'cpus' => cpus, 'memory_mb' => memory_mb, 'other_services' => other_services, 'puppetserver' => puppetserver }
  end

  def puppetserver(xmx_mb: 2048, xms_mb: xmx_mb, code_cache_mb: nil, max_active_instances: nil, ca_enabled: true)
    {
      'defaults_file' => '/etc/sysconfig/puppetserver',
      'xms_mb' => xms_mb,
      'xmx_mb' => xmx_mb,
      'code_cache_mb' => code_cache_mb,
      'max_active_instances' => max_active_instances,
      'ca_enabled' => ca_enabled,
    }
  end

  let(:note) do
    '# Note: this host also runs puppetdb, postgresql@16-main. The default reserve covers ' \
      'the operating system only; set reserved_memory_mb to include other services.'
  end

  before do
    allow_out_message
  end

  it 'recommends num-cpus - 1 instances when the memory allows them' do
    expect_task('openvox_tune::host_resources')
      .with_targets('medium.example.com')
      .always_return(host_resources(8, 16_000))
    expect_out_message.with_params('# medium.example.com: 8 CPU(s), 16000 MB memory, 4000 MB reserved')
    expect_out_message.with_params('# Current: OpenVox Server is not installed.')
    expect_out_message.with_params('jruby-puppet.max-active-instances: 7')
    expect_out_message.with_params('JAVA_ARGS: -Xms4096m -Xmx4096m -XX:ReservedCodeCacheSize=1024m')

    result = run_plan('openvox_tune::tune', 'targets' => 'medium.example.com')
    expect(result).to be_ok
    expect(result.value).to eq(
      [
        {
          'target' => 'medium.example.com',
          'role' => 'server',
          'cpus' => 8,
          'memory-mb' => 16_000,
          'other-services' => [],
          'max-active-instances' => 7,
          'jvm-heap-mb' => 4096,
          'reserved-code-cache-mb' => 1024,
          'memory-per-jruby-mb' => 512,
          'reserved-memory-mb' => 4000,
          'available-memory-mb' => 12_000,
          'instance-limit' => 7,
          'limited-by' => 'cpu',
          'fits' => true,
          'current' => nil,
          'matches-current' => false,
          'hiera' => {
            'puppet::server_max_active_instances' => 7,
            'puppet::server_jvm_min_heap_size' => '4096m',
            'puppet::server_jvm_max_heap_size' => '4096m',
            'puppet::server_jvm_extra_args' => [
              '-Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger',
              '-XX:ReservedCodeCacheSize=1024m',
            ],
          },
        },
      ],
    )
  end

  context 'with compilers' do
    let(:server_with_compilers) do
      '# Server with compilers: the compilers compile the catalogs, so this server ' \
        'keeps 1 instance below 4 CPUs, 2 below 16 and 4 from 16.'
    end

    it 'keeps few instances on a server whose compilers are in the run' do
      expect_task('openvox_tune::host_resources').return_for_targets(
        'puppet.example.com' => host_resources(8, 16_000, puppetserver: puppetserver),
        'compiler01.example.com' => host_resources(8, 16_000, puppetserver: puppetserver(ca_enabled: false)),
      )
      expect_out_message.with_params(server_with_compilers)
      expect_out_message.with_params('# Compiler: its CA service is disabled.')

      result = run_plan('openvox_tune::tune', 'targets' => ['puppet.example.com', 'compiler01.example.com'])
      expect(result).to be_ok
      by_target = result.value.to_h { |r| [r['target'], r] }
      expect(by_target['puppet.example.com']).to include(
        'role' => 'server-with-compilers', 'max-active-instances' => 2, 'jvm-heap-mb' => 1536, 'limited-by' => 'role',
      )
      expect(by_target['compiler01.example.com']).to include(
        'role' => 'compiler', 'max-active-instances' => 7, 'jvm-heap-mb' => 4096, 'limited-by' => 'cpu',
      )
    end

    it 'sizes a server as a server when no compiler is in the run' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000, puppetserver: puppetserver))
      expect_out_message.with_params(server_with_compilers).not_be_called

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com')
      expect(result).to be_ok
      expect(result.value.first).to include('role' => 'server', 'max-active-instances' => 7)
    end

    it 'counts a server whose CA state is unknown as a server with compilers, and a bare host as a server' do
      expect_task('openvox_tune::host_resources').return_for_targets(
        'puppet.example.com' => host_resources(8, 16_000, puppetserver: puppetserver(ca_enabled: nil)),
        'compiler01.example.com' => host_resources(8, 16_000, puppetserver: puppetserver(ca_enabled: false)),
        'new.example.com' => host_resources(8, 16_000),
      )

      result = run_plan('openvox_tune::tune', 'targets' => ['puppet.example.com', 'compiler01.example.com', 'new.example.com'])
      expect(result).to be_ok
      expect(result.value.to_h { |r| [r['target'], r['role']] }).to eq(
        'puppet.example.com' => 'server-with-compilers',
        'compiler01.example.com' => 'compiler',
        'new.example.com' => 'server',
      )
    end
  end

  context 'with hiera' do
    let(:hiera_header) { '# Hiera for theforeman-puppet. Setting server_jvm_extra_args replaces the module\'s own' }

    it 'prints the settings as Hiera data for theforeman-puppet' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000))
      [
        hiera_header,
        '# -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger, so it is repeated here; ' \
        'add any other arguments you pass.',
        'puppet::server_max_active_instances: 7',
        'puppet::server_jvm_min_heap_size: 4096m',
        'puppet::server_jvm_max_heap_size: 4096m',
        'puppet::server_jvm_extra_args:',
        "  - '-Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger'",
        "  - '-XX:ReservedCodeCacheSize=1024m'",
      ].each { |line| expect_out_message.with_params(line) }

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com', 'hiera' => true)
      expect(result).to be_ok
    end

    it 'leaves the Hiera data out of the output by default' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000))
      expect_out_message.with_params(hiera_header).not_be_called

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com')
      expect(result).to be_ok
      expect(result.value.first['hiera']['puppet::server_max_active_instances']).to eq(7)
    end
  end

  context 'with OpenVox Server installed' do
    it 'shows the packaged settings, with the default instance count' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000, puppetserver: puppetserver))
      expect_out_message.with_params(
        '# Current: 4 instances (default), 2048m heap, JVM default code cache, 384 MB heap per instance',
      )
      expect_out_message.with_params('# The current settings already match the recommendation.').not_be_called

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com')
      expect(result).to be_ok
      expect(result.value.first).to include(
        'max-active-instances' => 7,
        'matches-current' => false,
        'current' => {
          'max-active-instances' => nil,
          'effective-max-active-instances' => 4,
          'jvm-min-heap-mb' => 2048,
          'jvm-heap-mb' => 2048,
          'reserved-code-cache-mb' => nil,
          'memory-per-jruby-mb' => 384,
        },
      )
    end

    it 'says when the current settings already match' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000, puppetserver: puppetserver(xmx_mb: 4096, code_cache_mb: 1024, max_active_instances: 7)))
      expect_out_message.with_params('# The current settings already match the recommendation.')

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com')
      expect(result).to be_ok
      expect(result.value.first['matches-current']).to be(true)
    end

    it 'does not count a minimum heap below the maximum as a match' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000, puppetserver: puppetserver(xmx_mb: 4096, xms_mb: 1024, code_cache_mb: 1024, max_active_instances: 7)))

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com')
      expect(result).to be_ok
      expect(result.value.first['matches-current']).to be(false)
    end
  end

  context 'with the memory per JRuby instance' do
    it 'sizes with memory_per_jruby_mb and says so' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000))
      expect_out_message.with_params('# Sized for 1024 MB of heap per JRuby instance.')
      expect_out_message.with_params('JAVA_ARGS: -Xms7680m -Xmx7680m -XX:ReservedCodeCacheSize=1024m')

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com', 'memory_per_jruby_mb' => 1024)
      expect(result).to be_ok
      expect(result.value.first).to include('max-active-instances' => 7, 'memory-per-jruby-mb' => 1024)
    end

    it 'takes it from the current settings with use_current_memory_per_jruby' do
      # (8704 - 512) / 4 = 2048 MB per instance; 5 instances fit in 12000 MB.
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000, puppetserver: puppetserver(xmx_mb: 8704, max_active_instances: 4)))

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com', 'use_current_memory_per_jruby' => true)
      expect(result).to be_ok
      expect(result.value.first).to include(
        'max-active-instances' => 5,
        'jvm-heap-mb' => 10_752,
        'memory-per-jruby-mb' => 2048,
        'limited-by' => 'memory',
      )
    end

    it 'never goes below 512 MB with use_current_memory_per_jruby' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000, puppetserver: puppetserver))
      expect_out_message.with_params('# Sized for 384 MB of heap per JRuby instance.').not_be_called

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com', 'use_current_memory_per_jruby' => true)
      expect(result).to be_ok
      expect(result.value.first).to include('memory-per-jruby-mb' => 512, 'jvm-heap-mb' => 4096)
    end

    it 'uses 512 MB with use_current_memory_per_jruby where OpenVox Server is not installed' do
      expect_task('openvox_tune::host_resources')
        .with_targets('puppet.example.com')
        .always_return(host_resources(8, 16_000))

      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com', 'use_current_memory_per_jruby' => true)
      expect(result).to be_ok
      expect(result.value.first['memory-per-jruby-mb']).to eq(512)
    end

    it 'refuses both memory_per_jruby_mb and use_current_memory_per_jruby' do
      result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com',
                                              'memory_per_jruby_mb' => 1024, 'use_current_memory_per_jruby' => true)
      expect(result).not_to be_ok
      expect(result.value.message).to match(%r{not both})
    end
  end

  it 'counts reserved_memory_mb and says when memory is the limit' do
    expect_task('openvox_tune::host_resources')
      .with_targets('medium.example.com')
      .always_return(host_resources(8, 16_000))
    expect_out_message.with_params(
      '# Limited by memory: 5 of 7 instances fit in the 4000 MB left after the reserve.',
    )
    expect_out_message.with_params('JAVA_ARGS: -Xms3072m -Xmx3072m -XX:ReservedCodeCacheSize=512m')

    result = run_plan('openvox_tune::tune', 'targets' => 'medium.example.com', 'reserved_memory_mb' => 12_000)
    expect(result).to be_ok
    expect(result.value.first).to include(
      'max-active-instances' => 5,
      'reserved-memory-mb' => 12_000,
      'limited-by' => 'memory',
      'fits' => true,
    )
  end

  it 'warns when one instance does not fit in the memory left after the reserve' do
    expect_task('openvox_tune::host_resources')
      .with_targets('small.example.com')
      .always_return(host_resources(1, 1900))
    expect_out_message.with_params(
      '# Warning: one JRuby instance needs 1536 MB of heap and code cache, but only 1425 MB is left after the reserve.',
    )

    result = run_plan('openvox_tune::tune', 'targets' => 'small.example.com')
    expect(result).to be_ok
    expect(result.value.first).to include('max-active-instances' => 1, 'fits' => false)
  end

  it 'notes OpenVoxDB and PostgreSQL on the same host' do
    expect_task('openvox_tune::host_resources')
      .with_targets('puppet.example.com')
      .always_return(host_resources(4, 8000, ['puppetdb', 'postgresql@16-main']))
    expect_out_message.with_params(note)

    result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com')
    expect(result).to be_ok
    expect(result.value.first['other-services']).to eq(['puppetdb', 'postgresql@16-main'])
  end

  it 'leaves the note out when reserved_memory_mb is passed' do
    expect_task('openvox_tune::host_resources')
      .with_targets('puppet.example.com')
      .always_return(host_resources(4, 8000, ['puppetdb', 'postgresql@16-main']))
    expect_out_message.with_params(note).not_be_called

    result = run_plan('openvox_tune::tune', 'targets' => 'puppet.example.com', 'reserved_memory_mb' => 4096)
    expect(result).to be_ok
  end

  it 'reports settings for every target in one run' do
    expect_task('openvox_tune::host_resources').return_for_targets(
      'small.example.com' => host_resources(1, 4000),
      'medium.example.com' => host_resources(8, 16_000),
    )

    result = run_plan('openvox_tune::tune', 'targets' => ['small.example.com', 'medium.example.com'])
    expect(result).to be_ok
    expect(result.value.to_h { |r| [r['target'], r['max-active-instances']] }).to eq(
      'small.example.com' => 1,
      'medium.example.com' => 7,
    )
  end

  it 'fails the plan when the task fails on a target' do
    expect_task('openvox_tune::host_resources')
      .with_targets('broken.example.com')
      .error_with('msg' => 'nproc: command not found', 'kind' => 'openvox_tune/host_resources-error')

    result = run_plan('openvox_tune::tune', 'targets' => 'broken.example.com')
    expect(result).not_to be_ok
  end
end
