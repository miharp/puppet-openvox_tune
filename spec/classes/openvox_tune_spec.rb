# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      define_method(:defaults_file) { (os_facts[:os]['family'] == 'Debian') ? '/etc/default/puppetserver' : '/etc/sysconfig/puppetserver' }
      define_method(:conf) { '/etc/puppetlabs/puppetserver/conf.d/openvox_tune.conf' }
      # 8 CPUs and 16000 MB: 7 instances, 4096 MB of heap, 1024 MB of code cache.
      let(:server) do
        {
          'cpus' => 8,
          'memory_mb' => 16_000,
          'defaults_file' => defaults_file,
          'java_args' => '-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger',
          'ca_enabled' => true,
          'jruby_puppet' => { 'max-requests-per-instance' => ['puppetserver.conf'] },
        }
      end
      let(:openvox_tune_fact) { server }
      let(:facts) { os_facts.merge(openvox_tune: openvox_tune_fact) }

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
        )
      end

      it 'sets max-active-instances in its own conf.d file' do
        expect(subject).to contain_file(conf).with(ensure: 'file', owner: 'root', group: 'root', mode: '0644')
                                             .with_content(%r{^jruby-puppet: \{\n    max-active-instances: 7\n\}$})
      end

      it 'restarts puppetserver after the run when either changes' do
        expect(subject).to contain_exec('openvox_tune restart puppetserver').with(
          command: 'systemd-run --on-active=30 --collect systemctl try-restart puppetserver.service',
          refreshonly: true,
        ).that_subscribes_to(['Augeas[openvox_tune JAVA_ARGS]', "File[#{conf}]"])
      end

      context 'with a code cache already set and an option of the operator\'s' do
        let(:openvox_tune_fact) do
          server.merge('java_args' => '-Xms1g -XX:ReservedCodeCacheSize=256m -XX:+UseG1GC -Xmx1g')
        end

        it 'replaces the options it manages and keeps the rest' do
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS')
            .with_changes(java_args('-Xms4096m -Xmx4096m -XX:+UseG1GC -XX:ReservedCodeCacheSize=1024m'))
        end
      end

      context 'with values passed in' do
        let(:params) { { max_active_instances: 3, heap_mb: 2048, reserved_code_cache_mb: 384, restart_delay: 5 } }

        it 'uses them instead of the recommendation' do
          expect(subject).to contain_file(conf).with_content(%r{max-active-instances: 3$})
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS').with_changes(%r{-Xms2048m -Xmx2048m .* -XX:ReservedCodeCacheSize=384m})
          expect(subject).to contain_exec('openvox_tune restart puppetserver').with_command(%r{--on-active=5 })
        end
      end

      context 'with reserved_memory_mb and memory_per_jruby_mb' do
        let(:params) { { reserved_memory_mb: 12_000, memory_per_jruby_mb: 1024 } }

        it 'sizes with them' do
          # 4000 MB left: 2 instances of 1024 MB, 2560 MB of heap and 512 MB of code cache.
          expect(subject).to contain_file(conf).with_content(%r{max-active-instances: 2$})
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS').with_changes(%r{-Xms2560m -Xmx2560m})
        end
      end

      context 'on a compiler' do
        let(:openvox_tune_fact) { server.merge('ca_enabled' => false) }

        it 'sizes it like a server' do
          expect(subject).to contain_file(conf).with_content(%r{max-active-instances: 7$})
        end
      end

      context 'with role server-with-compilers' do
        let(:params) { { role: 'server-with-compilers' } }

        it 'gives the server fewer instances' do
          expect(subject).to contain_file(conf).with_content(%r{max-active-instances: 2$})
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS').with_changes(%r{-Xms1536m -Xmx1536m})
        end
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

      context 'without restart' do
        let(:params) { { restart: false } }

        it { is_expected.not_to contain_exec('openvox_tune restart puppetserver') }
      end

      context 'on a host too small for one instance' do
        let(:openvox_tune_fact) { server.merge('cpus' => 1, 'memory_mb' => 1900) }

        it 'applies the smallest recommendation' do
          expect(subject).to contain_augeas('openvox_tune JAVA_ARGS').with_changes(%r{-Xms1024m -Xmx1024m})
          expect(subject).to contain_file(conf).with_content(%r{max-active-instances: 1$})
        end
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
