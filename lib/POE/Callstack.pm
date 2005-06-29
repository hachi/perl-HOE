package POE::Callstack;

use base 'Exporter';

@EXPORT_OK = qw(PUSH POP PEEK CURRENT_SESSION CURRENT_EVENT);

my @stack;

sub PUSH {
	my ($session, $event) = @_;

	push @stack, [$session, $event];
}

sub POP	{
	my $return = pop @stack;
	return @$return;
}

sub PEEK {
	return $stack[-1];
}

sub CURRENT_SESSION {
	return $stack[-1]->[0];
}

sub CURRENT_EVENT {
	return $stack[-1]->[1];
}

sub CLEAN {
	die if @stack;
}

1;
