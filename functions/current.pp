# @summary OpenVox Server's current settings, from the host_resources task.
#
# @api private
#
# @param host
#   The `host_resources` task's result for a target.
#
# @return [Optional[Hash]]
#   Undef where OpenVox Server is not installed. Otherwise
#   `max-active-instances` (undef when unset), `effective-max-active-instances`
#   (OpenVox Server's own default of `num-cpus - 1`, 1 to 4, when unset),
#   `jvm-min-heap-mb`, `jvm-heap-mb`, `reserved-code-cache-mb`,
#   `memory-per-jruby-mb` (the heap per instance by the tuning guide's
#   formula), `environment-timeout`, `max-requests-per-instance`,
#   `max-queued-requests` and `multithreaded`.
#
function openvox_tune::current(
  Hash $host,
) >> Optional[Hash] {
  $server = $host['puppetserver']
  if $server =~ Undef {
    undef
  } else {
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
      'environment-timeout'            => $server['environment_timeout'],
      'max-requests-per-instance'      => $server['max_requests_per_instance'],
      'max-queued-requests'            => $server['max_queued_requests'],
      'multithreaded'                  => $server['multithreaded'],
    }
    $current
  }
}
