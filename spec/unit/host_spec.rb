# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../lib/puppet_x/openvox_tune/host'

describe PuppetX::OpenvoxTune::Host do
  let(:root) { Dir.mktmpdir('openvox-tune-root') }

  after do
    FileUtils.remove_entry(root)
  end

  def write(file, content)
    path = File.join(root, file)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  describe '.cpus' do
    it 'counts the CPUs on a host without a CPU quota' do
      expect(described_class.cpus(root: root, nprocessors: 8)).to eq(8)
    end

    it 'caps them by a container\'s CPU quota, rounding up' do
      write('/sys/fs/cgroup/cpu.max', "150000 100000\n")
      expect(described_class.cpus(root: root, nprocessors: 8)).to eq(2)
    end

    it 'ignores an unlimited quota' do
      write('/sys/fs/cgroup/cpu.max', "max 100000\n")
      expect(described_class.cpus(root: root, nprocessors: 8)).to eq(8)
    end
  end

  describe '.memory_mb' do
    before do
      write('/proc/meminfo', "MemTotal:       16000000 kB\nMemFree:         1000000 kB\n")
    end

    it 'reads MemTotal' do
      expect(described_class.memory_mb(root: root)).to eq(15_625)
    end

    it 'caps it by a cgroup v2 memory limit' do
      write('/sys/fs/cgroup/memory.max', "3221225472\n")
      expect(described_class.memory_mb(root: root)).to eq(3072)
    end

    it 'ignores an unlimited cgroup v2 limit and the effectively unlimited v1 one' do
      write('/sys/fs/cgroup/memory/memory.limit_in_bytes', "9223372036854771712\n")
      expect(described_class.memory_mb(root: root)).to eq(15_625)
      write('/sys/fs/cgroup/memory.max', "max\n")
      expect(described_class.memory_mb(root: root)).to eq(15_625)
    end
  end

  describe '.defaults_file' do
    it 'is nil without OpenVox Server' do
      expect(described_class.defaults_file(root: root)).to be_nil
    end

    it 'finds the EL file' do
      write('/etc/sysconfig/puppetserver', "JAVA_ARGS=\"-Xmx2g\"\n")
      expect(described_class.defaults_file(root: root)).to eq('/etc/sysconfig/puppetserver')
    end
  end

  describe '.java_args' do
    it 'reads JAVA_ARGS by sourcing the file, as the service does' do
      write('/etc/default/puppetserver', <<~SH)
        # comment
        JAVA_BIN="/usr/bin/java"
        JAVA_ARGS="-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"
        JAVA_ARGS_CLI="${JAVA_ARGS_CLI:-}"
      SH
      expect(described_class.java_args(File.join(root, '/etc/default/puppetserver')))
        .to eq('-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger')
    end

    it 'is nil without a file' do
      expect(described_class.java_args(nil)).to be_nil
    end
  end

  describe '.ca_enabled' do
    let(:enabled) { 'puppetlabs.services.ca.certificate-authority-service/certificate-authority-service' }
    let(:disabled) { 'puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service' }

    it 'is true as packaged' do
      write(described_class::CA_CFG, "#{enabled}\n##{disabled}\n")
      expect(described_class.ca_enabled(root: root)).to be(true)
    end

    it 'is false on a compiler' do
      write(described_class::CA_CFG, "##{enabled}\n#{disabled}\n")
      expect(described_class.ca_enabled(root: root)).to be(false)
    end

    it 'is nil without ca.cfg' do
      expect(described_class.ca_enabled(root: root)).to be_nil
    end
  end
end
