#!/usr/bin/perl

use strict;
use Test;

BEGIN
{
    plan tests => 2, todo => [];
}

use Games::PerlWar;

ok(1); # So we can load PerlWar. Yay!

my $pw = new Games::PerlWar( 't' );
$pw->load;

ok(1);  # game loaded

# let's test the variables accessibles from a cell

=item $_
the code of the snippet.

=item @_
the whole Array, positioned relatively to the current snippet. (i.e., $_[0] == $_ )

=item $W, $R, $r
the game's parameters $W (max snippet's length) and $R (max # of rounds), plus the current round $r.



$pw->insert_agent( 0, 'foo', "':-1';" );

$pw->clear_log;

$pw->runSlot(0);

die join ":", $pw->log;
