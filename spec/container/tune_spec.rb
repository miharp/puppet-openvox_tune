# frozen_string_literal: true

require 'spec_helper_container'

describe 'openvox_tune::tune plan through Bolt' do
  let(:server) { "openvox-tune-server-#{Process.pid}" }
  let(:compiler) { "openvox-tune-compiler-#{Process.pid}" }

  around do |example|
    [server, compiler].each { |name| docker('run', '-d', '--name', name, image, 'sleep', 'infinity') }
    docker('exec', compiler, 'bash', '-c', disable_ca)
    example.run
  ensure
    [server, compiler].each { |name| Open3.capture3('docker', 'rm', '-f', name) }
  end

  it 'sizes a server with compilers and its compiler from the real hosts' do
    by_target = run_tune(server, compiler).to_h { |r| [r['target'], r] }
    on_server = by_target["docker://#{server}"]
    on_compiler = by_target["docker://#{compiler}"]

    # Both containers see the runner's CPUs, which differ from machine to
    # machine (2 on GitHub's runners), so the limits are worked out from them.
    cpus = on_server['cpus']
    cpu_limit = [cpus - 1, 1].max
    server_cap = case cpus
                 when 1..3 then 1
                 when 4..15 then 2
                 else 4
                 end
    server_limit = [cpu_limit, server_cap].min

    expect(on_server).to include('role' => 'server-with-compilers', 'instance-limit' => server_limit, 'matches-current' => false)
    expect(on_server['current']).to include('environment-timeout' => 0, 'max-active-instances' => nil)
    expect(on_compiler).to include('role' => 'compiler', 'instance-limit' => cpu_limit)
    expect(on_compiler['hiera']['puppet::server_jvm_extra_args']).to include(%r{\A-XX:ReservedCodeCacheSize=\d+m\z})
  end
end
