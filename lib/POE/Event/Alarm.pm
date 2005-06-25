package POE::Event::Alarm;

use base 'POE::Event';
use POE::Event;

use strict;
use warnings;

BEGIN {
	foreach my $attr (qw(CTIME ALARM_ID)) {
		eval "sub $attr () { " . POE::Event::_ATTR_COUNTER . " }";
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
		$self->[POE::Event::TIME] += shift;
	}

	return $self->[POE::Event::TIME];
}

sub set_when {
	my $self = shift;

	if (@_) {
		$self->[POE::Event::TIME] = shift;
	}

	return $self->[POE::Event::TIME];
}

1;
