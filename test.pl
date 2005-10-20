#!/usr/bin/perl

use Test::Harness;

use strict;
use warnings;

use lib './mylib';

use HOE;

runtests(<tests/*.t>);
