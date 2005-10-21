=head1 NAME

Games::PerlWar - A Perl variant of the classic Corewar game

=head1 DESCRIPTION

	This is a sparring program, similar to the programmed reality of the Matrix. 
	It has the same basic rules, rules like gravity. What you must learn is that 
	these rules are no different than the rules of a computer system. Some of 
	them can be bent, others can be broken.  - Morpheus

PerlWar is inspired by the classic L<http://www.corewar.info/|Corewar> game.
In this game, players pit snippets of Perl code (called 'agents') against each other in order to
gain control of the vicious virtual battlefield known as... the Array.

=head1 GAME PARAMETERS

=over 

=item Size of the Array

The number of cells that the Array possesses. Each cell can hold one agent.

=item Agent Maximal Size 

The maximal length, in characters, of an agent. If an agent is or becomes larger than this limit, it automatically segfaults upon execution.

=item Game Maximal Number of Iterations

The maximal number of rounds that can be played before a game is declared over.

=back


=head1 DESCRIPTION OF A TURN

A turn of the game is made up of the following steps:

=head2 Introduction of New Agents

Each player has the opportunity to submit a new agent to be introduced into the Array. 
Insertions are treated in order of submission time. The cell into which an entrant agent
lands is picked randomly amongst the empty positions of the Array. 

If there are no empty
positions left, an entrant agent replaces one of the already-present agents owned
by the player, chosen randomly. If the player doesn't have any agents already
present in the Array, the new agent is  discarded.


=head2 Elimination of Players

A player is eliminated from the game if he doesn't have any agents present in the 
Array at the end of the introduction of new agents.


=head2 Running the Array

Each cell of the Array is visited sequentially. If a cell contains an agent, it is executed 
(agents exceeding the permitted length segfault on initialization). 

=head3 Variables accessibles to the agents

=over

=item $_

the code of the agent.

=item @_

the whole Array, positioned relatively to the current agent. (i.e., $_[0] eq $_ )

=item $S, $I, $i

the game's parameters $S (max agent's size) and $I (max # of iterations), plus the current iteration $i. 
Those are local variables and can't be used to modified the game parameters, obviously.

=back

=head3 Outcomes

If the agent segfaults, it is erased and the cell ownership is cleared. 

If the agent executes without segfault'ing, the changes made to $_ (that is, on the snippet itself)
are brought to the Array.
E.g., the snippet 

	$turn = 13; s/\d+/$&+1/e;

once executed, will become

	$turn = 14; s/\d+/$&+1/e;

In addition, the agent can return an instruction (see below). If it returns
a value that does not match any valid instruction, it is treated as a no-op.


=head1 Agent Return Instructions

An agent can return one instruction of the set below. All positions are are 
relative to the position of the executing agent.

=over

=item $x:$y

Copy the code of cell $x of @_ (as defined after execution of the agent) into position
$y of the Array (relative to the position of the current agent). $x and $y must be 
integers with an absolute value between 0 and $#_. 
If either $x or $y are not explicitly given, they default to 
the position 0. If the destination position is already occupied by an agent belonging to
a different player, the copy fails. If the copy succeed, the newly copied agent will only become operational during the next iteration (i.e., it will not be executed during
the current iteration). 

Example:

	# crawler - copy itself to the next position
	return ":1"
	


=item !$x

Nuke the agent presents in position $x. The cell then 
returns to its empty and unowned state. If $x is not given, defaults to 0.

Example:

	# berserker
	return '!'.1+int(rand(@_))

=item ~$x

Update the agent in position $x of the Array by its counterpart in @_. If $x is not explicitly given,
defaults to 0. Ownership of the modified agent isn't modified. If an agent isn't present,
nothing happens.

Example:

	# drive neighbor to suicide
	$_[1] =~ s//return "!"/;
	return "~1";

=item ^$x

Claim ownership of the agent in position $x of the Array. If there is no agent at that 
position, nothing happens.

Example:

	# crawling borg
	$pos = 1; 
	s/\d+/$&+1/e; 
	return "^$pos";

=back


=head1 END OF GAME

The game ends once the final round is played, or until all but one player have been eliminated. 
The winner of the game is the player with the most agents still alive
in the Array.

=head1 GAME VARIANTS

=over

=item Mambo War

In this variant, the agent maximal size is decremented after each turn. 

=back


=cut

'end of Games::PerlWar::Rules'
