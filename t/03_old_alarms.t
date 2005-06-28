#!/usr/bin/perl

use Test::Simple tests => 6;

my $i = 0;

use POE;
use POE::Session::Hachi;

POE::Session::Hachi->create(
	inline_states => {
		_start => sub {
			ok( ++$i == 1, "Startup" );
			$POE::KERNEL->delay( 'one', 1 );
			$POE::KERNEL->delay( 'one', 1 );
			$POE::KERNEL->alarm( 'one', time + 1 );
			$POE::KERNEL->delay( 'two', 2 );
		},
		one => sub {
			ok( ++$i == 2, "One" );
		},
		two => sub {
			$POE::KERNEL->delay( 'three', 1 );
			$POE::KERNEL->delay_add( 'three', 1 );
			$POE::KERNEL->alarm_add( 'three', time + 1 );
		},
		three => sub {
			++$i;
			ok( $i >= 3 and $i <= 5, "Parent yield for child creation" );
		},
		_stop => sub {
			ok( ++$i == 6, "Destruction" );
		},
	}
);

POE::Kernel->run();

# vim: filetype=perl
