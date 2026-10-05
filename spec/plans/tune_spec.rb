# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::tune' do
  include BoltSpec::Plans

  def host_resources(cpus, memory_mb, other_services = [])
    { 'cpus' => cpus, 'memory_mb' => memory_mb, 'other_services' => other_services }
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
    expect_out_message.with_params('jruby-puppet.max-active-instances: 7')
    expect_out_message.with_params('JAVA_ARGS: -Xms4096m -Xmx4096m -XX:ReservedCodeCacheSize=1024m')

    result = run_plan('openvox_tune::tune', 'targets' => 'medium.example.com')
    expect(result).to be_ok
    expect(result.value).to eq(
      [
        {
          'target' => 'medium.example.com',
          'cpus' => 8,
          'memory-mb' => 16_000,
          'other-services' => [],
          'max-active-instances' => 7,
          'jvm-heap-mb' => 4096,
          'reserved-code-cache-mb' => 1024,
          'reserved-memory-mb' => 4000,
          'available-memory-mb' => 12_000,
          'limited-by' => 'cpu',
          'fits' => true,
        },
      ],
    )
  end

  it 'counts reserved_memory_mb and says when memory is the limit' do
    expect_task('openvox_tune::host_resources')
      .with_targets('medium.example.com')
      .always_return(host_resources(8, 16_000))
    expect_out_message.with_params(
      '# Limited by memory: the CPUs allow 7 instances; 5 fit in the 4000 MB left after the reserve.',
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
