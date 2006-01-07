package POE::Event::Signal;

use POE::Kernel;
use POE::Event;
use base 'POE::Event';

use strict;
use warnings;

our $flag;

sub dispatch {
	my $self = shift;

	my $kernel	= $self->[POE::Event::KERNEL];
	my $time	= $self->[POE::Event::TIME];
	my $sender	= $self->[POE::Event::FROM];
	my $session	= $self->[POE::Event::TO];
	my $signal	= $self->[POE::Event::NAME]; # I think
	my $args	= $self->[POE::Event::ARGS];

	# Reset the sig_handled flag
	# $flag = 0; # not thread safe
	local $flag = 0;

	# This algorithm is copied pretty much verbatim from POE's Kernel.pm, it's very elegant anyways.
	
	my @touched_sessions = ($session);
	my $touched_index = 0;
	while ($touched_index < @touched_sessions) {
		my $next_target = $touched_sessions[$touched_index];
		push @touched_sessions, $kernel->get_children($next_target);
		$touched_index++;
	}

	if (my $signal_watchers = $kernel->[POE::Kernel::KR_SIGNALS()]->{$signal}) { 
		while( $touched_index-- ) {
			my $target_session = $touched_sessions[$touched_index];
			if (exists( $signal_watchers->{$target_session} )) {
				POE::Event->new(
					$kernel,
					$time,
					$sender,
					$target_session,
					$signal_watchers->{$target_session}->[1],
					$args,
				)->dispatch();
			}
		}
	}

	foreach my $dead_session (@touched_sessions) {
		# Sessions go boom
	}
	
	# Flag not set? KILL ALL HUMANS.
	# TODO
}

sub HANDLED {
	$flag = 1;
}

1;
