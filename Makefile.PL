use ExtUtils::MakeMaker;

use strict;
use warnings;

WriteMakefile(
    NAME		=> 'Games::PerlWar',
    VERSION_FROM => 'PerlWar.pm',
     AUTHOR     => 'Yanick Champoux <yanick@babyl.dyndns.org>',
     EXE_FILES => [ qw/ pwcreate pwround  / ]
     
);

