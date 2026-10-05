# frozen_string_literal: true

# Specs that run the host_resources task, and the plan through Bolt's Docker
# transport, against containers with real openvox-server packages installed
# but not started. They need Docker and two images:
#
#   CONTAINER_IMAGE  built from spec/container/Dockerfile.deb or .rpm
#   BASE_IMAGE       the image it was built from, without OpenVox
#
# See "Development" in README.md.

require 'json'
require 'open3'
require 'rbconfig'

module ContainerHelpers
  REPO = File.expand_path('..', __dir__)

  # Shell lines for setup scripts.
  PATH_LINE = 'export PATH=/opt/puppetlabs/bin:$PATH'
  DEFAULTS_LINE = 'd=/etc/default/puppetserver; [ -f "$d" ] || d=/etc/sysconfig/puppetserver'
  CONFD = '/etc/puppetlabs/puppetserver/conf.d'

  def image
    ENV.fetch('CONTAINER_IMAGE')
  end

  def base_image
    ENV.fetch('BASE_IMAGE')
  end

  # Runs setup, then the task, in a fresh container, and returns the task's
  # output.
  def host_resources(setup = 'true', docker_args: [], from: image)
    script = "#{PATH_LINE}\n#{setup}\nbash /t/host_resources.sh"
    out, err, status = Open3.capture3(
      'docker', 'run', '--rm', *docker_args, '-v', "#{REPO}/tasks:/t:ro", from, 'bash', '-c', script
    )
    raise "host_resources failed (exit #{status.exitstatus}): #{err}" unless status.success?

    JSON.parse(out.lines.last)
  end

  def java_args_setup(java_args)
    %(#{DEFAULTS_LINE}; sed -i -E 's/^JAVA_ARGS="[^"]*"/JAVA_ARGS="#{java_args}"/' "$d")
  end

  # Disables the CA service the way ovadm's configure_compiler_ssl task does.
  def disable_ca
    <<~SH
      sed -i \\
        -e 's|^puppetlabs.services.ca.certificate-authority-service/|#puppetlabs.services.ca.certificate-authority-service/|' \\
        -e 's|^#puppetlabs.services.ca.certificate-authority-disabled-service/|puppetlabs.services.ca.certificate-authority-disabled-service/|' \\
        /etc/puppetlabs/puppetserver/services.d/ca.cfg
    SH
  end

  def docker(*args)
    out, err, status = Open3.capture3('docker', *args)
    raise "docker #{args.first} failed: #{err}" unless status.success?

    out
  end

  # Runs openvox_tune::tune from this checkout and returns its result.
  def run_tune(*targets)
    out, err, status = Open3.capture3(
      { 'BOLT_GEM' => '1', 'BOLT_DISABLE_ANALYTICS' => 'true' },
      RbConfig.ruby, Gem.bin_path('openbolt', 'bolt'), 'plan', 'run', 'openvox_tune::tune',
      '--targets', targets.map { |t| "docker://#{t}" }.join(','), '--format', 'json',
      chdir: REPO
    )
    raise "bolt plan run failed (exit #{status.exitstatus}): #{err}#{out}" unless status.success?

    JSON.parse(out)
  end
end

RSpec.configure do |config|
  config.include ContainerHelpers
end
