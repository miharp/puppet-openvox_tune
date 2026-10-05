# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::tune' do
  include BoltSpec::Plans

  before do
    allow_out_message
  end

  it 'clamps max-active-instances to a minimum of 1 on a single-CPU target' do
    expect_task('openvox_tune::cpu_count')
      .with_targets('small.example.com')
      .always_return('count' => 1)

    result = run_plan('openvox_tune::tune', 'targets' => 'small.example.com')
    expect(result).to be_ok
    expect(result.value).to eq(
      [
        {
          'target' => 'small.example.com',
          'cpus' => 1,
          'max-active-instances' => 1,
          'jvm-heap-mb' => 1024,
          'reserved-code-cache-mb' => 512,
        },
      ],
    )
  end

  it 'recommends num-cpus - 1 instances and matching heap for a mid-size target' do
    expect_task('openvox_tune::cpu_count')
      .with_targets('medium.example.com')
      .always_return('count' => 8)

    result = run_plan('openvox_tune::tune', 'targets' => 'medium.example.com')
    expect(result).to be_ok
    expect(result.value).to eq(
      [
        {
          'target' => 'medium.example.com',
          'cpus' => 8,
          'max-active-instances' => 7,
          'jvm-heap-mb' => 4096,
          'reserved-code-cache-mb' => 1024,
        },
      ],
    )
  end

  it 'recommends the largest reserved code cache tier above 12 instances' do
    expect_task('openvox_tune::cpu_count')
      .with_targets('busy.example.com')
      .always_return('count' => 14)

    result = run_plan('openvox_tune::tune', 'targets' => 'busy.example.com')
    expect(result).to be_ok
    expect(result.value).to eq(
      [
        {
          'target' => 'busy.example.com',
          'cpus' => 14,
          'max-active-instances' => 13,
          'jvm-heap-mb' => 7168,
          'reserved-code-cache-mb' => 2048,
        },
      ],
    )
  end

  it 'reports settings for every target in one run' do
    expect_task('openvox_tune::cpu_count').return_for_targets(
      'small.example.com' => { 'count' => 1 },
      'medium.example.com' => { 'count' => 8 },
    )

    result = run_plan('openvox_tune::tune', 'targets' => ['small.example.com', 'medium.example.com'])
    expect(result).to be_ok
    expect(result.value.map { |r| r['target'] }).to contain_exactly('small.example.com', 'medium.example.com')
  end

  it 'fails the plan when the task fails on a target' do
    expect_task('openvox_tune::cpu_count')
      .with_targets('broken.example.com')
      .error_with('msg' => 'nproc: command not found', 'kind' => 'openvox_tune/cpu_count-error')

    result = run_plan('openvox_tune::tune', 'targets' => 'broken.example.com')
    expect(result).not_to be_ok
  end
end
