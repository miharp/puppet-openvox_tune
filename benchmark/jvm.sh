#!/bin/bash
# Prints puppetserver's heap use and GC totals from its status service. Run
# as root on the server; run it twice, a minute apart, to see how much time a
# minute of load spends in GC.
set -uo pipefail
export PATH=/opt/puppetlabs/bin:$PATH
ssl=$(puppet config print ssldir --section agent)
cn=$(puppet config print certname --section agent)
curl -s --cert "$ssl/certs/$cn.pem" --key "$ssl/private_keys/$cn.pem" --cacert "$ssl/certs/ca.pem" \
  --resolve "${cn}:8140:127.0.0.1" "https://${cn}:8140/status/v1/services/status-service?level=debug" |
  /opt/puppetlabs/puppet/bin/ruby -rjson -e '
    j = JSON.parse($stdin.read)["status"]["experimental"]["jvm-metrics"]
    heap = j["heap-memory"]
    puts "#{Time.now.to_i} heap used #{heap["used"] / 1_048_576} MB of #{heap["max"] / 1_048_576}, " \
         "non-heap #{j["non-heap-memory"]["used"] / 1_048_576} MB"
    j["gc-stats"].each { |name, s| puts "  #{name}: count #{s["count"]}, total #{s["total-time-ms"]} ms" }'
