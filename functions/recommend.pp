# @summary Recommend OpenVox Server tuning for a host's CPUs and memory.
#
# The OpenVox Server tuning guide's sizing, lowered to fit the host's memory;
# see "What it recommends and why" in README.md.
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
# @param role
#   `server` for a server that compiles catalogs itself, `compiler` for a
#   compiler (sized the same way), or `server-with-compilers` for the CA
#   server of a deployment whose compilers compile the catalogs, which gets
#   1 instance below 4 CPUs, 2 below 16 and 4 from 16.
#
# @return [Hash]
#   `max-active-instances`: `num-cpus - 1` (at least 1), or the role's
#   limit, lowered until the heap and code cache fit in the memory left
#   after the reserve and the host has at least 1.1 times the heap, which
#   OpenVox Server checks at startup. `jvm-heap-mb`: 512 MB plus
#   `memory_per_jruby_mb` per instance. `reserved-code-cache-mb`: 512 MB
#   below 6 instances, 1024 MB for 6 to 12, 2048 MB above.
#   `memory-per-jruby-mb`, `reserved-memory-mb` and `available-memory-mb`:
#   what it was sized with. `instance-limit`: the instances the CPUs and
#   role allow before memory is counted. `limited-by`: `cpu`, `role` or
#   `memory`. `fits`: false when even one instance needs more memory than is
#   available, in which case the recommendation is for one instance anyway.
#
function openvox_tune::recommend(
  Integer[1]           $cpus,
  Integer[1]           $memory_mb,
  Optional[Integer[0]] $reserved_memory_mb = undef,
  Integer[1]           $memory_per_jruby_mb = 512,
  Enum['server', 'compiler', 'server-with-compilers'] $role = 'server',
) >> Hash {
  $reserved = $reserved_memory_mb ? {
    undef   => $memory_mb / 4,
    default => $reserved_memory_mb,
  }
  $available = $memory_mb - $reserved
  $cpu_instances = max($cpus - 1, 1)
  $instance_limit = $role ? {
    'server-with-compilers' => min($cpu_instances, $cpus ? {
      Integer[1, 3]  => 1,
      Integer[4, 15] => 2,
      default        => 4,
    }),
    default                 => $cpu_instances,
  }

  $candidates = Integer[1, $instance_limit].map |Integer $instances| {
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

  $limited_by = if !$fits or $chosen['max-active-instances'] < $instance_limit {
    'memory'
  } elsif $instance_limit < $cpu_instances {
    'role'
  } else {
    'cpu'
  }

  $chosen + {
    'memory-per-jruby-mb' => $memory_per_jruby_mb,
    'reserved-memory-mb'  => $reserved,
    'available-memory-mb' => $available,
    'instance-limit'      => $instance_limit,
    'limited-by'          => $limited_by,
    'fits'                => $fits,
  }
}
