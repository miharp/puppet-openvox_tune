# frozen_string_literal: true

require 'voxpupuli/test/spec_helper'

begin
  require 'bolt_spec/plans'
rescue LoadError
  # The openbolt gem is only in bundles with OpenVox 8 (see the Gemfile), so
  # the plan specs, tagged :plan, are skipped elsewhere.
end

RSpec.configure do |config|
  if defined?(BoltSpec::Plans)
    config.before(:suite) do
      Bolt::PAL.load_puppet
      Logging.init :trace, :debug, :info, :notice, :warn, :error, :fatal
    end

    # Bolt runs plans in Puppet's tasks mode, in which catalogs cannot be
    # compiled, so turn it on only around the plan specs (BoltSpec::Plans.init
    # would turn it on for the class specs too).
    config.around(:each, :plan) do |example|
      Puppet[:tasks] = true
      example.run
    ensure
      Puppet[:tasks] = false
    end
  else
    config.filter_run_excluding(:plan)
  end
end
