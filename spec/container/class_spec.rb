# frozen_string_literal: true

require 'spec_helper_container'

# The fact through the agent's facter, and the class through puppet apply,
# on the real packages. Without systemd in the containers the class runs
# with restart => false; the acceptance tests cover the restart.
describe 'openvox_tune class and fact' do
  def run(script, docker_args: [])
    out, err, status = Open3.capture3(
      'docker', 'run', '--rm', *docker_args, *ContainerHelpers::MODULE_MOUNT, image, 'bash', '-c',
      "#{ContainerHelpers::PATH_LINE}\n#{script}"
    )
    raise "container script failed (exit #{status.exitstatus}): #{err}#{out}" unless status.success?

    out
  end

  def fact(setup = 'true', docker_args: [])
    out = run("#{setup}\nFACTERLIB=/installdir/openvox_tune/lib/facter facter --json openvox_tune", docker_args: docker_args)
    JSON.parse(out)['openvox_tune']
  end

  def apply
    "puppet apply --modulepath /installdir --detailed-exitcodes -e \"class { 'openvox_tune': restart => false }\""
  end

  it 'reports the packaged server' do
    result = fact

    expect(result['cpus']).to be_a(Integer).and be_positive
    expect(result['memory_mb']).to be_a(Integer).and be_positive
    expect(result['defaults_file']).to match(%r{\A/etc/(default|sysconfig)/puppetserver\z})
    expect(result['java_args']).to match(%r{-Xmx2g})
    expect(result['ca_enabled']).to be(true)
    expect(result['jruby_puppet']).not_to include('max-active-instances')
  end

  it 'reports a compiler and container limits' do
    result = fact(disable_ca, docker_args: ['--memory=3g', '--cpus=1.5'])

    expect(result).to include('ca_enabled' => false, 'cpus' => 2, 'memory_mb' => 3072)
  end

  it 'applies the recommendation, keeping the other JAVA_ARGS, and changes nothing the second time' do
    out = run(<<~SH, docker_args: ['--memory=8g', '--cpus=4'])
      #{apply}; echo "first: $?"
      #{apply}; echo "second: $?"
      #{ContainerHelpers::DEFAULTS_LINE}; grep '^JAVA_ARGS=' "$d"
      cat #{ContainerHelpers::CONFD}/openvox_tune.conf
    SH

    # 4 CPUs and 8192 MB: 3 instances, 2048 MB of heap, 512 MB of code cache.
    expect(out).to match(%r{^first: 2$}) # changes applied
    expect(out).to match(%r{^second: 0$}) # nothing left to change
    expect(out).to match(%r{^JAVA_ARGS="-Xms2048m -Xmx2048m .*-XX:ReservedCodeCacheSize=512m"$})
    expect(out).to match(%r{^    max-active-instances: 3$})
  end

  it 'fails when another conf.d file sets max-active-instances' do
    out = run(<<~SH)
      printf 'jruby-puppet.max-active-instances: 4\\n' > #{ContainerHelpers::CONFD}/tuning.conf
      #{apply} 2>&1; echo "exit: $?"
      test -e #{ContainerHelpers::CONFD}/openvox_tune.conf && echo "openvox_tune.conf written" || true
    SH

    expect(out).to match(%r{max-active-instances is already set in tuning.conf})
    expect(out).to match(%r{^exit: 1$})
    expect(out).not_to include('openvox_tune.conf written')
  end
end
