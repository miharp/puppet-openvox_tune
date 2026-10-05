# openvox_tune

[![CI](https://github.com/miharp/puppet-openvox_tune/actions/workflows/ci.yml/badge.svg)](https://github.com/miharp/puppet-openvox_tune/actions/workflows/ci.yml)
[![OpenBolt](https://img.shields.io/badge/OpenBolt-5-orange.svg)](https://github.com/OpenVoxProject/openbolt)
[![License](https://img.shields.io/github/license/miharp/puppet-openvox_tune)](https://github.com/miharp/puppet-openvox_tune/blob/main/LICENSE)

[![Puppet Forge](https://img.shields.io/puppetforge/v/miharp/openvox_tune)](https://forge.puppet.com/modules/miharp/openvox_tune)
[![Puppet Forge downloads](https://img.shields.io/puppetforge/dt/miharp/openvox_tune)](https://forge.puppet.com/modules/miharp/openvox_tune)

An [OpenBolt](https://github.com/OpenVoxProject/openbolt) plan that recommends
[OpenVox Server](https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html)
tuning settings based on a target's CPU count. Advisory only: it never
modifies a target, it prints recommended values for you to apply via Hiera
or your provisioning tooling.

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
# puppet.example.com: 8 CPU(s)
jruby-puppet.max-active-instances: 7
JAVA_ARGS: -Xms4096m -Xmx4096m -XX:ReservedCodeCacheSize=1024m
```

The plan also returns the values for each target, for use from another plan.
See [REFERENCE.md](https://github.com/miharp/puppet-openvox_tune/blob/main/REFERENCE.md)
for the plan's parameters and return value.

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

## Limitations

- Covers OpenVox Server only. It does not size OpenVoxDB, PostgreSQL, or any
  other service; those aren't covered by the tuning guide this plan
  implements.
- Does not check total system RAM or reserve memory for the OS or other
  services. The recommended heap must fit alongside everything else running
  on the node, so verify that yourself before applying.
- CPU count comes from this module's own `openvox_tune::cpu_count` task
  (runs `nproc`), not the Forge `facts` module, so the module has no
  dependencies. Linux targets only.

## Development

Plan tests use [`bolt_spec`](https://github.com/OpenVoxProject/openbolt)
(mocks `run_task`/`run_plan` calls) on top of `voxpupuli-test`. Run the same
checks as CI with the local bundle (Ruby 3.2):

```console
bundle install
bundle exec rake validate lint check rubocop parallel_spec
```

Regenerate `REFERENCE.md` after changing plan or task documentation:

```console
bundle exec rake strings:generate:reference
```
