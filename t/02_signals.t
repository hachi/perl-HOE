#!/usr/bin/perl

use Test::Simple tests => 7;

my $i = 0;

use POE;
use POE::Session::Hachi;

POE::Session::Hachi->create(
	inline_states => {
		_start => sub {
			ok( ++$i == 1, "Parent startup" );
			$POE::KERNEL->sig( 'foo', 'signal' );
			$POE::KERNEL->yield( 'create_child' );
		},
		create_child => sub {
			ok( ++$i == 2, "Parent yield for child creation" );
			make_child();
		},
		_stop => sub {
			ok( ++$i == 7, "Parent Destruction" );
		},
		signal => sub {
			ok( ++$i == 5, "Parent signal" );
			$POE::KERNEL->sig_handled()
		},
	}
);

sub make_child {
	POE::Session::Hachi->create(
		inline_states => {
			_start => sub {
				ok( ++$i == 3, "Child startup" );
				$POE::KERNEL->sig( 'foo', 'signal' );
				$POE::KERNEL->signal( $POE::KERNEL, 'foo' );
			},
			signal => sub {
				ok( ++$i == 4, "Child signal" );
				$POE::KERNEL->sig_handled();
			},
			_stop => sub {
				ok( ++$i == 6, "Child Destruction" );
			},
		}
	);
}

POE::Kernel->run();

# vim: filetype=perl
