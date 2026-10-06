# frozen_string_literal: true

require 'json'
require 'spec_helper_acceptance'

# Beaker installs the agent from BEAKER_PUPPET_COLLECTION; these examples add
# openvox-server from the same collection, start it, tune it, and check that
# the deferred restart brings it back with the new settings.
#
# The stages build on each other, so the examples depend on running in
# order. RSpec runs a group's own examples before its nested groups, and
# it_behaves_like is a nested group, so each stage's checks sit in a group
# defined after the apply.
CONFD = '/etc/puppetlabs/puppetserver/conf.d'
# When puppetserver last started before the class ran, kept on the host so
# that the check after it can tell the restart happened.
STARTED_BEFORE = '/root/openvox_tune-started-before'

def server_available?
  # openvox-server 9 needs Java 21, which Debian 12 does not ship.
  !(ENV.fetch('BEAKER_PUPPET_COLLECTION', 'openvox8') == 'openvox9' &&
    fact('os.name') == 'Debian' && fact('os.release.major') == '12')
end

def certname
  shell('/opt/puppetlabs/bin/puppet config print certname --section agent').stdout.strip
end

# The JRuby pool and heap of the running server, from its status API and its
# command line.
def running_server
  cn = certname
  ssl = '/etc/puppetlabs/puppet/ssl'
  metrics = shell(
    "curl -sf --cert #{ssl}/certs/#{cn}.pem --key #{ssl}/private_keys/#{cn}.pem --cacert #{ssl}/certs/ca.pem " \
    "--resolve #{cn}:8140:127.0.0.1 'https://#{cn}:8140/status/v1/services/jruby-metrics?level=debug'",
  ).stdout
  args = shell("tr '\\0' ' ' < /proc/$(systemctl show -p MainPID --value puppetserver)/cmdline").stdout
  {
    'jrubies' => JSON.parse(metrics)['status']['experimental']['metrics']['num-jrubies'],
    'heap' => args[%r{-Xmx(\d+m)}, 1],
  }
end

STARTED = 'systemctl show -p ExecMainStartTimestampMonotonic --value puppetserver'

# Waits until puppetserver answers; with restarted, also until it has started
# again since STARTED_BEFORE was recorded.
def wait_for_server(restarted: false)
  since = %([ "$(#{STARTED})" != "$(cat #{STARTED_BEFORE})" ] && ) if restarted
  shell(<<~SH)
    for i in $(seq 1 90); do
      #{since}curl -sfk https://localhost:8140/status/v1/simple | grep -q running && exit 0
      sleep 2
    done
    exit 1
  SH
end

describe 'openvox_tune' do
  before(:all) do
    skip 'openvox-server 9 needs Java 21, which Debian 12 does not ship' unless server_available?

    apply_manifest("package { 'openvox-server': ensure => installed }", catch_failures: true)
    shell('/opt/puppetlabs/bin/puppetserver ca setup', acceptable_exit_codes: [0, 1])
    shell('systemctl start puppetserver')
    wait_for_server
  end

  context 'with values' do
    before(:all) do
      shell("#{STARTED} > #{STARTED_BEFORE}") if server_available?
    end

    it_behaves_like 'an idempotent resource' do
      let(:manifest) do
        "class { 'openvox_tune': max_active_instances => 2, heap_mb => 1536, reserved_code_cache_mb => 512, restart_delay => 5 }"
      end
    end

    describe 'afterwards' do
      it 'writes the settings' do
        defaults = file('/etc/default/puppetserver').exists? ? '/etc/default/puppetserver' : '/etc/sysconfig/puppetserver'
        expect(file("#{CONFD}/openvox_tune.conf").content).to match(%r{max-active-instances: 2$})
        expect(file(defaults).content).to match(%r{^JAVA_ARGS="-Xms1536m -Xmx1536m .*-XX:ReservedCodeCacheSize=512m"$})
      end

      it 'restarts puppetserver shortly after the run, with them' do
        wait_for_server(restarted: true)
        expect(running_server).to eq('jrubies' => 2, 'heap' => '1536m')
      end
    end
  end

  context 'when another conf.d file sets max-active-instances' do
    before(:all) do
      shell("printf 'jruby-puppet.max-active-instances: 4\\n' > #{CONFD}/tuning.conf") if server_available?
    end

    after(:all) do
      shell("rm -f #{CONFD}/tuning.conf") if server_available?
    end

    it 'fails rather than leave puppetserver unable to start' do
      result = apply_manifest("class { 'openvox_tune': max_active_instances => 2 }", expect_failures: true)
      expect(result.stderr).to match(%r{max-active-instances is already set in tuning.conf})
    end
  end
end
