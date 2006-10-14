package Games::PerlWar;

use version; our $VERSION = qv('0.1_1');

use strict;
use warnings;
use utf8;

use Safe;
use XML::Simple;
use XML::Writer;
use IO::File;

use Games::PerlWar::Array;
use Games::PerlWar::Cell;
use Games::PerlWar::AgentEval;

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub new {
    my( $class, $dir ) = @_;
    my $self = { dir => $dir, interactive => 1 };
    chdir $self->{dir};
    bless $self, $class;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub clear_log {
	my $self = shift;
	$self->{log} = ();
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub load {
    my ( $self, $iteration ) = @_;
	
	print "loading configuration.. ";

	$self->{conf} = XMLin( 'configuration.xml' );
	my %players;
	for( @{$self->{conf}{player}} )
	{
		$players{ $_->{content} } = { 
                password => $_->{password},
				color => $_->{color}, 
        };
	}
	$self->{conf}{player} = \%players;

    my $xml;
    my $filename;
    if ( defined $iteration ) {
        $filename = sprintf( "round_%05d.xml", $iteration );
        -e $filename or die "couldn't load round $iteration\n";
    } 
    else {
        $filename = 'round_current.xml';
    }
    $xml = XML::LibXML->new->parse_file( $filename );

	$self->{round} = $xml->findvalue( '/round/@number' ) || 0;
    $self->{round}++ unless defined $iteration;
	print "this is round $self->{round}\n";

	$self->{theArray} = Games::PerlWar::Array->new({ 
                            size => $self->{conf}{theArraySize} });

    $self->{theArray}->load_from_xml( $xml );

    if ( defined $iteration ) {
        my @newcomers;
        for my $n ( $xml->findnodes( '/newcomer' ) ) {
            push @newcomers, { map { $n->findvalue( $_ ) } 
                                    '@player', '@time', 'text()' };
        }
        $self->{newcomers} = \@newcomers;
        $self->{old_iteration} = 1;
    }

    my @players = keys %{ $self->{conf}{player} };
    my $actives;
    $self->agent_census;
    # everyone's active on round 1
    if ( $self->{round} == 1 ) {
        $self->{conf}{player}{$_}{status} = 'OK' for @players;
        $actives = 99;
    } 
    else {
        for( @players) {
            $self->{conf}{player}{$_}{status} = $self->{conf}{player}{$_}{agents} 
                                              ? 'OK' 
                                              : 'EOT'
                                              ;
            $actives++ if $self->{conf}{player}{$_}{agents};
        } 
    }

    $self->set_game_status( 
        # game is over if we're out of time or there's only one man standing
        ( $actives < 2 ) || ( $self->{round} > $self->{conf}{gameLength} )
            ? 'over'
            : ''
    );
}   

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub visit_mobil_station {
    my $self = shift;

    $self->{newcomers} = [];
    chdir 'mobil';
        
    opendir my $dir, '.' or die "couldn't open dir mobil: $!\n";
    my @files = sort { -M $b <=> -M $a } 
                grep { exists $self->{conf}{player}{$_} } 
                     readdir $dir;
    closedir $dir;

    for my $player ( @files ) {
        my $date = localtime( $^T - (-M $player)*24*60*60 );
		
        my $fh;
        my $code;
        {
            undef $/;
            open $fh, $player or die;
            $code = <$fh>;
            close $fh;
        }
        # TODO remove
        #unlink $player or $self->log( "ERROR: $!" );
    
        push @{$self->{newcomers}}, [ $player, $date, $code  ];
    }

    chdir '..';
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub get_game_status {
    return $_[0]->{conf}{gameStatus};
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub set_game_status {
    return $_[0]->{conf}{gameStatus} = $_[1];
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub play_round
{
	my $self = shift;
	
	# check if the game is over (because a player won)
	if( $self->get_game_status eq 'over' ) {
		print "game is already over, exiting\n";
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
    $self->runSlot( $_ ) for 0..$self->{conf}{theArraySize}-1;

    # end of round checks
    $self->{theArray}->reset_operational;

	# check for victory
    $self->agent_census;

    my @survivors;
    for my $p ( keys %{$self->{conf}{player}} ) {
        if ( $self->{conf}{player}{$p}{agents} ) {
            push @survivors, $p;
        }
        else {
            $self->{conf}{player}{status} = 'EOT';
        }
    }

    if ( @survivors > 1 ) {
        print scalar( @survivors ), 
            " players still have agents on the field\n";
    } else {
        print @survivors ? "only $survivors[0] left!\n"
                        : "no survivor!\n";
        # TODO update the config w/ victory
        $self->set_game_status( 'over' );
    }

	# check if the game is over (because round > game length)
	$self->{round}++;
	$self->{conf}{currentIteration} = $self->{round};
	if( $self->{round} > $self->{conf}{gameLength} ) {
		print "number of rounds limit reached, game is over\n";
        $self->set_game_status( 'over' );
        # TODO find out who's won
	}

    $self->save;
    delete $self->{newcomers};
    delete $self->{old_iteration};
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub save
{
	my $self = shift;
	
	print "saving round $self->{round}..\n";
	
	$self->saveConfiguration;
	
	#XMLout( $self->{conf}, OutputFile => "configuration.xml", RootName => 'configuration' );
	

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

    $self->{theArray}->save_as_xml( $writer );

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
	my $writer = new XML::Writer(OUTPUT => $output, NEWLINES => 1);

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
	
	my %score = $self->{theArray}->census;
	
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

    $self->visit_mobil_station unless $self->{old_iteration};

    my @newcomers = @{$self->{newcomers}};

    $self->log( "\tno-one was aboard" ) unless @newcomers;

    AGENT: for my $newcomer ( @newcomers ) {
        my( $player, $date, $code ) = @$newcomer;
        $self->log( "\t".$player."'s new agent is aboard (u/l'ed $date)" );
        # dead players can't submit agents
        if( $self->{conf}{player}{$player}{status} eq 'EOT' ) {
            $self->log( "\tplayer is eliminated, can't submit a new agent" );
            next AGENT;
        }
    
        my @available_slots = $self->{theArray}->empty_cells;
    
        if( @available_slots > 0 )
        {
            my $slot = $available_slots[ rand @available_slots ];
            $self->log( "\tagent inserted at cell $slot" );
            $self->{theArray}->cell( $slot )->insert({
                owner => $player,
                code => $code,
            });
            next AGENT;
        }
   
        # no empty cells, maybe a cell already occupied by
        # the player?
        @available_slots = $self->{theArray}->cells_belonging_to( $player );
    
        if( @available_slots > 0 )
        {
            my $slot = $available_slots[ rand @available_slots ];
            $self->log( "agent at cell $slot is upgraded" );
            $self->{theArray}->cell( $slot )->insert({
                owner => $player,
                code => $code,
            });
            unlink $player or $self->log( "ERROR: $!" );
            next AGENT;
        }
    
        $self->log( "no empty slot left, agent deleted" ); 
    }
}

##########################################################################

sub log 
{
  my $self = shift;
  
  return @{$self->{log}} unless @_;

  if( $self->{interactive} ) {
    local $\ = "\n";
    print for @_;
  }

  push @{$self->{log}}, @_;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub insert_agent {
	my ( $self, $pos, $player, $code ) = @_;

    if( $pos >= $self->{conf}{theArraySize} ) { 
	    $self->log( "can't insert agent: cell $pos out of bound" );
        return;
    }
		
    $self->{theArray}->cell( $pos )->insert({
        owner => $player,
        code => $code,
    });
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub run_cell {
    my( $self, $cell_id, $vars_ref ) = @_;
    my %vars;
    %vars = %$vars_ref if $vars_ref;

    return $self->array->run_cell( $cell_id => {  
       %vars,
       '$S' => $self->{conf}{snippetMaxLength},
       '$I' => $self->{conf}{gameLength},
       '$i' => $self->{conf}{currentIteration},
    } );

}

##########################################################################

# ( $result, $error, @array ) = $pw->execute( @array )
# executes the code of $array[0]
sub execute
{
	my( $self, $cell_id ) = @_;

    # what happens in execute(), stays in execute
    local *STDERR;
    my $warnings;
    open STDERR, '>', \$warnings;

    my $owner =  $self->array->cell( $cell_id )->get_owner;
    
	local @_ = $self->array->get_cells_code( $cell_id );
	local $_ = $_[0];
	my @o = $self->array->get_facades( $cell_id );

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
		@Container::o = @o;
		@Container::O = $owner;
		$Container::S = $self->{conf}{snippetMaxLength};
		$Container::I = $self->{conf}{gameLength};
		$Container::i = $self->{conf}{currentIteration};
		$safe->share_from( 'Container', 
                           [ '$S', '$I', '$i', '@_', '@o', '$O' ] );
		$result = $safe->reval( <<EOT );
local *_ = \\\@Array;
\$_ = \$_[0];
$code
EOT
	
    	$error = $@;   
    	alarm 0;
  	};

    return ( $result, $error ) if $error;

    my @code_array = $safe->reval( '@Array' );
    $owner = $safe->reval( '$o[0]' );
    $code_array[0] = $safe->reval( '$_' );

    return( $result, $error, $owner, @code_array );
}

##########################################################################

sub runSlot {
  	my ( $self, $slotId ) = @_;

    my $cell = $self->{theArray}->cell( $slotId );

    # diddled cells and empty cells aren't executed
	return if $cell->is_empty 
           or not $cell->get_operational;
	
	$self->log( "cell $slotId: agent owned by ".$cell->get_owner ); 

    my @code_array  = $self->{theArray}->get_cells_code( $slotId );
    my @owner_array = $self->{theArray}->get_facades( $slotId );

	# exceed permited size?
    my $code = $cell->get_code;
  	if( length $code > $self->{conf}{snippetMaxLength} ) {
    	$self->log( "\tagent crashed: is ".length($code)." chars, exceeds max permitted size $self->{conf}{snippetMaxSize}" ); 
        $cell->delete;
    	return;
  	}

  	$self->log( "\texecuting.." );
  	
    # TODO  squeeze in the ownership array
    my $agent = $self->run_cell( $slotId );

	if( $agent->crashed ) {
    	$self->log( "\tagent crashed: ".$agent->error_msg );
        $cell->delete;
    	return;
  	} 

    $cell->set_code( $agent->eval( '$_' ) );
    $cell->set_facade( $agent->eval( '$o' ) );

    no warnings qw/ uninitialized /; 

  	my $output = $agent->return_value;
    my $result = $output;
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
        $self->_alter_operation( $slotId, $1, [ $agent->eval( '@Array' ) ] );
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
    
    if( $self->array->cell( $target_index )->is_empty ) {
        $self->log( "\tno agent found at cell $target_index" );
        return;
    }
		
    $self->array->cell( $target_index )->clear;
    $self->log( "\tagent in cell $target_index destroyed" );
}

sub _p0wn_operation {
    my( $self, $agent_index, $target_index ) = @_;

    $target_index = $self->relative_to_absolute_position( $agent_index, $target_index );

    return if $target_index == -1;

    my $target = $self->{theArray}->cell( $target_index );

    if( $target->is_empty ) {
	   $self->log( "\tno agent to p0wn in cell $target_index" );
	   return;
    }

    $self->log( "\tagent in cell $target_index p0wned" );
    $target->set_owner( $self->{theArray}->cell( $agent_index )->get_owner );
}

sub relative_to_absolute_position {
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

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub _alter_operation {
    my ( $self, $agent_index, $target_index, $Array_ref ) = @_;

    my $abs_target_index = $self->relative_to_absolute_position( $agent_index, $target_index );
    return if $abs_target_index == -1;

    my $target = $self->{theArray}->cell( $abs_target_index );
   
    if ( $target->is_empty ) {
        $self->log( "\tno agent found at cell $abs_target_index" );
      	return;
    }

    $target->set_code( $Array_ref->[$target_index] );
    $self->log( "\tcode of agent in cell $abs_target_index altered" );
}

sub _copy_operation {
    my( $self, $agent_index, $source_index, $dest_index ) = @_;
    
    $source_index = $self->relative_to_absolute_position( $agent_index, $source_index );
    $dest_index   = $self->relative_to_absolute_position( $agent_index, $dest_index );
    
    # source or destination invalid? We do nothing
    return if $source_index == -1 or $dest_index == -1;

    my $theArray = $self->{theArray};
    my $target = $theArray->cell( $dest_index );
    my $agent = $theArray->cell( $agent_index );
    
    if( $target->get_owner 
        and $target->get_owner ne $agent->get_owner )
    {
        $self->log( "\tagent in cell $dest_index already owned by ".
                    $target->get_owner );
        return;
    }

    $self->log( "\tagent of cell $source_index copied into cell $dest_index" );
    $target->copy( $agent );
    $target->set_operational( 0 );
}

sub _noop_operation {
    $_[0]->log( "\tno-op" );
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

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sub array {
    return $_[0]->{theArray};
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


sub agent_census {
    my( $self ) = @_;

    my %player = %{$self->{conf}{player}};

    my %census = $self->{theArray}->census;

    for my $p ( keys %player ) {
        $player{$p}{agents} = $census{$p} || 0;
    }
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

