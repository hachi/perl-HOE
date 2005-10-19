package HOE;

use 5.008007;
use strict;
use warnings;

our $VERSION = '0.00_01';
$VERSION = eval $VERSION;

my $location = $INC{'HOE.pm'};

$location =~ s{\.pm$}{/};

warn "Location: $location";

unshift @INC, $location;

1;
