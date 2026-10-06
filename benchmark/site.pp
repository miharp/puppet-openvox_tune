# openvox_tune benchmark. The server applies the openvox_tune class from its
# node data; the load generator's catalog, a web and database host, is only
# compiled, never applied.
node 'puppet.example.com' {
  include openvox_tune
}

node default {
  class { 'apache':
    default_vhost => false,
    mpm_module    => 'event',
  }
  Integer[1, 40].each |Integer $i| {
    apache::vhost { "site${i}.example.com":
      port          => 443,
      ssl           => true,
      docroot       => "/var/www/site${i}",
      serveraliases => ["www.site${i}.example.com"],
      proxy_pass    => [{ 'path' => '/api', 'url' => "http://127.0.0.1:${8000 + $i}/" }],
      headers       => ['always set Strict-Transport-Security "max-age=63072000"'],
      rewrites      => [{ 'rewrite_rule' => ['^/old/(.*)$ /new/$1 [R=301,L]'] }],
    }
  }

  class { 'mysql::server':
    root_password    => 'lab-only',
    override_options => { 'mysqld' => { 'max_connections' => 500 } },
  }
  Integer[1, 20].each |Integer $i| {
    mysql::db { "app${i}":
      user     => "app${i}",
      password => "lab-only-${i}",
      host     => 'localhost',
      grant    => ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
    }
  }

  Integer[1, 40].each |Integer $i| {
    firewall { sprintf('%03d allow site %d', 100 + $i, $i):
      dport => 8000 + $i,
      proto => 'tcp',
      jump  => 'accept',
    }
  }
}
