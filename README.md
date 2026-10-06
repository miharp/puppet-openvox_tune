# openvox_tune

[![CI](https://github.com/miharp/puppet-openvox_tune/actions/workflows/ci.yml/badge.svg)](https://github.com/miharp/puppet-openvox_tune/actions/workflows/ci.yml)
[![OpenVox compatible](https://img.shields.io/badge/OpenVox-8%20%7C%209-orange.svg)](https://voxpupuli.org/openvox/)
[![OpenBolt](https://img.shields.io/badge/OpenBolt-5-orange.svg)](https://github.com/OpenVoxProject/openbolt)
[![License](https://img.shields.io/github/license/miharp/puppet-openvox_tune)](https://github.com/miharp/puppet-openvox_tune/blob/main/LICENSE)

[![Puppet Forge](https://img.shields.io/puppetforge/v/miharp/openvox_tune)](https://forge.puppet.com/modules/miharp/openvox_tune)
[![Puppet Forge downloads](https://img.shields.io/puppetforge/dt/miharp/openvox_tune)](https://forge.puppet.com/modules/miharp/openvox_tune)

Sizes [OpenVox Server](https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html):
JRuby instances, JVM heap and reserved code cache, from the tuning guide and
the host's CPUs and memory.

- The `openvox_tune::tune` [OpenBolt](https://github.com/OpenVoxProject/openbolt)
  plan recommends the settings, beside the ones in force, and changes
  nothing.
- The `openvox_tune` class applies the values you commit to Hiera, on
  servers no other module manages. It never sizes a host itself, so a
  server's settings change only when its data does.
- The `openvox_tune::capacity` plan estimates how many nodes the servers can
  serve, from the load they served.

## Requirements

- OpenVox Server 8 or 9 on Linux.
- For the plans, [OpenBolt](https://github.com/OpenVoxProject/openbolt) 5,
  with the servers reachable as targets.

## Installing

Pin a release in your Bolt project's `Puppetfile`, from the
[Forge](https://forge.puppet.com/modules/miharp/openvox_tune):

```ruby
mod 'miharp-openvox_tune', '0.1.0'
```

or add it to `bolt-project.yaml` and run `bolt module install`:

```yaml
modules:
  - name: miharp-openvox_tune
```

## Usage

```shell
bolt plan run openvox_tune::tune --targets puppet.example.com
```

Example output:

```text
# puppet.example.com: 8 CPU(s), 15345 MB memory, 3836 MB reserved
# Current: 4 instances (default), 2048m heap, JVM default code cache, 384 MB heap per instance
jruby-puppet.max-active-instances: 7
JAVA_ARGS: -Xms4096m -Xmx4096m -XX:ReservedCodeCacheSize=1024m
```

The `Current:` line shows what OpenVox Server runs with now: the heap and
code cache from `JAVA_ARGS` in `/etc/sysconfig/puppetserver` or
`/etc/default/puppetserver`, and `max-active-instances` from
`/etc/puppetlabs/puppetserver/conf.d`, or the default it gets when that is
not set. The heap per instance is worked out with the tuning guide's
formula, `(heap - 512 MB) / instances`. When the current settings already
match, the plan says so.

An `Other settings:` line shows `environment_timeout`, and
`max-requests-per-instance`, `max-queued-requests` and `multithreaded`
where they are set. An `environment_timeout` of 0, the default, makes every
catalog compile read the environment's code from disk again, so the plan
points it out: set it to `unlimited` in `puppet.conf`'s `[server]` section
and flush the cache after each code deploy with the `environment-cache` API.
The plan reads `environment_timeout` the way OpenVox Server does;
`puppet config print environment_timeout --section server` ignores a value
in `[server]` and reports `[main]`'s or the default. With `multithreaded`
on, all instances share one JRuby, and the plan's sizing, which assumes one
JRuby per instance, overstates the heap.

By default a quarter of each target's memory is left for the operating
system. When OpenVoxDB, PostgreSQL or anything else large shares the host,
reserve room for it as well; the plan points this out when it finds
OpenVoxDB or PostgreSQL running:

```shell
bolt plan run openvox_tune::tune --targets puppet.example.com reserved_memory_mb=6144
```

Each JRuby instance is given the tuning guide's 512 MB of heap. Code with
many modules or a lot of Hiera data can need more; set it with
`memory_per_jruby_mb`, or keep what the servers have now with
`use_current_memory_per_jruby` (never less than 512 MB):

```shell
bolt plan run openvox_tune::tune --targets puppet.example.com memory_per_jruby_mb=1024
bolt plan run openvox_tune::tune --targets puppet.example.com use_current_memory_per_jruby=true
```

### Deployments with compilers

Run the plan against the server and its compilers together:

```shell
bolt plan run openvox_tune::tune --targets puppet.example.com,compiler01.example.com,compiler02.example.com
```

A host whose CA service is disabled in
`/etc/puppetlabs/puppetserver/services.d/ca.cfg` is a compiler, as
[ovadm](https://forge.puppet.com/modules/miharp/ovadm) and theforeman-puppet
set them up, and is sized like any server. When the run includes a
compiler, the server is sized as a server with compilers: the compilers
compile the catalogs, so it keeps 1 JRuby instance below 4 CPUs, 2 below 16
and 4 from 16, and leaves the rest of its memory to OpenVoxDB and
PostgreSQL. Certificate requests do not use JRuby instances, so the server's
instances only compile catalogs for agents that still point at it, such as
its own and the compilers'. This assumes the other agents get their
catalogs from the compilers, through a load balancer as in ovadm's Large
topology. Run against the server alone, it is sized as a standalone server.

### Servers managed by theforeman-puppet

If [theforeman-puppet](https://forge.puppet.com/modules/theforeman/puppet)
manages the server, changes made by hand are reverted on its next run. Pass
`hiera=theforeman-puppet` to also get the settings as Hiera data for that
module's `puppet` class, to commit to the server's node data:

```shell
bolt plan run openvox_tune::tune --targets puppet.example.com hiera=theforeman-puppet
```

```yaml
# Hiera for theforeman-puppet. Setting server_jvm_extra_args replaces the module's own
# -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger, so it is repeated here; add any other arguments you pass.
puppet::server_max_active_instances: 7
puppet::server_jvm_min_heap_size: 4096m
puppet::server_jvm_max_heap_size: 4096m
puppet::server_jvm_extra_args:
  - '-Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger'
  - '-XX:ReservedCodeCacheSize=1024m'
```

theforeman-puppet adds the `-Djruby.logger.class` argument only while
`puppet::server_jvm_extra_args` is unset, so the data repeats it. If you
already set `puppet::server_jvm_extra_args`, merge the code cache argument
into your list instead.

The plan also returns the values for each target, for use from another plan.
See [REFERENCE.md](https://github.com/miharp/puppet-openvox_tune/blob/main/REFERENCE.md)
for the plan's parameters and return value, and for the
`openvox_tune::recommend` function that does the sizing.

## Applying the settings

The `openvox_tune` class applies the settings you give it, and nothing else:
it does not size the host, so a server's settings change only when its data
does, through your usual review. Get the values from the plan with
`hiera=openvox_tune`. Run it against the whole deployment; targets that get
the same values share one block:

```shell
bolt plan run openvox_tune::tune --targets puppet.example.com,compiler01.example.com,compiler02.example.com,compiler03.example.com hiera=openvox_tune
```

```text
# Hiera for the openvox_tune class.
# For puppet.example.com:
openvox_tune::max_active_instances: 2
openvox_tune::heap_mb: 1536
openvox_tune::reserved_code_cache_mb: 512
# For compiler01.example.com, compiler02.example.com, compiler03.example.com (3 targets):
openvox_tune::max_active_instances: 7
openvox_tune::heap_mb: 4096
openvox_tune::reserved_code_cache_mb: 1024
```

Commit each block at a level of your hierarchy that the targets it lists
share. Compilers built alike, as these are with 8 CPUs and 16 GB of memory
each, get one set of values, so however many there are, it goes in once, at
a level for all of them such as their role. The server's goes in its node
data. With a control repo `hiera.yaml` that has a level by role, here from
the `pp_role` certificate extension:

```yaml
---
version: 5
defaults:
  datadir: data
  data_hash: yaml_data
hierarchy:
  - name: Per-node data
    path: nodes/%{trusted.certname}.yaml
  - name: Per-role data
    path: roles/%{trusted.extensions.pp_role}.yaml
  - name: Common data
    path: common.yaml
```

the compilers' block goes in `data/roles/compiler.yaml` and the server's in
`data/nodes/puppet.example.com.yaml`. Node data overrides role data, so a
compiler that differs can have its own.

When the compilers in the run do not all get the same values, the plan
prints a block for each set and notes it. Values sized for a larger compiler
can be too much for a smaller one; the class refuses a heap the host cannot
start with, but not every mismatch. Build the compilers alike, or give the
odd ones node data of their own. The module ships no Hiera data of its own,
since values there would apply to every host that includes the class.

Assign the class to the server and the compilers:

```puppet
include openvox_tune
```

`heap_mb` sets `-Xms` and `-Xmx`, and `reserved_code_cache_mb` sets
`-XX:ReservedCodeCacheSize`, in `JAVA_ARGS`, keeping the other arguments.
`max_active_instances` sets `jruby-puppet.max-active-instances` in a file
of its own, `/etc/puppetlabs/puppetserver/conf.d/openvox_tune.conf`, so the
package's `puppetserver.conf` is left alone. Each is optional: without
`heap_mb` or `reserved_code_cache_mb` that part of `JAVA_ARGS` is left as it
is, and without `max_active_instances` the class removes its file and the
server's default applies. The plan always gives all three, sized together;
set them together.

When a setting changes, the class queues a restart of puppetserver for 30
seconds later (`restart_delay`), so that a server applying its own catalog
finishes the run, report included, first. With `restart => false` the
settings apply at the next restart.

The class fails rather than leave puppetserver unable to restart:

- OpenVox Server refuses to start when two files in `conf.d` set the same
  setting. If another file already sets `max-active-instances`, by hand or
  through theforeman-puppet, whose template writes all of
  `puppetserver.conf`, the class says which. Use either this class or
  theforeman-puppet on a server, not both.
- OpenVox Server refuses to start with less memory than 1.1 times its heap.
  If the host has less, for example after being resized, the class says so
  instead of applying `heap_mb`. Run the plan again for new values.

Where OpenVox Server is not installed, the class does nothing and logs a
warning. It needs only what the agent ships: the `augeas` type, from its
vendored `augeas_core` module, for `JAVA_ARGS`, and the `openvox_tune` fact
for the host's memory and current settings.

## Capacity

`openvox_tune::capacity` estimates how many nodes the servers can serve,
from the load they actually served. Run it against the server and all its
compilers together:

```shell
bolt plan run openvox_tune::capacity --targets puppet.example.com,compiler01.example.com
```

```text
# puppet.example.com: 4 JRubies, 50000 requests (48000 held a JRuby); busy 10% on average, 24% at the busiest.

# Capacity over the last 24 h, from the access logs of 1 server:
# 300 nodes requested catalogs, every 30 min (median); each run held JRubies for 2.40 s in total.
# JRubies busy 10% on average, 24% in the busiest 5 minutes (from 2026-10-05 14:30 UTC).
# At this rate the 4 JRubies can serve about 3000 nodes; the nodes seen need at least 1 JRuby.
```

OpenVox Server's access log records how long every request held a JRuby
(`jruby.borrow-time` in `request-logging.xml`). The plan adds that up over
`window_hours` (24 by default; the logs are kept for up to 90 days), finds
the busiest `bucket_minutes` slot, and counts the nodes that requested
catalogs and how often they did. Little's law then gives the estimate: each
run holds JRubies for the time shown, catalog, file metadata and report
together, so the JRubies can serve their count times the run interval over
that time. Nodes are counted across all the targets, since a load balancer
sends one node's runs to different compilers.

The estimate counts only load that was served. Requests turned away with
503 because `max-queued-requests` was reached are counted and pointed out,
and a run interval longer than the window cannot be measured, so the plan
then uses `runinterval` instead. A window that spans a change of settings
or code blends the two; narrow it with `window_hours`. Reading the logs
needs root or the puppet user, and the plan only understands the access log
pattern OpenVox Server ships.

## What it recommends and why

Formulas come directly from the [OpenVox Server Tuning
Guide](https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html):

| Setting | Formula |
| --- | --- |
| `jruby-puppet.max-active-instances` | `num-cpus - 1` (minimum 1) |
| JVM heap (`-Xms`/`-Xmx`) | `512MB + (max-active-instances × 512MB)` |
| `-XX:ReservedCodeCacheSize` | 512MB under 6 instances, 1GB for 6-12, 2GB above 12 |

OpenVox Server's own built-in default already computes `num-cpus - 1`, but
clamps it to a maximum of 4 as a conservative, unsized default. This plan
recommends the same starting point *without* that cap, on the assumption
that you'll also apply the corresponding heap size, which is the entire
point of tuning past the out-of-the-box default on larger hardware.

The instance count is then lowered until the heap and the code cache fit in
the memory left after the reserve, and the plan says so when memory is the
limit. The heap also stays within the host's memory divided by 1.1:
OpenVox Server checks that at startup and exits when the heap is larger.

On a host too small for even one instance, the plan still recommends one
(a 1024 MB heap) and prints a warning. That is still worth applying: the
packaged 2 GB heap fails the startup check on any host with less than about
2.2 GB of memory, so OpenVox Server does not start there at all until the
heap is lowered.

## Limitations

- Covers OpenVox Server only. It does not size OpenVoxDB, PostgreSQL, or any
  other service; those aren't covered by the tuning guide this plan
  implements.
- It does not know how much memory other services need. It reserves a
  quarter of memory for the operating system unless you pass
  `reserved_memory_mb`.
- It reads `environment_timeout` from `puppet.conf` only; an environment's
  `environment.conf` can override it for that environment.
- CPUs and memory come from this module's own `openvox_tune::host_resources`
  task (`nproc` and `/proc/meminfo`, capped by a container's CPU quota and
  memory limit), not the Forge `facts` module, so the module has no
  dependencies. Linux targets only.

## Development

Plan tests use [`bolt_spec`](https://github.com/OpenVoxProject/openbolt)
(mocks `run_task`/`run_plan` calls) and function tests use rspec-puppet, both
on top of `voxpupuli-test`. Run the same checks as CI with the local bundle
(Ruby 3.2):

```console
bundle install
bundle exec rake validate lint check rubocop parallel_spec
```

Those tests give the plan made-up task results. The specs in
`spec/container` run the `host_resources` task, and the plan through Bolt's
Docker transport, against containers with real `openvox-server` packages
installed but not started. CI runs them on Ubuntu 24.04 and Rocky 9 with
OpenVox 8 and 9. Locally, with Docker:

```console
docker build -t openvox-tune-test -f spec/container/Dockerfile.deb \
  --build-arg BASE=ubuntu:24.04 \
  --build-arg RELEASE=https://apt.voxpupuli.org/openvox8-release-ubuntu24.04.deb \
  spec/container
CONTAINER_IMAGE=openvox-tune-test BASE_IMAGE=ubuntu:24.04 bundle exec rspec spec/container
```

Use `spec/container/Dockerfile.rpm` with a `rockylinux:9` base and a
`yum.voxpupuli.org` release package for the EL side.

Regenerate `REFERENCE.md` after changing plan or task documentation:

```console
bundle exec rake strings:generate:reference
```
