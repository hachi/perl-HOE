#!/usr/bin/perl

use Test::Simple tests => 161;

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
			},
			_stop => sub {
				ok( ++$i == 3, "Destruction" );
			},
		}
	);
}

foreach (1..40) {
	buildit();
	POE::Kernel->run();
}
continue {
	ok( ++$i == 4, "Between Instances" );
	$i -= 4;
}

ok( ++$i == 1, "After All" );

# vim: filetype=perl
