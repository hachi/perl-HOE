#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

MODULE = HOE			PACKAGE = HOE

MODULE = POE::Event		PACKAGE = POE::Event

void
dispatch( self )
	SV * self
	PPCODE:
	
	if (SvROK(self) && SvTYPE(SvRV(self))==SVt_PVAV) {
		AV *av = (AV*)SvRV(self);

		SV *from = *av_fetch(av, 2, 0);
		SV *to = *av_fetch(av, 3, 0);
		SV *name = *av_fetch(av, 4, 0);
		SV *args = *av_fetch(av, 5, 0);

		ENTER;
		SAVETMPS;

		PUSHMARK(SP);
		XPUSHs( to );
		XPUSHs( name );
		PUTBACK;
		call_pv("POE::Callstack::PUSH", G_DISCARD | G_VOID);

		FREETMPS;
		LEAVE;

		SPAGAIN;

		ENTER;
		SAVETMPS;

		PUSHMARK(SP);
		XPUSHs( to );
		XPUSHs( from );
		XPUSHs( name );
		XPUSHs( args );
		PUTBACK;
		/* call _invoke_state with the original call context, return will fall through */
		call_method("_invoke_state", GIMME_V | G_EVAL);

		SPAGAIN;

		if (SvTRUE(ERRSV))
		{
			if (GIMME_V & G_SCALAR)
				POPs;
			

		}
		
		/* magical scope trick, clear the event so everything destructs when we LEAVE
		 * but before we POE::Callstack::POP */
		av_clear(av);
	
		/* no FREETMPS here, keeps the return value from _invoke_state on the stack
		 * intact. Basically we want to let the return value just fall through and be
		 * cleaned up in the next layer up. */
		LEAVE;

		ENTER;
		/* save stack pointer so we can restore it after this call, same reason as
		 * the FREETMPS comment above */
		PUSHMARK(SP);
		
		call_pv("POE::Callstack::POP", G_DISCARD | G_NOARGS | G_VOID);

		PUTBACK;
		LEAVE;
	}

MODULE = HOE			PACKAGE = HOE
