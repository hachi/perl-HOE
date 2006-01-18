#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 205;

use POE;
use POE::Session::Hachi;

pass( "Before Create" );

POE::Session::Hachi->create(
	package_states => [
		main => [ qw(_start go chld _stop) ],
	],
	heap => {
		pids => {},
		child => 0,
	},
);

sub _start {
	pass( "Start" );
	$POE::KERNEL->sig( 'CHLD', 'chld' );
	$POE::KERNEL->yield( 'go' );
}

sub go {
	my $pids = $POE::HEAP->{pids};
	
	for my $count (1..100) {
		my $return = int( rand( 100 ) );
		my $fork = fork();

		if ($fork) {
			pass( "Parent ($$)!" );
			if (exists( $pids->{$fork} )) {
				fail( "Child PID already used" );
			}
			else {
				$pids->{$fork} = $return;
			}
		}
		elsif (defined( $fork )) {
			$POE::HEAP->{child} = 1;
			sleep( 2 );
			exit( $return );
		}
		else {
			fail( "Fork Failed!" );
		}
	}

	$POE::HEAP->{done} = 1;
}

sub chld {
	my $package = shift;
	my $pid = $_[1];
	my $return = $_[2] >> 8;

	my $pids = $POE::HEAP->{pids};

	if(exists( $pids->{$pid} )) {
		if($pids->{$pid} == $return) {
			pass( "Yay!" );
		}
		else {
			fail( "PID Return value was unexpected" );
		}
		delete( $pids->{$pid} );
	}
	else {
		fail( "Signal received for pid that was not forked" );
	}

	if (keys( %$pids ) == 0 and $POE::HEAP->{done}) {
		$POE::KERNEL->sig( 'CHLD' );
	}
	$POE::KERNEL->sig_handled();
}

sub _stop {
	if ($POE::HEAP->{child}) {
		fail( "This should not get called by a child." );
	}
	else {
		pass( "This should be called in the parent." );
	}
}

pass( "Before Run" );

POE::Kernel->run();

pass( "After Run" );

# vim: filetype=perl
