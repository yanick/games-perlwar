use ExtUtils::MakeMaker;

use strict;
use warnings;

WriteMakefile(
    NAME		=> 'Games::PerlWar',
    VERSION_FROM => 'PerlWar.pm',
    AUTHOR     => 'Yanick Champoux <yanick@cpan.org>',
    EXE_FILES => [ qw( scripts/pwcreate scripts/pwround scripts/pwupload ) ],
    PREREQ_PM => {
        'XML::Simple'   => 0,
        'File::Copy'    => 0,
        'IO::Prompt'    => 0,
        'version'       => 0,
    },
    ABSTRACT_FROM => 'lib/Games/PerlWar/Rules.pm',
);

