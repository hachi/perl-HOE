use 5.008007;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME		=> 'HOE',
	VERSION_FROM	=> 'lib/HOE.pm',
	PREREQ_PM	=> {
				Time::HiRes	=> 0,
				WeakRef		=> 0,
				Carp		=> 0,
				Errno		=> 0,
				POSIX		=> 0,
	},
	AUTHOR		=> 'Jonathan Steinert <hachi@cpan.org>',
	INC		=> '-I. -I./mylib',
);
