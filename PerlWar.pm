package Games::PerlWar;

use strict;
use warnings;

use Safe;

=pod

  $pw = new Games::PerlWar( );

  perl -MGames::PerlWar -e'create()'
  pwcreate
  perl -M..   -e'playround()'
  pwplayround

=cut

use XML::Simple;

sub new 
{
    my( $class, $dir ) = @_;
    my $self = { dir => $dir, interactive => 1 };
    bless $self, $class;
}

sub load 
{
	my $self = shift;
	
	print "loading configuration.. ";

	$self->{conf} = XMLin( 'configuration.xml' );

	my $xml = XML::LibXML->new->parse_file( 'round_current.xml' );

	$self->{round} = $xml->findvalue( '/round/@id' );
	print "this is round $self->{round}\n";
	my @theArray;
	$self->{theArray} = \@theArray;
	for my $slot ( 0..$self->{conf}{theArraySize}-1 )
	{
		my $owner = $xml->findvalue( "//slot[\@id=$slot]/owner/text()" );
		my $code = $xml->findvalue( "//slot[\@id=$slot]/code/text()" );
		print "$slot : $owner : $code\n";
		if( $code )
		{
			$theArray[ $slot ] = { owner => $owner, code => $code };
		}
	}
}

sub play_round
{
	my $self = shift;
	
	chdir $self->{dir};

	$self->load;

	# check if the game is over (because a player won)
	if( $self->{conf}{gameStatus} eq 'over' )
	{
		print "game is already over, exiting\n";
		return
	}

	# check if the game is over (because round > game length)
	$self->{round}++;
	if( $self->{round} > $self->{conf}{gameLength} )
	{
		print "number of rounds limit reached, game is over\n";
		return;
	}

	$self->{log} = [];
	
	# import newcomers
	$self->introduce_newcomers;
	
	# run each slot
	for( 0..$self->{conf}{theArraySize}-1 )
	{
		$self->runSlot( $_ );
	}
	
	# check for victory
	
	# if victory, change the config
	
	# save the round
	$self->save;
}

sub save
{
	my $self = shift;
	
	print "saving round $self->{round}..\n";
	
	XMLout( $self->{conf}, OutputFile => "configuration.xml", RootName => 'configuration' );
	
	use XML::Writer;
	use IO::File;

	my $output = new IO::File(">round_current.xml");
	my $writer = new XML::Writer(OUTPUT => $output);

	$writer->startTag( "round", number => $self->{round} );
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
}

sub introduce_newcomers
{
	my $self = shift;
	
	chdir 'atrium';
	my $dir;
	opendir $dir, '.' or die "couldn't open dir atrium: $!\n";
	my @files = sort { -M $a <=> -M $b } grep { exists $self->{conf}{player}{$_} } readdir $dir;
	closedir $dir;

	WARRIOR: for my $player ( @files )
	{
		my $date = localtime( -M $player );
		$self->log( "$player sends a new code warrior in the theArray ($date)" );
		
		my $fh;
		my $code;
		{
			undef $/;
			open $fh, $player or die;
			$code = <$fh>;
			close $fh;
		}
		
		
		my @available_slots;
		for( 0..$self->{conf}{theArraySize}-1 )
		{
			push @available_slots, $_ unless $self->{theArray}[$_];
		}
		$self->log( "there are ".scalar(@available_slots)." slots available" );
		
		if( @available_slots > 0 )
		{
			my $slot = $available_slots[ rand @available_slots ];
			$self->log( "code warrior enters theArray at slot $slot" );
			$self->{theArray}[$slot] = { owner => $player, code => $code };
			unlink $player or die;
			next WARRIOR;
		}
		
		for( 0..$self->{conf}{theArraySize}-1 )
		{
			push @available_slots, $_ if $self->{theArray}[$_]{owner} = $player;
		}
		
		if( @available_slots > 0 )
		{
			my $slot = $available_slots[ rand @available_slots ];
			$self->log( "code warrior bumps comrade and enters theArray at slot $slot" );
			$self->{theArray}[$slot] = { owner => $player, code => $code };
			unlink $player or die;
			next WARRIOR;
		}
		
		$self->log( "no empty slot left, code warrior left in the atrium" ); 
	}
	
	chdir '..';
}

sub log {
  my $self = shift;

  if( $self->{interactive} ) {
    local $\ = "\n";
    print for @_;
  }

  push @{$self->{log}}, @_;
}

sub runSlot 
{
  	my ( $self, $slotId ) = @_;

	return unless $self->{theArray}[ $slotId ];
	
	my %slot = %{$self->{theArray}[ $slotId ]};

	return if $slot{freshly_copied} or not $slot{code};

	$self->log( "slot $slotId: owned by $slot{owner}" ); 

  local @_;
  @_ = map $_->{code}, @{$self->{theArray}}[ $slotId..(@{$self->{theArray}}-1), 0..($slotId-1) ];
  local $_;
  $_ = $slot{code};
 
  # exceed permited size?
  if( length > $self->{conf}{snippetMaxLength} )
  {
    $self->log( "snippet crashed: is ".length($_)." chars, exceeds max permitted size $self->{conf}{snippetMaxSize}" ); 
    $self->{theArray}[ $slotId ] = {};
    return;
  }

  $self->log( "executing..." );

  # run this in a safe
  my $safe = new Safe;
  my $result;
  my $error;

  eval {
    local $SIG{ALRM} = sub { die "timed out\n" };
    alarm 1;
    $result = $safe->reval( $slot{code} );
    $error = $@;   
    alarm 0;
  };

  if( $error ) {
    $self->log( "snippet crashed: $error" );
    $self->{theArray}[$slotId] = {};
  } else {
    $self->log( "result: $result" );
    if( $result =~ /^!(-?\d*)$/ )   # !613
    {
      my $pos = $1 || 0;
      if( abs $pos > $#_ ) {
        $self->log( "position out-of-bound" );
      }
      else {
        $pos += $slotId;
        $pos %= @_ if $pos >= @_;
        $pos += @_ if $pos < 0;
        $self->log( "Cell $pos of the Array nuked" );
        $self->{theArray}[ $pos ] = { };
      }
    }
    elsif( $result =~ /^\^(-?\d*)$/ )  # ^613
    {
      my $pos = $self->relative_to_absolute_position( $slotId, $1 );

      return if $pos == -1;

      $self->log( "Cell $pos of the Array p0wned" );
      $self->{theArray}[$pos]{owner} = $self->{theArray}[$slotId]{owner};
    }
    elsif( $result =~ /^~(-?\d*)$/ )  # ~613
    {
      my $relative = $1;
      my $pos = $self->relative_to_absolute_position( $slotId, $1 );
      return if $pos == -1;

      $self->{theArray}[$pos]{code} = $_[$relative];
      $self->log( "Code of cell $pos updated" );
      
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
        $self->log( "cell $dest_pos already owned by $self->{theArray}[$dest_pos]{owner}" );
        return;
      }

      $self->log( "Snippet in cell $src_pos copied into cell $dest_pos" );
      $self->{theArray}[$dest_pos] = \%{$self->{theArray}[$src_pos]};
      $self->{theArray}[$dest_pos]{freshly_copied} = 1 ;
    }

  }
}

sub relative_to_absolute_position
{
  my( $self, $slotId, $shift ) = @_;
  $shift ||= 0;

  if( abs( $shift ) > $self->{conf}{theArraySize} ) {
    $self->log( "position $shift out-of-bound" );
    return -1;
  }
  $slotId += $shift + 2 * $self->{conf}{theArraySize};
  $slotId %= $self->{conf}{theArraySize};

  return $slotId;
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