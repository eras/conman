#!/usr/bin/perl -W

use strict;
use warnings;
use DBI;

my $dbfile = './cables.db';

print join("\n", DBI->available_drivers()), "\n";
