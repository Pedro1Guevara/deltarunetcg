class_name CardInPlay
extends RefCounted

var card: CardData
var damage: int = 0
var attached_energy: Array[CardData] = []
var turn_played: int = 0
## The cards this Pokemon evolved from, oldest first. They stay under it and share its fate.
var evolved_from: Array[CardData] = []


func _init(played_card: CardData, played_on_turn: int) -> void:
	card = played_card
	turn_played = played_on_turn


## Places an evolution card on top. Damage and attached cards stay; the Pokemon counts as
## new in play, so it cannot evolve again this turn.
func evolve(into: CardData, turn: int) -> void:
	evolved_from.append(card)
	card = into
	turn_played = turn


func remaining_hp() -> int:
	return maxi(card.hp - damage, 0)


func is_knocked_out() -> bool:
	return damage >= card.hp


func energy_pool() -> Array[String]:
	var pool: Array[String] = []
	for energy in attached_energy:
		pool.append_array(energy.provides)
	return pool


func can_pay(cost: Array[String]) -> bool:
	return EnergyPayment.can_pay(energy_pool(), cost)

