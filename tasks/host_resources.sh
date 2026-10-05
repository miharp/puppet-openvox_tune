#!/usr/bin/env bash
set -euo pipefail

# CPUs: nproc honours CPU affinity and cpusets. A container started with a
# CPU quota (docker --cpus) still sees every CPU, so cap by a cgroup v2
# quota as well. The host's root cgroup has no cpu.max, so on a VM or bare
# metal this changes nothing.
cpus=$(nproc)
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r quota period < /sys/fs/cgroup/cpu.max
  if [ "$quota" != 'max' ]; then
    quota_cpus=$(( (quota + period - 1) / period ))
    [ "$quota_cpus" -lt "$cpus" ] && cpus=$quota_cpus
  fi
fi

# Memory: MemTotal, capped by a container's memory limit, since a container
# sees the host's /proc/meminfo. The host's root cgroup has no memory.max
# (v2) and an effectively unlimited memory.limit_in_bytes (v1).
memory_mb=$(( $(awk '/^MemTotal:/ { print $2 }' /proc/meminfo) / 1024 ))
for limit_file in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
  [ -r "$limit_file" ] || continue
  limit=$(cat "$limit_file")
  if [ "$limit" != 'max' ]; then
    limit_mb=$(( limit / 1048576 ))
    [ "$limit_mb" -lt "$memory_mb" ] && memory_mb=$limit_mb
  fi
  break
done

# Services that share the host's memory with OpenVox Server. OpenVoxDB keeps
# PuppetDB's service name. Only running units count: on Debian and Ubuntu,
# postgresql.service is an active but exited wrapper around the
# postgresql@<version>-<cluster> units that run the servers.
other_services=''
if command -v systemctl >/dev/null 2>&1; then
  for unit in $(systemctl list-units --type=service --state=running --no-legend --plain \
                  'puppetdb.service' 'postgresql*.service' 2>/dev/null | awk '{ print $1 }'); do
    other_services="${other_services:+$other_services,}\"${unit%.service}\""
  done
fi

printf '{"cpus":%d,"memory_mb":%d,"other_services":[%s]}\n' "$cpus" "$memory_mb" "$other_services"
