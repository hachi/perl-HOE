package POE::Kernel;

use strict;
use warnings;

use Time::HiRes;
use WeakRef;
use POE::Event;
use POE::Event::Signal;
use POE::Callstack;

use Carp qw(cluck);

use vars qw($poe_kernel);

$poe_kernel = __PACKAGE__->new();

# This is for silently making POE::Kernel->whatever from a package to an object call...
# it may not even be necessary... heck, it may not even work... should test that.
sub POE::Kernel {
	return $poe_kernel; 
}

#$SIG{ALRM} = sub {
#	DEBUG( "BLOCKED!\n" );
#	cluck( "BLOCKED!\n" );
#	sleep 600;
#};
#
#alarm 20;

BEGIN {
	if($ENV{'HOE_DEBUG'}) {
		eval "sub DEBUGGING () { 1 }";
	}
	else {
		eval "sub DEBUGGING () { 0 }";
	}

	unless (__PACKAGE__->can('ASSERT_USAGE')) {
		eval "sub ASSERT_USAGE () { 0 }";
	}

	my $debug_file;
	
	if(my $debug_filename = $ENV{'HOE_DEBUG_FILE'}) {
		open $debug_file, '>', $debug_filename or die "can't open debug file '$debug_filename': $!";
		CORE::select((CORE::select($debug_file), $| = 1)[0]);
	}
	else {
		$debug_file = \*STDERR;
	}

	sub DEBUG {
		print $debug_file @_;
	}
}

sub ID {
	my $self = shift;
	return "THE KERNEL";
}

sub RUNNING_IN_HELL () { 0 }

sub new {
  my $class = shift;
  my $self = bless [
    {}, # Aliases
    [], # Queue
    {}, # FH Reads
    {}, # FH Reads (Paused)
    {}, # FH Writes
    {}, # FH Writes (Paused)
    {}, # FH Expedites
    {}, # FH Expedites (Paused spot, DANGEROUS, necessary for now)
    {}, # Refs
    {}, # IDS
    {}, # Sessions
    {}, # Signals
    {}, # Parent Session, by child session
    {}, # Child Sessions hashref "key"==value (weakened values), by parent session
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
sub KR_FH_EXPEDITES	() { 6 }
sub KR_FH_EXPEDITES_NASTY	() { 7 } # I have to make this exist to prevent crashes until I make watcher objects.
sub KR_REFS	() { 8 }
sub KR_IDS	() { 9 }
sub KR_SESSIONS	() { 10 }
sub KR_SIGNALS	() { 11 }
sub KR_PARENTS	() { 12 }
sub KR_CHILDREN	() { 13 }

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

		my $parent = POE::Callstack->peek();

		$self->[KR_PARENTS]->{$session} = $parent;
		weaken($self->[KR_CHILDREN]->{$parent}->{$session} = $session);
		
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
	my $parent = delete $self->[KR_PARENTS]->{$session};
	delete $self->[KR_CHILDREN]->{$parent}->{$session};
}

sub ID_session_to_id {
	my $self = shift;
	my $session = shift;
	
	return $self->[KR_SESSIONS]->{$session};
}

sub ID_id_to_session {
	my $self = shift;
	my $id = shift;

	return $self->[KR_IDS]->{$id};
}

sub get_active_session {
	return POE::Callstack->peek();
}

sub get_children {
	my $self = shift;
	my $parent = shift;

	unless (defined( $parent )) {
		cluck( "Undefined parent to find children of\n" );
	}
	
	if (exists $self->[KR_CHILDREN]->{$parent}) {
		return values %{$self->[KR_CHILDREN]->{$parent}};
	}
	return (); # return empty list or undef... empty list prevents recursion problems... undef seems more correct
}

sub post {
	my $self = shift;
	my ($to, $state, @etc) = @_;

	die "destination is undefined in post" unless(defined( $to ));
	die "event is undefined in post" unless(defined( $state ));

	# Name resolution /could/ happen during dispatch instead, I think everything would stay alive just fine simply because kernel is embedded in the event, and the sessions are all held inside aliases within that.
	my $from = POE::Callstack->peek();
	my $queue = $self->[KR_QUEUE];
	@$queue = sort { $a <=> $b } (@$queue, POE::Event->new( $self, time, $from, $to, $state, \@etc ));

	DEBUG "[POST] Kernel: $self From: $from To: $to State: $state Args: @etc\n" if DEBUGGING;
}

sub yield {
	my $self = shift;
	my ($state, @etc) = @_;

	die "event name is undefined in yield" unless(defined( $state )); 

	my $from = POE::Callstack->peek();
	my $queue = $self->[KR_QUEUE];
	@$queue = sort { $a <=> $b } (@$queue, POE::Event->new( $self, time, $from, $from, $state, \@etc ));
	
	DEBUG "[YIELD] Kernel $self From/To: $from State: $state\n" if DEBUGGING;
}

sub call {
	my $self = shift;
	my ($to, $state, @etc) = @_;

	die "destination undefined in call" unless(defined( $to ));
	die "event undefined in call" unless(defined( $to ));

	DEBUG "[CALL] Kernel: $self To: $to State: $state\n" if DEBUGGING;
	POE::Event->new( $self, undef, POE::Callstack->peek(), $to, $state, \@etc )->dispatch();
	DEBUG "[CALL] Completed\n" if DEBUGGING;
}

sub resolve_session {
	my $self = shift;
	my $input = $_[0];
  
	my $aliases = $self->[KR_ALIASES];
	my $ids = $self->[KR_IDS];

	unless( $input ) {
		cluck( "Undefined state resolution attempted\n" );
	}

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
#		return $input;
		return undef; # shouldn't this be more correct?
	}
}

sub _select_any {
	my $self = shift;
	my $class = shift;
	my $fh = shift;
	my $event = shift;

	my $fd = fileno($fh);

	my $current_session = POE::Callstack->peek();

	unless (defined( $current_session )) {
		DEBUG "[[[BAD]]] Current session undefined, global destruction?\n";
		return;
	}
	
	my $main_class = $self->[$class];
	my $paused_class = $self->[$class + 1];

	if ($event) { # Setup watcher
		DEBUG "[WATCH] Watch Fd: $fd Fh: $fh Class: $class Event: $event\n" if DEBUGGING;
		unless (exists $main_class->{$fd} and ref $main_class->{$fd} eq 'ARRAY') {
			$main_class->{$fd} = [];
		}

		unless (grep { $_->{session} == $current_session } @{$main_class->{$fd}}) {
			push @{$main_class->{$fd}}, {
				kernel	=> $self,
				session	=> $current_session,
				fd	=> $fd,
				fh	=> $fh,
				event	=> $event,
			};
		}
	}
	else { # Clear watcher
		DEBUG "[WATCH] Stop Fd: $fd Fh: $fh Class: $class\n" if DEBUGGING;
		@{$main_class->{$fd}} = grep { not $_->{session} == $current_session } (@{$main_class->{$fd}});
		@{$paused_class->{$fd}} = grep { not $_->{session} == $current_session } (@{$paused_class->{$fd}});

		unless (@{$main_class->{$fd}}) {
			delete $main_class->{$fd};
		}
		unless (@{$paused_class->{$fd}}) {
			delete $paused_class->{$fd};
		}
	}
}

sub select_read {
	my $self = shift;
	DEBUG "[WATCH] Read @_\n" if DEBUGGING;
	$self->_select_any( KR_FH_READS, @_ );
}

sub select_write {
	my $self = shift;
	DEBUG "[WATCH] Write @_\n" if DEBUGGING;
	$self->_select_any( KR_FH_WRITES, @_ );
}

sub select_expedite {
	my $self = shift;
	DEBUG "[WATCH] Expedite @_\n" if DEBUGGING;
	$self->_select_any( KR_FH_EXPEDITES, @_ );
}

sub select {
	my $self = shift;
	my $fh = shift;

	if (@_ == 3) {
		my ($read, $write, $expedite) = @_;

		$self->select_read( $fh, $read );
		$self->select_write( $fh, $write );
		$self->select_expedite( $fh, $expedite );
	}
	elsif (@_ == 0) {
		$self->select_read( $fh );
		$self->select_write( $fh );
		$self->select_expedite( $fh );
	}
	else {
		die();
	}
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
	DEBUG "[WATCH] Read pause: @_\n" if DEBUGGING;
	$self->_select_pause_any( KR_FH_READS, @_ );
}

sub select_pause_write {
	my $self = shift;
	DEBUG "[WATCH] Write pause: @_\n" if DEBUGGING;
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
	DEBUG "[WATCH] Read resume: @_\n" if DEBUGGING;
	$self->_select_resume_any( KR_FH_READS, @_ );
}

sub select_resume_write {
	my $self = shift;
	DEBUG "[WATCH] Write resume: @_\n" if DEBUGGING;
	$self->_select_resume_any( KR_FH_WRITES, @_ );
}

sub delay {
	die unless $_[1];
	die unless $_[2];

	$_[2] += time;

	&_internal_alarm_destroy_all;
	&_internal_alarm_add;
}

sub delay_add {
	die unless $_[1];
	die unless $_[2];

	$_[2] += time;

	&_internal_alarm_add;
}

sub alarm {
	die unless $_[1];
	die unless $_[2];

	&_internal_alarm_destroy_all;
	&_internal_alarm_add;
}

sub alarm_add {
	die unless $_[1];
	die unless $_[2];

	&_internal_alarm_add;
}

sub _internal_alarm_add {
	my ($self, $event, $seconds, @args) = @_;

	my $queue = $self->[KR_QUEUE];

	my $current_session = POE::Callstack->peek();

	@$queue = sort { $a <=> $b } (
		@$queue,
		POE::Event->new(
			$self,
			$seconds,
			$current_session,
			$current_session,
			$event,
			\@args,
		),
	);
}

sub _internal_alarm_destroy_all {
	my ($self, $event) = @_;

	my $queue = $self->[KR_QUEUE];

	my $current_session = POE::Callstack->peek();

	@$queue = grep { not ( $current_session == $_->from and $event eq $_->name() ) } @$queue;
}

sub run {
	my $self = shift;
	DEBUG "[KERNEL] Starting Loop\n" if DEBUGGING;
	weaken( $poe_kernel ) unless isweak( $poe_kernel );

	my $queue = $self->[KR_QUEUE];
	my $fh_reads = $self->[KR_FH_READS];
	my $fh_preads = $self->[KR_FH_READS_PAUSED];
	my $fh_writes = $self->[KR_FH_WRITES];
	my $fh_pwrites = $self->[KR_FH_WRITES_PAUSED];
	my $fh_expedites = $self->[KR_FH_EXPEDITES];

	while (
			@$queue or
			keys %$fh_reads or
			keys %$fh_preads or
			keys %$fh_writes or
			keys %$fh_pwrites or
			keys %$fh_expedites
		) {
		my $delay = undef;
		while (@$queue) {
			my $when = $queue->[0]->when();
			if ($when <= time) {
				my $event = shift @$queue;
				my $from = $event->from;
				my $name = $event->name;
				DEBUG "[DISPATCH] From: $from Event: $name\n" if DEBUGGING;
				$event->dispatch();
				DEBUG "[DISPATCH] Completed\n" if DEBUGGING;
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
	my $preads = $self->[KR_FH_READS_PAUSED];
	my $writes = $self->[KR_FH_WRITES];
	my $pwrites = $self->[KR_FH_WRITES_PAUSED];
	my $expedites = $self->[KR_FH_EXPEDITES];
	my $signals = $self->[KR_SIGNALS];

	my $rin = my $win = my $ein = '';
	
	my $read_count = 0;
	foreach my $fd (keys %$reads) {
		$read_count++;
		vec($rin, $fd, 1) = 1;
	}

	my $pread_count = 0;
	foreach my $fd (keys %$preads) {
		$pread_count++;
	}

	my $write_count = 0;
	foreach my $fd (keys %$writes) {
		$write_count++;
		vec($win, $fd, 1) = 1;
	}

	my $pwrite_count = 0;
	foreach my $fd (keys %$pwrites) {
		$pwrite_count++;
	}

	my $expedite_count = 0;
	foreach my $fd (keys %$expedites) {
		$expedite_count++;
		vec($ein, $fd, 1) = 1;
	}

	my $signal_count = 0;
	foreach my $signal (keys %$signals) {
		$signal_count++;
	}

	if (DEBUGGING) {
		if (defined( $timeout )) {
			DEBUG "[POLL] Waiting a maximum of $timeout for $read_count reads, $pread_count paused reads, $write_count writes, $pwrite_count paused writes, $expedite_count expedite reads, and $signal_count signals.\n" if DEBUGGING;
		}
		else {
			DEBUG "[POLL] Waiting for $read_count reads, $pread_count paused reads, $write_count writes, $pwrite_count paused writes, $expedite_count expedite reads, and $signal_count signals.\n" if DEBUGGING;
		}
#		use Data::Dumper;
#		if ($read_count == 0 and $write_count == 0) {
#			print Dumper( $preads );
#			print Dumper( $pwrites );
#		}
	}

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
	while (my ($fd, $watchers) = each %$expedites) {
		if (vec( $eout, $fd, 1 )) {
			foreach my $watcher( @$watchers) {
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

sub alias_resolve {
	my $self = shift;
	my $alias = $_[0];

	return $self->[KR_ALIASES]->{$alias};
}

sub alias_list {
	my $self = shift;
	my $session = shift or POE::Callstack->peek();

	my $aliases = $self->[KR_ALIASES];
	
	return grep { $aliases->{$_} == $session } keys %{$self->[KR_ALIASES]};
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
	DEBUG "[[[BAD]]] State removal attempted as kernel, @_\n";
}

sub sig {
	my $self = shift;
	my $signal_name = shift;
	my $event = shift;

	if (ASSERT_USAGE) {
		die "undefined signal in sig" unless(defined( $signal_name ));
	}

	my $signals = $self->[KR_SIGNALS];
	
	my $session = POE::Callstack->peek();

	if ($event) {
		DEBUG "[SIGNAL] Session: $session Signal: $signal_name Event: $event\n" if DEBUGGING;
		unless (exists( $signals->{$signal_name} )) {
			$signals->{$signal_name} = {};
		}
		$signals->{$signal_name}->{$session} = [ $session, $event ];

		if ($signal_name eq 'CHLD') {
			$self->_install_chld_handler;
		}
	}
	else {
		DEBUG "[SIGNAL] Session: $session Signal: $signal_name\n" if DEBUGGING;
		if (exists( $signals->{$signal_name} )) {
			delete $signals->{$signal_name}->{$session};
		}
		unless( keys %{$signals->{$signal_name}} ) {
			delete $signals->{$signal_name};
			$SIG{$signal_name} = "DEFAULT" if exists $SIG{$signal_name};
		}
	}
}

sub signal {
	my $self = shift;
	my $session = shift;
	my $signal = shift;
	my @args = @_;

	POE::Event::Signal->new(
		$self,
		time(),
		POE::Callstack->peek(),
		$session,
		$signal,
		\@args,
	)->dispatch();
}

use POSIX ":sys_wait_h";

sub _install_chld_handler {
	DEBUG "Installing CHLD Handler\n" if DEBUGGING;
	my $kernel = shift;
	
	$SIG{CHLD} = sub {
		# Since this could happen between any two perl opcodes we should localize the error variable... waitpid plays with it.
		local $!;
		DEBUG( "Got CHLD SIGNAL\n" ) if DEBUGGING;
		while ((my $child = waitpid( -1, WNOHANG)) > 0) {
			my $status = $?;
			my $watchers = $kernel->[KR_SIGNALS]->{CHLD};
			while (my ($session, $watcher) = each %$watchers) {
				$kernel->post( $watcher->[0], $watcher->[1], 'CHLD', $child, $status );
			}
		}
		$kernel->_install_chld_handler; # This line could be keeping the kernel alive wrongly, not sure.
	};
}

sub _data_sig_get_safe_signals {
	return keys %SIG;
}

sub sig_handled {
}

sub DESTROY {
  DEBUG "Kernel Destruction!\n" if DEBUGGING;
}

1;
