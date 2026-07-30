# openvox_tune

A Bolt plan that recommends [OpenVox Server](https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html)
tuning settings based on a target's CPU count. Advisory only — it never
modifies a target, it just prints recommended values for you to apply via
Hiera or your provisioning tooling.

## Usage

```shell
bolt plan run openvox_tune::tune --targets puppet.example.com
```

Or from another Bolt project / control-repo that vendors this module via
`Puppetfile`:

```shell
bolt plan run openvox_tune::tune --targets <target-or-group>
```

Example output:

```
# puppet.example.com: 8 CPU(s)
jruby-puppet.max-active-instances: 7
JAVA_ARGS: -Xms4096m -Xmx4096m -XX:ReservedCodeCacheSize=1024m
```

## What it recommends and why

Formulas come directly from the [OpenVox Server Tuning
Guide](https://docs.openvoxproject.org/openvox-server/latest/tuning_guide.html):

| Setting | Formula |
| --- | --- |
| `jruby-puppet.max-active-instances` | `num-cpus - 1` (minimum 1) |
| JVM heap (`-Xms`/`-Xmx`) | `512MB + (max-active-instances × 512MB)` |
| `-XX:ReservedCodeCacheSize` | 512MB under 6 instances, 1GB for 6-12, 2GB above 12 |

Puppet Server's own built-in default already computes `num-cpus - 1`, but
clamps it to a maximum of 4 as a conservative, unsized default. This plan
recommends the same starting point *without* that cap, on the assumption
that you'll also apply the corresponding heap size — which is the entire
point of tuning past the out-of-the-box default on larger hardware.

## Limitations

- Covers Puppet Server only. It does not size PuppetDB, PostgreSQL, or any
  other service — those aren't covered by the tuning guide this plan
  implements.
- Does not check total system RAM or reserve memory for the OS/other
  services. The recommended heap must fit alongside everything else running
  on the node — verify that yourself before applying.
- CPU count comes from this module's own `openvox_tune::cpu_count` task
  (runs `nproc`), not the Forge `facts` module — kept deliberately
  dependency-free. Linux targets only, matching `metadata.json`'s
  `operatingsystem_support`.

## Testing

Plan tests use [`bolt_spec`](https://github.com/puppetlabs/bolt) (mocks
`run_task`/`run_plan` calls) on top of `voxpupuli-test` for fixtures and
`rspec` plumbing:

```shell
bundle install
bundle exec rake spec
```

## Publishing

This is not yet published to the Forge. `metadata.json`'s `name`, `author`,
`source`, `project_page`, and `issues_url` fields are placeholders — update
those before tagging a release.
