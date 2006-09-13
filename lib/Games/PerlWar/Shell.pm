use strict;
use warnings;

package Games::PerlWar::Shell;

use Cwd;
use Games::PerlWar;
use XML::Simple;
use File::Copy;
use IO::Prompt;
use Term::ShellUI;
use IO::Prompt qw/ hand_print /;

my $pw;
# TODO: add color entry for players and default colors
my @colors = qw( pink lightblue yellow lime maroon purple 
                 olive pink gold red aqua );

my $shell = Term::ShellUI->new(
    commands => {
        load => {
            desc => "load a PerlWar game",
            maxargs => 2,
            proc => \&do_load,
        },
        save => {
            desc => "save the current PerlWar game",
            maxargs => 1,
            proc => \&do_save,
        },
        quit => {
            desc => "exit the shell",
            method => sub { shift->exit_requested(1) },
        },
        q => { syn => 'quit', exclude_from_completion => 1 },
    }
);

### help 
$shell->add_commands({ 
    help => {
        desc => "print list of commands",
        args => sub { shift->help_args(undef, @_); },
        method => sub { shift->help_call(undef, @_); },
    },
    h => { syn => "help", exclude_from_completion=>1},
});

### create
$shell->add_commands({ 
    create => {
        desc => "create a new game",
        proc => \&do_create,
    },
});

### cd, pwd
$shell->add_commands({
    cd => {
        desc => "change working directory",
        proc => \&do_cd,
    },
    pwd => {
        desc => "print current working directory",
        proc => \&do_pwd,
    },
});

### run
$shell->add_commands({
    run => {
        desc => 'run iterations of the game',
        proc => \&do_run,
    }
});

### exec, info
$shell->add_commands({ 
    eval => {
        desc => 'execute arbitrary perl code',
        proc => sub { print eval( join ' ', @_ ), "\n" },
    },
    e => { syn => 'eval', exclude_from_completion => 1 },
    info => { 
        desc => 'game stats',
        proc => \&do_info,
    },
});


$shell->prompt( 'pw> ' );

sub run { $shell->run; }

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_info {
    die "no game loaded\n" unless $pw;

    print 'iteration ', $pw->{round}, ' of ', $pw->{conf}{gameLength}, "\n",
          'game status: ', ( $pw->get_game_status || 'ongoing' ), "\n",
          'players', "\n";

    for my $p ( keys %{$pw->{conf}{player}} ) {
        print "\t$p : ", $pw->{conf}{player}{$p}{agents}, "\n";
    }
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_create {
    if ( $pw ) {
        my $r = prompt -yes, -d => 'y', 
                 "creating a new game will discard any unsaved information to "
                ."the currently loaded game. do it? [Yn] ";
        return unless $r;
    }

    my $game_name = shift || 'perlwar';
    my $game_dir = "./$game_name";

    print "creating game directories $game_dir..\n";

    mkdir $game_dir or die "couldn't create directory $game_dir: $!\n";
    chdir $game_dir or die "can't chdir to $game_dir: $!\n";

    mkdir "history" or die "couldn't create directory history:$!\n";
    mkdir 'mobil' or die "couldn't create directory mobil:$!\n";

    my ( $location ) = grep -d "$_/Games/PerlWar/web", @INC 
        or die "no installation of PerlWar found\n";

    $location = "$location/Games/PerlWar/web";

    copy( "$location/htaccess", ".htaccess" ) 
        or die "coudn't copy .htaccess: $!\n";

    for( qw/ submit.epl perlwar.ico upload.epl upload.html/ ) {
    	copy( "$location/$_", $_ ) or die "coudn't copy $_: $!\n";
    }

    for( qw/ include_config.xps  iteration2html.xps configuration.xps/ ) {
    	copy( "$location/stylesheets/$_", $_ ) or die "coudn't copy $_: $!\n";	
    }

    print "\n\ngame configuration\n";
    my %conf;

    $conf{gameStatus} = 'ongoing';

    my $input = prompt "game title [$game_name]: ", -d => $game_name; 

    $game_name = $input || $game_name;

    $conf{title} = $game_name;

    $conf{theArraySize} = 
        prompt -integer, "Size of the Array [100]: ", -d => 100;

    $conf{gameLength} = prompt 
                        -integer, 
                        "game length (0 = open-ended game) [100]: ",
                        -d => 100;

    $conf{currentIteration} = 0;

    $conf{snippetMaxLength} = prompt -integer, "snippet max. length [100]: ", 
                                -d => 100;

    $conf{mamboDecrement} = prompt -integer, 
            "mambo game (0=no, any positive integer is taken as the decrement)[0]: ", 
        -d => 0;

    my %players;
    $conf{player} = \%players;

    while(1) {
        my $line = prompt "enter a player (name password [color]), or nothing if done: ";
        my( $name, $password, $color ) = split ' ', $line, 3;
        
        last unless $name;

        $color ||= shift @colors;
		
        $players{ $name } = { password => $password, color => $color };
    }

    print "notes (empty line to terminate):\n";
    $conf{note} .= $_ while length( $_ = prompt );

    print "saving configuration..\n";

    Games::PerlWar::saveConfiguration( %conf );

    print "creating round 0.. \n";

    for my $filename ( qw/ round_current.xml round_00000.xml / )
    {
        my $fh;
        open $fh, ">$filename" or die "can't create file $game_dir/$filename: $!\n";
        print $fh "<round id='0'><theArray>\n";
        print $fh "<slot id='$_'><owner></owner><code></code></slot>\n" for 0..$conf{theArraySize}-1;
        print $fh "</theArray><log/></round>";
        close $fh;
    }

    print "\ngame '$game_name' created\n";

    $pw = Games::PerlWar->new( '.' );
    $pw->load;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_load {
    my $dir = shift || '.';
    my $iteration = shift;

    if ( $pw ) {
        my $r = prompt -yes, -d => 'y', 
                 "loading a new game will discard any unsaved information to "
                ."the currently loaded game. do it? [Yn] ";
        return unless $r;
    }

    $pw = Games::PerlWar->new( $dir );
    $pw->load( $iteration );
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_save {
    die "no game to save" unless $pw;

    $pw->save;

    print "game saved\n";
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_run {
    die "no game loaded" unless $pw;

    return print "game is already over\n" if $pw->get_game_status eq 'over';

    if ( my $turns = shift ) {
        $pw->play_round while $turns-- and $pw->get_game_status ne 'over';
    }
    else {
        $pw->play_round until $pw->get_game_status eq 'over';
    }
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_cd {
    my $dir = shift;
    unless( -d $dir ) {
        print "ERROR: can't change directory, $dir doesn't exist\n";
        return;
    }

    chdir $dir or print "ERROR: couldn't change to directory: $!\n";
    
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub do_pwd {
    print "current directory: ", getcwd, "\n";
}

__END__



