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
# Where OpenVox Server is installed, the plan also shows the current
# settings: the heap and code cache from JAVA_ARGS in the defaults file, and
# max-active-instances from conf.d (or the default it gets when unset), and
# says when they already match.
#
# The plan returns one hash per target with `target`, `cpus`, `memory-mb`,
# `other-services` (OpenVoxDB and PostgreSQL services running on the
# target), the keys `openvox_tune::recommend` returns, `current` (undef
# where OpenVox Server is not installed; otherwise `max-active-instances`,
# undef when unset, `effective-max-active-instances`, `jvm-min-heap-mb`,
# `jvm-heap-mb`, `reserved-code-cache-mb` and `memory-per-jruby-mb`, the
# heap per instance by the tuning guide's formula), and `matches-current`.
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
# @param memory_per_jruby_mb
#   Heap per JRuby instance, in MB, instead of the tuning guide's 512 MB.
#   Raise it for code with many modules or a lot of Hiera data.
#
# @param use_current_memory_per_jruby
#   Size each target with the heap per instance its current settings give,
#   `(heap - 512) / instances`, but never less than 512 MB. Keeps a per-JRuby
#   heap that was raised on purpose. Cannot be combined with
#   `memory_per_jruby_mb`.
#
# @example Recommend settings for a server
#   bolt plan run openvox_tune::tune --targets puppet.example.com
#
# @example Leave 6 GB for OpenVoxDB and PostgreSQL on the same host
#   bolt plan run openvox_tune::tune --targets puppet.example.com reserved_memory_mb=6144
#
# @example Keep the heap per JRuby instance the servers have now
#   bolt plan run openvox_tune::tune --targets servers use_current_memory_per_jruby=true
plan openvox_tune::tune(
  TargetSpec             $targets,
  Optional[Integer[0]]   $reserved_memory_mb           = undef,
  Optional[Integer[256]] $memory_per_jruby_mb          = undef,
  Boolean                $use_current_memory_per_jruby = false,
) {
  if $memory_per_jruby_mb =~ Integer and $use_current_memory_per_jruby {
    fail_plan('Pass memory_per_jruby_mb or use_current_memory_per_jruby, not both.')
  }

  $results = run_task('openvox_tune::host_resources', $targets)

  $recommendations = $results.map |$result| {
    $host = $result.value
    $server = $host['puppetserver']

    if $server =~ Undef {
      $current = undef
    } else {
      # OpenVox Server's own default when max-active-instances is unset.
      $instances = $server['max_active_instances'] ? {
        undef   => min(max($host['cpus'] - 1, 1), 4),
        default => $server['max_active_instances'],
      }
      $current = {
        'max-active-instances'           => $server['max_active_instances'],
        'effective-max-active-instances' => $instances,
        'jvm-min-heap-mb'                => $server['xms_mb'],
        'jvm-heap-mb'                    => $server['xmx_mb'],
        'reserved-code-cache-mb'         => $server['code_cache_mb'],
        'memory-per-jruby-mb'            => $server['xmx_mb'] ? {
          undef   => undef,
          default => ($server['xmx_mb'] - 512) / $instances,
        },
      }
    }

    $memory_per_jruby = if $memory_per_jruby_mb =~ Integer {
      $memory_per_jruby_mb
    } elsif $use_current_memory_per_jruby and $current =~ Hash and $current['memory-per-jruby-mb'] =~ Integer {
      max($current['memory-per-jruby-mb'], 512)
    } else {
      512
    }

    $settings = openvox_tune::recommend($host['cpus'], $host['memory_mb'], $reserved_memory_mb, $memory_per_jruby)

    $matches_current = $current =~ Hash and [
      $current['effective-max-active-instances'], $current['jvm-min-heap-mb'],
      $current['jvm-heap-mb'], $current['reserved-code-cache-mb'],
    ] == [
      $settings['max-active-instances'], $settings['jvm-heap-mb'],
      $settings['jvm-heap-mb'], $settings['reserved-code-cache-mb'],
    ]

    $recommendation = {
      'target'         => $result.target.name,
      'cpus'           => $host['cpus'],
      'memory-mb'      => $host['memory_mb'],
      'other-services' => $host['other_services'],
    } + $settings + {
      'current'         => $current,
      'matches-current' => $matches_current,
    }
    $recommendation
  }

  $recommendations.each |$r| {
    $heap = $r['jvm-heap-mb']
    $code_cache = $r['reserved-code-cache-mb']
    $needed = $heap + $code_cache
    $available = $r['available-memory-mb']
    $cpu_instances = max($r['cpus'] - 1, 1)
    $others = $r['other-services'].join(', ')
    $current_text = openvox_tune::describe_current($r['current'])

    out::message("# ${r['target']}: ${r['cpus']} CPU(s), ${r['memory-mb']} MB memory, ${r['reserved-memory-mb']} MB reserved")
    out::message("# Current: ${current_text}")
    if $r['matches-current'] {
      out::message('# The current settings already match the recommendation.')
    }
    if $r['memory-per-jruby-mb'] != 512 {
      out::message("# Sized for ${r['memory-per-jruby-mb']} MB of heap per JRuby instance.")
    }

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
