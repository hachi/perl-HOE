#!/usr/bin/perl

use Test::More tests => 42;

use strict;
use warnings;

use POE;

my @management = qw(ID run run_one_timeslice stop); # Add the last two to POE docs synopsis.
my @FIFO = qw(post yield call);
my @original_alarms = qw(alarm alarm_add delay delay_add);
my @new_alarms = qw(alarm_set delay_set alarm_adjust delay_adjust alarm_remove alarm_remove_all);
my @aliases = qw(alias_set alias_remove alias_resolve ID_id_to_session ID_session_to_id alias_list);
my @filehandle = qw(select_read select_write select_pause_read select_resume_read select_pause_write select_resume_write select_expedite select); # select_pause_read missing in POE docs main body
my @sessions = qw(detach_child detach_myself); # Missing from POE synopsis
my @signals = qw(sig sig_handled signal signal_ui_destroy); # signal_ui_destory missing from synposis
my @state = qw(state);
my @refcount = qw(refcount_increment refcount_decrement);
my @data = qw(get_active_session get_active_event);

my @all = (@management, @FIFO, @original_alarms, @new_alarms, @aliases, @filehandle, @sessions, @signals, @state, @refcount, @data);
		
foreach my $method (@all) {
	if (POE::Kernel->can($method)) {
		pass( "$method" );
	}
	else {
		fail( "$method" );
	}
}

1;

# vim: filetype=perl
