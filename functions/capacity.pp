# @summary Estimate OpenVox Server capacity from the JRuby load it served.
#
# Applies Little's law to what the access logs measured. Each agent run held
# JRubies for `jruby-seconds-per-run` in total (catalog, file metadata,
# report), and each node runs every `run-interval-seconds`, so N JRubies can
# serve N * interval / per-run nodes when they are busy all the time, and
# the nodes seen need at least nodes * per-run / interval JRubies.
#
# Nodes are merged across servers, since a load balancer sends one node's
# runs to different compilers. The run interval is the median, over nodes
# that ran at least twice, of the time between their catalog requests; when
# no node ran twice in the window it falls back to `runinterval`.
#
# @param loads
#   One hash per server or compiler: `jrubies`, its JRuby instances, and
#   from the `jruby_load` task `window_seconds`, `jruby_seconds`,
#   `catalog_requests`, `status_503`, `bucket_seconds`, `buckets`, `nodes`
#   and `runinterval`.
#
# @return [Hash]
#   `jrubies`; `window-seconds`, the longest window the logs cover;
#   `jruby-seconds`; `busy-jrubies`, the JRubies in use on average, and
#   `utilization`, that over `jrubies`; `peak-busy-jrubies`,
#   `peak-utilization` and `peak-from` (seconds since the epoch) for the
#   busiest whole time slot of `bucket-seconds` (the average, and undef
#   `peak-from`, when the window holds no whole slot); `nodes` and `catalog-requests`;
#   `run-interval-seconds` and `run-interval-source` (`measured` or
#   `runinterval`); `jruby-seconds-per-run`; `node-capacity` and
#   `minimum-jrubies`, undef without agent runs in the window; and
#   `status-503`.
#
function openvox_tune::capacity(
  Array[Hash, 1] $loads,
) >> Hash {
  $jrubies = $loads.reduce(0) |$total, $load| { $total + $load['jrubies'] }
  $jruby_seconds = $loads.reduce(0.0) |$total, $load| { $total + Float($load['jruby_seconds']) }
  $catalog_requests = $loads.reduce(0) |$total, $load| { $total + $load['catalog_requests'] }
  $status_503 = $loads.reduce(0) |$total, $load| { $total + $load['status_503'] }
  $window = $loads.reduce(0) |$longest, $load| { max($longest, $load['window_seconds']) }

  # Each server's JRuby-seconds over the time its own logs cover.
  $busy = $loads.reduce(0.0) |$total, $load| {
    $rate = ($load['window_seconds'] > 0) ? {
      true    => Float($load['jruby_seconds']) / $load['window_seconds'],
      default => 0.0,
    }
    $total + $rate
  }

  # The busiest time slot, adding up the servers' slots that start together.
  $bucket_seconds = $loads[0]['bucket_seconds']
  $slots = $loads.reduce([]) |$all, $load| {
    $all + $load['buckets'].map |$start, $seconds| { [Integer($start), Float($seconds)] }
  }
  $slot_totals = $slots.group_by |$slot| { $slot[0] }.map |$start, $same| {
    [$start, $same.reduce(0.0) |$total, $slot| { $total + $slot[1] }]
  }
  $peak = $slot_totals.reduce(undef) |$best, $slot| {
    ($best =~ Undef or $slot[1] > $best[1]) ? {
      true    => $slot,
      default => $best,
    }
  }
  # Without a whole time slot in the window, the window's average stands in.
  $peak_busy = $peak ? {
    undef   => $busy,
    default => $peak[1] / $bucket_seconds,
  }

  # Each node's catalog requests across all the logs: count, first, last.
  $requests = $loads.reduce([]) |$all, $load| {
    $all + $load['nodes'].map |$certname, $seen| { [$certname] + $seen }
  }
  $nodes = $requests.group_by |$entry| { $entry[0] }.map |$certname, $entries| {
    [
      $entries.reduce(0) |$count, $entry| { $count + $entry[1] },
      $entries.reduce($entries[0][2]) |$first, $entry| { min($first, $entry[2]) },
      $entries.reduce($entries[0][3]) |$last, $entry| { max($last, $entry[3]) },
    ]
  }
  $intervals = $nodes.filter |$node| { $node[0] > 1 }.map |$node| {
    Float($node[2] - $node[1]) / ($node[0] - 1)
  }.sort
  $runinterval = $loads.map |$load| { $load['runinterval'] }.filter |$value| { $value =~ Integer }

  if !empty($intervals) {
    $middle = $intervals.length / 2
    $interval = ($intervals.length % 2 == 1) ? {
      true    => $intervals[$middle],
      default => ($intervals[$middle - 1] + $intervals[$middle]) / 2.0,
    }
    $interval_source = 'measured'
  } elsif !empty($runinterval) {
    $interval = Float($runinterval[0])
    $interval_source = 'runinterval'
  } else {
    $interval = undef
    $interval_source = undef
  }

  if $catalog_requests > 0 and $interval =~ Float and $interval > 0 {
    $per_run = $jruby_seconds / $catalog_requests
    $node_capacity = ($per_run > 0) ? {
      true    => floor($jrubies * $interval / $per_run),
      default => undef,
    }
    $minimum_jrubies = max(1, ceiling($nodes.length * $per_run / $interval))
  } else {
    $per_run = undef
    $node_capacity = undef
    $minimum_jrubies = undef
  }

  $estimate = {
    'jrubies'               => $jrubies,
    'window-seconds'        => $window,
    'jruby-seconds'         => $jruby_seconds,
    'busy-jrubies'          => $busy,
    'utilization'           => ($jrubies > 0) ? { true => $busy / $jrubies, default => undef },
    'peak-busy-jrubies'     => $peak_busy,
    'peak-utilization'      => ($jrubies > 0) ? { true => $peak_busy / $jrubies, default => undef },
    'peak-from'             => $peak ? { undef => undef, default => $peak[0] },
    'bucket-seconds'        => $bucket_seconds,
    'nodes'                 => $nodes.length,
    'catalog-requests'      => $catalog_requests,
    'run-interval-seconds'  => $interval,
    'run-interval-source'   => $interval_source,
    'jruby-seconds-per-run' => $per_run,
    'node-capacity'         => $node_capacity,
    'minimum-jrubies'       => $minimum_jrubies,
    'status-503'            => $status_503,
  }
  $estimate
}
