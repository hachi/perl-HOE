package POE::Event::Alarm;

use base 'POE::Event';

use strict;
use warnings;

BEGIN {
	my $i = 0;
	foreach my $attr (@POE::Event::_ELEMENTS, qw(CTIME ALARM_ID)) {
		eval "sub $attr () { $i }";
		$i++;
	}
}

my $i = 0;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	$self->[CTIME] = shift;
	$self->[ALARM_ID] = $i++;

	return $self;
}

sub ctime {
	my $self = shift;

	return $self->[CTIME];
}

sub alarm_id {
	my $self = shift;

	return $self->[ALARM_ID];
}

sub adjust_when {
	my $self = shift;

	if (@_) {
		$self->[TIME] += shift;
	}

	return $self->[TIME];
}

sub set_when {
	my $self = shift;

	if (@_) {
		$self->[TIME] = shift;
	}

	return $self->[TIME];
}

1;
