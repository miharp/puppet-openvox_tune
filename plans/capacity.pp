# @summary Estimate how many nodes OpenVox Server can serve, from the load it served.
#
# OpenVox Server's access log records how long each request held a JRuby
# (`jruby.borrow-time`). This plan adds that up over a window on each
# target, with the `jruby_load` task, and shows how busy the JRubies were on
# average and in the busiest time slot. With the nodes that requested
# catalogs and how often they did, it estimates how many nodes the JRubies
# can serve at this rate and how many JRubies the nodes need. See
# `openvox_tune::capacity`. Advisory only: it changes nothing on the targets.
#
# Run it against the server and all its compilers together, so that load
# and nodes add up across the deployment. When the run includes compilers
# (hosts whose CA service is disabled), the estimate covers the compilers:
# the server is shown but left out, since the compilers serve the agents.
# Targets without OpenVox Server or without a readable access log, and
# targets where a task fails, are left out with the reason; reading the logs
# needs root or the puppet user. JRuby counts are the current settings.
#
# The plan returns `targets`, one hash per target with `target`, `role`
# (`server`, `compiler` or `server-with-compilers`), `jrubies`,
# `access-log` (`found`, `missing`, `unreadable`, `unrecognized`, or `failed`
# when a task failed there),
# `requests`, `jruby-requests`, `jruby-seconds`, `window-seconds`,
# `utilization` and `peak-utilization`, and `estimate`, the hash
# `openvox_tune::capacity` returns for the targets whose logs were read.
#
# @param targets
#   The OpenVox Server node(s) and compilers to read.
#
# @param window_hours
#   How many hours of access logs to read, back from now. The logs are
#   rotated daily and kept for up to 90 days.
#
# @param bucket_minutes
#   Length of the time slots for finding the busiest period, in minutes.
#
# @example Estimate capacity from the last day
#   bolt plan run openvox_tune::capacity --targets puppet.example.com,compiler01.example.com
#
# @example Use a week of logs, in 15-minute slots
#   bolt plan run openvox_tune::capacity --targets servers window_hours=168 bucket_minutes=15
plan openvox_tune::capacity(
  TargetSpec     $targets,
  Integer[1]     $window_hours   = 24,
  Integer[1, 60] $bucket_minutes = 5,
) {
  # A target where a task fails is left out rather than stopping the plan.
  $hosts = run_task('openvox_tune::host_resources', $targets, '_catch_errors' => true)
  $logs = run_task('openvox_tune::jruby_load', $targets, {
    'window_hours'   => $window_hours,
    'bucket_minutes' => $bucket_minutes,
    '_catch_errors'  => true,
  })

  # As in openvox_tune::tune: compilers disable the CA service, and when the
  # run includes one, the hosts with the CA enabled are the servers those
  # compilers serve the agents for.
  $with_compilers = $hosts.ok_set.results.any |$result| {
    $found = $result.value['puppetserver']
    $found =~ Hash and $found['ca_enabled'] == false
  }

  $per_target = $logs.map |$result| {
    $host_result = $hosts.find($result.target.name)
    $failed = [$host_result, $result].filter |$r| { !$r.ok }
    $load = empty($failed) ? {
      true    => $result.value,
      default => { 'access_log' => 'failed', 'error' => $failed[0].error.message },
    }
    $host = $host_result.ok ? {
      true    => $host_result.value,
      default => { 'puppetserver' => undef },
    }
    $current = empty($failed) ? {
      true    => openvox_tune::current($host),
      default => undef,
    }
    $role = if $current =~ Undef {
      undef
    } elsif $host['puppetserver']['ca_enabled'] == false {
      'compiler'
    } elsif $with_compilers {
      'server-with-compilers'
    } else {
      'server'
    }
    $jrubies = $current ? {
      undef   => undef,
      default => $current['effective-max-active-instances'],
    }
    $readable = $jrubies =~ Integer and $load['access_log'] == 'found'
    # A server with compilers is not where the agents' catalogs compile, so
    # its JRubies would overstate the capacity.
    $usable = $readable and $role != 'server-with-compilers'
    $utilization = ($readable and $load['window_seconds'] > 0) ? {
      true    => Float($load['jruby_seconds']) / $load['window_seconds'] / $jrubies,
      default => undef,
    }
    $peak_slot = ($readable and !empty($load['buckets'])) ? {
      true    => $load['buckets'].values.reduce(0.0) |$most, $seconds| { max($most, Float($seconds)) },
      default => undef,
    }
    $summary = {
      'target'           => $result.target.name,
      'role'             => $role,
      'jrubies'          => $jrubies,
      'access-log'       => $load['access_log'],
      'requests'         => $load['requests'],
      'jruby-requests'   => $load['jruby_requests'],
      'jruby-seconds'    => $load['jruby_seconds'],
      'window-seconds'   => $load['window_seconds'],
      'utilization'      => $utilization,
      'peak-utilization' => $peak_slot ? {
        undef   => $utilization,
        default => $peak_slot / $load['bucket_seconds'] / $jrubies,
      },
      'usable'           => $usable,
      'load'             => $load,
    }
    $summary
  }

  $per_target.each |$t| {
    if $t['access-log'] == 'failed' {
      out::message("# ${t['target']}: ${t['load']['error']}; left out.")
    } elsif $t['jrubies'] =~ Undef {
      out::message("# ${t['target']}: OpenVox Server is not installed; left out.")
    } elsif $t['access-log'] != 'found' {
      out::message("# ${t['target']}: access log ${t['access-log']} in ${t['load']['log_dir']}; left out.")
    } else {
      $average = openvox_tune::percent($t['utilization'])
      $peak = openvox_tune::percent($t['peak-utilization'])
      $pool = $t['jrubies'] ? {
        1       => '1 JRuby',
        default => "${t['jrubies']} JRubies",
      }
      out::message(@("MSG"/L))
        # ${t['target']}: ${pool}, ${t['requests']} requests \
        (${t['jruby-requests']} held a JRuby); busy ${average} on average, ${peak} at the busiest.
        |- MSG
      if $t['role'] == 'server-with-compilers' {
        out::message("# ${t['target']}: the server; left out of the estimate, since its compilers serve the agents.")
      }
    }
  }

  $usable = $per_target.filter |$t| { $t['usable'] }
  if empty($usable) {
    fail_plan('No target had OpenVox Server with a readable access log to estimate from.')
  }

  $estimate = openvox_tune::capacity($usable.map |$t| { $t['load'] + { 'jrubies' => $t['jrubies'] } })

  $hours = sprintf('%g', round($estimate['window-seconds'] / 360.0) / 10.0)
  $kind = $with_compilers ? {
    true    => 'compiler',
    default => 'server',
  }
  $servers = $usable.length ? {
    1       => "1 ${kind}",
    default => "${usable.length} ${kind}s",
  }
  out::message('')
  out::message("# Capacity over the last ${hours} h, from the access logs of ${servers}:")
  if $estimate['window-seconds'] < $window_hours * 3600 - 60 {
    out::message("# The logs cover less than the ${window_hours} h asked for; the server has not been up that long.")
  }

  if $estimate['catalog-requests'] == 0 {
    out::message('# No agent requested a catalog in that time, so there is nothing to estimate from.')
  } else {
    $interval = $estimate['run-interval-seconds']
    $interval_text = ($interval >= 120) ? {
      true    => "${round($interval / 60.0)} min",
      default => "${round($interval)} s",
    }
    $interval_note = $estimate['run-interval-source'] ? {
      'runinterval' => ' (runinterval; no node ran twice in the window)',
      default       => ' (median)',
    }
    $per_run = sprintf('%.2f', $estimate['jruby-seconds-per-run'])
    $average = openvox_tune::percent($estimate['utilization'])
    $peak = openvox_tune::percent($estimate['peak-utilization'])
    $nodes = $estimate['nodes'] ? {
      1       => '1 node',
      default => "${estimate['nodes']} nodes",
    }
    $slot_minutes = $estimate['bucket-seconds'] / 60
    $minimum = $estimate['minimum-jrubies'] ? {
      1       => '1 JRuby',
      default => "${estimate['minimum-jrubies']} JRubies",
    }

    out::message(@("MSG"/L))
      # ${nodes} requested catalogs, every ${interval_text}${interval_note}; \
      each run held JRubies for ${per_run} s in total.
      |- MSG
    if $estimate['peak-from'] =~ Integer {
      $peak_from = Timestamp($estimate['peak-from']).strftime('%Y-%m-%d %H:%M', 'UTC')
      out::message(@("MSG"/L))
        # JRubies busy ${average} on average, ${peak} in the busiest ${slot_minutes} minutes \
        (from ${peak_from} UTC).
        |- MSG
    } else {
      out::message("# JRubies busy ${average} on average; the logs hold no whole ${slot_minutes}-minute slot.")
    }
    out::message(@("MSG"/L))
      # At this rate the ${estimate['jrubies']} JRubies can serve about ${estimate['node-capacity']} \
      nodes; the nodes seen need at least ${minimum}.
      |- MSG
    if $estimate['peak-utilization'] >= 0.9 {
      out::message(@("MSG"/L))
        # Note: the JRubies were nearly all in use at the busiest time; agents checking in \
        together wait for one. splay on the agents spreads their runs out.
        |- MSG
    }
  }
  if $estimate['status-503'] > 0 {
    out::message(@("MSG"/L))
      # Note: ${estimate['status-503']} requests got 503 because the JRuby queue was full \
      (max-queued-requests), so demand was higher than this load shows.
      |- MSG
  }

  $outcome = {
    'targets'  => $per_target.map |$t| { $t.filter |$key, $value| { !($key in ['usable', 'load']) } },
    'estimate' => $estimate,
  }
  return $outcome
}
