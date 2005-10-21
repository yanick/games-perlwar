#!/usr/bin/perl

use strict;
use Test;

BEGIN
{
    plan tests => 20, todo => [];
}

use Games::PerlWar;

ok(1); # So we can load PerlWar. Yay!

my $pw = new Games::PerlWar( 't' );
$pw->load;

ok(1);  # game loaded

my( $result, $error, @Array );

( $result, $error, @Array ) = $pw->execute( '"hello world!"' );
ok( $result, "hello world!" );

( $result, $error, @Array ) = $pw->execute( 'die' );
ok( $error ne "" );

( $result, $error, @Array ) = $pw->execute( '6/0' );
ok( $error ne "" );

( $result, $error, @Array ) = $pw->execute( 'system "ls"' );
ok( $error ne "" );

( $result, $error, @Array ) = $pw->execute( '1 while 1' );
ok( $error ne "" );

( $result, $error, @Array ) = $pw->execute( 'scalar @_', ('a')x99 );
ok( $result, 100 );

# access to $_
( $result, $error, @Array ) = $pw->execute( '$_', "next cell" );
ok( $result, '$_' );

# Can we access other cells? 
( $result, $error, @Array ) = $pw->execute( '$_[1]', "next cell" );
ok( $error, "" );
ok( $result, "next cell" );

# let's test the variables accessibles from a cell

# $S, $I, $i
( $result, $error, @Array ) = $pw->execute( '"$S:$I:$i"' );
ok( $result, '67:97:13' );

# And now, operations

# nuke function
$pw->writeCell( 10, 'neo', '"!13"' );
$pw->writeCell( 11, 'smith', '$_[-1] =~ s/!/#/g;"~-1"' );
$pw->writeCell( 23, 'smith', '1' );
$pw->writeCell( 24, 'smith', 'join ":", @_' );
$pw->writeCell( 25, 'neo', '"^-1"' );

$pw->play_round;

ok $pw->readCell(23), undef, "nuke function (!)";

ok( ($pw->readCell(10))[0], 'neo', "alter function (~)" );
ok( ($pw->readCell(10))[1], '"#13"', "alter function (~)" );
ok( ($pw->readCell(24))[0], 'neo', 'p0wning function (^)' );

# 0wning
$pw->{theArray}[0] = { owner => 'luigi', code => "':2'" };
$pw->{theArray}[1] = { owner => 'mario', code => "'^1'" };
$pw->play_round;
ok $pw->{theArray}[0]{owner}, 'luigi', "parents shouldn't be 0wned";
ok $pw->{theArray}[$_]{owner}, 'mario', "0wning" for 1..2;

# self-modification

ok( ($pw->execute( '$_="tadam"' ))[2], 'tadam', "self-modification" );


