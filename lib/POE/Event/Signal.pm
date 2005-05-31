package POE::Event::Signal;

use POE::Kernel;
#use POE::Event;
use base 'POE::Event';

use strict;
use warnings;

sub dispatch {
	my $self = shift;

	my $kernel	= $self->[POE::Event::KERNEL];
	my $time	= $self->[POE::Event::TIME];
	my $sender	= $self->[POE::Event::FROM];
	my $session	= $self->[POE::Event::TO];
	my $signal	= $self->[POE::Event::NAME]; # I think
	my $args	= $self->[POE::Event::ARGS];

	# Reset the sig_handled flag
	
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
}

1;
