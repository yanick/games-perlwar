use strict;
use warnings;
use Test::More tests => 24;

use Games::PerlWar;

ok(1); # So we can load PerlWar. Yay!

my $pw = new Games::PerlWar( 't' );
$pw->load;

ok(1);  # game loaded

my( $result, $error, @Array );

$pw->array->cell(0)->set({ code => '"hello world!"' });
( $result, $error, @Array ) = $pw->execute( 0 );

is $result => "hello world!", 'cell execution';


$pw->array->cell(1)->set({ code => 'die' });
( $result, $error, @Array ) = $pw->execute( 1 );
isnt $error => '',  'agent doing a hara-kiri';

$pw->array->cell(2)->set({ code => '6/0' });
( $result, $error, @Array ) = $pw->execute( 2 );
isnt $error => '', "agent's code segfault'ing";

$pw->array->cell(3)->set_code('system "ls"');
( $result, $error, @Array ) = $pw->execute( 3 );
isnt $error => '', "agent trying to be naughty";

$pw->array->cell(4)->set_code('q while 1');
( $result, $error, @Array ) = $pw->execute( 4 );
isnt $error => '', 'agent running forever';

$pw->array->cell(5)->set_code('scalar @_');
( $result, $error, @Array ) = $pw->execute( 5 );
is $result => 97, 'Array size';

# access to $_
$pw->array->cell(6)->set_code('$_');
$pw->array->cell(7)->set_code('middle cell');
$pw->array->cell(8)->set_code('$_[-1]');
( $result, $error, @Array ) = $pw->execute( 6 );
is $result => '$_', 'access to $_';
( $result, $error, @Array ) = $pw->execute( 8 );
is $result => 'middle cell', 'access to other cells';

# access to @_
$pw->array->clear;
$pw->array->cell(0)->set_code('join ":",@_');
$pw->array->cell($_)->set_code($_) for 1..20;
( $result, $error, @Array ) = $pw->execute( 0 );

is $result => 'join ":",@_:1:2:3:4:5:6:7:8:9:10:11:12:13:14:15:16:17:18:19:20::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::', 'access to @_';

$pw->array->cell(0)->set_code('join ":",@o');
$pw->array->cell(0)->set_owner('neo');
( $result, $error, @Array ) = $pw->execute( 0 );
is $result => 'neo::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::', 'access to @o';

$pw->array->cell(0)->set_code('@x = map undef, 0..5; join ":",@x');
( $result, $error, @Array ) = $pw->execute( 0 );
is $result => ':::::', 'code with undef values';

# variables accessibles from a cell
# $S, $I, $i
$pw->array->cell(9)->set_code('"$S:$I:$i"');
( $result, $error, @Array ) = $pw->execute( 9 );
is $result => '67:97:13', '$S, $I, $i';

# And now, operations

$pw->array->clear;

# nuke function
$pw->array->cell(10)->set({ owner => 'neo', code => '"!13"' });
$pw->array->cell(11)->set({ owner => 'smith', 
                            code => '$_[-1] =~ s/!/#/g;"~-1"' });
$pw->array->cell(23)->set({ owner => 'smith', code => '1' });
$pw->array->cell(24)->set({ owner => 'smith', code => 'join ":", @_' });
$pw->array->cell(25)->set({ owner => 'neo', code => '"^-1"'  });

$pw->runSlot( $_ ) for 10..25;
my $array = $pw->array;

ok $array->cell(23)->is_empty, "nuke function (!)";

is $array->cell(10)->get_owner => 'neo', "alter function (~)";
is $array->cell(10)->get_code => '"#13"', "alter function (~)";
is $array->cell( 24 )->get_owner => 'neo', 'p0wning function (^)';

# 0wning
$array->cell(0)->set( { owner => 'luigi', code => "':2'" } );
$array->cell(1)->set( { owner => 'mario', code => "'^1'" } );
$pw->runSlot($_) for 0..1;
is $array->cell(0)->get_owner => 'luigi', "parents shouldn't be 0wned";
is $array->cell($_)->get_owner => 'mario', "0wning" for 1..2;

# self-modification
$array->cell(0)->set_code( '$_="tadam"' );

my $owner;
( $result, $error, $owner, @Array ) = $pw->execute( 0 );
is $Array[0] => 'tadam', "self-modification";

# ownership
$pw->array->clear;
$array->cell(0)->set( { owner => 'neo', code => '$o[0]="morpheus"' } );
$array->cell(1)->set( { owner => 'smith', code => '$_[1]="neo"' } );
$array->cell(2)->set( { owner => 'smith', code => '1' } );

$pw->runSlot(0);
is $array->cell(0)->get_apparent_owner => 'morpheus', 
    'agent can change its own facade';
$pw->runSlot(1);
is $array->cell(2)->get_apparent_owner => 'smith', 
    '..but not the facade of another agent';
