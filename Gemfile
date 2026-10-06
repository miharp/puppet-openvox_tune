# frozen_string_literal: true

source 'https://rubygems.org'

openvox_version = ENV.fetch('OPENVOX_GEM_VERSION', '~> 8.0')

group :test do
  gem 'openvox', openvox_version, require: false
  # bolt_spec, for the plan specs. OpenBolt 5 requires openvox ~> 8.0, so in
  # a bundle with OpenVox 9 it is left out and the plan specs (tagged :plan)
  # are skipped.
  gem 'openbolt', '~> 5.0', require: false if openvox_version[%r{\d+}].to_i < 9
  gem 'puppet_metadata', '~> 6.0', require: false
  gem 'voxpupuli-test', '~> 14.0', require: false
end

group :development do
  gem 'openvox-strings', '~> 7.0', require: false
end

group :system_tests do
  gem 'voxpupuli-acceptance', '~> 4.4', require: false
end

group :release do
  gem 'voxpupuli-release', '~> 5.4', require: false
end
