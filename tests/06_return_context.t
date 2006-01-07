#!/usr/bin/perl

use Test::More tests => 7;

my $i = 0;

use POE;
use POE::Session::Hachi;

my @contexts = qw(Scalar Array Void);

my @expected = qw(2 2 0 1 2);

{
	my $i = 0;
	sub check {
		my $number = shift;
		my $wanted = shift;
		my $context = defined( $wanted ) ? $wanted : 2;
		my $expected = shift @expected;

		ok( ++$i == $number and $context == $expected );
		diag( "Expected $contexts[$expected] got $contexts[$context]; i: $i number: $number" );
	}
}

POE::Session::Hachi->create(
	inline_states => {
		_start => sub {
			$POE::KERNEL->yield( 'one' );
		},
		one => sub {
			check( 1, wantarray );
			$POE::KERNEL->post( $POE::SESSION, 'two' );
		},
		two => sub {
			check( 2, wantarray );
			my $scalar = $POE::KERNEL->call( $POE::SESSION, 'three' );

			ok( $scalar eq 'Raccoon' );
			
			my @array = $POE::KERNEL->call( $POE::SESSION, 'four' );

			ok( @array == 3 );
			
			$POE::KERNEL->call( $POE::SESSION, 'five' );
		},
		three => sub {
			check( 3, wantarray );
			return "Raccoon";
		},
		four => sub {
			check( 4, wantarray );
			return qw(Apple Orange Pear);
		},
		five => sub {
			check( 5, wantarray );
		},
	}
);

POE::Kernel->run();

# vim: filetype=perl
