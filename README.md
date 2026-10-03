# Net-Async-Keycloak

Async Perl client for [Keycloak](https://www.keycloak.org/) on IO::Async and
Future: the twin of [WWW::Keycloak](../p5-www-keycloak), with the same facade,
the same parts and every method as `_f` returning a future.

```perl
use IO::Async::Loop;
use Future::AsyncAwait;
use Net::Async::Keycloak;

my $loop = IO::Async::Loop->new;
my $kc   = Net::Async::Keycloak->new(
  base_url => 'https://id.example.org',
  realm    => 'main',
  username => 'admin',
  password => $ENV{KEYCLOAK_ADMIN_PASSWORD},
);
$loop->add($kc);

my $claims = await $kc->oidc->verify_token_f( $jwt, audience => 'my-api', type => 'Bearer' );
my $r      = await $kc->admin->ensure_client_f( clientId => 'cli', publicClient => \1 );
```

Requests are built and responses read by the same code as in WWW::Keycloak,
and the `ensure_*_f` methods compare with the same `WWW::Keycloak::Diff`, so
both clients do the same thing to a realm. Errors are
`Net::Async::Keycloak::Error::*`, each also the matching
`WWW::Keycloak::Error::*`.

Callers that need an admin token while a login is under way share that login.

Developed and live-tested against Keycloak 26.8.0.

## Live tests

```bash
KEYCLOAK_LIVE_TEST=1 KEYCLOAK_URL=http://localhost:8080 prove -lv t/90-live-keycloak.t
```

## License

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.
