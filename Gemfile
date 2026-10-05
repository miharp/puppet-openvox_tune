# frozen_string_literal: true

source 'https://rubygems.org'

group :test do
  gem 'openvox', ENV.fetch('OPENVOX_GEM_VERSION', '~> 8.0'), require: false
  # bolt_spec, for the plan tests. OpenBolt 5 requires openvox ~> 8.0.
  gem 'openbolt', '~> 5.0', require: false
  gem 'puppet_metadata', '~> 6.0', require: false
  gem 'voxpupuli-test', '~> 14.0', require: false
end

group :development do
  gem 'openvox-strings', '~> 7.0', require: false
end

group :release do
  gem 'voxpupuli-release', '~> 5.4', require: false
end
