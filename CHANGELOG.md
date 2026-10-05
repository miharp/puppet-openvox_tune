# Changelog

Notable changes to openvox_tune are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The `openvox_tune::tune` plan: reads each target's CPU count and prints the
  `jruby-puppet.max-active-instances`, JVM heap and
  `-XX:ReservedCodeCacheSize` that the OpenVox Server tuning guide
  recommends for it, without the default cap of 4 JRuby instances. Advisory
  only; it changes nothing on the targets.
- The `openvox_tune::cpu_count` task, which the plan uses to read the CPU
  count with `nproc`.

[Unreleased]: https://github.com/miharp/puppet-openvox_tune/commits/main
