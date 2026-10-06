# frozen_string_literal: true

require 'spec_helper'

describe 'openvox_tune::capacity' do
  # 4 JRubies over an hour; 3600 JRuby-seconds = 1 JRuby busy on average.
  def load(overrides = {})
    {
      'jrubies' => 4,
      'window_seconds' => 3600,
      'jruby_seconds' => 3600.0,
      'catalog_requests' => 1200,
      'status_503' => 0,
      'bucket_seconds' => 300,
      'buckets' => { '0' => 150.0, '300' => 600.0, '600' => 300.0 },
      'nodes' => {},
      'runinterval' => 1800,
    }.merge(overrides.transform_keys(&:to_s))
  end

  # n nodes, each with two catalog requests interval seconds apart.
  def nodes(count, interval, prefix: 'node')
    (1..count).to_h { |i| ["#{prefix}#{i}.example.com", [2, i, i + interval]] }
  end

  it 'applies Little\'s law to the measured load' do
    result = subject.execute([load(nodes: nodes(600, 1800))])

    expect(result).to include(
      'jrubies' => 4,
      'busy-jrubies' => 1.0,
      'utilization' => 0.25,
      'nodes' => 600,
      'run-interval-seconds' => 1800.0,
      'run-interval-source' => 'measured',
      'jruby-seconds-per-run' => 3.0,
      # 4 JRubies * 1800 s / 3 s per run
      'node-capacity' => 2400,
      # 600 nodes * 3 s / 1800 s
      'minimum-jrubies' => 1,
    )
  end

  it 'finds the busiest time slot' do
    result = subject.execute([load(nodes: nodes(10, 1800))])

    # 600 JRuby-seconds in a 300 s slot: 2 JRubies busy, half of 4.
    expect(result).to include('peak-from' => 300, 'peak-busy-jrubies' => 2.0, 'peak-utilization' => 0.5)
  end

  it 'adds up servers, their time slots and the nodes they share' do
    compiler01 = load(buckets: { '300' => 600.0 }, nodes: nodes(100, 1800).merge('shared.example.com' => [1, 0, 0]))
    # A load balancer sent shared.example.com's next run to the other compiler.
    compiler02 = load(buckets: { '300' => 300.0, '900' => 750.0 }, nodes: { 'shared.example.com' => [1, 1800, 1800] })
    result = subject.execute([compiler01, compiler02])

    expect(result).to include(
      'jrubies' => 8,
      'busy-jrubies' => 2.0,
      'nodes' => 101,
      'catalog-requests' => 2400,
      'peak-from' => 300,
      'peak-busy-jrubies' => 3.0,
      'run-interval-seconds' => 1800.0,
    )
  end

  it 'takes the median interval, so a few odd nodes do not move it' do
    odd = { 'fast.example.com' => [10, 0, 900], 'slow.example.com' => [2, 0, 86_400] }
    result = subject.execute([load(nodes: nodes(5, 1800).merge(odd))])

    expect(result['run-interval-seconds']).to eq(1800.0)
  end

  it 'falls back to runinterval when no node ran twice' do
    once = { 'a.example.com' => [1, 0, 0], 'b.example.com' => [1, 60, 60] }
    result = subject.execute([load(nodes: once, runinterval: 900)])

    expect(result).to include('run-interval-seconds' => 900.0, 'run-interval-source' => 'runinterval')
  end

  it 'leaves the estimate out when no agent ran' do
    result = subject.execute([load(catalog_requests: 0, jruby_seconds: 0, buckets: {}, nodes: {}, runinterval: nil)])

    expect(result).to include(
      'busy-jrubies' => 0.0,
      'peak-from' => nil,
      'run-interval-seconds' => nil,
      'node-capacity' => nil,
      'minimum-jrubies' => nil,
    )
  end

  it 'counts 503 responses across servers' do
    expect(subject.execute([load('status_503' => 3), load('status_503' => 4)])['status-503']).to eq(7)
  end
end
