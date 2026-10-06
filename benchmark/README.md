# Benchmark

Measures what the `openvox_tune::tune` plan's recommendation changes: how
many catalogs an OpenVox Server compiles per minute, and how long agents
wait, as the number of concurrent requests grows. Results are in
[results/](results/). This directory is not part of the module on the Forge.

**Don't run this against a production server.** It keeps the server's
JRubies busy for as long as it runs, so real agents queue behind it. With
PuppetDB, every compile also sends PuppetDB a catalog to store. To see how
much headroom a production server has, use the `openvox_tune::capacity`
plan, which reads the load the server already served and adds none.

## What it measures

A load generator, a separate host with an agent certificate, requests its
own catalog from the server over and over, with 1, 4, 8, 16, 24 and 32
requests in flight in turn. For each level, the analysis reports:

- catalogs per minute, and p50 and p95 latency, from the load generator;
- how long each request waited for a free JRuby and how long it held one
  compiling, from the `jruby.borrow-time` in the server's access log;
- the server's CPU use and puppetserver's memory, from a sampler on the
  server.

Catalogs are compiled, never applied, so the load generator needs only the
agent package.

## Files

- `site.pp`, `hiera.yaml`: the production environment's manifest and Hiera
  configuration. The load generator's catalog is a web and database host
  from puppetlabs-apache, puppetlabs-mysql and puppetlabs-firewall, about
  1,500 resources. The server's node block includes `openvox_tune`.
- `bench.sh`: runs on the load generator and logs every request.
- `cpu.sh`: runs on the server and logs CPU use and puppetserver's memory
  every 2 seconds.
- `jvm.sh`: prints puppetserver's heap use and GC totals, to check that a
  configuration isn't short of heap.
- `analyze.rb`: turns the logs into the tables in [results/](results/).

## Running it

On the server, with OpenVox Server and this module in the production
environment:

```shell
cd /etc/puppetlabs/code/environments/production
puppet module install puppetlabs-apache --environment production
puppet module install puppetlabs-mysql --environment production
puppet module install puppetlabs-firewall --environment production
cp /path/to/benchmark/site.pp manifests/site.pp     # set the server's certname in its node block
cp /path/to/benchmark/hiera.yaml hiera.yaml
mkdir -p data/nodes
systemd-run --unit bench-cpu --collect /path/to/benchmark/cpu.sh
```

On the load generator, install the agent, point it at the server, get its
certificate signed, and run the agent once, so the server has its facts:

```shell
puppet config set server puppet.example.com --section main
puppet ssl bootstrap
puppet agent -t --noop     # errors applying the catalog are expected; it is only compiled
```

Then warm up and measure each configuration. Labels starting with `warmup`
are left out of the tables:

```shell
./bench.sh warmup-default 300 16 && ./bench.sh default 120 1 4 8 16 24 32
```

To measure the recommendation, run the plan with `hiera=openvox_tune`, put
its output in `data/nodes/<server certname>.yaml`, and run the agent on the
server. The class restarts puppetserver 30 seconds after the run. Then
warm up and measure again under a new label. More JRubies take longer to
warm up, so repeat the levels once more straight after, under another
label, to see the warmed-up numbers.

Finally, collect `/var/tmp/bench/requests.log` and `levels.log` from the
load generator and `/var/tmp/bench/cpu.log` and
`/var/log/puppetlabs/puppetserver/puppetserver-access.log*` from the server
into one directory, and run:

```shell
ruby analyze.rb <directory>
```
