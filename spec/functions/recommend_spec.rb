# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::recommend' do
  context 'when CPUs are the limit' do
    it 'recommends num-cpus - 1 instances and reserves a quarter of memory' do
      expect(subject).to run.with_params(8, 16_000).and_return(
        'max-active-instances' => 7,
        'jvm-heap-mb' => 4096,
        'reserved-code-cache-mb' => 1024,
        'reserved-memory-mb' => 4000,
        'available-memory-mb' => 12_000,
        'limited-by' => 'cpu',
        'fits' => true,
      )
    end

    it 'recommends one instance on a single CPU' do
      expect(subject).to run.with_params(1, 4000).and_return(
        'max-active-instances' => 1,
        'jvm-heap-mb' => 1024,
        'reserved-code-cache-mb' => 512,
        'reserved-memory-mb' => 1000,
        'available-memory-mb' => 3000,
        'limited-by' => 'cpu',
        'fits' => true,
      )
    end

    it 'uses the largest code cache above 12 instances' do
      expect(subject).to run.with_params(14, 64_000).and_return(
        'max-active-instances' => 13,
        'jvm-heap-mb' => 7168,
        'reserved-code-cache-mb' => 2048,
        'reserved-memory-mb' => 16_000,
        'available-memory-mb' => 48_000,
        'limited-by' => 'cpu',
        'fits' => true,
      )
    end
  end

  context 'when memory is the limit' do
    it 'lowers the instance count until the heap and code cache fit' do
      expect(subject).to run.with_params(16, 10_000).and_return(
        'max-active-instances' => 11,
        'jvm-heap-mb' => 6144,
        'reserved-code-cache-mb' => 1024,
        'reserved-memory-mb' => 2500,
        'available-memory-mb' => 7500,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'counts the reserve passed in instead of a quarter of memory' do
      expect(subject).to run.with_params(8, 16_000, 12_000).and_return(
        'max-active-instances' => 5,
        'jvm-heap-mb' => 3072,
        'reserved-code-cache-mb' => 512,
        'reserved-memory-mb' => 12_000,
        'available-memory-mb' => 4000,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'accepts a recommendation that fills the available memory exactly' do
      expect(subject).to run.with_params(4, 2048, 0).and_return(
        'max-active-instances' => 2,
        'jvm-heap-mb' => 1536,
        'reserved-code-cache-mb' => 512,
        'reserved-memory-mb' => 0,
        'available-memory-mb' => 2048,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'keeps the heap within the 1.1 x heap that OpenVox Server checks at startup' do
      # Without that check, 57 instances (29696 MB heap, 2048 MB code cache)
      # would fit the 32000 MB.
      expect(subject).to run.with_params(64, 32_000, 0).and_return(
        'max-active-instances' => 55,
        'jvm-heap-mb' => 28_672,
        'reserved-code-cache-mb' => 2048,
        'reserved-memory-mb' => 0,
        'available-memory-mb' => 32_000,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'recommends one instance and reports that it does not fit on a host too small for one' do
      expect(subject).to run.with_params(1, 1900).and_return(
        'max-active-instances' => 1,
        'jvm-heap-mb' => 1024,
        'reserved-code-cache-mb' => 512,
        'reserved-memory-mb' => 475,
        'available-memory-mb' => 1425,
        'limited-by' => 'memory',
        'fits' => false,
      )
    end

    it 'reports that nothing fits when the reserve exceeds memory' do
      expect(subject).to run.with_params(4, 4000, 5000).and_return(
        'max-active-instances' => 1,
        'jvm-heap-mb' => 1024,
        'reserved-code-cache-mb' => 512,
        'reserved-memory-mb' => 5000,
        'available-memory-mb' => -1000,
        'limited-by' => 'memory',
        'fits' => false,
      )
    end
  end

  it 'rejects a CPU count below 1' do
    expect(subject).to run.with_params(0, 4000).and_raise_error(ArgumentError, %r{cpus})
  end
end
