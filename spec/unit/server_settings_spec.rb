# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../files/server_settings'

# environment_timeout needs a process whose Puppet settings are not yet
# initialized, so spec/container covers it.
describe OpenvoxTune::ServerSettings do
  let(:confd) { Dir.mktmpdir('openvox-tune-confd') }

  after do
    FileUtils.remove_entry(confd)
  end

  def conf(name, content)
    File.write(File.join(confd, name), content)
  end

  it 'reports nothing set in the packaged puppetserver.conf' do
    conf('puppetserver.conf', "jruby-puppet: {\n    #max-active-instances: 1\n    max-requests-per-instance: 0\n}\n")

    expect(described_class.jruby_puppet(confd)).to eq(
      'max_active_instances' => nil, 'max_requests_per_instance' => 0, 'max_queued_requests' => nil, 'multithreaded' => nil,
    )
  end

  it 'reads nested and dotted settings, a later file winning and a broken one skipped' do
    conf('puppetserver.conf', "jruby-puppet: {\n  max-active-instances: 7\n  multithreaded: true\n}\n")
    conf('tuning.conf', %(jruby-puppet.max-active-instances: 5\njruby-puppet.max-queued-requests: "50"\n))
    conf('zz-broken.conf', "jruby-puppet { max-active-instances: \n")

    expect(described_class.jruby_puppet(confd)).to eq(
      'max_active_instances' => 5, 'max_requests_per_instance' => nil, 'max_queued_requests' => 50, 'multithreaded' => true,
    )
  end

  it 'reads multithreaded false, and a number that is not one as nothing' do
    conf('puppetserver.conf', %(jruby-puppet: {\n  multithreaded: "false"\n  max-active-instances: "many"\n}\n))

    expect(described_class.jruby_puppet(confd)).to include('multithreaded' => false, 'max_active_instances' => nil)
  end

  it 'reports nothing set without a conf.d' do
    expect(described_class.jruby_puppet(File.join(confd, 'missing'))).to eq(
      'max_active_instances' => nil, 'max_requests_per_instance' => nil, 'max_queued_requests' => nil, 'multithreaded' => nil,
    )
  end
end
