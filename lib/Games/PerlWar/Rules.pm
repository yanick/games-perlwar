=head1 NAME

Games::PerlWar - A Perl variant of the classic Corewar game

=head1 DESCRIPTION

	This is a sparring program, similar to the programmed reality of the Matrix. 
	It has the same basic rules, rules like gravity. What you must learn is that 
	these rules are no different than the rules of a computer system. Some of 
	them can be bent, others can be broken.  - Morpheus

PerlWar is inspired by the classic L<http://www.corewar.info/|Corewar> game.
In this game, players pit snippets of Perl code against each other in order to
gain control of the vicious virtual battlefield known as... the Array.

=head1 GAME'S PARAMETERS

=over 

=item *
Size of the Array

=item *
The maximal length, in characters, of a snippet. If a snippet is larger than this limit, it automatically segfaults upon execution.

=item *
The maximal number of rounds that can be played before a game is declared over.

=back

=head1 DESCRIPTION OF A TURN

A turn of the game is made up of the following steps:

=head2 Introduction of New Snippets

Each player has the opportunity to submit a new snippet to be entered into the Array. 
Insertions are treated in order of submission time. The cell into which an entrant snippet
lands is picked randomly amongst the empty positions of the Array. 

If there are no empty
positions left, an entrant snippet replaces one of the already-present snippets owned
by the player, chosen randomly. If the player does not own any snippet on the Array, 
well, guess who the fat lady just sang for?

=head2 Running the Array

Each cell of the Array is visited sequentially. If a cell contains a snippet, it is executed 
(snippets exceeding the permitted length segfault on initialization). 

=head3 Variables accessibles to the agents

=over

=item $_
the code of the snippet.

=item @_
the whole Array, positioned relatively to the current snippet. (i.e., $_[0] == $_ )

=item $W, $R, $r
the game's parameters $W (max snippet's length) and $R (max # of rounds), plus the current round $r.

=back

=head3 Outcomes

If the snippet segfaults, it is erased and the cell ownership is cleared. 

If a snippet executes without segfault'ing, the changes made to $_ (that is, on the snippet itself)
are brought to the Array.
E.g., the snippet 

	$turn = 13; s/\d+/$&+1/e;

once executed, will become

	$turn = 14; s/\d+/$&+1/e;

In addition, if the return value of the snippet matches a valid instruction (see below), it will
be acted upon. If not, it is treated as a no-op.


=head1 Snippet Return Instructions

A snippet can return one instruction of the following set:

=over

=item $x:$y
Copy the code of cell $x of @_ (as defined after execution of the snippet) into position
$y of the Array (relative to the position of the current snippet). $x and $y must be positive
integers between 0 and $#_. If either $x or $y are not explicitly given, they default to 
the position 0. If the destination position is already occupied by a snippet belonging to
a different player, the copy fails.
E.g.:

	# crawler - copy itself to the next position
	return ":1"

=item !$x
Nuke the snippet presents in position $x of the Array (relative to the position of the current snippet), which
returns to its empty and unowned state. If $x is not given, defaults to 0.
E.g.:

	# berserker
	return '!'.1+int(rand(@_))

=item ~$x
Update the snippet in position $x of the Array by its counterpart in @_. If $x is not explicitly given,
defaults to 0. Ownership of the modified snippet isn't modified.
E.g.:

	# drive neighbor to suicide
	$_[1] =~ s//return "!"/;
	return "~1";

=item ^$x
Claim ownership of the snippet in position $x of the Array. If there is no snippet at that 
position, nothing happens.
E.g.:

	# crawling borg
	$pos = 1; 
	$s/\d+/$&+1/e; 
	return "^$pos";

=back


=head1 END OF GAME

The game ends once the final round is played, or until all but one player have been eliminated. 
The winner of the game is the player with the most snippets still alive
in the Array.


'end of Games::PerlWar::Rules';