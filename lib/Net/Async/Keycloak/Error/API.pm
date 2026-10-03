package Net::Async::Keycloak::Error::API;

# ABSTRACT: Net::Async::Keycloak's API error, a WWW::Keycloak::Error::API

use Moo;
extends 'WWW::Keycloak::Error::API', 'Net::Async::Keycloak::Error';

our $VERSION = '0.001';

=description

The same error as L<WWW::Keycloak::Error::API>, with the same attributes and
methods. It is both a L<WWW::Keycloak::Error::API> and a
L<Net::Async::Keycloak::Error>, so code written for the sync client catches it
unchanged.

=cut

1;
