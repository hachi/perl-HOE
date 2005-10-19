#!/usr/bin/perl

use strict;
use warnings;

use Test::Simple tests => 3;

my $i = 0;

use POE;
use POE::Session::Hachi;

POE::Session::Hachi->create(
	inline_states => {
		_start => sub {
			ok( $POE::SENDER == $POE::KERNEL, "First born child's parent" );
			$POE::KERNEL->yield( 'one' );
			another( $POE::HEAP->{token} = [] );
		},
		_child => sub {
			if ($_[0] eq 'create') {
				ok( $_[2] == $POE::HEAP->{token}, "Child Token" ) ;
			}
		}
	}
);

sub another {
	my $token = shift; # Magic token
	POE::Session::Hachi->create(
		inline_states => {
			_start => sub {
				if (defined( wantarray ) && wantarray) {
					ok( 0, "Child called in array context" );
				}
				elsif( defined( wantarray )) {
					ok( 1, "Child called in scalar context" );
				}
				else {
					ok( 0, "Child called in void context" );
				}
				return $token;
			},
		}
	);
}

POE::Kernel->run();

# vim: filetype=perl
