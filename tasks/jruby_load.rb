#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

# Measures how much JRuby time OpenVox Server used over a window, from its
# access logs; see files/access_log.rb. Runs with the Ruby the agent ships,
# which every OpenVox Server host has.

require 'json'

params = JSON.parse($stdin.read)
require File.join(params.fetch('_installdir'), 'openvox_tune', 'files', 'access_log.rb')

summary = OpenvoxTune::AccessLog.new(
  log_dir: params['log_dir'] || '/var/log/puppetlabs/puppetserver',
  window_hours: params['window_hours'] || 24,
  bucket_minutes: params['bucket_minutes'] || 5,
).summary

# The agents' run interval, where nothing better can be measured.
summary['runinterval'] = begin
  require 'puppet'
  Puppet.initialize_settings([])
  Integer(Puppet[:runinterval])
rescue StandardError, LoadError
  nil
end

puts JSON.generate(summary)
