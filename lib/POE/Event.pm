package POE::Event;

use POE::Callstack qw(POP PUSH);

{
	my $i = 0;

	sub _ATTR_COUNTER {
		return $i++;
	}
}
	
BEGIN {
	foreach my $attr (qw(KERNEL TIME FROM TO NAME ARGS)) {
		eval "sub $attr () { " . _ATTR_COUNTER . " }";
	}
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
	my $class = shift;
	my $kernel = shift;
	my $when = shift;
	my $from = shift;
	my $to = shift; # Resolution does nasty things, figure out where it belongs later (used to be here)
	my $name = shift;
	my $args = shift;

	DEBUG( "New Class: $class Kernel: $kernel\n" );

	my $self = bless [
		$kernel,  # KERNEL
		$when,    # TIME
		$from,    # FROM
		$to,      # TO
		$name,    # NAME
		$args,    # ARGS
	], (ref $class || $class);

	return $self;
}

sub dispatch {
	my $self = shift;

	DEBUG( "Event: @$self\n" );

	{	# Wrap this baby in a magical scope so destruction happens in a timely manner... yes
	
		my $to = $self->[KERNEL]->resolve_session( $self->[TO] );

		DEBUG "[DISPATCH] Event dispatching From: $self->[FROM] To: $to Event: $self->[NAME]\n" if DEBUGGING;
		
		# push inside, so we know the $to

		PUSH( $to, $self->[NAME] );
	
		my $return = $to->_invoke_state( $self->[FROM], $self->[NAME], $self->[ARGS] );
		@$self = ();

	}

	# Pop outside, so we know that as much destruction as possible has happened
	POP;

	return $return;
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
	return $self->[ARGS];
}

1;
