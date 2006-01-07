package POE::Kernel;

use strict;
use warnings;

use Time::HiRes;
use WeakRef;

use POE::Callstack qw(CURRENT_SESSION CURRENT_EVENT);
use POE::Event;
use POE::Event::Signal;
use POE::Event::Alarm;
use POE::Session::Dead;

use Carp qw(cluck croak);

use Errno qw(EPERM ESRCH EEXIST);

use vars qw($poe_kernel);

# This is for silently making POE::Kernel->whatever from a package to an object call...
# it may not even be necessary... heck, it may not even work... should test that.
# Followup: It is necessary.
sub POE::Kernel {
	return $poe_kernel; 
}

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
		unless (open $debug_file, '>', $debug_filename) {
			warn "can't open debug file '$debug_filename': $!";
			$debug_file = \*STDERR;
		}
		CORE::select((CORE::select($debug_file), $| = 1)[0]);
	}
	else {
		$debug_file = \*STDERR;
	}

	sub DEBUG {
		print $debug_file @_;
	}
}

sub RUNNING_IN_HELL () { 0 }

sub CHECKING_INTEGRITY () { 1 }

sub new {
  my $class = shift;
  my $self = bless [], (ref $class || $class);
  $self->_init();

  return $self;
}

my $counter = 0;

sub _init {
	my $self = shift;

	++$counter;
	
	@$self = (
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
		"THE KERNEL $counter", # ID
	);
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
sub KR_ID	() { 14 }

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

		my $parent = CURRENT_SESSION;

		$self->[KR_PARENTS]->{$session} = $parent;
		weaken($self->[KR_CHILDREN]->{$parent}->{$session} = $session);
		
		# Who is SENDER in this case?
		my $result = $self->call( $session, '_start', @args );
		
		# $parent could be the Kernel, \@result may not be correct, see POE::Session docs which are vague.
		$self->call( $parent, '_child', 'create', $session, $result );

		no strict 'refs';
		no warnings 'redefine';
		my $package = ref($session);
		unless (exists $hijacked_namespaces{$package}) {
			my $old_destroy = *{"${package}::DESTROY"}{CODE};
			*{"${package}::DESTROY"} = sub {
				my $inner_self = shift;
				defined( $POE::Kernel::poe_kernel ) and
					$POE::Kernel::poe_kernel->session_dealloc( $inner_self );
				return unless $old_destroy;
				$old_destroy->($inner_self);
				bless $inner_self, 'POE::Session::Dead';
			};
			$hijacked_namespaces{$package} = undef;
		}
	}
}

sub session_dealloc {
	my $self = shift;
	my $session = shift;
	DEBUG "[SESSION] Deallocating $session\n" if DEBUGGING;

	if (exists $self->[KR_SESSIONS]->{$session}) {
		my @result = $self->call( $session, '_stop' );
		my $parent = $self->[KR_PARENTS]->{$session};

		# $parent could be the Kernel, the args list is vaguely documented in POE::Session... not sure this is correct
		$self->call( $parent, '_child', 'lose', $session, \@result );
	}
	$self->cleanup_session( $session );
}

sub cleanup_session {
	my $self = shift;
	my $session = shift;

	# We could destroy the innards of the session and that may help clean things up

	if (my $id = $self->[KR_SESSIONS]->{$session} ) {
		delete $self->[KR_SESSIONS]->{$session};
		delete $self->[KR_IDS]->{$id};
	}
	if (my $parent = delete $self->[KR_PARENTS]->{$session}) {
		delete $self->[KR_CHILDREN]->{$parent}->{$session};
	}
	return;
}

sub ID {
	my $self = shift;
	return $self->[KR_ID];
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
	return CURRENT_SESSION;
}

sub get_active_event {
	return CURRENT_EVENT;
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

sub stop {
	# If this gets called from within an event dispatched by a signal event,
	# then it won't stop till the signal event is finished dispatching, dangerous
	my $self = shift;
	foreach my $child ($self->get_children($self)) {
		$self->cleanup_session( $child );
	}
	
	# all kernel structures need to be purged in the same way, yucky, but very necessary
	@{$self->[KR_QUEUE]} = ();
	$self->_init();
	initialize_kernel();
}

sub detach_child {
	my $self = shift;
	my $session = shift;

	if (grep { $session == $_ } $self->get_children( CURRENT_SESSION )) {
		return _internal_detach( $session );
	}
	else {
		$! = EPERM;
		return 0;
	}
}

sub detach_myself {
	my $self = shift;
	return _internal_detach( CURRENT_SESSION );
}

sub _internal_detach {
	my $self = shift;
	my $session = shift;

	my $parents = $self->[KR_PARENTS];
	my $children = $self->[KR_CHILDREN];

	if (exists( $parents->{$session} )) {
		my $old_parent = $parents->{$session};
		
		if ($old_parent == $self) {
			$! = EPERM;
			return 0;
		}
		else {
			$self->call( $old_parent, '_child', 'lose', $session );
			delete( $children->{$old_parent}->{$session} );

			# Prevent leaks
			keys( %{$children->{$old_parent}} ) or delete $children->{$old_parent};

			$self->[KR_PARENTS]->{$session} = $self;
			weaken($self->[KR_CHILDREN]->{$self}->{$session} = $session);

			$self->call( $session, '_parent', $old_parent, $self );
			# This is always the kernel... what the heck is this event for?
			#$self->call( $self, '_child', 'gain', $session );
			
			return 1;
		}
	}
	else {
		$! = ESRCH;
		return 0;
	}
}

sub post {
	my $self = shift;
	my ($to, $state, @etc) = @_;

	die "destination is undefined in post" unless(defined( $to ));
	die "event is undefined in post" unless(defined( $state ));

	# Name resolution /could/ happen during dispatch instead, I think everything would stay alive just fine simply because kernel is embedded in the event, and the sessions are all held inside aliases within that.
	my $from = CURRENT_SESSION;
	my $queue = $self->[KR_QUEUE];
	@$queue = sort { $a <=> $b } (@$queue, POE::Event->new( $self, time, $from, $to, $state, \@etc ));

	DEBUG "[POST] Kernel: $self From: $from To: $to State: $state Args: @etc\n" if DEBUGGING;
}

sub yield {
	my $self = shift;
	my ($state, @etc) = @_;

	die "event name is undefined in yield" unless(defined( $state )); 

	my $from = CURRENT_SESSION;
	my $queue = $self->[KR_QUEUE];
	@$queue = sort { $a <=> $b } (@$queue, POE::Event->new( $self, time, $from, $from, $state, \@etc ));
	
	DEBUG "[YIELD] Kernel $self From/To: $from State: $state\n" if DEBUGGING;
}

sub call {
	my $self = shift;
	my ($to, $state, @etc) = @_;

	croak( "destination undefined in call" ) unless(defined( $to ));
	croak( "event undefined in call" ) unless(defined( $to ));

	DEBUG "[CALL] Kernel: $self To: $to State: $state\n" if DEBUGGING;
	my $return;
	my @return;
	my $wantarray = wantarray;

	my $event = POE::Event->new( $self, undef, CURRENT_SESSION, $to, $state, \@etc );

	if (defined( $wantarray )) {
		if ($wantarray) {
			@return = $event->dispatch();
		}
		else {
			$return = $event->dispatch();
		}
	}
	else {
		$event->dispatch();
	}
	
	DEBUG "[CALL] Completed\n" if DEBUGGING;

	if (defined( $wantarray )) {
		if ($wantarray) {
			return @return;
		}
		else {
			return $return;
		}
	}
	else {
		return;
	}
}

sub resolve_session {
	my $self = shift;
	my $input = $_[0];
  
	my $aliases = $self->[KR_ALIASES];
	my $ids = $self->[KR_IDS];

	DEBUG( "[RESOLVE] Input: $input\n" ) if DEBUGGING;

	unless( $input ) {
		cluck( "Undefined state resolution attempted\n" );
	}

	if (ref( $input ) and $input->can('_invoke_state')) {
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

	my $current_session = CURRENT_SESSION;

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
		@{$main_class->{$fd}} = grep {
			defined( $_->{session} ) and $_->{session} != $current_session
		} (@{$main_class->{$fd}});
		
		@{$paused_class->{$fd}} = grep {
			defined( $_->{session} ) and $_->{session} != $current_session
		} (@{$paused_class->{$fd}});

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

#	$self->
#	if (@_ == 3) {
		my ($read, $write, $expedite) = @_;

		$self->select_read( $fh, $read );
		$self->select_write( $fh, $write );
		$self->select_expedite( $fh, $expedite );
#	}
#	elsif (@_ == 0) {
#		$self->select_read( $fh );
#		$self->select_write( $fh );
#		$self->select_expedite( $fh );
#	}
#	else {
#		die();
#	}
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
	my @stuff = @_;

	DEBUG( "[ALARM] delay\n" ) if DEBUGGING;
	
	die unless $_[1];

	_internal_alarm_destroy(@stuff);

	my $result;

	if (defined( $_[2] )) {
		$stuff[2] += time;
		$result = _internal_alarm_add(@stuff);
	}

	return 0 if (defined( $result ));
}

sub delay_add {
	my @stuff = @_;
	
	DEBUG( "[ALARM] delay_add\n" ) if DEBUGGING;
	
	die unless $_[1];
	die unless $_[2];

	$stuff[2] += time;

	return 0 if (defined( _internal_alarm_add(@stuff) ));
}

sub alarm {
	DEBUG( "[ALARM] alarm\n" ) if DEBUGGING;

	die unless $_[1];

	_internal_alarm_destroy(@_);

	my $result;
	
	if (defined( $_[2] )) {
		_internal_alarm_add(@_);
	}

	return 0 if (defined( $result ));
}

sub alarm_add {
	DEBUG( "[ALARM] alarm_add\n" ) if DEBUGGING;

	die unless $_[1];
	die unless $_[2];

	return 0 if (defined( _internal_alarm_add(@_) ));
}

sub _internal_alarm_add {
	my ($self, $name, $seconds, @args) = @_;

	DEBUG( "[ALARM] _internal_alarm_add\n" ) if DEBUGGING;

	my $queue = $self->[KR_QUEUE];

	my $current_session = CURRENT_SESSION;

	my $event = POE::Event::Alarm->new(
			$self,
			$seconds,
			$current_session,
			$current_session,
			$name,
			\@args,
			time,
		);

	@$queue = sort { $a <=> $b } (
		@$queue,
		$event
	);

	return $event->alarm_id;
}

sub _internal_alarm_destroy {
	my ($self, $event) = @_;

	my $queue = $self->[KR_QUEUE];

	my $current_session = CURRENT_SESSION;

	# This algorithm is completely wrong, I don't know what I was thinking when I wrote it
	
	@$queue = grep { not ( $_->can('alarm_id') and $current_session == $_->from and $event eq $_->name() ) } @$queue;
}

sub alarm_adjust {
	my ($self, $alarm_id, $delta) = @_;

	DEBUG( "[ALARM] Adjusting $alarm_id by $delta\n" ) if DEBUGGING;
	
	my $queue = $self->[KR_QUEUE];

	my @alarms = grep { $_->can('alarm_id') and $_->alarm_id == $alarm_id } @$queue;

	if (@alarms == 1) {
		return $alarms[0]->adjust_when( $delta );
	}
}

sub alarm_set {
	DEBUG( "[ALARM] Setting Alarm @_\n" ) if DEBUGGING;
	return _internal_alarm_add(@_);
}

sub alarm_remove {
	my ($self, $alarm_id) = @_;

	my $queue = $self->[KR_QUEUE];
	my @events;

	my $current_session = CURRENT_SESSION;

	DEBUG( "[ALARM] Attempting removal of ID# $alarm_id from $current_session\n" ) if DEBUGGING;

	@$queue = map { 
		DEBUG( "[ALARM] Iterating: $_ from " . $_->from . "\n" ) if DEBUGGING; 
		if ($_->can('alarm_id') and $_->alarm_id == $alarm_id and $current_session == $_->from) {
			push @events, $_;
			();
		}
		else {
			$_;
		}
	} @$queue;

	DEBUG( "[ALARM] " . @events . " matching events found, and removed\n" ) if DEBUGGING;

	if (@events == 1) {
		my $event = shift @events;
		my $things = [ $event->name, $event->when, $event->args ];

		if (wantarray) {
			return @$things;
		}
		else {
			return $things;
		}
	}

	return;
}

sub alarm_remove_all {
	my ($self) = @_;

	my $queue = $self->[KR_QUEUE];
	my @events;

	my $current_session = CURRENT_SESSION;

	DEBUG( "[ALARM] alarm_remove_all\n" ) if DEBUGGING;

	@$queue = map { 
		if ($_->can('alarm_id') and $current_session == $_->from) {
			push @events, $_;
			();
		}
		else {
			$_;
		}
	} @$queue;

	DEBUG( "[ALARM] alarm_remove_all: removed " . @events . " alarm events for $current_session.\n" ) if DEBUGGING;

	my $things = [ map { [ $_->name, $_->when, $_->args ] } @events ];

	if (wantarray) {
		return @$things;
	}
	else {
		return $things;
	}
}

sub delay_set {
	my @stuff = @_;

	DEBUG( "[ALARM] delay_set\n" ) if DEBUGGING;
	
	die unless $_[1];
	die unless $_[2];

	$stuff[2] += time;

	_internal_alarm_add(@stuff);
}

sub delay_adjust {
	my ($self, $alarm_id, $when) = @_;

	DEBUG( "[ALARM] delay_adjust\n" ) if DEBUGGING;

	my $queue = $self->[KR_QUEUE];

	my @alarms = grep { $_->can('alarm_id') and $_->alarm_id == $alarm_id } @$queue;

	if (@alarms == 1) {
		return $alarms[0]->set_when( $when + time );
	}
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
	my $signals = $self->[KR_SIGNALS];

	while (
			@$queue or
			keys %$fh_reads or
			keys %$fh_preads or
			keys %$fh_writes or
			keys %$fh_pwrites or
			keys %$fh_expedites or
			keys %$signals
		) {
		my $when;
		while (@$queue) {
			$when = $queue->[0]->when();
			my $now = time;
			if ($when <= $now) {
				my $event = shift @$queue;
				my $from = $event->from;
				my $name = $event->name;
				DEBUG "[DISPATCH] $event @$event From: $from Event: $name Args: " . join(',', $event->args) . "\n" if DEBUGGING;
				$event->dispatch();
				DEBUG "[DISPATCH] Completed\n" if DEBUGGING;
				if (@$queue) {
					$when = $queue->[0]->when();
				}
			}
			else {
				last;
			}
		}
		
		if (defined( $when )) {
			$when -= time;
			if ($when < 0) {
				$when = 0;
			}
		}
		
		$self->_select($when);
	}
	
	POE::Callstack::POP;
	POE::Callstack::CLEAN;
	POE::Callstack::PUSH( $poe_kernel );

	DEBUG "[RUN] Kernel exited cleanly\n" if DEBUGGING;
}

sub run_one_timeslice {
	my $self = shift;

	my $queue = $self->[KR_QUEUE];

	$self->_select( 0 );

	my $when;
	
	while (@$queue) {
		$when = $queue->[0]->when();
		if ($when <= time) {
			my $event = shift @$queue;
			my $from = $event->from;
			my $name = $event->name;
			$event->dispatch();
			if (@$queue) {
				$when = $queue->[0]->when();
			}
		}
		else {
			last;
		}
	}

	if (defined( $when )) {
		$when -= time;
		if ($when < 0) {
			$when = 0;
		}
	}

	return $when;
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
			DEBUG "[POLL] Waiting a maximum of $timeout for $read_count reads, $pread_count paused reads, $write_count writes, $pwrite_count paused writes, $expedite_count expedite reads, and $signal_count signals.\n";
		}
		else {
			DEBUG "[POLL] Waiting for $read_count reads, $pread_count paused reads, $write_count writes, $pwrite_count paused writes, $expedite_count expedite reads, and $signal_count signals.\n";
		}
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
	
	my $session = CURRENT_SESSION;
	my $aliases = $self->[KR_ALIASES];

	if (exists( $aliases->{$alias} )) {
		if ($aliases->{$alias} == $session) {
			return 0;
		}
		else {
			return EEXIST;
		}
	}
	else {
		$self->[KR_ALIASES]->{$alias} = $session;
		return 0;
	}

	# We can either hook into the session and wait for a DESTROY event to come back to us to clean up the alias, or we can stipulate that the session object must clean up all of it's own aliases. The latter may be better for speed and clean code.
}
 
sub alias_remove {
	my $self = shift;
	my $alias = $_[0];

	croak( "Called alias_remove with no arguments\n" ) unless @_;

	my $aliases = $self->[KR_ALIASES];

	if (exists( $aliases->{$alias} )) {
		if ($aliases->{$alias} == CURRENT_SESSION) {
			delete $aliases->{$alias};
			return 0
		}
		else {
			return EPERM;
		}
	}
	else {
		return ESRCH;
	}
}

sub alias_resolve {
	my $self = shift;
	my $alias = $_[0];

	my $aliases = $self->[KR_ALIASES];
	my $ids = $self->[KR_IDS];
	my $sessions = $self->[KR_SESSIONS];

	if (exists( $aliases->{$alias} )) {
		return $aliases->{$alias};
	}
	elsif (exists( $ids->{$alias} )) {
		return $ids->{$alias};
	}
	elsif (exists( $sessions->{$alias} )) {
		return $ids->{$sessions->{$alias}};
	}

	$! = ESRCH;
	return undef;
}

sub alias_list {
	my $self = shift;
	my $session = (@_ ? shift : CURRENT_SESSION);

	my $aliases = $self->[KR_ALIASES];
	
	return grep { $aliases->{$_} == $session } keys %$aliases;
}

sub _data_alias_loggable {
	my $self = shift;
	my $session = shift;

	my @aliases = $self->alias_list( $session );

	"session " . $session->ID . " (" .
		( @aliases
		? join( ", ", @aliases )
		: $session
	) . ")"
}

sub _warn {
#	DEBUG( @_ );
}

sub refcount_increment {
	my $self = shift;
	my $session = CURRENT_SESSION;
	my $refs = $self->[KR_REFS];
	unless (exists $refs->{$session} and ref $refs->{$session} eq 'ARRAY') {
		$refs->{$session} = [];
	}

	push @{$refs->{$session}}, $session;
}

sub refcount_decrement {
	my $self = shift;
	my $session = CURRENT_SESSION;
	my $refs = $self->[KR_REFS];

	shift @{$refs->{$session}};

	unless (@{$refs->{$session}}) {
		delete $refs->{$session};
	}
}

sub state {
	my $self = shift;
	my $session = CURRENT_SESSION;

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
	
	my $session = CURRENT_SESSION;

	if ($event) {
		DEBUG "[SIGNAL] Session: $session Signal: $signal_name Event: $event\n" if DEBUGGING;
		unless (exists( $signals->{$signal_name} )) {
			$signals->{$signal_name} = {};
		}
		my $watcher = $signals->{$signal_name}->{$session} = [ $session, $event ];

		# weaken( $watcher->[0] );

		if ($signal_name eq 'CHLD' or $signal_name eq 'CLD') {
			$self->_install_chld_handler;
		}
		elsif (exists( $SIG{$signal_name} )) {
			$self->_install_sig_handler( $signal_name );
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
	my $signal = $_[0];
	my @args = @_;
	
	my $queue = $self->[KR_QUEUE];
	@$queue = sort { $a <=> $b } (
		@$queue,
		POE::Event::Signal->new(
			$self,
			time(),
			CURRENT_SESSION,
			$session,
			$signal,
			\@args,
		)
	);
}

sub signal_ui_destroy {
	die( "Not implemented at this time\n" );
}

use POSIX ":sys_wait_h";

sub _install_chld_handler {
	DEBUG "Installing CHLD Handler\n" if DEBUGGING;
	my $kernel = shift;
	
	$SIG{CHLD} = sub {
		# Since this could happen between any two perl opcodes we should localize the error variable... waitpid plays with it.
		local $!;
		DEBUG( "Got CHLD SIGNAL\n" ) if DEBUGGING;
		my $child;
		while (($child = waitpid( -1, WNOHANG)) > 0) {
			my $status = $?;
			my $watchers = $kernel->[KR_SIGNALS]->{CHLD};
			DEBUG( "Reaped pid $child with result $status\n" ) if DEBUGGING;
			while (my ($session, $watcher) = each %$watchers) {
				DEBUG( "  Dispatching 'CHLD' to $watcher->[0]\n" ) if DEBUGGING;
				$kernel->signal( $watcher->[0], 'CHLD', $child, $status );
			}
		}
		DEBUG( "waitpid( -1, WNOHANG ) ended with status $child ($!)\n" ) if DEBUGGING;
		$kernel->_install_chld_handler; # This line could be keeping the kernel alive wrongly, not sure.
	};
}

sub _install_sig_handler {
	my $kernel = shift;
	my $signal_name = shift;
	my @args = @_;

	$SIG{$signal_name} = sub {
		my $watchers = $kernel->[KR_SIGNALS]->{$signal_name};
		while (my ($session, $watcher) = each %$watchers) {
			$kernel->signal( $watcher->[0], $signal_name, @args );
		}
		$kernel->_install_sig_handler( $signal_name );
	}
}

sub _data_sig_get_safe_signals {
	return keys %SIG;
}

sub sig_handled {
	POE::Event::Signal::HANDLED(1);
}

sub DESTROY {
  DEBUG "Kernel Destruction!\n" if DEBUGGING;
}

sub _invoke_state {

}

sub initialize_kernel {
	$poe_kernel = __PACKAGE__->new();
	weaken( $poe_kernel->[KR_IDS]->{$poe_kernel->ID} = $poe_kernel );
	$poe_kernel->[KR_SESSIONS]->{$poe_kernel} = $poe_kernel->ID;
}

initialize_kernel();
POE::Callstack::PUSH( $poe_kernel );

1;
