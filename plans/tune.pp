# @summary Recommend OpenVox Server tuning settings based on the official tuning guide.
#
# Implements the formulas from:
#   https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html
#
# This plan is advisory only: it inspects CPU facts on each target and prints
# recommended `jruby-puppet.max-active-instances`, JVM heap, and
# `-XX:ReservedCodeCacheSize` values. It does not modify any target.
#
# Puppet Server's built-in default for max-active-instances is already
# `num-cpus - 1` (clamped to a max of 4) as a conservative, unsized default.
# This plan recommends the same `num-cpus - 1` starting point without the
# cap at 4, on the assumption that you will also size the heap accordingly
# (which is the point of tuning past the conservative default).
#
# @param targets
#   The Puppet Server node(s) to inspect.
#
# @example Tune the primary master
#   bolt plan run openvox_tune::tune --targets puppet.example.com
plan openvox_tune::tune(
  TargetSpec $targets,
) {
  run_plan('facts', 'targets' => $targets)

  $recommendations = get_targets($targets).map |$target| {
    $cpus = $target.facts.dig('processors', 'count')
    if $cpus =~ Undef {
      fail_plan("Unable to determine CPU count for ${target.name}; ensure Facter facts are available")
    }

    $max_active_instances = if ($cpus - 1) >= 1 { $cpus - 1 } else { 1 }
    $heap_mb = 512 + ($max_active_instances * 512)
    $code_cache_mb = if $max_active_instances < 6 {
      512
    } elsif $max_active_instances <= 12 {
      1024
    } else {
      2048
    }

    $recommendation = {
      'target'                  => $target.name,
      'cpus'                    => $cpus,
      'max-active-instances'    => $max_active_instances,
      'jvm-heap-mb'             => $heap_mb,
      'reserved-code-cache-mb'  => $code_cache_mb,
    }
    $recommendation
  }

  $recommendations.each |$r| {
    out::message("# ${r['target']}: ${r['cpus']} CPU(s)")
    out::message("jruby-puppet.max-active-instances: ${r['max-active-instances']}")
    out::message("JAVA_ARGS: -Xms${r['jvm-heap-mb']}m -Xmx${r['jvm-heap-mb']}m -XX:ReservedCodeCacheSize=${r['reserved-code-cache-mb']}m")
    out::message('')
  }

  return $recommendations
}
