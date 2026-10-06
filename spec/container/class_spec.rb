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

  def apply(params = 'max_active_instances => 3, heap_mb => 2048, reserved_code_cache_mb => 512')
    "puppet apply --modulepath /installdir --detailed-exitcodes -e \"class { 'openvox_tune': #{params}, restart => false }\""
  end

  it 'reports the packaged server' do
    result = fact

    expect(result['memory_mb']).to be_a(Integer).and be_positive
    expect(result['defaults_file']).to match(%r{\A/etc/(default|sysconfig)/puppetserver\z})
    expect(result['java_args']).to match(%r{-Xmx2g})
    expect(result['jruby_puppet']).not_to include('max-active-instances')
  end

  it 'reports a container\'s memory limit' do
    expect(fact(docker_args: ['--memory=3g'])).to include('memory_mb' => 3072)
  end

  it 'applies the values, keeping the other JAVA_ARGS, and changes nothing the second time' do
    out = run(<<~SH)
      #{apply}; echo "first: $?"
      #{apply}; echo "second: $?"
      #{ContainerHelpers::DEFAULTS_LINE}; grep '^JAVA_ARGS=' "$d"
      cat #{ContainerHelpers::CONFD}/openvox_tune.conf
    SH

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

  it 'fails when the host has too little memory to start with the heap' do
    out = run(<<~SH, docker_args: ['--memory=2g'])
      #{apply('heap_mb => 2048')} 2>&1; echo "exit: $?"
    SH

    expect(out).to match(%r{refuses to start with 2048 MB of heap on this host's 2048 MB of memory})
    expect(out).to match(%r{^exit: 1$})
  end
end
