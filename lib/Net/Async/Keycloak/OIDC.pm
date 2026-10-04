package Net::Async::Keycloak::OIDC;

# ABSTRACT: OpenID Connect against one Keycloak realm, asynchronously

use Moo;
with 'Net::Async::Keycloak::Role::HTTP';
with 'WWW::Keycloak::Role::HTTP';
use Crypt::JWT qw( decode_jwt );
use Future;
use Future::AsyncAwait;
use Types::Standard qw( ArrayRef CodeRef Int Object Str );
use namespace::autoclean;

our $VERSION = '0.002';

=synopsis

    my $oidc   = $kc->oidc;
    my $claims = await $oidc->verify_token_f( $jwt, audience => 'my-api', type => 'Bearer' );
    my $tokens = await $oidc->password_token_f( client_id => 'cli', username => 'alice', password => $pw );

=description

The asynchronous L<WWW::Keycloak::OIDC>: the same methods with C<_f> and
futures. Token verification follows the same rules, including when the keys
are fetched again.

=cut

has issuer => ( is => 'ro', isa => Str, required => 1 );
has http   => ( is => 'ro', isa => Object, required => 1 );

=attr issuer

Required. C<< <base_url>/realms/<realm> >>.

=attr http

Required. The L<Net::Async::HTTP> to use.

=cut

has algorithms => (
  is      => 'ro',
  isa     => ArrayRef[Str],
  default => sub { [qw( RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512 )] }
);
has jwks_min_age => ( is => 'ro', isa => Int, default => 60 );
has now          => ( is => 'ro', isa => CodeRef, default => sub { sub { time } } );

=attr algorithms

=attr jwks_min_age

=attr now

As in L<WWW::Keycloak::OIDC>.

=cut

has _discovery    => ( is => 'rw' );
has _jwks         => ( is => 'rw' );
has _jwks_fetched => ( is => 'rw' );
has _in_flight    => ( is => 'ro', init_arg => undef, default => sub { {} } );

# One fetch for everybody who asks while it is under way, each with a view of
# its own so that cancelling one does not cancel the fetch.
sub _shared {
  my ( $self, $key, $start ) = @_;
  my $in_flight = $self->_in_flight;
  unless ( $in_flight->{$key} ) {
    my $future = $start->()->on_ready( sub { delete $in_flight->{$key} } );
    return $future if $future->is_ready;
    $in_flight->{$key} = $future;
  }
  return $in_flight->{$key}->without_cancel;
}

sub discovery_f {
  my ( $self ) = @_;
  return Future->done( $self->_discovery ) if $self->_discovery;
  return $self->_shared( discovery => sub { $self->_fetch_discovery_f } );
}

async sub _fetch_discovery_f {
  my ( $self ) = @_;
  my $data = ( await $self->send_request_f( GET => $self->issuer.'/.well-known/openid-configuration' ) )->{data};
  $self->validation_error_class->throw( message => 'discovery for '.$self->issuer.' returned no JSON object' ) unless ref $data eq 'HASH';
  return $self->_discovery($data);
}

=method discovery_f

The discovery document, fetched once.

=cut

async sub endpoint_f {
  my ( $self, $name ) = @_;
  my $url = ( await $self->discovery_f )->{$name};
  $self->validation_error_class->throw( message => 'the discovery document of '.$self->issuer.' has no '.$name ) unless defined $url;
  return $url;
}

=method endpoint_f

    my $url = await $oidc->endpoint_f('device_authorization_endpoint');

=cut

sub token_endpoint_f         { $_[0]->endpoint_f('token_endpoint') }
sub userinfo_endpoint_f      { $_[0]->endpoint_f('userinfo_endpoint') }
sub introspection_endpoint_f { $_[0]->endpoint_f('introspection_endpoint') }
sub end_session_endpoint_f   { $_[0]->endpoint_f('end_session_endpoint') }
sub device_endpoint_f        { $_[0]->endpoint_f('device_authorization_endpoint') }
sub jwks_uri_f               { $_[0]->endpoint_f('jwks_uri') }

sub jwks_f {
  my ( $self, %opt ) = @_;
  return Future->done( $self->_jwks ) if $self->_jwks && !$opt{force_refresh};
  return $self->_shared( jwks => sub {
    # counted from the start, so that verifications already under way see it
    $self->_jwks_fetched( $self->now->() );
    $self->_fetch_jwks_f;
  } );
}

async sub _fetch_jwks_f {
  my ( $self ) = @_;
  my $uri = await $self->jwks_uri_f;
  return $self->_jwks( ( await $self->send_request_f( GET => $uri ) )->{data} );
}

=method token_endpoint_f

=method userinfo_endpoint_f

=method introspection_endpoint_f

=method end_session_endpoint_f

=method device_endpoint_f

=method jwks_uri_f

A URL from the discovery document.

=method jwks_f

    my $keys = await $oidc->jwks_f( force_refresh => 1 );

Callers asking while a fetch is under way share it; so do callers of
L</discovery_f>.

=cut

async sub verify_token_f {
  my ( $self, $token, %opt ) = @_;
  $self->validation_error_class->throw( message => 'verify_token needs a token' ) unless defined $token && length $token;
  my %check = (
    token          => $token,
    verify_iss     => $self->issuer,
    verify_exp     => 1,
    accepted_alg   => $self->algorithms,
    decode_payload => 1,
    defined $opt{audience} ? ( verify_aud => $opt{audience} ) : ()
  );
  my $keys   = await $self->jwks_f;
  my $claims = eval { decode_jwt( %check, kid_keys => $keys ) };
  my $error  = $@;
  my $again  = $self->_in_flight->{jwks} || $self->now->() - ( $self->_jwks_fetched // 0 ) >= $self->jwks_min_age;
  if ( !$claims && $error =~ /kid_keys lookup failed/ && $again ) {
    $keys   = await $self->jwks_f( force_refresh => 1 );
    $claims = eval { decode_jwt( %check, kid_keys => $keys ) };
    $error  = $@;
  }
  $self->_reject( $error =~ s/ at \S+ line \d+.*//sr ) unless $claims;
  $self->_reject( 'typ is '.( $claims->{typ} // 'missing' ).', expected '.$opt{type} )
    if defined $opt{type} && ( $claims->{typ} // '' ) ne $opt{type};
  return $claims;
}

sub _reject {
  my ( $self, $why ) = @_;
  $self->validation_error_class->throw( message => 'token rejected: '.$why );
}

=method verify_token_f

    my $claims = await $oidc->verify_token_f( $jwt, audience => 'my-api', type => 'Bearer' );

=cut

async sub userinfo_f {
  my ( $self, $access_token ) = @_;
  return ( await $self->send_request_f( GET => await( $self->userinfo_endpoint_f ), bearer => $access_token ) )->{data};
}

async sub introspect_f {
  my ( $self, $token, %client ) = @_;
  return await $self->_token_call_f( await( $self->endpoint_f('introspection_endpoint') ), { token => $token }, %client );
}

sub password_token_f           { my ( $self, %arg ) = @_; $self->_grant_f( password => [qw( username password totp scope )], %arg ) }
sub client_credentials_token_f { my ( $self, %arg ) = @_; $self->_grant_f( client_credentials => ['scope'], %arg ) }
sub refresh_token_f            { my ( $self, $refresh, %arg ) = @_; $self->_grant_f( refresh_token => [qw( refresh_token scope )], %arg, refresh_token => $refresh ) }
sub exchange_authorization_code_f { my ( $self, %arg ) = @_; $self->_grant_f( authorization_code => [qw( code redirect_uri code_verifier )], %arg ) }
sub device_token_f             { my ( $self, %arg ) = @_; $self->_grant_f( 'urn:ietf:params:oauth:grant-type:device_code' => ['device_code'], %arg ) }

async sub device_authorization_f {
  my ( $self, %arg ) = @_;
  return await $self->_token_call_f( await( $self->device_endpoint_f ), { defined $arg{scope} ? ( scope => $arg{scope} ) : () }, %arg );
}

async sub logout_f {
  my ( $self, %arg ) = @_;
  await $self->_token_call_f( await( $self->endpoint_f('end_session_endpoint') ), { refresh_token => $arg{refresh_token} }, %arg );
  return 1;
}

=method userinfo_f

=method introspect_f

=method password_token_f

=method client_credentials_token_f

=method refresh_token_f

=method exchange_authorization_code_f

=method device_authorization_f

=method device_token_f

=method logout_f

As the methods without C<_f> in L<WWW::Keycloak::OIDC>, returning futures. A
pending device-flow poll fails with an API error whose C<oauth_error> is
C<authorization_pending>.

=cut

async sub _grant_f {
  my ( $self, $type, $fields, %arg ) = @_;
  return await $self->_token_call_f( await( $self->token_endpoint_f ),
    { grant_type => $type, map { $_ => $arg{$_} } grep { defined $arg{$_} } @$fields }, %arg );
}

async sub _token_call_f {
  my ( $self, $url, $form, %arg ) = @_;
  $self->validation_error_class->throw( message => 'a client_id is needed' ) unless defined $arg{client_id};
  my %form = ( %$form, client_id => $arg{client_id}, defined $arg{client_secret} ? ( client_secret => $arg{client_secret} ) : () );
  return ( await $self->send_request_f( POST => $url, form => \%form ) )->{data} // {};
}

1;
