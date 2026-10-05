# frozen_string_literal: true

require 'voxpupuli/test/spec_helper'
require 'bolt_spec/plans'

RSpec.configure do |config|
  config.before(:suite) do
    BoltSpec::Plans.init
  end
end
