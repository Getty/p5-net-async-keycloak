#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use Future;
use HTTP::Response;
use Net::Async::Keycloak::Auth;

{
  package CaptivePortal;

  sub new { my ( $class, %arg ) = @_; return bless { count => 0, %arg }, $class }

  sub do_request {
    my ( $self, %arg ) = @_;
    $self->{count}++;
    my $response = HTTP::Response->new( 200, 'OK' );
    $response->header( 'Content-Type' => $self->{type} );
    $response->content( $self->{body} );
    return Future->done($response);
  }
}

for my $case (
  [ 'an HTML page'             => 'text/html',        '<html>please log in</html>' ],
  [ 'JSON without a token'     => 'application/json', '{"expires_in":300}' ],
  [ 'JSON with an empty token' => 'application/json', '{"access_token":"","expires_in":300}' ],
) {
  my ( $name, $type, $body ) = @$case;
  subtest "2xx with $name is a failed login" => sub {
    my $http = CaptivePortal->new( type => $type, body => $body );
    my $auth = Net::Async::Keycloak::Auth->new(
      http => $http, username => 'admin', password => 'admin',
      token_endpoint => 'http://kc.test/realms/master/protocol/openid-connect/token'
    );
    my $f = $auth->token_f;
    ok( $f->is_failed, 'the login future failed' );
    my $error = $f->failure;
    isa_ok( $error, 'WWW::Keycloak::Error::API', 'failure' );
    like( ref $error ? $error->message : '', qr/admin login failed: the token endpoint answered 200 without an access_token/, 'says no token was issued' );
    is( $http->{count}, 1, 'one request, no retry loop' );
    ok( !defined $auth->_access, 'no token cached' );
    my $again = $auth->token_f;
    ok( $again->is_failed, 'a later call asks again and fails again, the failed login is not shared' );
    is( $http->{count}, 2, 'one more request for the second call' );
  };
}

done_testing;
