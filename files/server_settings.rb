# frozen_string_literal: true

require 'json'

module OpenvoxTune
  # OpenVox Server settings that only the Ruby the agent ships can read: the
  # jruby-puppet settings in conf.d, which is HOCON, and environment_timeout
  # as the server resolves it from puppet.conf. Used by the host_resources
  # task, which runs this file with that Ruby where OpenVox Server is
  # installed (openvox-server depends on openvox-agent).
  module ServerSettings
    JRUBY_KEYS = {
      'max_active_instances' => 'max-active-instances',
      'max_requests_per_instance' => 'max-requests-per-instance',
      'max_queued_requests' => 'max-queued-requests',
      'multithreaded' => 'multithreaded',
    }.freeze
    INTEGER_KEYS = ['max_active_instances', 'max_requests_per_instance', 'max_queued_requests'].freeze

    module_function

    # The jruby-puppet settings from the *.conf files in confd, a later file
    # winning and one that does not parse skipped. A setting that is not
    # there, or not a number where one is expected, is nil.
    def jruby_puppet(confd)
      require 'hocon'
      found = JRUBY_KEYS.keys.to_h { |name| [name, nil] }
      Dir.glob(File.join(confd, '*.conf')).sort.each do |file|
        jruby = begin
          Hocon.load(file)['jruby-puppet']
        rescue StandardError
          nil
        end
        next unless jruby.is_a?(Hash)

        JRUBY_KEYS.each { |name, key| found[name] = jruby[key] if jruby.key?(key) }
      end
      INTEGER_KEYS.each { |name| found[name] = integer_or_nil(found[name]) unless found[name].nil? }
      found['multithreaded'] = [true, 'true'].include?(found['multithreaded']) unless found['multithreaded'].nil?
      found
    end

    # environment_timeout as OpenVox Server resolves it, in the server run
    # mode (puppet/server/puppet_config.rb), so that a [server] value in
    # puppet.conf counts: seconds, or 'unlimited'. `puppet config print
    # --section server` misses a [server] value for this setting. Needs
    # Puppet's settings to be uninitialized in this process.
    def environment_timeout
      require 'puppet'
      Puppet.settings.preferred_run_mode = :server
      Puppet.initialize_settings([])
      Puppet.settings.initialize_app_defaults(
        Puppet::Settings.app_defaults_for_run_mode(Puppet::Util::RunMode[:server]).merge(name: 'server'),
      )
      timeout = Puppet[:environment_timeout]
      timeout.to_f.infinite? ? 'unlimited' : Integer(timeout)
    end

    def integer_or_nil(value)
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    # Both, for the task: each part is nil when it cannot be read.
    def read(confd)
      settings = begin
        jruby_puppet(confd)
      rescue LoadError
        JRUBY_KEYS.keys.to_h { |name| [name, nil] }
      end
      settings['environment_timeout'] = begin
        environment_timeout
      rescue StandardError, LoadError
        nil
      end
      settings
    end
  end
end

# The host_resources task runs this file and splices its output, a JSON
# object without braces, into its own.
print JSON.generate(OpenvoxTune::ServerSettings.read(ARGV[0]))[1..-2] if $PROGRAM_NAME == __FILE__
