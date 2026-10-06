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

  # The checkout, mounted where Bolt would put the module for a task that
  # ships files: $_installdir/openvox_tune.
  MODULE_MOUNT = ['-v', "#{REPO}:/installdir/openvox_tune:ro"].freeze

  # Runs setup, then the task, in a fresh container, and returns the task's
  # output.
  def host_resources(setup = 'true', docker_args: [], from: image)
    script = "#{PATH_LINE}\n#{setup}\nbash /installdir/openvox_tune/tasks/host_resources.sh"
    out, err, status = Open3.capture3(
      'docker', 'run', '--rm', *docker_args, *MODULE_MOUNT, '-e', 'PT__installdir=/installdir', from, 'bash', '-c', script
    )
    raise "host_resources failed (exit #{status.exitstatus}): #{err}" unless status.success?

    JSON.parse(out.lines.last)
  end

  # Runs the jruby_load task in a fresh container, reading the access logs
  # in log_dir on this machine, and returns the task's output.
  def jruby_load(log_dir, **params)
    input = JSON.generate({ '_installdir' => '/installdir', 'log_dir' => '/logs' }.merge(params.transform_keys(&:to_s)))
    out, err, status = Open3.capture3(
      'docker', 'run', '--rm', '-i', *MODULE_MOUNT, '-v', "#{log_dir}:/logs:ro", image,
      '/opt/puppetlabs/puppet/bin/ruby', '/installdir/openvox_tune/tasks/jruby_load.rb',
      stdin_data: input
    )
    raise "jruby_load failed (exit #{status.exitstatus}): #{err}#{out}" unless status.success?

    JSON.parse(out.lines.last)
  end

  # An access log line in the format OpenVox Server's request-logging.xml
  # ships, as one taken from a real server.
  def access_line(time, path, borrow_ms:, method: 'POST', status: 200)
    stamp = time.utc.strftime('%d/%b/%Y:%H:%M:%S +0000')
    %(10.0.0.5 - - [#{stamp}] "#{method} #{path} HTTP/1.1" #{status} 318 "-" ) +
      %("Puppet/8.29.0 Ruby/3.2.11-p268 (x86_64-linux)" #{borrow_ms.to_i + 8} 16557 #{borrow_ms || '-'}\n)
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
