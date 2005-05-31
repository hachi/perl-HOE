#!/usr/bin/perl

use Test::Simple tests => 5;

my $i = 0;

use POE;
use POE::Session;

POE::Session->create(
	inline_states => {
		_start => sub {
			ok( ++$i == 1, "Parent startup" );
			$_[KERNEL]->yield( 'create_child' );
		},
		create_child => sub {
			ok( ++$i == 2, "Parent yield for child creation" );
			make_child();
		},
		_stop => sub {
			ok( ++$i == 5, "Parent Destruction" );
		},
	}
);

sub make_child {
	POE::Session->create(
		inline_states => {
			_start => sub {
				ok( ++$i == 3, "Child startup" );
				$_[KERNEL]->yield( 'child_post' );
			},
			child_post => sub {
				ok( ++$i == 4, "Child Post" );
			},
		}
	);
}

POE::Kernel->run();

# vim: filetype=perl
