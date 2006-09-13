use strict;
use warnings;
use Module::Build;

Module::Build->new(
    module_name         => 'Games::Perlwar',
    license             => 'perl',
    dist_author         => 'Yanick Champoux <yanick@cpan.org>',
    dist_version_from   => 'lib/Games/PerlWar.pm',
    build_requires => {
        'XML::Simple'      => 0,
        'File::Copy'       => 0,
        'Carp'             => 0,
        'IO::Prompt'       => 0,
        'version'          => 0,
    },
    script_files => [ qw# scripts/pwcreate 
                          scripts/pwround 
                          scripts/pwupload 
                          scripts/perlwar   # ],
    add_to_cleanup      => [ ],
    create_makefile_pl  => 'traditional',
    sign            => 1,
    dist_abstract   => <<END_ABSTRACT,
PerlWar is inspired by the classic Corewar game.
In this game, players pit snippets of Perl code (called 'agents') 
against each other in order to gain control of the vicious virtual
battlefield known as... the Array.
END_ABSTRACT
)->create_build_script;