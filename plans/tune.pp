# @summary Recommend OpenVox Server tuning settings based on the official tuning guide.
#
# Implements the formulas from:
#   https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html
#
# This plan is advisory only: it inspects the CPUs and memory on each target
# and prints recommended `jruby-puppet.max-active-instances`, JVM heap, and
# `-XX:ReservedCodeCacheSize` values. It does not modify any target.
#
# CPUs and memory are gathered via this module's own `host_resources` task
# rather than the Forge `facts` module, so the module has no external
# dependencies. Inside a container they are capped by its CPU quota and
# memory limit.
#
# OpenVox Server's built-in default for max-active-instances is already
# `num-cpus - 1` (clamped to a max of 4) as a conservative, unsized default.
# This plan recommends the same `num-cpus - 1` starting point without the
# cap at 4, then lowers it until the heap and code cache fit in the memory
# left after `reserved_memory_mb`. See `openvox_tune::recommend`.
#
# The plan returns one hash per target with `target`, `cpus`, `memory-mb`,
# `other-services` (OpenVoxDB and PostgreSQL services running on the
# target), and the keys `openvox_tune::recommend` returns.
#
# @param targets
#   The OpenVox Server node(s) to inspect.
#
# @param reserved_memory_mb
#   Memory to leave for the operating system and other services on each
#   target, in MB. Defaults to a quarter of the target's memory, which is
#   meant for the operating system alone; raise it when OpenVoxDB,
#   PostgreSQL or anything else large runs on the same host.
#
# @example Recommend settings for a server
#   bolt plan run openvox_tune::tune --targets puppet.example.com
#
# @example Leave 6 GB for OpenVoxDB and PostgreSQL on the same host
#   bolt plan run openvox_tune::tune --targets puppet.example.com reserved_memory_mb=6144
plan openvox_tune::tune(
  TargetSpec           $targets,
  Optional[Integer[0]] $reserved_memory_mb = undef,
) {
  $results = run_task('openvox_tune::host_resources', $targets)

  $recommendations = $results.map |$result| {
    $host = $result.value
    $settings = openvox_tune::recommend($host['cpus'], $host['memory_mb'], $reserved_memory_mb)

    $recommendation = {
      'target'         => $result.target.name,
      'cpus'           => $host['cpus'],
      'memory-mb'      => $host['memory_mb'],
      'other-services' => $host['other_services'],
    } + $settings
    $recommendation
  }

  $recommendations.each |$r| {
    $heap = $r['jvm-heap-mb']
    $code_cache = $r['reserved-code-cache-mb']
    $needed = $heap + $code_cache
    $available = $r['available-memory-mb']
    $cpu_instances = max($r['cpus'] - 1, 1)
    $others = $r['other-services'].join(', ')

    out::message("# ${r['target']}: ${r['cpus']} CPU(s), ${r['memory-mb']} MB memory, ${r['reserved-memory-mb']} MB reserved")

    if !$r['fits'] {
      out::message(@("MSG"/L))
        # Warning: one JRuby instance needs ${needed} MB of heap and code cache, \
        but only ${available} MB is left after the reserve.
        |- MSG
    } elsif $r['limited-by'] == 'memory' {
      out::message(@("MSG"/L))
        # Limited by memory: the CPUs allow ${cpu_instances} instances; \
        ${r['max-active-instances']} fit in the ${available} MB left after the reserve.
        |- MSG
    }

    if !empty($r['other-services']) and $reserved_memory_mb =~ Undef {
      out::message(@("MSG"/L))
        # Note: this host also runs ${others}. The default reserve covers \
        the operating system only; set reserved_memory_mb to include other services.
        |- MSG
    }

    out::message("jruby-puppet.max-active-instances: ${r['max-active-instances']}")
    out::message("JAVA_ARGS: -Xms${heap}m -Xmx${heap}m -XX:ReservedCodeCacheSize=${code_cache}m")
    out::message('')
  }

  return $recommendations
}
