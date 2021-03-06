package POE::Session::Hachi;

use base 'POE::Session';

use Errno qw(ENOSYS);

use strict;

sub _invoke_state {
 my ($self, $source_session, $state, $etc, $file, $line, $fromstate) = @_;

  # Trace the state invocation if tracing is enabled.

  if ($self->[POE::Session::SE_OPTIONS]->{+POE::Session::OPT_TRACE}) {
    POE::Kernel::_warn(
      $POE::Kernel::poe_kernel->ID_session_to_id($self),
      " -> $state (from $file at $line)\n"
    );
  }

  # The desired destination state doesn't exist in this session.
  # Attempt to redirect the state transition to _default.

  unless (exists $self->[POE::Session::SE_STATES]->{$state}) {

    # There's no _default either; redirection's not happening today.
    # Drop the state transition event on the floor, and optionally
    # make some noise about it.

    unless (exists $self->[POE::Session::SE_STATES]->{+POE::Session::EN_DEFAULT}) {
      $! = ENOSYS;
      if ($self->[POE::Session::SE_OPTIONS]->{+POE::Session::OPT_DEFAULT} and $state ne POE::Session::EN_SIGNAL) {
        my $loggable_self =
          $POE::Kernel::poe_kernel->_data_alias_loggable($self);
        POE::Kernel::_warn(
          "a '$state' event was sent from $file at $line to $loggable_self ",
          "but $loggable_self has neither a handler for it ",
          "nor one for _default\n"
        );
      }
      return undef;
    }

    # If we get this far, then there's a _default state to redirect
    # the transition to.  Trace the redirection.

    if ($self->[POE::Session::SE_OPTIONS]->{+POE::Session::OPT_TRACE}) {
      POE::Kernel::_warn(
        $POE::Kernel::poe_kernel->ID_session_to_id($self),
        " -> $state redirected to _default\n"
      );
    }

    # Transmogrify the original state transition into a corresponding
    # _default invocation.

    $etc   = [ $state, $etc ];
    $state = POE::Session::EN_DEFAULT;
  }

  # If we get this far, then the state can be invoked.  So invoke it
  # already!

  local $POE::SESSION	= $self;
  local $POE::KERNEL	= $POE::Kernel::poe_kernel;
  local $POE::HEAP	= $self->[POE::Session::SE_NAMESPACE];
  local $POE::STATE	= $state;
  local $POE::SENDER	= $source_session;
  local $POE::CALLER_FILE	= $file;
  local $POE::CALLER_LINE	= $line;
  local $POE::CALLER_STATE	= $fromstate;

  # Inline states are invoked this way.

  if (ref($self->[POE::Session::SE_STATES]->{$state}) eq 'CODE') {
    return $self->[POE::Session::SE_STATES]->{$state}->( @$etc );
  }

  # Package and object states are invoked this way.

  my ($object, $method) = @{$self->[POE::Session::SE_STATES]->{$state}};
  return $object->$method( @$etc );
}

1;
