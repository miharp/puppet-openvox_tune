# frozen_string_literal: true

begin
  require 'voxpupuli/test/rake'
rescue LoadError
  # voxpupuli-test is only available in the test gem group
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
