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
		perl -Mlib=mylib -Mlib=lib test.pl

poetest:
		perl -Mlib=mylib test.pl

coverage:
		perl -Mlib=mylib -Mlib=lib t/00_coverage.t > coverage || true

coverageupload:	coverage
		scp coverage hachi.kuiki.net:/www/hachi.kuiki.net/projects/hoe/coverage.txt
