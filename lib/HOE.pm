package HOE;

use 5.008007;
use strict;
use warnings;

our $VERSION = '0.00_01';
our $XS_VERSION = $VERSION;
$VERSION = eval $VERSION;

unless (exists( $ENV{HOE_DISABLE} ) and $ENV{HOE_DISABLE}) {
	my $location = $INC{'HOE.pm'};
	$location =~ s{\.pm$}{/};
	unshift @INC, $location;

}
else {
	warn( "Disabling HOE via environment HOE_DISABLE=$ENV{HOE_DISABLE}\n" );
}

1;
