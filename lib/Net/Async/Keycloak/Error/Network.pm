package Net::Async::Keycloak::Error::Network;

# ABSTRACT: Net::Async::Keycloak's Network error, a WWW::Keycloak::Error::Network

use Moo;
extends 'WWW::Keycloak::Error::Network', 'Net::Async::Keycloak::Error';

our $VERSION = '0.002';

=description

The same error as L<WWW::Keycloak::Error::Network>, with the same attributes and
methods. It is both a L<WWW::Keycloak::Error::Network> and a
L<Net::Async::Keycloak::Error>, so code written for the sync client catches it
unchanged.

=cut

1;
