# openvox_tune

[![CI](https://github.com/miharp/puppet-openvox_tune/actions/workflows/ci.yml/badge.svg)](https://github.com/miharp/puppet-openvox_tune/actions/workflows/ci.yml)
[![OpenBolt](https://img.shields.io/badge/OpenBolt-5-orange.svg)](https://github.com/OpenVoxProject/openbolt)
[![License](https://img.shields.io/github/license/miharp/puppet-openvox_tune)](https://github.com/miharp/puppet-openvox_tune/blob/main/LICENSE)

[![Puppet Forge](https://img.shields.io/puppetforge/v/miharp/openvox_tune)](https://forge.puppet.com/modules/miharp/openvox_tune)
[![Puppet Forge downloads](https://img.shields.io/puppetforge/dt/miharp/openvox_tune)](https://forge.puppet.com/modules/miharp/openvox_tune)

An [OpenBolt](https://github.com/OpenVoxProject/openbolt) plan that recommends
[OpenVox Server](https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html)
tuning settings based on a target's CPUs and memory. Advisory only: it
never modifies a target, it prints recommended values for you to apply via
Hiera or your provisioning tooling.

## Requirements

- [OpenBolt](https://github.com/OpenVoxProject/openbolt) 5
- Linux targets running OpenVox Server 8 or 9, reachable by OpenBolt

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

The plan also returns the values for each target, for use from another plan.
See [REFERENCE.md](https://github.com/miharp/puppet-openvox_tune/blob/main/REFERENCE.md)
for the plan's parameters and return value, and for the
`openvox_tune::recommend` function that does the sizing.

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

Regenerate `REFERENCE.md` after changing plan or task documentation:

```console
bundle exec rake strings:generate:reference
```
