#!/usr/bin/perl

use strict;
use Test;

BEGIN
{
    plan tests => 11, todo => [];
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
print "$error\n";
ok( $result, '67:97:13' );


