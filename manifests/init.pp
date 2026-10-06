# @summary Tune OpenVox Server: JRuby instances, heap and code cache.
#
# Sizes OpenVox Server with `openvox_tune::recommend` from the host's CPUs
# and memory, as the `openvox_tune::tune` plan does, and applies it:
# `-Xms`, `-Xmx` and `-XX:ReservedCodeCacheSize` in `JAVA_ARGS`, keeping the
# other arguments, and `jruby-puppet.max-active-instances` in its own file,
# `conf.d/openvox_tune.conf`, so the package's `puppetserver.conf` is left
# alone. When either changes, puppetserver is restarted shortly after the
# run, so that a server applying its own catalog still sends its report.
#
# For servers no other module manages. With theforeman-puppet, use the
# plan's `hiera=true` output instead: OpenVox Server refuses to start when
# two conf.d files set `max-active-instances`, so the class fails when
# another file sets it. Where OpenVox Server is not installed, the class
# does nothing and logs a warning.
#
# @param role
#   `server`, `compiler` or `server-with-compilers`; see
#   `openvox_tune::recommend`. By default a host whose CA service is
#   disabled is a compiler and any other a server. A server cannot tell it
#   has compilers, so set `server-with-compilers` on it.
#
# @param reserved_memory_mb
#   Memory to leave for the operating system and other services, in MB.
#   Defaults to a quarter of the host's memory.
#
# @param memory_per_jruby_mb
#   Heap per JRuby instance, in MB.
#
# @param max_active_instances
#   JRuby instances to use instead of the recommendation.
#
# @param heap_mb
#   Heap to use instead of the recommendation, in MB.
#
# @param reserved_code_cache_mb
#   Reserved code cache to use instead of the recommendation, in MB.
#
# @param restart
#   Whether to restart puppetserver, when it is running, after a change.
#   Without, the settings apply at its next restart.
#
# @param restart_delay
#   Seconds after the change to restart puppetserver.
#
# @example Tune a server
#   include openvox_tune
#
# @example Tune the server of a deployment with compilers, leaving room for OpenVoxDB
#   class { 'openvox_tune':
#     role               => 'server-with-compilers',
#     reserved_memory_mb => 6144,
#   }
#
class openvox_tune (
  Optional[Enum['server', 'compiler', 'server-with-compilers']] $role = undef,
  Optional[Integer[0]]   $reserved_memory_mb     = undef,
  Integer[256]           $memory_per_jruby_mb    = 512,
  Optional[Integer[1]]   $max_active_instances   = undef,
  Optional[Integer[512]] $heap_mb                = undef,
  Optional[Integer[32]]  $reserved_code_cache_mb = undef,
  Boolean                $restart                = true,
  Integer[0]             $restart_delay          = 30,
) {
  $host = $facts['openvox_tune']

  if $host =~ Undef {
    warning('openvox_tune: OpenVox Server is not installed on this host; nothing to tune.')
  } else {
    $conf_file = 'openvox_tune.conf'
    $set_elsewhere = $host['jruby_puppet'].dig('max-active-instances').then |$files| { $files - [$conf_file] }
    if $set_elsewhere =~ Array and !empty($set_elsewhere) {
      fail(@("MSG"/L))
        openvox_tune: jruby-puppet.max-active-instances is already set in \
        ${set_elsewhere.join(', ')} under /etc/puppetlabs/puppetserver/conf.d, and OpenVox Server \
        refuses to start when two files set it. Remove it there, or tune through whatever manages that file.
        |- MSG
    }

    $detected_role = $host['ca_enabled'] ? {
      false   => 'compiler',
      default => 'server',
    }
    $recommended = openvox_tune::recommend(
      $host['cpus'], $host['memory_mb'], $reserved_memory_mb, $memory_per_jruby_mb, $role.lest || { $detected_role },
    )
    if !$recommended['fits'] and $heap_mb =~ Undef {
      warning(@("MSG"/L))
        openvox_tune: one JRuby instance needs more memory than this host has left after the reserve; \
        applying the smallest recommendation, ${recommended['jvm-heap-mb']} MB of heap.
        |- MSG
    }

    $instances = $max_active_instances.lest || { $recommended['max-active-instances'] }
    $heap = $heap_mb.lest || { $recommended['jvm-heap-mb'] }
    $code_cache = $reserved_code_cache_mb.lest || { $recommended['reserved-code-cache-mb'] }

    # The options this class sets go first and last; the others keep their order.
    $kept = String($host['java_args'].lest || { '' }).split(/\s+/).filter |$arg| {
      !empty($arg) and $arg !~ /\A(-Xms|-Xmx|-XX:ReservedCodeCacheSize=)/
    }
    $java_args = (["-Xms${heap}m", "-Xmx${heap}m"] + $kept + ["-XX:ReservedCodeCacheSize=${code_cache}m"]).join(' ')

    augeas { 'openvox_tune JAVA_ARGS':
      incl    => $host['defaults_file'],
      lens    => 'Shellvars.lns',
      changes => "set JAVA_ARGS '\"${java_args}\"'",
    }

    file { "/etc/puppetlabs/puppetserver/conf.d/${conf_file}":
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => @("CONF"),
        # Managed by Puppet (openvox_tune). OpenVox Server refuses to start when
        # another file in conf.d also sets jruby-puppet.max-active-instances.
        jruby-puppet: {
            max-active-instances: ${instances}
        }
        | CONF
    }

    if $restart {
      # Queued rather than run in place, so that a server applying its own
      # catalog finishes the run, report included, before it restarts.
      exec { 'openvox_tune restart puppetserver':
        command     => "systemd-run --on-active=${restart_delay} --collect systemctl try-restart puppetserver.service",
        path        => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
        refreshonly => true,
        subscribe   => [Augeas['openvox_tune JAVA_ARGS'], File["/etc/puppetlabs/puppetserver/conf.d/${conf_file}"]],
      }
    }
  }
}
