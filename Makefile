BASE	?= /usr/local
PREFIX	= $(DESTDIR)$(BASE)
SHARE	= $(PREFIX)/share/hoe/POE

install:	lib/POE/Kernel.pm lib/POE/Event.pm lib/POE/Callstack.pm
		install -d $(SHARE)
		install lib/POE/Kernel.pm $(SHARE)
		install lib/POE/Event.pm $(SHARE)
		install lib/POE/Callstack.pm $(SHARE)

diff-install:
		diff -u $(SHARE)/Kernel.pm lib/POE/Kernel.pm || true
		diff -u $(SHARE)/Event.pm lib/POE/Event.pm || true
		diff -u $(SHARE)/Callstack.pm lib/POE/Callstack.pm || true

test:
		perl -Mlib=lib test.pl
