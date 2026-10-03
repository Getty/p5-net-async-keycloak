package Net::Async::Keycloak::Error;

# ABSTRACT: Exception base class for Net::Async::Keycloak

use Moo;
extends 'WWW::Keycloak::Error';

our $VERSION = '0.001';

=synopsis

    $kc->admin->get_client_f($id)->else( sub {
      my ( $error ) = @_;
      return Future->done(undef) if $error->isa('Net::Async::Keycloak::Error::API') && $error->is_not_found;
      return Future->fail($error);
    } );

=description

Failed futures of Net::Async::Keycloak fail with one of
L<Net::Async::Keycloak::Error::Validation>,
L<Net::Async::Keycloak::Error::Network> and
L<Net::Async::Keycloak::Error::API>. Each is also the matching
L<WWW::Keycloak::Error> class, and stringifies to its message.

=cut

1;
