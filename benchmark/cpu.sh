#!/bin/bash
# Logs the server's CPU use and puppetserver's memory every 2 seconds:
#   <epoch> <busy %> <steal %> <puppetserver RSS MB>
# to /var/tmp/bench/cpu.log. Run as root on the server, with systemd-run so
# it outlives the shell: systemd-run --unit bench-cpu --collect /root/cpu.sh
mkdir -p /var/tmp/bench
read -r _ u0 n0 s0 i0 w0 q0 sq0 st0 _ < /proc/stat
while sleep 2; do
  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
  tot=$(( (u1+n1+s1+i1+w1+q1+sq1+st1) - (u0+n0+s0+i0+w0+q0+sq0+st0) ))
  busy=$(( 100 * ((u1+n1+s1+q1+sq1) - (u0+n0+s0+q0+sq0)) / tot ))
  steal=$(( 100 * (st1 - st0) / tot ))
  pid=$(systemctl show -p MainPID --value puppetserver)
  rss=$(( $(ps -o rss= -p "$pid" 2>/dev/null || echo 0) / 1024 ))
  echo "$(date +%s) $busy $steal $rss" >> /var/tmp/bench/cpu.log
  u0=$u1 n0=$n1 s0=$s1 i0=$i1 w0=$w1 q0=$q1 sq0=$sq1 st0=$st1
done
