#!/usr/bin/perl

use Test::Simple tests => 121;

my $i = 0;

use POE;
use POE::Session::Hachi;

sub buildit {
	POE::Session::Hachi->create(
		inline_states => {
			_start => sub {
				ok( ++$i == 1, "Startup" );
				$POE::KERNEL->yield( 'one' );
			},
			one => sub {
				ok( ++$i == 2, "One" );
				$POE::KERNEL->yield( 'two' );
				$POE::KERNEL->stop();
			},
			two => sub {
				die( "This should never get called" );
			},
			_stop => sub {
				die( "This should never get called" );
			},
		}
	);
}

foreach (1..40) {
	buildit();
	POE::Kernel->run();
}
continue {
	ok( ++$i == 3, "Between Instances" );
	$i -= 3;
}

ok( ++$i == 1, "After All" );

# vim: filetype=perl
