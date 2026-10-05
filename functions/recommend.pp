# @summary Recommend OpenVox Server tuning for a host's CPUs and memory.
#
# Starts from the OpenVox Server tuning guide: `num-cpus - 1` JRuby
# instances (at least 1), a heap of 512 MB plus 512 MB per instance (or
# `memory_per_jruby_mb`), and a
# reserved code cache of 512 MB below 6 instances, 1 GB for 6 to 12, and
# 2 GB above 12. It then lowers the instance count until the heap and the
# code cache fit in the memory left after the reserve for the operating
# system and other services, and the host has at least 1.1 times the heap:
# OpenVox Server refuses to start with less.
#
# @param cpus
#   The CPUs available to OpenVox Server.
#
# @param memory_mb
#   The memory available to OpenVox Server, in MB.
#
# @param reserved_memory_mb
#   Memory to leave for the operating system and other services, in MB.
#   Defaults to a quarter of `memory_mb`.
#
# @param memory_per_jruby_mb
#   Heap per JRuby instance, in MB. The tuning guide's 512 MB suits most
#   code; raise it for many modules or a lot of Hiera data.
#
# @return [Hash]
#   `max-active-instances`, `jvm-heap-mb` and `reserved-code-cache-mb`;
#   `memory-per-jruby-mb`, the heap per instance they were sized with;
#   `reserved-memory-mb` and `available-memory-mb`, the memory the
#   recommendation was sized for; `limited-by`, `cpu` or `memory`; and
#   `fits`, false when even one instance needs more memory than is
#   available, in which case the recommendation is for one instance anyway.
#
function openvox_tune::recommend(
  Integer[1]           $cpus,
  Integer[1]           $memory_mb,
  Optional[Integer[0]] $reserved_memory_mb = undef,
  Integer[1]           $memory_per_jruby_mb = 512,
) >> Hash {
  $reserved = $reserved_memory_mb ? {
    undef   => $memory_mb / 4,
    default => $reserved_memory_mb,
  }
  $available = $memory_mb - $reserved
  $cpu_instances = max($cpus - 1, 1)

  $candidates = Integer[1, $cpu_instances].map |Integer $instances| {
    {
      'max-active-instances'   => $instances,
      'jvm-heap-mb'            => 512 + $instances * $memory_per_jruby_mb,
      'reserved-code-cache-mb' => $instances ? {
        Integer[1, 5]  => 512,
        Integer[6, 12] => 1024,
        default        => 2048,
      },
    }
  }
  # OpenVox Server checks the second condition itself at startup, against
  # MemTotal, and exits when the heap is larger.
  $fitting = $candidates.filter |Hash $c| {
    $c['jvm-heap-mb'] + $c['reserved-code-cache-mb'] <= $available and
    $c['jvm-heap-mb'] * 11 <= $memory_mb * 10
  }
  $fits = !empty($fitting)
  $chosen = $fits ? {
    true    => $fitting[-1],
    default => $candidates[0],
  }

  $chosen + {
    'memory-per-jruby-mb' => $memory_per_jruby_mb,
    'reserved-memory-mb'  => $reserved,
    'available-memory-mb' => $available,
    'limited-by'          => ($fits and $chosen['max-active-instances'] == $cpu_instances) ? {
      true    => 'cpu',
      default => 'memory',
    },
    'fits'                => $fits,
  }
}
