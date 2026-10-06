# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      define_method(:defaults_file) { (os_facts[:os]['family'] == 'Debian') ? '/etc/default/puppetserver' : '/etc/sysconfig/puppetserver' }
      define_method(:conf) { '/etc/puppetlabs/puppetserver/conf.d/openvox_tune.conf' }
      define_method(:restart) { 'Exec[openvox_tune restart puppetserver]' }
      let(:server) do
        {
          'memory_mb' => 16_000,
          'defaults_file' => defaults_file,
          'java_args' => '-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger',
          'jruby_puppet' => { 'max-requests-per-instance' => ['puppetserver.conf'] },
        }
      end
      let(:openvox_tune_fact) { server }
      let(:facts) { os_facts.merge(openvox_tune: openvox_tune_fact) }
      let(:params) { { max_active_instances: 7, heap_mb: 4096, reserved_code_cache_mb: 1024 } }

      def java_args(args)
        "set JAVA_ARGS '\"#{args}\"'"
      end

      it { is_expected.to compile.with_all_deps }

      it 'sets the heap and code cache in JAVA_ARGS, keeping the other arguments' do
        expect(subject).to contain_augeas('openvox_tune JAVA_ARGS').with(
          incl: defaults_file,
          lens: 'Shellvars.lns',
          changes: java_args(
            '-Xms4096m -Xmx4096m -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger -XX:ReservedCodeCacheSize=1024m',
          ),
        ).that_notifies(restart)
      end

      it 'sets max-active-instances in its own conf.d file' do
        expect(subject).to contain_file(conf).with(ensure: 'file', owner: 'root', group: 'root', mode: '0644')
                                             .with_content(%r{^jruby-puppet: \{\n    max-active-instances: 7\n\}$})
                                             .that_notifies(restart)
      end

      it 'restarts puppetserver after the run when they change' do
        expect(subject).to contain_exec('openvox_tune restart puppetserver').with(
          command: 'systemd-run --on-active=30 --collect systemctl try-restart puppetserver.service',
          refreshonly: true,
        )
      end

      context 'with a code cache already set and an option of the operator\'s' do
        let(:openvox_tune_fact) do
          server.merge('java_args' => '-Xms1g -XX:ReservedCodeCacheSize=256m -XX:+UseG1GC -Xmx1g')
        end

        it 'replaces the options it sets and keeps the rest' do
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS')
            .with_changes(java_args('-Xms4096m -Xmx4096m -XX:+UseG1GC -XX:ReservedCodeCacheSize=1024m'))
        end
      end

      context 'with only the heap' do
        let(:params) { { heap_mb: 4096 } }
        let(:openvox_tune_fact) { server.merge('java_args' => '-Xms2g -XX:ReservedCodeCacheSize=256m -Xmx2g') }

        it 'leaves the code cache as it is' do
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS')
            .with_changes(java_args('-Xms4096m -Xmx4096m -XX:ReservedCodeCacheSize=256m'))
        end
      end

      context 'with only the code cache' do
        let(:params) { { reserved_code_cache_mb: 512 } }

        it 'leaves the heap as it is' do
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS').with_changes(
            java_args('-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger -XX:ReservedCodeCacheSize=512m'),
          )
        end
      end

      context 'without max_active_instances' do
        let(:params) { { heap_mb: 4096 } }

        it 'removes its conf.d file, so the server\'s default applies' do
          expect(subject).to contain_file(conf).with_ensure('absent').that_notifies(restart)
        end

        context 'when another conf.d file sets max-active-instances' do
          let(:openvox_tune_fact) { server.merge('jruby_puppet' => { 'max-active-instances' => ['puppetserver.conf'] }) }

          it { is_expected.to compile.with_all_deps }
        end
      end

      context 'without values' do
        let(:params) { {} }

        it 'leaves JAVA_ARGS alone' do
          expect(subject).to compile.with_all_deps
          expect(subject).to have_augeas_resource_count(0)
          expect(subject).to contain_file(conf).with_ensure('absent')
        end
      end

      context 'with restart_delay' do
        let(:params) { super().merge(restart_delay: 5) }

        it { is_expected.to contain_exec('openvox_tune restart puppetserver').with_command(%r{--on-active=5 }) }
      end

      context 'when this class already set max-active-instances' do
        let(:openvox_tune_fact) { server.merge('jruby_puppet' => { 'max-active-instances' => ['openvox_tune.conf'] }) }

        it { is_expected.to compile.with_all_deps }
      end

      context 'when another conf.d file sets max-active-instances' do
        let(:openvox_tune_fact) do
          server.merge('jruby_puppet' => { 'max-active-instances' => ['openvox_tune.conf', 'puppetserver.conf'] })
        end

        it { is_expected.to compile.and_raise_error(%r{max-active-instances is already set in puppetserver.conf}) }
      end

      context 'with more heap than the host can start with' do
        # OpenVox Server needs 1.1 times the heap: 4096 MB of heap needs 4506 MB.
        let(:openvox_tune_fact) { server.merge('memory_mb' => 4500) }

        it { is_expected.to compile.and_raise_error(%r{refuses to start with 4096 MB of heap on this host's 4500 MB of memory}) }
      end

      context 'with the most heap the host can start with' do
        let(:openvox_tune_fact) { server.merge('memory_mb' => 4506) }

        it { is_expected.to compile.with_all_deps }
      end

      context 'without restart' do
        let(:params) { super().merge(restart: false) }

        it { is_expected.not_to contain_exec('openvox_tune restart puppetserver') }
        it { is_expected.to contain_file(conf).without_notify }
      end

      context 'where OpenVox Server is not installed' do
        let(:openvox_tune_fact) { nil }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to have_augeas_resource_count(0) }
        it { is_expected.to have_file_resource_count(0) }
        it { is_expected.to have_exec_resource_count(0) }
      end
    end
  end
end
