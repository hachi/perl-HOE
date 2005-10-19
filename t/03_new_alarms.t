#!/usr/bin/perl

use Test::More tests => 3;

my $i = 0;

use POE;
use POE::Session::Hachi;

POE::Session::Hachi->create(
	inline_states => {
		_start => sub {
			pass( "Startup" );
			$POE::KERNEL->delay_set( 'two', 2 );
			my $id = $POE::KERNEL->delay_set( 'one', 1 );
			$POE::KERNEL->alarm_remove( $id );
		},
		one => sub {
			fail( "Alarm Removal" );
		},
		two => sub {
			pass( "Delay Usage" );
			$POE::KERNEL->alarm_set( 'three', time + 1 );
		},
		three => sub {
			pass( "Alarm Usage" );
		},
	}
);

POE::Kernel->run();

# vim: filetype=perl
