package Games::PerlWar;

$Games::PerlWar::VERSION = 0.01;

use strict;
use warnings;
use utf8;

use Safe;
use XML::Simple;


=pod

  $pw = new Games::PerlWar( );

  perl -MGames::PerlWar -e'create()'
  pwcreate
  perl -M..   -e'playround()'
  pwplayround

=cut


sub new 
{
    my( $class, $dir ) = @_;
    my $self = { dir => $dir, interactive => 1 };
    chdir $self->{dir};
    bless $self, $class;
}

sub clear_log
{
	my $self = shift;
	$self->{log} = ();
}

sub load 
{
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
		if( $self->{theArray}[ $_ ]{owner} and not $self->{theArray}[ $_ ]{code} ) 
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
	
	my @files = sort { -M $a <=> -M $b } grep { exists $self->{conf}{player}{$_} } readdir $dir;
	closedir $dir;
	
	$self->log( "\tno-one was aboard" ) if not @files;

	AGENT: for my $player ( @files )
	{
		my $date = localtime( $^T - (-M $player)/24*60*60 );
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
			push @available_slots, $_ if $self->{theArray}[$_]{owner} = $player;
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
	$safe->permit( qw/ time sort :browse :default / );
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
		$safe->share( '$S', '$I', '$i', '@_' );
		$result = $safe->reval( <<EOT );
local *_ = *Array;
\$_ = \$_[0];
$code
EOT
    	$code = $_[0];
    	$error = $@;   
    	alarm 0;
  	};

	return ( $result, $error, $error? undef : $safe->reval( '@Array' ) );
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
  	if( length > $self->{conf}{snippetMaxLength} )
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
    
    if( $result =~ /^!(-?\d*)$/ )   # !613 - nuke
    {
		my $pos = $self->relative_to_absolute_position( $slotId, $1 || 0 );
		return if $pos == -1;
		
        if( $self->{theArray}[ $pos ] )
        {
        	$self->{theArray}[ $pos ] = { };
        	$self->log( "\tagent in cell $pos destroyed" );
        }
        else
        {
        	$self->log( "\tno agent found at cell $pos" );
        }
    }
    elsif( $result =~ /^\^(-?\d*)$/ )  # ^613  - p0wning
    {

      my $pos = $self->relative_to_absolute_position( $slotId, $1 );

      return if $pos == -1;

	  unless( $self->{theArray}[$pos] and $self->{theArray}[$pos]{code} )
	  {
	  	$self->log( "\tno agent to p0wn in cell $pos" );
		return;
	  }

      $self->log( "\tagent in cell $pos p0wned" );
      $self->{theArray}[$pos]{owner} = $self->{theArray}[$slotId]{owner};
    }
    elsif( $result =~ /^~(-?\d*)$/ )  # ~613
    {
      my $relative = $1;
      my $pos = $self->relative_to_absolute_position( $slotId, $1 );
      return if $pos == -1;
      
      unless( $self->{theArray}[$pos] and $self->{theArray}[$pos]{code} )
      {
      	$self->log( "\tno agent found at cell $pos" );
      	return;
      }

      $self->{theArray}[$pos]{code} = $Array[$relative];
      $self->log( "\tcode of agent in cell $pos altered" );
      
    }
    elsif( $result =~ /^(-?\d*):(-?\d*)$/ )  # 212:213
    {
    
	# big problem here. we don't want a newly copied guy to be effective
	# during the same turn
	
      my $src_pos += $self->relative_to_absolute_position( $slotId, $1 );
      my $dest_pos += $self->relative_to_absolute_position( $slotId, $2 );

      return if $src_pos == -1 or $dest_pos == -1;

      if( $self->{theArray}[$dest_pos]{owner} and
          $self->{theArray}[$dest_pos]{owner} ne $self->{theArray}[$slotId]{owner} ) 
      {
        $self->log( "\tagent in cell $dest_pos already owned by $self->{theArray}[$dest_pos]{owner}" );
        return;
      }

      $self->log( "\tagent of cell $src_pos copied into cell $dest_pos" );
      $self->{theArray}[$dest_pos] = \%{$self->{theArray}[$src_pos]};
      $self->{theArray}[$dest_pos]{freshly_copied} = 1 ;
    }
    else
    {
    	$self->log( "\tno-op" );
    }
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

sub readCell
{
	my( $self, $cellId ) = @_;
	return undef unless $self->{theArray}[$cellId];
	return ( $self->{theArray}[$cellId]{owner}, $self->{theArray}[$cellId]{code}  );
}

sub writeCell
{
	my( $self, $pos, $owner, $code ) = @_;
	$self->{theArray}[$pos] = { owner => $owner, code => $code };
}


=pod

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

=cut

1;
