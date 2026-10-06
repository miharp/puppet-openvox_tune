# frozen_string_literal: true

require 'etc'
require 'open3'

module PuppetX
  module OpenvoxTune
    # What the openvox_tune fact reports about an OpenVox Server host: the
    # CPUs and memory available to it, capped by a container's CPU quota and
    # memory limit as in the host_resources task, its JAVA_ARGS, and whether
    # its CA service is enabled. Paths are taken under root, for the specs.
    module Host
      DEFAULTS_FILES = ['/etc/default/puppetserver', '/etc/sysconfig/puppetserver'].freeze
      CA_CFG = '/etc/puppetlabs/puppetserver/services.d/ca.cfg'

      module_function

      # Etc.nprocessors honours CPU affinity and cpusets. A container started
      # with a CPU quota still sees every CPU; the host's root cgroup has no
      # cpu.max, so on a VM or bare metal the quota changes nothing.
      def cpus(root: '/', nprocessors: Etc.nprocessors)
        quota, period = read(root, '/sys/fs/cgroup/cpu.max')&.split
        return nprocessors if quota.nil? || quota == 'max'

        [nprocessors, (Integer(quota) + Integer(period) - 1) / Integer(period)].min
      rescue ArgumentError
        nprocessors
      end

      # MemTotal, capped by a container's memory limit, since a container sees
      # the host's /proc/meminfo. The host's root cgroup has no memory.max (v2)
      # and an effectively unlimited memory.limit_in_bytes (v1).
      def memory_mb(root: '/')
        total_kb = read(root, '/proc/meminfo').to_s[%r{^MemTotal:\s+(\d+)}, 1]
        return nil if total_kb.nil?

        memory = Integer(total_kb) / 1024
        ['/sys/fs/cgroup/memory.max', '/sys/fs/cgroup/memory/memory.limit_in_bytes'].each do |file|
          limit = read(root, file)
          next if limit.nil?

          memory = [memory, Integer(limit) / 1_048_576].min unless limit == 'max'
          break
        end
        memory
      end

      def defaults_file(root: '/')
        DEFAULTS_FILES.find { |file| File.readable?(path(root, file)) }
      end

      # JAVA_ARGS read as the service and the puppetserver CLI read it: by
      # sourcing the defaults file. nil when the file cannot be read.
      def java_args(file)
        return nil if file.nil?

        out, status = Open3.capture2(
          'bash', '-c', 'set +eu; . "$1" >/dev/null 2>&1; printf %s "${JAVA_ARGS:-}"', 'java_args', file
        )
        status.success? ? out : nil
      end

      # Compilers comment out the CA service in ca.cfg and enable the disabled
      # one instead (ovadm and theforeman-puppet both do). nil without ca.cfg.
      def ca_enabled(root: '/')
        cfg = read(root, CA_CFG)
        return nil if cfg.nil?
        return true if cfg.match?(%r{^\s*puppetlabs\.services\.ca\.certificate-authority-service/})
        return false if cfg.match?(%r{^\s*puppetlabs\.services\.ca\.certificate-authority-disabled-service/})

        nil
      end

      def read(root, file)
        File.read(path(root, file)).strip
      rescue SystemCallError
        nil
      end

      def path(root, file)
        File.join(root, file)
      end
    end
  end
end
