# @summary Describe OpenVox Server's other current settings in one line.
#
# @api private
#
# @param current
#   The `current` hash `openvox_tune::tune` builds for a target, or undef
#   where OpenVox Server is not installed.
#
# @return [String]
#   `environment_timeout` and whichever of `max-requests-per-instance`,
#   `max-queued-requests` and `multithreaded` are set, for example
#   `environment_timeout 0, max-requests-per-instance 100000, multithreaded`;
#   empty when none of them is known.
#
function openvox_tune::describe_options(
  Optional[Hash] $current,
) >> String {
  if $current =~ Undef {
    ''
  } else {
    $timeout = $current['environment-timeout']
    $parts = [
      $timeout ? {
        undef   => undef,
        Integer => $timeout ? { 0 => 'environment_timeout 0', default => "environment_timeout ${timeout}s" },
        default => "environment_timeout ${timeout}",
      },
      $current['max-requests-per-instance'] ? {
        undef   => undef,
        default => "max-requests-per-instance ${current['max-requests-per-instance']}",
      },
      $current['max-queued-requests'] ? {
        undef   => undef,
        default => "max-queued-requests ${current['max-queued-requests']}",
      },
      $current['multithreaded'] ? {
        true    => 'multithreaded',
        default => undef,
      },
    ]
    $parts.filter |$part| { $part =~ String }.join(', ')
  }
}
