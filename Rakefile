# frozen_string_literal: true

begin
  require 'voxpupuli/test/rake'
rescue LoadError
  # voxpupuli-test is only available in the test gem group
end

# configure_beaker installs the module on the test host with its
# dependencies resolved from metadata.json, so the beaker task needs no
# fixtures:prep prerequisite (which would need a local puppet binary).
begin
  require 'voxpupuli/acceptance/rake'
rescue LoadError
  # voxpupuli-acceptance is only available in the system_tests gem group
end

begin
  require 'puppet-strings/tasks'
rescue LoadError
  # openvox-strings is only available in the development gem group
end

begin
  require 'voxpupuli/release/rake_tasks'
rescue LoadError
  # voxpupuli-release is only available in the release gem group
else
  GCGConfig.user = 'miharp'
  GCGConfig.project = 'puppet-openvox_tune'
end
