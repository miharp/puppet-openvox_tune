# frozen_string_literal: true

require 'open3'

module PuppetX
  module OpenvoxTune
    # What the openvox_tune fact reports about an OpenVox Server host: the
    # memory available to it, capped by a container's memory limit as in the
    # host_resources task, and its JAVA_ARGS. Paths are taken under root, for
    # the specs.
    module Host
      DEFAULTS_FILES = ['/etc/default/puppetserver', '/etc/sysconfig/puppetserver'].freeze

      module_function

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
