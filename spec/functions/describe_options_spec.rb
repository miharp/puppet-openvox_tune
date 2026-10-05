# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::describe_options' do
  def current(**settings)
    {
      'environment-timeout' => 0,
      'max-requests-per-instance' => nil,
      'max-queued-requests' => nil,
      'multithreaded' => nil,
    }.merge(settings.transform_keys { |k| k.to_s.tr('_', '-') })
  end

  it 'is empty where OpenVox Server is not installed' do
    expect(subject).to run.with_params(nil).and_return('')
  end

  it 'shows environment_timeout alone on packaged settings' do
    expect(subject).to run.with_params(current).and_return('environment_timeout 0')
  end

  it 'shows environment_timeout in seconds, or unlimited' do
    expect(subject).to run.with_params(current(environment_timeout: 300)).and_return('environment_timeout 300s')
    expect(subject).to run.with_params(current(environment_timeout: 'unlimited')).and_return('environment_timeout unlimited')
  end

  it 'adds the JRuby options that are set' do
    expect(subject).to run.with_params(
      current(environment_timeout: 'unlimited', max_requests_per_instance: 100_000, max_queued_requests: 50, multithreaded: true),
    ).and_return('environment_timeout unlimited, max-requests-per-instance 100000, max-queued-requests 50, multithreaded')
  end

  it 'leaves out multithreaded when it is off, and an environment_timeout that is not known' do
    expect(subject).to run.with_params(current(environment_timeout: nil, multithreaded: false)).and_return('')
  end
end
