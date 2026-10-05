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

# OpenVox Server's current settings, when it is installed: the heap and code
# cache from JAVA_ARGS in the defaults file, and an explicit
# jruby-puppet.max-active-instances from conf.d. A setting that is not there
# is reported as null.
json_number() { if [ -n "$1" ]; then printf '%s' "$1"; else printf 'null'; fi; }

to_mb() {
  local value=$1 number=${1%[kKmMgG]}
  case $value in
    *[gG]) echo $(( number * 1024 )) ;;
    *[mM]) echo "$number" ;;
    *[kK]) echo $(( number / 1024 )) ;;
    *)     echo $(( number / 1048576 )) ;;
  esac
}

puppetserver='null'
defaults=/etc/default/puppetserver
[ -r "$defaults" ] || defaults=/etc/sysconfig/puppetserver
if [ -r "$defaults" ]; then
  # Read JAVA_ARGS as the service and the puppetserver CLI do: by sourcing
  # the file. For repeated options the JVM takes the last one, as here.
  # shellcheck source=/dev/null
  java_args=$(set +eu; . "$defaults" >/dev/null 2>&1; printf '%s' "${JAVA_ARGS:-}") || true
  xms='' xmx='' code_cache=''
  for arg in $java_args; do
    case $arg in
      -Xms[0-9]*) xms=$(to_mb "${arg#-Xms}") ;;
      -Xmx[0-9]*) xmx=$(to_mb "${arg#-Xmx}") ;;
      -XX:ReservedCodeCacheSize=[0-9]*) code_cache=$(to_mb "${arg#*=}") ;;
    esac
  done

  # conf.d is HOCON, so read it with the hocon gem the agent ships rather
  # than with grep.
  max_active=''
  ruby=/opt/puppetlabs/puppet/bin/ruby
  confd=/etc/puppetlabs/puppetserver/conf.d
  if [ -x "$ruby" ] && [ -d "$confd" ]; then
    max_active=$("$ruby" -e '
      require "hocon"
      value = nil
      Dir.glob(File.join(ARGV[0], "*.conf")).sort.each do |file|
        found = (Hocon.load(file).dig("jruby-puppet", "max-active-instances") rescue nil)
        value = found unless found.nil?
      end
      print Integer(value) unless value.nil?
    ' "$confd" 2>/dev/null) || max_active=''
  fi

  puppetserver=$(printf '{"defaults_file":"%s","xms_mb":%s,"xmx_mb":%s,"code_cache_mb":%s,"max_active_instances":%s}' \
    "$defaults" "$(json_number "$xms")" "$(json_number "$xmx")" "$(json_number "$code_cache")" "$(json_number "$max_active")")
fi

printf '{"cpus":%d,"memory_mb":%d,"other_services":[%s],"puppetserver":%s}\n' \
  "$cpus" "$memory_mb" "$other_services" "$puppetserver"
