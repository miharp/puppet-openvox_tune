# frozen_string_literal: true

# What the openvox_tune class sizes OpenVox Server from, on hosts where it is
# installed:
#
# - cpus, memory_mb: available to it, capped by a container's CPU quota and
#   memory limit
# - defaults_file: /etc/default/puppetserver or /etc/sysconfig/puppetserver
# - java_args: JAVA_ARGS as the service reads it from that file
# - ca_enabled: whether the CA service is enabled in services.d/ca.cfg
#   (false on compilers; nil without ca.cfg)
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
        'cpus' => host.cpus,
        'memory_mb' => host.memory_mb,
        'defaults_file' => defaults_file,
        'java_args' => host.java_args(defaults_file),
        'ca_enabled' => host.ca_enabled,
        'jruby_puppet' => PuppetX::OpenvoxTune::ServerSettings.jruby_puppet_sources('/etc/puppetlabs/puppetserver/conf.d'),
      }
    end
  end
end
