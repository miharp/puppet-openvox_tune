# Changelog

Notable changes to openvox_tune are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-06

### Added

- The `openvox_tune` class: applies the settings it is given, usually Hiera
  data from the plan's `hiera=openvox_tune` output, on servers no other
  module manages; it does not size the host itself. `heap_mb` and
  `reserved_code_cache_mb` set `-Xms`, `-Xmx` and
  `-XX:ReservedCodeCacheSize` in `JAVA_ARGS` with the `augeas` type the agent
  ships, keeping the other arguments, and `max_active_instances` sets
  `max-active-instances` in its own `conf.d/openvox_tune.conf`. It queues a
  restart of puppetserver shortly after the run when they change. It fails
  when another `conf.d` file sets `max-active-instances`, or when the host
  has less memory than 1.1 times `heap_mb`, since OpenVox Server refuses to
  start in either case.
- The `openvox_tune` fact: the memory available to OpenVox Server (capped by
  a container's limit), its `JAVA_ARGS`, and which `conf.d` files set each
  `jruby-puppet` setting.
- The `openvox_tune::tune` plan: reads each target's CPUs and memory and
  prints the `jruby-puppet.max-active-instances`, JVM heap and
  `-XX:ReservedCodeCacheSize` that the OpenVox Server tuning guide
  recommends for it, without the default cap of 4 JRuby instances, as many
  as fit in the memory left after a reserve for the operating system and
  other services (`reserved_memory_mb`, a quarter of memory by default) and
  pass the memory check OpenVox Server makes at startup (memory at least
  1.1 times the heap). Where OpenVox Server is installed it shows the current
  settings beside the recommendation and says when they already match, along
  with `environment_timeout`, pointing out the default of 0, and the
  `max-requests-per-instance`, `max-queued-requests` and `multithreaded`
  settings that are set. The
  heap per JRuby instance is the tuning guide's 512 MB, or
  `memory_per_jruby_mb`, or what the current settings give
  (`use_current_memory_per_jruby`). Run against a deployment with
  compilers (hosts whose CA service is disabled), it gives the server only
  1 to 4 instances, since the compilers compile the catalogs. With
  `hiera=openvox_tune` or `hiera=theforeman-puppet` it also prints the
  settings as Hiera data for the `openvox_tune` class or theforeman-puppet's
  `puppet` class, one block per set of values with the targets it is for, so
  that a fleet of compilers built alike gets one, and notes compilers that
  get different values; it returns both modules' data. It warns
  when a host is too small for one instance, and notes OpenVoxDB or
  PostgreSQL running on the same host. Advisory only; it changes nothing on
  the targets.
- The `openvox_tune::capacity` plan: adds up how long requests held a JRuby,
  from OpenVox Server's access logs over a window, and estimates from it how
  many nodes the servers can serve and how many JRubies the nodes need,
  with how busy the JRubies were on average and in the busiest time slot.
  Counts nodes across the server and its compilers. The
  `openvox_tune::jruby_load` task reads the logs, and the
  `openvox_tune::capacity` function does the arithmetic.
- The `openvox_tune::recommend` function, which does the sizing for given
  CPUs, memory, reserve, heap per JRuby instance and role.
- The `openvox_tune::host_resources` task, which the plan uses to read the
  CPUs and memory (capped by a container's CPU quota and memory limit), the
  OpenVoxDB and PostgreSQL services running on a target, and OpenVox
  Server's current heap, code cache, JRuby pool settings and
  `environment_timeout` (resolved as the server resolves it) and whether its
  CA service is enabled.
- OpenVox 8 and 9 on Debian 12 and 13, Ubuntu 22.04 and 24.04, and EL 8, 9
  and 10. The plans run with OpenBolt 5.

[Unreleased]: https://github.com/miharp/puppet-openvox_tune/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/miharp/puppet-openvox_tune/releases/tag/v0.1.0
