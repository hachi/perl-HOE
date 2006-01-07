package POE::Session::Dead;

use strict;

sub _invoke_state {
	my $self = shift;
	my ($from, $event, $args) = @_;

	warn( "Event dispatch happening on a session that has been destroyed: ($self) Event: $event Args: @$args\n" );
}

1;
