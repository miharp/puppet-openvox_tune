#!/bin/bash
# Catalog benchmark, run as root on the load generator:
#   bench.sh <label> <seconds per level> <level>...
# At each level, that many workers request this node's catalog from its
# configured server back to back for the given time. Every request is logged
# to /var/tmp/bench/requests.log as
#   <label> <level> <start epoch> <seconds> <http code>
# and each level's window to /var/tmp/bench/levels.log as
#   <label> <level> <start epoch> <end epoch>
# Labels starting with "warmup" are left out of the analysis.
set -uo pipefail
export PATH=/opt/puppetlabs/bin:$PATH
label=$1 secs=$2
shift 2

ssl=$(puppet config print ssldir --section agent)
cn=$(puppet config print certname --section agent)
server=$(puppet config print server --section agent)
environment=${BENCH_ENVIRONMENT:-production}
tls=(--cert "$ssl/certs/$cn.pem" --key "$ssl/private_keys/$cn.pem" --cacert "$ssl/certs/ca.pem")
url="https://${server}:8140/puppet/v3/catalog/${cn}?environment=${environment}"
mkdir -p /var/tmp/bench

worker() {
  local level=$1 end=$2 start
  while [ "$(date +%s)" -lt "$end" ]; do
    start=$(date +%s.%N)
    curl -s -o /dev/null --max-time 600 "${tls[@]}" -w "$label $level $start %{time_total} %{http_code}\n" "$url" \
      >> /var/tmp/bench/requests.log
  done
}

for level in "$@"; do
  begin=$(date +%s.%N)
  end=$(( $(date +%s) + secs ))
  for _ in $(seq 1 "$level"); do worker "$level" "$end" & done
  wait
  echo "$label $level $begin $(date +%s.%N)" >> /var/tmp/bench/levels.log
  echo "$label level $level done: $(awk -v l="$label" -v c="$level" '$1 == l && $2 == c' /var/tmp/bench/requests.log | wc -l) requests"
done
