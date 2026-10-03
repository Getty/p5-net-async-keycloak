package Net::Async::Keycloak::Error::Validation;

# ABSTRACT: Net::Async::Keycloak's Validation error, a WWW::Keycloak::Error::Validation

use Moo;
extends 'WWW::Keycloak::Error::Validation', 'Net::Async::Keycloak::Error';

our $VERSION = '0.001';

=description

The same error as L<WWW::Keycloak::Error::Validation>, with the same attributes and
methods. It is both a L<WWW::Keycloak::Error::Validation> and a
L<Net::Async::Keycloak::Error>, so code written for the sync client catches it
unchanged.

=cut

1;
