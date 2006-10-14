package Games::PerlWar::Cell;

use strict;
use warnings;
use Carp;

use Class::Std;

use Safe;

my %owner_of          : ATTR( :name<owner> :default<undef> );
my %apparent_owner_of : ATTR( :set<apparent_owner> :init_args<apparent_owner> :default<undef>);
my %code_of           : ATTR( :get<code> :init_args<code> :default<undef> );
my %operational_of    : ATTR( :name<operational> :default<1> );

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sub set_code {
    my ( $self, $code ) = @_;
    my $id = ident $self;

    $code = '' if !$code or $code =~ /^\s*$/;

    $code_of{ $id } = $code;

    unless( $code ) {
        $self->set_owner( undef );
        $self->set_apparent_owner( undef );
    }
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub get_apparent_owner {
    my $self = shift;
    my $id = ident $self;

    return $apparent_owner_of{ $id } || $owner_of{ $id };
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub set {
    my( $self, $ref_args ) = @_;
    my $id = ident $self;

    my %args = %$ref_args;

    $self->set_owner( $args{owner} ) if $args{owner};
    $self->set_apparent_owner( $args{apparent_owner} ) if $args{apparent_owner};
    $self->set_code( $args{code} ) if $args{code};
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub is_empty {
    my $self = shift;
    my $id = ident $self;

    return !$code_of{ $id };
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub delete {
    my ( $self ) = @_;
    $self->set_code( undef );
}

sub clear { $_[0]->delete; }

sub insert {
    my ( $self, $ref_args ) = @_;
    my $id = ident $self;

    $self->set_owner( $ref_args->{ owner } );
    $self->set_apparent_owner( $ref_args->{ apparent_owner } );
    $self->set_code( $ref_args->{ code } );
}

sub copy {
    my ( $self, $original ) = @_;
    my $id = ident $self;

    $self->set_owner( $original->get_owner );
    $self->set_apparent_owner( $original->get_apparent_owner );
    $self->set_code( $original->get_code );
}

sub save_as_xml {
    my( $self, $writer ) = @_;
    my $id = ident $self;

    $writer->dataElement( owner => $self->get_owner );
    $writer->dataElement( facade => $self->get_apparent_owner );
    $writer->dataElement( code => $self->get_code );
}




1;
