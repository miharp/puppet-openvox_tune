# frozen_string_literal: true

require 'spec_helper_container'

describe 'openvox_tune::host_resources task' do
  it 'reads the packaged settings' do
    result = host_resources
    server = result['puppetserver']

    expect(result['cpus']).to be_a(Integer).and be_positive
    expect(result['memory_mb']).to be_a(Integer).and be_positive
    expect(result['other_services']).to eq([])
    expect(server['defaults_file']).to match(%r{\A/etc/(default|sysconfig)/puppetserver\z})
    expect(server['xmx_mb']).to be_a(Integer).and be_positive
    expect(server['xms_mb']).to eq(server['xmx_mb'])
    expect(server).to include(
      'code_cache_mb' => nil,
      'ca_enabled' => true,
      'max_active_instances' => nil,
      'max_requests_per_instance' => nil,
      'max_queued_requests' => nil,
      'multithreaded' => nil,
      'environment_timeout' => 0,
    )
  end

  it 'reads the heap and code cache in any unit, the last of a repeated option winning' do
    server = host_resources(java_args_setup('-Xms3g -Xmx2g -XX:ReservedCodeCacheSize=524288k -Xmx3072m'))['puppetserver']

    expect(server).to include('xms_mb' => 3072, 'xmx_mb' => 3072, 'code_cache_mb' => 512)
  end

  it 'reads the JRuby settings from conf.d, a later file winning and a broken one skipped' do
    setup = <<~SH
      /opt/puppetlabs/puppet/bin/ruby -e '
        require "hocon/parser/config_document_factory"
        file = ARGV[0]
        doc = Hocon::Parser::ConfigDocumentFactory.parse_file(file)
        File.write(file, doc.set_value("jruby-puppet.max-active-instances", "7").render)
      ' #{ContainerHelpers::CONFD}/puppetserver.conf
      printf 'jruby-puppet.max-active-instances: 5\\njruby-puppet.max-queued-requests: "50"\\n' > #{ContainerHelpers::CONFD}/tuning.conf
      printf 'jruby-puppet: {\\n  max-requests-per-instance: 100000\\n  multithreaded: true\\n}\\n' > #{ContainerHelpers::CONFD}/zz-more.conf
      printf 'jruby-puppet { max-active-instances: \\n' > #{ContainerHelpers::CONFD}/zzz-broken.conf
    SH

    expect(host_resources(setup)['puppetserver']).to include(
      'max_active_instances' => 5,
      'max_requests_per_instance' => 100_000,
      'max_queued_requests' => 50,
      'multithreaded' => true,
    )
  end

  it 'sees a compiler set up by ovadm as a host with the CA disabled' do
    expect(host_resources(disable_ca)['puppetserver']['ca_enabled']).to be(false)
  end

  context 'with environment_timeout' do
    it 'takes the [server] value over [main], as the server does' do
      setup = <<~SH
        puppet config set environment_timeout 10m --section main
        puppet config set environment_timeout 5m --section server
      SH
      expect(host_resources(setup)['puppetserver']['environment_timeout']).to eq(300)
    end

    it 'reports unlimited' do
      setup = 'puppet config set environment_timeout unlimited --section server'
      expect(host_resources(setup)['puppetserver']['environment_timeout']).to eq('unlimited')
    end

    it 'falls back to [main]' do
      setup = 'puppet config set environment_timeout 10m --section main'
      expect(host_resources(setup)['puppetserver']['environment_timeout']).to eq(600)
    end
  end

  it 'caps CPUs and memory by the container limits' do
    result = host_resources(docker_args: ['--memory=3g', '--cpus=1.5'])

    expect(result).to include('cpus' => 2, 'memory_mb' => 3072)
  end

  it 'reports no OpenVox Server where it is not installed' do
    expect(host_resources(from: base_image)['puppetserver']).to be_nil
  end
end
