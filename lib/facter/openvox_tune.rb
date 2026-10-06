# frozen_string_literal: true

# What the openvox_tune class needs to apply settings to OpenVox Server, on
# hosts where it is installed:
#
# - memory_mb: memory available to it, capped by a container's memory limit
# - defaults_file: /etc/default/puppetserver or /etc/sysconfig/puppetserver
# - java_args: JAVA_ARGS as the service reads it from that file
# - jruby_puppet: which conf.d files set each jruby-puppet setting, since
#   OpenVox Server refuses to start when two files set the same one
Facter.add(:openvox_tune) do
  confine kernel: 'Linux'

  setcode do
    require_relative '../puppet_x/openvox_tune/host'
    require_relative '../puppet_x/openvox_tune/server_settings'

    host = PuppetX::OpenvoxTune::Host
    defaults_file = host.defaults_file
    if defaults_file
      {
        'memory_mb' => host.memory_mb,
        'defaults_file' => defaults_file,
        'java_args' => host.java_args(defaults_file),
        'jruby_puppet' => PuppetX::OpenvoxTune::ServerSettings.jruby_puppet_sources('/etc/puppetlabs/puppetserver/conf.d'),
      }
    end
  end
end
