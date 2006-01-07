#!/usr/bin/perl

use Test::More tests => 8;

my $i = 0;

use POE;
use POE::Session::Hachi;

POE::Session::Hachi->create(
	inline_states => {
		_start => sub {
			ok( ++$i == 1, "Parent startup" );
			$POE::KERNEL->sig( 'KILL', 'signal' );
			$POE::KERNEL->yield( 'create_child' );
			$POE::KERNEL->delay( 'too_slow', 20 );
		},
		create_child => sub {
			ok( ++$i == 2, "Parent yield for child creation" );
			make_child();
		},
		_stop => sub {
			ok( ++$i == 8, "Parent Destruction" );
		},
		signal => sub {
			ok( ++$i == 6, "Parent signal" );
#			$POE::KERNEL->sig_handled()
		},
		too_slow => sub {
			fail( "Too Slow" );
			exit();
		},
	}
);

sub make_child {
	POE::Session::Hachi->create(
		inline_states => {
			_start => sub {
				ok( ++$i == 3, "Child startup" );
				$POE::KERNEL->sig( 'KILL', 'signal' );
				$POE::KERNEL->yield( 'yielding' );
				$POE::KERNEL->signal( $POE::KERNEL, 'KILL' );
				$POE::KERNEL->yield( 'yield_again' );
			},
			yielding => sub {
				ok( ++$i == 4, "Yield before signals" );
			},
			yield_again => sub {
				fail( "This shouldn't happen" );
			},
			signal => sub {
				ok( ++$i == 5, "Child signal" );
#				$POE::KERNEL->sig_handled();
			},
			_stop => sub {
				ok( ++$i == 7, "Child Destruction" );
			},
		}
	);
}

POE::Kernel->run();

# vim: filetype=perl
