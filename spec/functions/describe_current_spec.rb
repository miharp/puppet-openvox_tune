# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::describe_current' do
  def current(**settings)
    {
      'max-active-instances' => nil,
      'effective-max-active-instances' => 4,
      'jvm-min-heap-mb' => 2048,
      'jvm-heap-mb' => 2048,
      'reserved-code-cache-mb' => nil,
      'memory-per-jruby-mb' => 384,
    }.merge(settings.transform_keys { |k| k.to_s.tr('_', '-') })
  end

  it 'says when OpenVox Server is not installed' do
    expect(subject).to run.with_params(nil).and_return('OpenVox Server is not installed.')
  end

  it 'describes the packaged settings, marking the default instance count' do
    expect(subject).to run.with_params(current).and_return(
      '4 instances (default), 2048m heap, JVM default code cache, 384 MB heap per instance',
    )
  end

  it 'describes explicit settings' do
    expect(subject).to run.with_params(
      current(max_active_instances: 1, effective_max_active_instances: 1, jvm_min_heap_mb: 1024,
              reserved_code_cache_mb: 512, memory_per_jruby_mb: 1536),
    ).and_return('1 instance, 2048m heap (-Xms1024m), 512m code cache, 1536 MB heap per instance')
  end

  it 'falls back to the JVM defaults for a heap and minimum heap that are not set' do
    expect(subject).to run.with_params(current(jvm_min_heap_mb: nil, jvm_heap_mb: nil, memory_per_jruby_mb: nil)).and_return(
      '4 instances (default), JVM default heap, JVM default code cache',
    )
    expect(subject).to run.with_params(current(jvm_min_heap_mb: nil)).and_return(
      '4 instances (default), 2048m heap (JVM default minimum), JVM default code cache, 384 MB heap per instance',
    )
  end

  it 'leaves out the heap per instance when the heap is too small to give one' do
    expect(subject).to run.with_params(
      current(effective_max_active_instances: 1, jvm_min_heap_mb: 512, jvm_heap_mb: 512, memory_per_jruby_mb: 0),
    ).and_return('1 instance (default), 512m heap, JVM default code cache')
  end
end
