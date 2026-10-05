# Changelog

Notable changes to openvox_tune are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The `openvox_tune::tune` plan: reads each target's CPUs and memory and
  prints the `jruby-puppet.max-active-instances`, JVM heap and
  `-XX:ReservedCodeCacheSize` that the OpenVox Server tuning guide
  recommends for it, without the default cap of 4 JRuby instances, as many
  as fit in the memory left after a reserve for the operating system and
  other services (`reserved_memory_mb`, a quarter of memory by default) and
  pass the memory check OpenVox Server makes at startup (memory at least
  1.1 times the heap). Where OpenVox Server is installed it shows the current
  settings beside the recommendation and says when they already match. The
  heap per JRuby instance is the tuning guide's 512 MB, or
  `memory_per_jruby_mb`, or what the current settings give
  (`use_current_memory_per_jruby`). Run against a deployment with
  compilers (hosts whose CA service is disabled), it gives the server only
  1 to 4 instances, since the compilers compile the catalogs. With
  `hiera=true` it also prints the
  settings as Hiera data for theforeman-puppet's `puppet` class. It warns
  when a host is too small for one instance, and notes OpenVoxDB or
  PostgreSQL running on the same host. Advisory only; it changes nothing on
  the targets.
- The `openvox_tune::recommend` function, which does the sizing for given
  CPUs, memory, reserve, heap per JRuby instance and role.
- The `openvox_tune::host_resources` task, which the plan uses to read the
  CPUs and memory (capped by a container's CPU quota and memory limit), the
  OpenVoxDB and PostgreSQL services running on a target, and OpenVox
  Server's current heap, code cache and `max-active-instances` and whether
  its CA service is enabled.

[Unreleased]: https://github.com/miharp/puppet-openvox_tune/commits/main
