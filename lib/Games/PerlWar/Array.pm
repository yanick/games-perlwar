package Games::PerlWar::Array;

use strict;
use warnings;
use Carp;
use utf8;

use Class::Std;
use Games::PerlWar::Cell;

my %cells_of          ;
my %size_of           : ATTR( :name<size> :default<100> );

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub START {
    my( $self, $id ) = @_;

    my @cells;

    push @cells, Games::PerlWar::Cell->new for 1..$size_of{ $id };

    $cells_of{ $id } = \@cells;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub load_from_xml {
    my( $self, $xml ) = @_;
    my $id = ident $self;

    for my $cell ( $xml->findnodes( '//slot' ) ) {
        my $position = $cell->findvalue( '@id' );
		my $owner = $cell->findvalue( "owner/text()" );
		my $apparent_owner = 
            $cell->findvalue( "apparent_owner/text()" );
		my $code = $cell->findvalue( "code/text()" );
        utf8::decode( $code );

        $self->set_cell( $position => {
                owner => $owner,
                code => $code,
                ( apparent_owner => $apparent_owner ) x !! $apparent_owner,
        } );
    }
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub set_cell {
    my( $self, $position, $ref_args ) = @_;
    my $id = ident $self;

    $self->get_cell( $position )->set( $ref_args );
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub clear {
    my $self = shift;

    $_->clear for @{$cells_of{ ident $self }};
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub get_cell {
    my( $self, $position ) = @_;
    my $id = ident $self;

    $position %= $size_of{ $id };

    return $cells_of{ $id }[ $position ];
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub get_code_array {
    my( $self, $base ) = @_;
    my $id = ident $self;

    my $last_index = $size_of{ $id } - 1;
    return map { $_->get_code  } 
               @{$cells_of{ $id }}[ $base..$last_index, 0..($base-1) ];

}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub get_apparent_owner_array {
    my( $self, $base ) = @_;
    my $id = ident $self;

    my $last_index = $size_of{ $id } - 1;
    return map { $_->get_apparent_owner } 
               @{$cells_of{ $id }}[ $base..$last_index, 0..($base-1) ];
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub census {
    my ( $self ) = @_;
    my $id = ident $self;

    my %census;
    my @cells = @{ $cells_of{ $id } };

    for my $cell ( @cells ) {
        my $owner = $cell->get_owner;
        $census{ $owner }++ if $owner;
    }

    return %census;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub empty_cells {
    my $self = shift;
    my $id = ident $self;
    
    return grep { $cells_of{$id}[$_]->is_empty } 0..$size_of{ $id }-1;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub cells_belonging_to {
    my( $self, $player ) = @_;
    my $id = ident $self;

    return grep { $cells_of{$id}[$_]->get_owner eq $player } 0..$size_of{ $id };
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub cell { $_[0]->get_cell( $_[1] ); }

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub reset_operational {
    my( $self ) = @_;
    my $id = ident $self;

    $_->set_operational( 1 ) for @{ $cells_of{ $id } };
}

sub save_as_xml {
    my( $self, $writer ) = @_;
    my $id = ident $self;
        
	$writer->startTag( 'theArray', size => $size_of{ $id } );
    for my $id ( 0..@{$cells_of{ $id}} ) {
        next if $self->cell( $id )->is_empty;
        $writer->startTag( 'slot', id => $id );
        $self->cell( $id )->save_as_xml( $writer );
        $writer->endTag;
    }
    $writer->endTag;
}   

1;
