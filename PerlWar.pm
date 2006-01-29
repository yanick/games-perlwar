package Games::PerlWar;

use version; our $VERSION = qv('0.1_1');

use strict;
use warnings;
use utf8;

use Safe;
use XML::Simple;


sub new {
    my( $class, $dir ) = @_;
    my $self = { dir => $dir, interactive => 1 };
    chdir $self->{dir};
    bless $self, $class;
}

sub clear_log {
	my $self = shift;
	$self->{log} = ();
}

sub load {
	my $self = shift;
	
	print "loading configuration.. ";

	$self->{conf} = XMLin( 'configuration.xml' );
	my %players;
	for( @{$self->{conf}{player}} )
	{
		$players{ $_->{content} } = 
			{ password => $_->{password},
				color => $_->{color},
				status => $_->{status} };
	}
	$self->{conf}{player} = \%players;

	my $xml = XML::LibXML->new->parse_file( 'round_current.xml' );

	$self->{round} = $xml->findvalue( '/round/@number' ) || 0;
	print "this is round $self->{round}\n";
	my @theArray;
	$self->{theArray} = \@theArray;
	for my $slot ( 0..$self->{conf}{theArraySize}-1 )
	{
		my $owner = $xml->findvalue( "//slot[\@id=$slot]/owner/text()" );
		my $code = $xml->findvalue( "//slot[\@id=$slot]/code/text()" );

		#print "$slot : $owner : $code\n";
		if( $code )
		{
			utf8::decode( $code );
			$theArray[ $slot ] = { owner => $owner, code => $code };
		}
	}
}

sub play_round
{
	my $self = shift;
	
	# $self->load;

	# check if the game is over (because a player won)
	if( $self->{conf}{gameStatus} eq 'over' )
	{
		print "game is already over, exiting\n";
		return
	}

	# check if the game is over (because round > game length)
	$self->{round}++;
	$self->{conf}{currentIteration} = $self->{round};
	if( $self->{round} > $self->{conf}{gameLength} )
	{
		print "number of rounds limit reached, game is over\n";
		return;
	}

	$self->{log} = [];
	$self->log( localtime() . " : running round ".$self->{round} );
	
	# import newcomers
	$self->log( "train arriving from Station Mobil.." );
	$self->introduce_newcomers;
	
	# check if players are eliminated
	$self->checkForEliminatedPlayers;
	
	# run each slot
	$self->log( "running the Array.." );
	for( 0..$self->{conf}{theArraySize}-1 )
	{
		$self->runSlot( $_ );
	}

	# sanity check, make sure cells without agents are without owner
	for( 0..$self->{conf}{theArraySize}-1 )
	{
		if( $self->{theArray}[ $_ ]{owner} and not length $self->{theArray}[ $_ ]{code} ) 
		{
			$self->log( "warning: cell at position is empty and yet owned. Correcting the Array.." );
			$self->{theArray}[ $_ ] = undef;
		}
	}
	
	# check for victory
	
	# if victory, change the config
	
	# save the round
	#$self->save;
}

sub save
{
	my $self = shift;
	
	print "saving round $self->{round}..\n";
	
	$self->saveConfiguration;
	
	#XMLout( $self->{conf}, OutputFile => "configuration.xml", RootName => 'configuration' );
	
	use XML::Writer;
	use IO::File;

	my $output = new IO::File(">round_current.xml");
	my $writer = new XML::Writer(OUTPUT => $output);

	$writer->startTag( "round", number => $self->{round} );
	
	if( $self->{newcomers} )
	{
		$writer->startTag( 'newcomers' );
		
		for( @{$self->{newcomers}} )
		{
			my @x = @$_;
			$writer->dataElement( 'newcomer', $x[2], player => $x[0], time => $x[1] );
		}
		$writer->endTag;
	}
	
	
	if( $self->{log} )
	{
  		$writer->startTag( 'log' );
  		$writer->dataElement( 'entry', $_ ) for @{$self->{log}};
  		$writer->endTag;
	}

	$writer->startTag( 'theArray' );
	for( 0..$self->{conf}{theArraySize} )
	{
		next unless $self->{theArray}[$_];
  		$writer->startTag( 'slot', id => $_ );
  		my %slot = %{ $self->{theArray}[$_] };
  		$writer->dataElement( owner => $slot{owner} );
  		$writer->dataElement( code => $slot{code} );
  		$writer->endTag;
	}
	$writer->endTag;

	$writer->endTag;
	$writer->end();

	$output->close();

	open my $current_file, "round_current.xml" or die;
	open my $archive, sprintf( ">round_%05d.xml", $self->{round} ) or die "$!";
	print $archive $_ while <$current_file>;
	close $current_file;
	close $archive;
}

##########################################################################

sub saveConfiguration
{
	my %conf = @_ == 1 ? %{$_[0]->{conf}} : @_;
	
	my $output = new IO::File(">configuration.xml");
	my $writer = new XML::Writer(OUTPUT => $output);

	$writer->startTag( 'configuration' );
	$writer->dataElement( 'title', $conf{title} );
	$writer->dataElement( 'gameStatus', $conf{gameStatus} );
	$writer->dataElement( 'gameLength', $conf{gameLength} );
	$writer->dataElement( 'theArraySize', $conf{theArraySize} );
	$writer->dataElement( 'snippetMaxLength', $conf{snippetMaxLength} );
	
	$writer->dataElement( 'currentIteration', $conf{currentIteration} );
	if( $conf{mamboDecrement} )
	{
		$writer->dataElement( 'mamboDecrement', $conf{mamboDecrement} );
	}
	$writer->dataElement( 'note', $conf{note} );
	
	foreach( keys %{$conf{player}} )
	{
		$writer->dataElement( 'player', $_, color => $conf{player}{$_}{color}, 
			password => $conf{player}{$_}{password}, status => $conf{player}{$_}{status} );
	}
	
	$writer->endTag;
	$writer->end;
	$output->close;
}

##########################################################################

sub checkForEliminatedPlayers
{
	my $self = shift;
	
	no warnings 'uninitialized';
	
	$self->log( "checking for eliminated players.." );
	
	my %score;
	for my $pos ( 0..$self->{conf}{theArraySize} -1 ) 
	{
		$score{ $self->{theArray}[$pos]{owner} }++;
	}
	
	for my $player ( keys %{ $self->{conf}{player} } )
	{
		next if $self->{conf}{player}{$player}{status} eq 'EOT';
		unless( $score{ $player }  )
		{
			$self->log( "\tplayer $player lost all agents, eliminated" );
			$self->{conf}{player}{$player}{status} = 'EOT';	
		}
	}
	
}

##########################################################################

sub introduce_newcomers
{
	no warnings 'uninitialized';
	my $self = shift;
	
	chdir 'mobil';
	my $dir;
	opendir $dir, '.' or die "couldn't open dir mobil: $!\n";
	
	my @files = sort { -M $b <=> -M $a } grep { exists $self->{conf}{player}{$_} } readdir $dir;
	closedir $dir;
	
	$self->log( "\tno-one was aboard" ) if not @files;

	AGENT: for my $player ( @files )
	{
		my $date = localtime( $^T - (-M $player)*24*60*60 );
		$self->log( "\t".$player."'s new agent is aboard (u/l'ed $date)" );
		
		my $fh;
		my $code;
		{
			undef $/;
			open $fh, $player or die;
			$code = <$fh>;
			close $fh;
		}
		
		push @{$self->{newcomers}}, [ $player, $date, $code  ];
		
		# dead players can't submit agents
		if( $self->{conf}{player}{$player}{status} eq 'EOT' )
		{
			$self->log( "\tplayer is eliminated, can't submit a new agent" );
			unlink $player or $self->log( "ERROR: $!" );
			next AGENT;
		}
		
		my @available_slots;
		for( 0..$self->{conf}{theArraySize}-1 )
		{
			push @available_slots, $_ unless $self->{theArray}[$_];
		}
		
		if( @available_slots > 0 )
		{
			my $slot = $available_slots[ rand @available_slots ];
			$self->log( "\tagent inserted at cell $slot" );
			$self->{theArray}[$slot] = { owner => $player, code => $code };
			unlink $player or $self->log( "ERROR: $!" );
			next AGENT;
		}
		
		for( 0..$self->{conf}{theArraySize}-1 )
		{
			push @available_slots, $_ if $self->{theArray}[$_]{owner} eq $player;
		}
		
		if( @available_slots > 0 )
		{
			my $slot = $available_slots[ rand @available_slots ];
			$self->log( "agent at cell $slot is upgraded" );
			$self->{theArray}[$slot] = { owner => $player, code => $code };
			unlink $player or $self->log( "ERROR: $!" );
			next AGENT;
		}
		
		$self->log( "no empty slot left, agent deleted" ); 
		unlink $player or $self->log( "ERROR: $!" );
	}
	
	chdir '..';
}

##########################################################################

sub log 
{
  my $self = shift;
  
  return @{$self->{log}} unless @_;

  if( $self->{interactive} ) 
  {
    local $\ = "\n";
    print for @_;
  }

  push @{$self->{log}}, @_;
}

##########################################################################

sub insert_agent
{
	my ( $self, $pos, $player, $code ) = @_;
	
	$self->log( "can't insert agent: cell $pos out of bound" )
		if $pos >= $self->{conf}{theArraySize};
		
	$self->{theArray}[$pos] = { owner => $player, code => $code };
	
}

##########################################################################

# ( $result, $error, @array ) = $pw->execute( @array )
# executes the code of $array[0]
sub execute
{
	my $self = shift;
	local @_ = @_;
	local $_ = $_[0];
	   
	# run this in a safe
	my $safe = new Safe 'Container';
	$safe->permit( qw/ rand time sort :browse :default / );
	my $result;
	my $error;
  
	eval 
	{
    	local $SIG{ALRM} = sub { die "timed out\n" };
    	alarm 3;
		undef $@;
		my $code = $_[0];
		@Container::Array = @_;
		$Container::S = $self->{conf}{snippetMaxLength};
		$Container::I = $self->{conf}{gameLength};
		$Container::i = $self->{conf}{currentIteration};
		$safe->share_from( 'Container', [ '$S', '$I', '$i', '@_' ] );
		$result = $safe->reval( <<EOT );
local *_ = \\\@Array;
#*_ = *Array;
\$_ = \$_[0];
$code
EOT
	
    	$error = $@;   
    	alarm 0;
  	};

	if( $error )
	{
		return( $result, $error );
	}
	else
	{
		my @array = $safe->reval( '@Array' );
		$array[0] = $safe->reval( '$_' );
		return( $result, $error, @array );
	}
}

##########################################################################

sub runSlot 
{
  	my ( $self, $slotId ) = @_;

	return unless $self->{theArray}[ $slotId ];
	
	my %slot = %{$self->{theArray}[ $slotId ]};

	return if $slot{freshly_copied} or not $slot{code};

	$self->log( "cell $slotId: agent owned by $slot{owner}" ); 

	my @Array = map $_->{code}, @{$self->{theArray}}[ $slotId..(@{$self->{theArray}}-1), 0..($slotId-1) ];
 
	# exceed permited size?
  	if( length $slot{code} > $self->{conf}{snippetMaxLength} )
  	{
    	$self->log( "\tagent crashed: is ".length($Array[0])." chars, exceeds max permitted size $self->{conf}{snippetMaxSize}" ); 
    	$self->{theArray}[ $slotId ] = {};
    	return;
  	}

  	$self->log( "\texecuting.." );
  	
  	my( $result, $error );
  	( $result, $error, @Array ) = $self->execute( @Array );

	$self->{theArray}[$slotId]{code} = $Array[0];

	if( $error ) {
    	$self->log( "\tagent crashed: $error" );
    	$self->{theArray}[$slotId] = {};
    	return;
  	} 

  	my $output = $result;
  	$output = substr( $output, 0, 24 ).".." if length $output > 25;
  	$output =~ s#\n#\\n#g;
  	
    $self->log( "\tagent returned: $output" );
    
    if( $result =~ /^!(-?\d*)$/ ) {
        $self->_nuke_operation( $slotId, $1 );
    }
    elsif( $result =~ /^\^(-?\d*)$/ ) {
        $self->_p0wn_operation( $slotId, $1 );
    }
    elsif( $result =~ /^~(-?\d*)$/ ) {
        $self->_alter_operation( $slotId, $1, \@Array );
    }
    elsif( $result =~ /^(-?\d*):(-?\d*)$/ ) {
        $self->_copy_operation( $slotId, $1, $2 );
    }
    else {
    	$self->_noop_operation();
    }
}

sub _nuke_operation {
    my( $self, $agent_index, $target_index ) = @_;

    $target_index = $self->relative_to_absolute_position( $agent_index, $target_index );
    return if $target_index == -1;
    
    unless( $self->{theArray}[ $target_index ] ) {
        $self->log( "\tno agent found at cell $target_index" );
        return;
    }
		
    $self->{theArray}[ $target_index ] = { };
    $self->log( "\tagent in cell $target_index destroyed" );
}

sub _p0wn_operation {
    my( $self, $agent_index, $target_index ) = @_;

    $target_index = $self->relative_to_absolute_position( $agent_index, $target_index );

    return if $target_index == -1;

    unless( $self->{theArray}[$target_index] and $self->{theArray}[$target_index]{code} ) {
	   $self->log( "\tno agent to p0wn in cell $target_index" );
	   return;
    }

    $self->log( "\tagent in cell $target_index p0wned" );
    $self->{theArray}[$target_index]{owner} = $self->{theArray}[$agent_index]{owner};
}

sub _alter_operation {
    my ( $self, $agent_index, $target_index, $Array_ref ) = @_;

    my $abs_target_index = $self->relative_to_absolute_position( $agent_index, $target_index );
    return if $abs_target_index == -1;
      
    unless( $self->{theArray}[$abs_target_index] and $self->{theArray}[$abs_target_index]{code} ) {
        $self->log( "\tno agent found at cell $abs_target_index" );
      	return;
    }

    $self->{theArray}[$abs_target_index]{code} = $Array_ref->[$target_index];
    $self->log( "\tcode of agent in cell $abs_target_index altered" );
}

sub _copy_operation {
    my( $self, $agent_index, $source_index, $dest_index ) = @_;
    
    $source_index = $self->relative_to_absolute_position( $agent_index, $source_index );
    $dest_index   = $self->relative_to_absolute_position( $agent_index, $dest_index );
    
    # source or destination invalid? We do nothing
    return if $source_index == -1 or $dest_index == -1;
    
    if( $self->{theArray}[$dest_index]{owner} 
            and $self->{theArray}[$dest_index]{owner} ne $self->{theArray}[$agent_index]{owner} )
    {
        $self->log( "\tagent in cell $dest_index already owned by $self->{theArray}[$dest_index]{owner}" );
        return;
    }

    $self->log( "\tagent of cell $source_index copied into cell $dest_index" );
    $self->{theArray}[$dest_index] = { %{$self->{theArray}[$source_index]} };
    $self->{theArray}[$dest_index]{freshly_copied} = 1 ;
}

sub _noop_operation {
    my( $self ) = @_;
    
    $self->log( "\tno-op" );
}

sub relative_to_absolute_position
{
  my( $self, $slotId, $shift ) = @_;
  $shift ||= 0;

  if( abs( $shift ) > $self->{conf}{theArraySize} ) {
    $self->log( "\tposition $shift out-of-bound" );
    return -1;
  }
  $slotId += $shift + 2 * $self->{conf}{theArraySize};
  $slotId %= $self->{conf}{theArraySize};

  return $slotId;
}

sub readCell {
	my( $self, $cellId ) = @_;
	return undef unless $self->{theArray}[$cellId];
	return ( $self->{theArray}[$cellId]{owner}, $self->{theArray}[$cellId]{code}  );
}

sub writeCell {
	my( $self, $pos, $owner, $code ) = @_;
	$self->{theArray}[$pos] = { owner => $owner, code => $code };
}


=begin notes

my $pw = new Games::PerlWar;

$pw->{interactive} = 1;
$pw->{theArray} = [ { owner => 'Yanick', name => 'Neo', code => 'print "Hello world!"' },
                    { owner => '1337 h4ck3r', name => 'crash me', code => 'exit' },
                    { owner => '1337 h4ck3r', name => 'readdir me', code => 'opendir DIR, "."; return readdir DIR;' },
                    { owner => '1337 h4ck3r', name => 'infinite loop', code => '1 while 1' },
                    { owner => '1337 h4ck3r', name => 'backticks', code => '`ls`' },
                    { owner => '1337 h4ck3r', name => 'kill next', code => '"!1"' },
                    { owner => '1337 h4ck3r', name => 'must die', code => '"I am still alive?"' },
                    { owner => 'Yanick', name => 'good boy', code => '1' },
                    { owner => 'Yanick', name => 'owner', code => '"~-1"' },
                    { owner => 'Yanick', name => 'too big', code => 'a' x 200 },
                    ];
$pw->{config}{arraySize} = @{ $pw->{theArray} };
$pw->{config}{maxSnippetSize} = 100;

$pw->runSlot( $_ ) for 0..9;

=end notes

=cut

1;

__END__

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#  Module Documentation
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

=head1 NAME

Games::PerlWar - A Perl variant of the classic Corewar game

=head1 DESCRIPTION

For the rules of PerlWar, please refers to the Games::PerlWar::Rules manpage.

=head1 HOW TO START AND MANAGE A PW GAME (THE SHORT AND SKINNY)

Use the script I<pwcreate> to create a new game. 

    $ pwcreate [ <game_directory> ]

pwcreate will create I<game_directory> and populate it with the everything
the new game will need. If I<game_directory> is not provided, I<pwcreate> will
create a sub-directory called 'game'. 

Once the game is created, 
the script I<pwupload> can be used to submit the agents to
be introduced into the Array:

    $ pwupload <game_directory> <player> 

I<pwupload> takes two arguments: the game directory and the name of
the agent's owner. The script then reads the script from STDIN. 
E.g.:

    $ pwupload /home/perlwar/myWar yanick < borg.pl

Finally, I<pwround> executes an iteration of the game:

    $ pwround <game_directory>

I<pwround> isn't interactive and can easily be called from a cron job.

=head1 BUGS AND LIMITATIONS

I<pwupload> currently only works for local games. It will be
soonishly extended to allow submissions to network games.

=head1 AUTHOR

Yanick Champoux (yanick@perl.org)

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2005, 2006 Yanick Champoux (yanick@cpan.org). All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See perldoc perlartistic.

This program is distributed in the hope that it will be useful
(or at least entertaining), but WITHOUT ANY WARRANTY; without 
even the implied warranty of MERCHANTABILITY or FITNESS FOR 
A PARTICULAR PURPOSE.

=cut

