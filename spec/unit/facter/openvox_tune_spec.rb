# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/puppet_x/openvox_tune/host'
require_relative '../../../lib/puppet_x/openvox_tune/server_settings'

describe 'openvox_tune fact' do
  subject(:fact) { Facter.fact(:openvox_tune).value }

  let(:host) { PuppetX::OpenvoxTune::Host }

  before do
    Facter.clear
    allow(Facter.fact(:kernel)).to receive(:value).and_return('Linux')
  end

  after { Facter.clear }

  it 'reports what the class sizes from where OpenVox Server is installed' do
    allow(host).to receive_messages(defaults_file: '/etc/sysconfig/puppetserver', cpus: 4, memory_mb: 7488, ca_enabled: false)
    allow(host).to receive(:java_args).with('/etc/sysconfig/puppetserver').and_return('-Xms2g -Xmx2g')
    allow(PuppetX::OpenvoxTune::ServerSettings).to receive(:jruby_puppet_sources)
      .with('/etc/puppetlabs/puppetserver/conf.d').and_return('max-active-instances' => ['openvox_tune.conf'])

    expect(fact).to eq(
      'cpus' => 4,
      'memory_mb' => 7488,
      'defaults_file' => '/etc/sysconfig/puppetserver',
      'java_args' => '-Xms2g -Xmx2g',
      'ca_enabled' => false,
      'jruby_puppet' => { 'max-active-instances' => ['openvox_tune.conf'] },
    )
  end

  it 'is nil where OpenVox Server is not installed' do
    allow(host).to receive(:defaults_file).and_return(nil)

    expect(fact).to be_nil
  end
end
