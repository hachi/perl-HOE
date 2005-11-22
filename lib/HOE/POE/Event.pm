package POE::Event;

use strict;
use POE::Callstack qw(POP PUSH);

use HOE;

BEGIN {
	our @_ELEMENTS = qw(KERNEL TIME FROM TO NAME ARGS);
	my $i = 0;
	foreach my $element (@_ELEMENTS) {
		eval "sub $element () { $i }";
		$i++;
	}
}

unless( exists( $ENV{HOE_NOXS} ) and $ENV{HOE_NOXS} ) {
	eval {
		require XSLoader;
		local $^W = 0;
		XSLoader::load('HOE', $HOE::XS_VERSION);
	} or warn( "XS Failed to load: $@\n" );
}
else {
	warn( "Skipping HOE XS load via environment HOE_NOXS=$ENV{HOE_NOXS}\n" );
}

use overload (
	"<=>"	=> sub {
		return $_[0]->[TIME] <=> $_[1]->[TIME];
	},
	fallback => 1,
);

sub DEBUG {
	print @_;
}

sub DEBUGGING () { 0 }

sub new {
#	my $class = shift;
#	my $kernel = shift;
#	my $when = shift;
#	my $from = shift;
#	my $to = shift; # Resolution does nasty things, figure out where it belongs later (used to be here)
#	my $name = shift;
#	my $args = shift;

	return bless [
		$_[1],  # KERNEL
		$_[2],    # TIME
		$_[3],    # FROM
		$_[1]->resolve_session( $_[4] ),      # TO
		$_[5],    # NAME
		$_[6],    # ARGS
	], (ref $_[0] || $_[0]);
}

sub dispatch {
	my $self = shift;

	my $return;
	my @return;

	my $wantarray = wantarray;

	{	# Wrap this baby in a magical scope so destruction happens in a timely manner... yes
	
		#my $to = $self->[KERNEL]->resolve_session( $self->[TO] );
		my $to = $self->[TO];

		DEBUG "[DISPATCH] Event dispatching From: $self->[FROM] To: $to Event: $self->[NAME]\n" if DEBUGGING;
		
		# push inside, so we know the $to

		PUSH( $to, $self->[NAME] );

		if (defined( $wantarray )) {
			if ($wantarray) {
				@return = $to->_invoke_state( $self->[FROM], $self->[NAME], $self->[ARGS] );
			}
			else {
				$return = $to->_invoke_state( $self->[FROM], $self->[NAME], $self->[ARGS] );
			}
		}
		else {
			$to->_invoke_state( $self->[FROM], $self->[NAME], $self->[ARGS] );
		}

		# Magic scope manipulation, destruct all the related things while we are still
		# in teh context of a session (before POP)
		@$self = ();
	}

	# Pop outside, so we know that as much destruction as possible has happened
	POP;

	if (defined( $wantarray )) {
		if ($wantarray) {
			return @return;
		}
		else {
			return $return;
		}
	}
	else {
		return;
	}
}

sub when {
	my $self = shift;
	return $self->[TIME];
}

sub from {
	my $self = shift;
	return $self->[FROM];
}

sub name {
	my $self = shift;
	return $self->[NAME];
}

sub args {
	my $self = shift;
	if (wantarray) {
		return @{$self->[ARGS]};
	}
	else {
		return $self->[ARGS];
	}
}

1;
