# @summary Apply OpenVox Server tuning settings: JRuby instances, heap and code cache.
#
# Applies the values it is given, usually from Hiera, and nothing else: it
# does not size the host itself, so the settings change only when the data
# does. The `openvox_tune::tune` plan recommends the values and, with
# `hiera=openvox_tune`, prints them as Hiera data for this class.
#
# `heap_mb` sets `-Xms` and `-Xmx`, and `reserved_code_cache_mb` sets
# `-XX:ReservedCodeCacheSize`, in `JAVA_ARGS`, keeping the other arguments;
# unset, they are left as they are. `max_active_instances` sets
# `jruby-puppet.max-active-instances` in a file of its own,
# `conf.d/openvox_tune.conf`, so the package's `puppetserver.conf` is left
# alone; unset, that file is removed and the server's default applies. When
# a setting changes, puppetserver is restarted shortly after the run, so
# that a server applying its own catalog still sends its report.
#
# The class fails rather than leave puppetserver unable to restart: when
# another conf.d file also sets `max-active-instances`, and when the host has
# less memory than OpenVox Server needs to start with `heap_mb`, 1.1 times
# the heap.
#
# For servers no other module manages. With theforeman-puppet, use the
# plan's `hiera=theforeman-puppet` output instead. Where OpenVox Server is not
# installed, the class does nothing and logs a warning.
#
# @param max_active_instances
#   JRuby instances, `jruby-puppet.max-active-instances`.
#
# @param heap_mb
#   JVM heap, in MB, set as both `-Xms` and `-Xmx`.
#
# @param reserved_code_cache_mb
#   JVM reserved code cache, in MB, `-XX:ReservedCodeCacheSize`.
#
# @param restart
#   Whether to restart puppetserver, when it is running, after a change.
#   Without, the settings apply at its next restart.
#
# @param restart_delay
#   Seconds after the change to restart puppetserver.
#
# @example Hiera data for a server, from the plan's `hiera=openvox_tune` output
#   openvox_tune::max_active_instances: 7
#   openvox_tune::heap_mb: 4096
#   openvox_tune::reserved_code_cache_mb: 1024
#
# @example Apply settings in a manifest
#   class { 'openvox_tune':
#     max_active_instances   => 7,
#     heap_mb                => 4096,
#     reserved_code_cache_mb => 1024,
#   }
#
class openvox_tune (
  Optional[Integer[1]]   $max_active_instances   = undef,
  Optional[Integer[512]] $heap_mb                = undef,
  Optional[Integer[32]]  $reserved_code_cache_mb = undef,
  Boolean                $restart                = true,
  Integer[0]             $restart_delay          = 30,
) {
  $server = $facts['openvox_tune']

  if $server =~ Undef {
    warning('openvox_tune: OpenVox Server is not installed on this host; nothing to apply.')
  } else {
    $conf_file = 'openvox_tune.conf'
    $conf = "/etc/puppetlabs/puppetserver/conf.d/${conf_file}"
    $restart_exec = 'openvox_tune restart puppetserver'
    $notify = $restart ? {
      true    => Exec[$restart_exec],
      default => undef,
    }

    if $heap_mb =~ Integer and $server['memory_mb'] =~ Integer and $heap_mb * 11 > $server['memory_mb'] * 10 {
      fail(@("MSG"/L))
        openvox_tune: OpenVox Server refuses to start with ${heap_mb} MB of heap on this host's \
        ${server['memory_mb']} MB of memory: it needs 1.1 times the heap. Lower heap_mb.
        |- MSG
    }

    if $heap_mb =~ Integer or $reserved_code_cache_mb =~ Integer {
      $heap_args = $heap_mb.then |$mb| { ["-Xms${mb}m", "-Xmx${mb}m"] }.lest || { [] }
      $code_cache_args = $reserved_code_cache_mb.then |$mb| { ["-XX:ReservedCodeCacheSize=${mb}m"] }.lest || { [] }

      # The arguments this class sets replace any with the same option and go
      # first and last; the others keep their order.
      $options = ($heap_args + $code_cache_args).map |$arg| { $arg.regsubst(/\d+m\z/, '') }
      $kept = String($server['java_args'].lest || { '' }).split(/\s+/).filter |$arg| {
        !empty($arg) and !$options.any |$option| { $arg[0, $option.length] == $option }
      }
      $java_args = ($heap_args + $kept + $code_cache_args).join(' ')

      augeas { 'openvox_tune JAVA_ARGS':
        incl    => $server['defaults_file'],
        lens    => 'Shellvars.lns',
        changes => "set JAVA_ARGS '\"${java_args}\"'",
        notify  => $notify,
      }
    }

    if $max_active_instances =~ Integer {
      $set_elsewhere = $server['jruby_puppet'].dig('max-active-instances').then |$files| { $files - [$conf_file] }
      if $set_elsewhere =~ Array and !empty($set_elsewhere) {
        fail(@("MSG"/L))
          openvox_tune: jruby-puppet.max-active-instances is already set in \
          ${set_elsewhere.join(', ')} under /etc/puppetlabs/puppetserver/conf.d, and OpenVox Server \
          refuses to start when two files set it. Remove it there, or tune through whatever manages that file.
          |- MSG
      }

      file { $conf:
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => @("CONF"),
          # Managed by Puppet (openvox_tune). OpenVox Server refuses to start when
          # another file in conf.d also sets jruby-puppet.max-active-instances.
          jruby-puppet: {
              max-active-instances: ${max_active_instances}
          }
          | CONF
        notify  => $notify,
      }
    } else {
      file { $conf:
        ensure => absent,
        notify => $notify,
      }
    }

    if $restart {
      # Queued rather than run in place, so that a server applying its own
      # catalog finishes the run, report included, before it restarts.
      exec { $restart_exec:
        command     => "systemd-run --on-active=${restart_delay} --collect systemctl try-restart puppetserver.service",
        path        => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
        refreshonly => true,
      }
    }
  }
}
