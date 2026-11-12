class_name PlayerView
extends RefCounted
## What one player at the table can see of a round, and nothing more (Design Document 8.4):
## their own hand, how many cards everyone else holds, both boards, the discard piles, the Area
## and TP. Nobody sees the order of a deck or which cards are Mercy Cards. A question and the
## legal actions are shown only to the player who answers. A CPU decides from this; the hotseat
## and a remote client could render it. Built by MatchEngine.view_for(); a snapshot that never
## changes the round.

## One player's side, as the viewer sees it. (Not "Side": Godot has a global enum by that name.)
class SideView:
	extends RefCounted
	var index: int
	## Empty unless this is the viewer's own side.
	var hand: Array[CardData] = []
	var hand_size: int = 0
	var deck_size: int = 0
	var prize_count: int = 0
	var discard: Array[CardData] = []
	## Copies of the Darkners in play: changing them changes nothing in the round.
	var active: CardInPlay = null
	var bench: Array[CardInPlay] = []
	var tp: int = 0
	var mulligans: int = 0
	var energy_attached_this_turn := false
	var retreated_this_turn := false
	var supporter_played_this_turn := false
	var stadium_played_this_turn := false
	var attack_used_this_turn: String = ""
	var attack_used_last_turn: String = ""
	var powers_used_this_turn: Dictionary = {}
	## Turns this player has started: the first-turn rules read it.
	var turns_started: int = 0


var viewer: int
var turn: int
## The player taking the turn.
var current: int
var is_over: bool
var winner: int
## Whether the player taking the turn takes another turn after it (Quick Selfie).
var extra_turn := false
## The player who chose to Fight, or -1 (Design Document 4.5).
var fighting: int = -1
## A copy of the round's rules, as they stand now (effects can change some).
var rules: MatchRules
## The Area in play and who played it, or null and -1.
var stadium: CardData = null
var stadium_owner: int = -1
## How many events the round has had so far. The events themselves, as this player sees them,
## come from MatchEngine.events_for(), from any index on, so a client asks only for new ones.
var event_count: int = 0
## The ACT card the player taking the turn is playing, while it resolves, or null.
var resolving_trainer: CardData = null
## Both sides, by player index.
var sides: Array[SideView] = []
## The player who answers the open question, or -1. Every player sees that one is open and its
## kind; only the chooser sees the rest.
var chooser: int = -1
var choice_kind: String = ""
var choice_details: Dictionary = {}
var choice_options: Array[Dictionary] = []
## Cards shown to the chooser, such as their deck during a search.
var revealed: Array[CardData] = []
## What each Spell in the viewer's hand costs to cast now, in quarters of TP, by card id: its
## printed cost as the continuous effects change it (Mewers Live).
var spell_costs: Dictionary = {}
## The viewer's legal actions: empty unless they are the one to act.
var legal_actions: Array[Dictionary] = []


## The viewer's own side.
func me() -> SideView:
	return sides[viewer]


## The other player's side.
func opponent() -> SideView:
	return sides[1 - viewer]
