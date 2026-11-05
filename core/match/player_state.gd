class_name PlayerState
extends RefCounted

## The top of the deck is the back of the array.
var deck: Array[CardData] = []
var hand: Array[CardData] = []
var discard: Array[CardData] = []
var prizes: Array[CardData] = []
var active: CardInPlay = null
var bench: Array[CardInPlay] = []
var energy_attached_this_turn := false
var retreated_this_turn := false
var supporter_played_this_turn := false
var stadium_played_this_turn := false
## Turns this player has started. Evolution is not allowed during a player's first turn.
var turns_started: int = 0
## Mulligans taken during setup. Public information, as at the table.
var mulligans: int = 0
## TP in quarters: 0 is 0%, 4 is 100% (Design Document 5). The round rules set the start.
var tp: int = 0
## The attack this player used during this turn and during their previous turn, by name, or "".
var attack_used_this_turn: String = ""
var attack_used_last_turn: String = ""
## How many times each Ability or Area action was used this turn, by name, every copy together.
var powers_used_this_turn: Dictionary = {}

func reset_turn_flags() -> void:
	attack_used_last_turn = attack_used_this_turn
	attack_used_this_turn = ""
	powers_used_this_turn.clear()
	energy_attached_this_turn = false
	retreated_this_turn = false
	supporter_played_this_turn = false
	stadium_played_this_turn = false


func draw_card() -> bool:
	if deck.is_empty():
		return false
	hand.append(deck.pop_back() as CardData)
	return true


func first_basic_pokemon_in_hand() -> int:
	for i in hand.size():
		if hand[i].is_basic_pokemon():
			return i
	return -1


func discard_from_play(pokemon: CardInPlay) -> void:
	discard.append_array(pokemon.evolved_from)
	pokemon.evolved_from.clear()
	discard.append(pokemon.card)
	discard.append_array(pokemon.attached_energy)
	pokemon.attached_energy.clear()