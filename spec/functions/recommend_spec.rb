# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::recommend' do
  context 'when CPUs are the limit' do
    it 'recommends num-cpus - 1 instances and reserves a quarter of memory' do
      expect(subject).to run.with_params(8, 16_000).and_return(
        'max-active-instances' => 7,
        'jvm-heap-mb' => 4096,
        'reserved-code-cache-mb' => 1024,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 4000,
        'available-memory-mb' => 12_000,
        'instance-limit' => 7,
        'limited-by' => 'cpu',
        'fits' => true,
      )
    end

    it 'recommends one instance on a single CPU' do
      expect(subject).to run.with_params(1, 4000).and_return(
        'max-active-instances' => 1,
        'jvm-heap-mb' => 1024,
        'reserved-code-cache-mb' => 512,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 1000,
        'available-memory-mb' => 3000,
        'instance-limit' => 1,
        'limited-by' => 'cpu',
        'fits' => true,
      )
    end

    it 'uses the largest code cache above 12 instances' do
      expect(subject).to run.with_params(14, 64_000).and_return(
        'max-active-instances' => 13,
        'jvm-heap-mb' => 7168,
        'reserved-code-cache-mb' => 2048,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 16_000,
        'available-memory-mb' => 48_000,
        'instance-limit' => 13,
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
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 2500,
        'available-memory-mb' => 7500,
        'instance-limit' => 15,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'sizes the heap with the memory per JRuby instance passed in' do
      expect(subject).to run.with_params(16, 16_000, nil, 1024).and_return(
        'max-active-instances' => 10,
        'jvm-heap-mb' => 10_752,
        'reserved-code-cache-mb' => 1024,
        'memory-per-jruby-mb' => 1024,
        'reserved-memory-mb' => 4000,
        'available-memory-mb' => 12_000,
        'instance-limit' => 15,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'counts the reserve passed in instead of a quarter of memory' do
      expect(subject).to run.with_params(8, 16_000, 12_000).and_return(
        'max-active-instances' => 5,
        'jvm-heap-mb' => 3072,
        'reserved-code-cache-mb' => 512,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 12_000,
        'available-memory-mb' => 4000,
        'instance-limit' => 7,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'accepts a recommendation that fills the available memory exactly' do
      expect(subject).to run.with_params(4, 2048, 0).and_return(
        'max-active-instances' => 2,
        'jvm-heap-mb' => 1536,
        'reserved-code-cache-mb' => 512,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 0,
        'available-memory-mb' => 2048,
        'instance-limit' => 3,
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
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 0,
        'available-memory-mb' => 32_000,
        'instance-limit' => 63,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'recommends one instance and reports that it does not fit on a host too small for one' do
      expect(subject).to run.with_params(1, 1900).and_return(
        'max-active-instances' => 1,
        'jvm-heap-mb' => 1024,
        'reserved-code-cache-mb' => 512,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 475,
        'available-memory-mb' => 1425,
        'instance-limit' => 1,
        'limited-by' => 'memory',
        'fits' => false,
      )
    end

    it 'reports that nothing fits when the reserve exceeds memory' do
      expect(subject).to run.with_params(4, 4000, 5000).and_return(
        'max-active-instances' => 1,
        'jvm-heap-mb' => 1024,
        'reserved-code-cache-mb' => 512,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 5000,
        'available-memory-mb' => -1000,
        'instance-limit' => 3,
        'limited-by' => 'memory',
        'fits' => false,
      )
    end
  end

  context 'with a role' do
    it 'sizes a compiler like a server' do
      expect(subject).to run.with_params(8, 16_000, nil, 512, 'compiler').and_return(
        'max-active-instances' => 7,
        'jvm-heap-mb' => 4096,
        'reserved-code-cache-mb' => 1024,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 4000,
        'available-memory-mb' => 12_000,
        'instance-limit' => 7,
        'limited-by' => 'cpu',
        'fits' => true,
      )
    end

    {
      2 => 1,
      4 => 2,
      8 => 2,
      15 => 2,
      16 => 4,
      48 => 4,
    }.each do |cpus, instances|
      it "gives a server with compilers #{instances} instance(s) on #{cpus} CPUs" do
        expect(subject.execute(cpus, 64_000, nil, 512, 'server-with-compilers')).to include(
          'max-active-instances' => instances,
          'jvm-heap-mb' => 512 + (instances * 512),
          'instance-limit' => instances,
          'limited-by' => ((cpus == 2) ? 'cpu' : 'role'),
          'fits' => true,
        )
      end
    end

    it 'still lowers a server with compilers to what fits in memory' do
      expect(subject).to run.with_params(16, 3000, nil, 512, 'server-with-compilers').and_return(
        'max-active-instances' => 2,
        'jvm-heap-mb' => 1536,
        'reserved-code-cache-mb' => 512,
        'memory-per-jruby-mb' => 512,
        'reserved-memory-mb' => 750,
        'available-memory-mb' => 2250,
        'instance-limit' => 4,
        'limited-by' => 'memory',
        'fits' => true,
      )
    end

    it 'rejects an unknown role' do
      expect(subject).to run.with_params(8, 16_000, nil, 512, 'primary').and_raise_error(ArgumentError, %r{role})
    end
  end

  it 'rejects a CPU count below 1' do
    expect(subject).to run.with_params(0, 4000).and_raise_error(ArgumentError, %r{cpus})
  end
end
