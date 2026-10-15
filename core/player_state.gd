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
## Turns this player has started. Evolution is not allowed during a player's first turn.
var turns_started: int = 0


func reset_turn_flags() -> void:
	energy_attached_this_turn = false
	retreated_this_turn = false


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


func has_pokemon_in_play() -> bool:
	return active != null or not bench.is_empty()


func discard_from_play(pokemon: CardInPlay) -> void:
	discard.append_array(pokemon.evolved_from)
	pokemon.evolved_from.clear()
	discard.append(pokemon.card)
	discard.append_array(pokemon.attached_energy)
	pokemon.attached_energy.clear()
