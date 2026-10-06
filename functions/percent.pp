# @summary Format a fraction as a percentage, with a decimal below 10%.
#
# @api private
#
# @param fraction
#   For example 0.412 or 0.004.
#
# @return [String]
#   For example `41%` or `0.4%`.
#
function openvox_tune::percent(
  Numeric $fraction,
) >> String {
  ($fraction < 0.1) ? {
    true    => sprintf('%.1f%%', $fraction * 100),
    default => "${round($fraction * 100)}%",
  }
}
