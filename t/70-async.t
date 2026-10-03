#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use Future;
use FakeKeycloak;
use Net::Async::Keycloak;

# A Net::Async::HTTP stand-in whose answers arrive only when the test says so,
# to see what happens while requests are under way.
{
  package DeferredHTTP;
  sub new { bless { fake => $_[1], queue => [] }, $_[0] }
  sub pending { scalar @{ $_[0]{queue} } }
  sub do_request {
    my ( $self, %arg ) = @_;
    my $future = Future->new;
    push @{ $self->{queue} }, [ $future, $arg{request} ];
    return $future;
  }
  sub answer_all {
    my ( $self ) = @_;
    while ( my $next = shift @{ $self->{queue} } ) { $next->[0]->done( $self->{fake}->request( $next->[1] ) ) }
    return;
  }
}

my $fake = FakeKeycloak->new;

subtest 'callers waiting for a token share one login' => sub {
  my $http = DeferredHTTP->new($fake);
  my $auth = Net::Async::Keycloak::Auth->new( http => $http, token_endpoint => $fake->base.'/realms/master/protocol/openid-connect/token', username => 'admin', password => 'admin' );
  @{ $fake->logins } = ();
  my @waiting = map { $auth->token_f } 1 .. 3;
  is( $http->pending, 1, 'three callers, one request' );
  ok( !$waiting[0]->is_ready, 'nobody has a token yet' );
  $http->answer_all;
  ok( !grep( { !$_->is_done } @waiting ), 'all three are served' );
  my %seen = map { $_->get => 1 } @waiting;
  is( scalar keys %seen, 1, 'with the same token' );
  is( scalar @{ $fake->logins }, 1, 'from one login' );
  is( $auth->token_f->get, $waiting[0]->get, 'and the next caller gets it at once' );
  is( $http->pending, 0, 'without a request' );
};

subtest 'a failed login does not stick' => sub {
  my $http = DeferredHTTP->new($fake);
  my $auth = Net::Async::Keycloak::Auth->new( http => $http, token_endpoint => $fake->base.'/realms/master/protocol/openid-connect/token', username => 'admin', password => 'nope' );
  my $first = $auth->token_f;
  $http->answer_all;
  ok( $first->is_failed, 'the login fails' );
  my $second = $auth->token_f;
  is( $http->pending, 1, 'the next caller tries again instead of getting the old failure' );
  $http->answer_all;
};

subtest 'requests run side by side' => sub {
  my $http  = DeferredHTTP->new($fake);
  my $kc    = Net::Async::Keycloak->new( base_url => $fake->base, realm => 'master', token => 'x', http => $http );
  $fake->{tokens}{x} = 1;
  my @calls = ( $kc->admin->get_realm_f, $kc->admin->list_clients_f, $kc->admin->list_users_f );
  is( $http->pending, 3, 'three requests are out at once' );
  $http->answer_all;
  ok( !grep( { !$_->is_done } @calls ), 'and all three complete' );
};

done_testing;
