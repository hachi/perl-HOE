package POE::Kernel;

use strict;
use warnings;

use Time::HiRes;
use WeakRef;
use POE::Event;
use POE::Callstack;

use vars qw($poe_kernel);

$poe_kernel = __PACKAGE__->new();

sub POE::Kernel {
	return $poe_kernel;
}

BEGIN {
	if($ENV{'DEBUG'}) {
		eval "sub DEBUGGING () { 1 }";
	}
	else {
		eval "sub DEBUGGING () { 0 }";
	}
}

sub DEBUG {
	print @_;
}

sub ID {
	my $self = shift;
	return "THE KERNEL";
}

sub new {
  my $class = shift;
  my $self = bless [
    {}, # Aliases
    [], # Queue
    {}, # FH Reads
    {}, # FH Reads (Paused)
    {}, # FH Writes
    {}, # FH Writes (Paused)
    {}, # Refs
    {}, # IDS
    {}, # Sessions
  ], (ref $class || $class);

  POE::Callstack->push($self);

  return $self;
}

sub KR_ALIASES	() { 0 }
sub KR_QUEUE	() { 1 }
sub KR_FH_READS	() { 2 }
sub KR_FH_READS_PAUSED	() { 3 }
sub KR_FH_WRITES	() { 4 }
sub KR_FH_WRITES_PAUSED	() { 5 }
sub KR_REFS	() { 6 }
sub KR_IDS	() { 7 }
sub KR_SESSIONS	() { 8 }

sub import {
  my $package = caller();
  no strict 'refs';
  my $export_kernel = $poe_kernel;
  *{ "${package}::poe_kernel" } = \$export_kernel;
  weaken( ${ "${package}::poe_kernel" } );
}

{
	my $next_id = 1;
	my %hijacked_namespaces;
	
	sub session_alloc {
		my $self = shift;
		my $session = shift;
		my @args = @_;
		my $id = $next_id++;
		weaken($self->[KR_IDS]->{$id} = $session);
		$self->[KR_SESSIONS]->{$session} = $id;
		# Who is SENDER in this case?
		$self->call( $session, '_start', @args );
		# TODO _parent and _child calls, as approrpriate
		# TODO keep track of parent/children relationships
		# parents cannot die until they have no children alive

		no strict 'refs';
		no warnings 'redefine';
		my $package = ref($session);
		unless (exists $hijacked_namespaces{$package}) {
			my $old_destroy = *{"${package}::DESTROY"}{CODE};
			*{"${package}::DESTROY"} = sub {
				my $inner_self = shift;
				$POE::Kernel::poe_kernel->session_dealloc( $inner_self );
				return unless $old_destroy;
				$old_destroy->($inner_self);
			};
			$hijacked_namespaces{$package} = undef;
		}
	}
}

sub session_dealloc {
	my $self = shift;
	my $session = shift;
	DEBUG "[SESSION] Deallocating $session\n" if DEBUGGING;

	$self->call( $session, '_stop' );
	my $id = $self->[KR_SESSIONS]->{$session};
	delete $self->[KR_SESSIONS]->{$session};
	delete $self->[KR_IDS]->{$id};
}

sub ID_session_to_id {
	my $self = shift;
	my $session = shift;
	
	return $self->[KR_SESSIONS]->{$session};
}

sub post {
  my $self = shift;
  my ($to, $state, @etc) = @_;

  # Name resolution /could/ happen during dispatch instead, I think everything would stay alive just fine simply because kernel is embedded in the event, and the sessions are all held inside aliases within that.
  my $from = POE::Callstack->peek();
  my $queue = $self->[KR_QUEUE];
  @$queue = sort { $a <=> $b } (@$queue, POE::Event->new( $self, time, $from, $to, $state, \@etc ));

  DEBUG "[POST] Kernel: $self From: $from To: $to State: $state\n" if DEBUGGING;
}

sub yield {
	my $self = shift;
	$self->post( POE::Callstack->peek(), @_ );
}

sub call {
  my $self = shift;
  my ($to, $state, @etc) = @_;

  DEBUG "[CALL] Kernel: $self To: $to State: $state\n" if DEBUGGING;
  POE::Event->new( $self, undef, POE::Callstack->peek(), $to, $state, \@etc )->dispatch();
}

sub resolve_session {
  my $self = shift;
  my $input = $_[0];
  
  my $aliases = $self->[KR_ALIASES];
  my $ids = $self->[KR_IDS];
  
  if ($input->can('_invoke_state')) {
    return $input;
  }
  elsif (exists( $aliases->{$input} )) {
    return $aliases->{$input};
  }
  elsif (exists( $ids->{$input} )) {
    return $ids->{$input};
  }
  else {
    return $input;
  }
}

sub signal {
	my $self = shift;
	DEBUG "Signal WTF? @_\n" if DEBUGGING;
}

sub _select_any {
	my $self = shift;
	my $class = shift;
	my $fh = shift;
	my $event = shift;

	my $fd = fileno($fh);

	my $current_session = POE::Callstack->peek();
	
	my $main_class = $self->[$class];
	my $paused_class = $self->[$class + 1];

	if ($event) { # Setup watcher
		DEBUG "[SELECT] Watch Fh: $fh Class: $class Event: $event\n" if DEBUGGING;
		unless (exists $main_class->{$fd} and ref $main_class->{$fd} eq 'ARRAY') {
			$main_class->{$fd} = [];
		}

		push @{$main_class->{$fd}}, {
			kernel	=> $self,
			session	=> $current_session,
			fd	=> $fd,
			fh	=> $fh,
			event	=> $event,
		};
	}
	else { # Clear watcher
		DEBUG "[SELECT] Stop Fh: $fh Class: $class\n" if DEBUGGING;
		@{$main_class->{$fd}} = grep { not $_->{session} == $current_session } (@{$main_class->{$fd}});
		@{$paused_class->{$fd}} = grep { not $_->{session} == $current_session } (@{$paused_class->{$fd}});

		unless (@{$main_class->{$fd}}) {
			DEBUG "[SELECT] Delete ${class} Fh: $fh\n" if DEBUGGING;
			delete $main_class->{$fd};
		}
		unless (@{$paused_class->{$fd}}) {
			DEBUG "[SELECT] Delete ${class}_paused Fh: $fh\n" if DEBUGGING;
			delete $paused_class->{$fd};
		}
	}
}

sub select_read {
	my $self = shift;
	$self->_select_any( KR_FH_READS, @_ );
}

sub select_write {
	my $self = shift;
	$self->_select_any( KR_FH_WRITES, @_ );
}

sub select {
	my $self = shift;
	my $fh = shift;
	my $read = shift;
	my $write = shift;
	my $expedite = shift;

	die if $expedite;

	$self->select_read( $fh, $read );
	$self->select_write( $fh, $write );
}

sub _select_pause_any {
	my $self = shift;
	my $class = shift;
	my $fh = shift;
	my $fd = fileno( $fh );

	my $main_class = $self->[$class];
	my $paused_class = $self->[$class + 1];

	$paused_class->{$fd} = $main_class->{$fd};
	delete $main_class->{$fd};
}

sub select_pause_read {
	my $self = shift;
	$self->_select_pause_any( KR_FH_READS, @_ );
}

sub select_pause_write {
	my $self = shift;
	$self->_select_pause_any( KR_FH_WRITES, @_ );
}

sub _select_resume_any {
	my $self = shift;
	my $class = shift;
	my $fh = shift;
	my $fd = fileno( $fh );

	my $main_class = $self->[$class];
	my $paused_class = $self->[$class + 1];

	$main_class->{$fd} = $paused_class->{$fd};
	delete $paused_class->{$fd};
}

sub select_resume_read {
	my $self = shift;
	$self->_select_resume_any( KR_FH_READS, @_ );
}

sub select_resume_write {
	my $self = shift;
	$self->_select_resume_any( KR_FH_WRITES, @_ );
}

sub delay {
	my $self = shift;
	my $event = shift;
	my $seconds = shift;
	my $args = [@_];

	my $queue = $self->[KR_QUEUE];

	die unless $event;

	my $current_session = POE::Callstack->peek();

	if (defined $seconds) {
		$seconds += time;
	
		@$queue = sort { $a <=> $b } (
			@$queue,
			POE::Event->new(
				$self,
				$seconds,
				$current_session,
				$current_session,
				$event,
				$args,
			),
		);
	}
	else {
		@$queue = grep { not ( $current_session == $_->from and $event eq $_->name() ) } @$queue;
	}
}

sub delay_set {
	my $self = shift;
	my $event = shift;
	my $seconds = shift;
	my $args = [@_];


}

sub run {
	my $self = shift;
	DEBUG "[KERNEL] Starting Loop\n" if DEBUGGING;
	weaken( $poe_kernel ) unless isweak( $poe_kernel );

	my $queue = $self->[KR_QUEUE];
	my $fh_reads = $self->[KR_FH_READS];
	my $fh_writes = $self->[KR_FH_WRITES];

	while (@$queue or keys %$fh_reads or keys %$fh_writes) {
		my $delay = undef;
		while (@$queue) {
			my $when = $queue->[0]->when();
			if ($when <= time) {
				my $event = shift @$queue;
				$event->dispatch();
				if (@$queue) {
					$when = $queue->[0]->when();
				}
			}
			else {
				last;
			}
			$delay = $when - time;
			$delay = 0 if $delay < 0;
		}
		$self->_select($delay);
	}
	DEBUG "[RUN] Kernel exited cleanly\n" if DEBUGGING;
}

sub _select {
	my $self = shift;
	my $timeout = shift;

	my $reads = $self->[KR_FH_READS];
	my $writes = $self->[KR_FH_WRITES];

	my $rin = my $win = my $ein = '';
	
	my $read_count = 0;
	foreach my $fd (keys %$reads) {
		$read_count++;
		vec($rin, $fd, 1) = 1;
	}

	my $write_count = 0;
	foreach my $fd (keys %$writes) {
		$write_count++;
		vec($win, $fd, 1) = 1;
	}

	DEBUG "[SELECT] Waiting a maximum of $timeout for $read_count reads and $write_count writes.\n" if DEBUGGING;

	my $nfound = CORE::select( my $rout = $rin, my $wout = $win, my $eout = $ein, $timeout );

	while (my ($fd, $watchers) = each %$reads) {
		if (vec( $rout, $fd, 1 )) {
			foreach my $watcher (@$watchers) {
				$self->post( $watcher->{session}, $watcher->{event}, $watcher->{fh} );
			}
		}
	}
	while (my ($fd, $watchers) = each %$writes) {
		if (vec( $wout, $fd, 1 )) {
			foreach my $watcher (@$watchers) {
				$self->post( $watcher->{session}, $watcher->{event}, $watcher->{fh} );
			}
		}
	}
}

sub alias_set {
  my $self = shift;
  my $alias = $_[0];
  my $session = POE::Callstack->peek();
  
  $self->[KR_ALIASES]->{$alias} = $session;

  # We can either hook into the session and wait for a DESTROY event to come back to us to clean up the alias, or we can stipulate that the session object must clean up all of it's own aliases. The latter may be better for speed and clean code.
}
 
sub alias_remove {
  my $self = shift;
  my $alias = $_[0];

  delete $self->[KR_ALIASES]->{$alias};
}

sub refcount_increment {
	my $self = shift;
	my $session = POE::Callstack->peek();
	my $refs = $self->[KR_REFS];
	unless (exists $refs->{$session} and ref $refs->{$session} eq 'ARRAY') {
		$refs->{$session} = [];
	}

	push @{$refs->{$session}}, $session;
}

sub refcount_decrement {
	my $self = shift;
	my $session = POE::Callstack->peek();
	my $refs = $self->[KR_REFS];

	shift @{$refs->{$session}};

	unless (@{$refs->{$session}}) {
		delete $refs->{$session};
	}
}

sub state {
	my $self = shift;
	my $session = POE::Callstack->peek();

	return $session->register_state( @_ );
}

sub register_state {
	my $self = shift;
	DEBUG "State removal attempted as kernel, @_\n";
}

sub DESTROY {
  DEBUG "Kernel Destruction!\n" if DEBUGGING;
}

1;
