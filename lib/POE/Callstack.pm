package POE::Callstack;

my @stack;

sub push {
	my $self = shift;
	my $item = shift;

	push @stack, $item;
}

sub pop	{
	my $self = shift;
	return pop @stack;
}

sub peek {
	return $stack[-1];
}

1;
