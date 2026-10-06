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

  # The rest needs the Ruby the agent ships: the jruby-puppet settings from
  # conf.d, which is HOCON, and environment_timeout from puppet.conf. Bolt
  # puts lib/puppet_x/openvox_tune/server_settings.rb under $PT__installdir
  # (see the metadata).
  unknown='"max_active_instances":null,"max_requests_per_instance":null,"max_queued_requests":null,"multithreaded":null,"environment_timeout":null'
  server_settings=$unknown
  ruby=/opt/puppetlabs/puppet/bin/ruby
  settings_rb="${PT__installdir:-}/openvox_tune/lib/puppet_x/openvox_tune/server_settings.rb"
  if [ -x "$ruby" ] && [ -r "$settings_rb" ]; then
    server_settings=$("$ruby" "$settings_rb" /etc/puppetlabs/puppetserver/conf.d 2>/dev/null) || server_settings=$unknown
    [ -n "$server_settings" ] || server_settings=$unknown
  fi

  # Whether this host is a CA or a compiler. Compilers comment out the CA
  # service in services.d/ca.cfg and enable the disabled one instead (ovadm
  # and theforeman-puppet both do); without ca.cfg it is unknown.
  ca_enabled=''
  ca_cfg=/etc/puppetlabs/puppetserver/services.d/ca.cfg
  if grep -q '^[[:space:]]*puppetlabs\.services\.ca\.certificate-authority-service/' "$ca_cfg" 2>/dev/null; then
    ca_enabled=true
  elif grep -q '^[[:space:]]*puppetlabs\.services\.ca\.certificate-authority-disabled-service/' "$ca_cfg" 2>/dev/null; then
    ca_enabled=false
  fi

  puppetserver=$(printf '{"defaults_file":"%s","xms_mb":%s,"xmx_mb":%s,"code_cache_mb":%s,"ca_enabled":%s,%s}' \
    "$defaults" "$(json_number "$xms")" "$(json_number "$xmx")" "$(json_number "$code_cache")" \
    "$(json_number "$ca_enabled")" "$server_settings")
fi

printf '{"cpus":%d,"memory_mb":%d,"other_services":[%s],"puppetserver":%s}\n' \
  "$cpus" "$memory_mb" "$other_services" "$puppetserver"
