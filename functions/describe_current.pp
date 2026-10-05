# @summary Describe OpenVox Server's current tuning settings in one line.
#
# @api private
#
# @param current
#   The `current` hash `openvox_tune::tune` builds for a target, or undef
#   where OpenVox Server is not installed.
#
# @return [String]
#   For example `4 instances (default), 2048m heap, JVM default code cache,
#   384 MB heap per instance`.
#
function openvox_tune::describe_current(
  Optional[Hash] $current,
) >> String {
  if $current =~ Undef {
    'OpenVox Server is not installed.'
  } else {
    $instances = $current['effective-max-active-instances']
    $instances_text = $instances ? {
      1       => '1 instance',
      default => "${instances} instances",
    }
    $default_text = $current['max-active-instances'] ? {
      undef   => ' (default)',
      default => '',
    }

    $xms = $current['jvm-min-heap-mb']
    $xmx = $current['jvm-heap-mb']
    $heap_text = if $xmx =~ Undef {
      'JVM default heap'
    } elsif $xms == $xmx {
      "${xmx}m heap"
    } elsif $xms =~ Undef {
      "${xmx}m heap (JVM default minimum)"
    } else {
      "${xmx}m heap (-Xms${xms}m)"
    }

    $code_cache = $current['reserved-code-cache-mb']
    $code_cache_text = $code_cache ? {
      undef   => 'JVM default code cache',
      default => "${code_cache}m code cache",
    }

    $per_jruby = $current['memory-per-jruby-mb']
    $per_jruby_text = ($per_jruby =~ Integer and $per_jruby > 0) ? {
      true    => ", ${per_jruby} MB heap per instance",
      default => '',
    }

    "${instances_text}${default_text}, ${heap_text}, ${code_cache_text}${per_jruby_text}"
  }
}
