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


## A copy that shares the printed cards but none of the state: changing it changes nothing
## here. For views of the round (PlayerView).
func snapshot() -> CardInPlay:
	var copy := CardInPlay.new(card, turn_played)
	copy.damage = damage
	copy.attached_energy = attached_energy.duplicate()
	copy.evolved_from = evolved_from.duplicate()
	return copy


## Places an evolution card on top. Damage and attached cards stay; the Pokemon counts as
## new in play, so it cannot evolve again this turn.
func evolve(into: CardData, turn: int) -> void:
	evolved_from.append(card)
	card = into
	turn_played = turn


## The card whose printed Weakness, Resistance and Flee cost apply. A BREAK evolution keeps
## those of the card it evolved from (Design Document 3.2); any other card uses its own.
func base_card() -> CardData:
	return _cards_in_effect()[0]


## The attacks this Darkner can use: a BREAK evolution keeps the attacks of the card it evolved
## from, listed first, and adds its own.
func attacks() -> Array[AttackData]:
	var result: Array[AttackData] = []
	for printed in _cards_in_effect():
		result.append_array(printed.attacks)
	return result


## The Abilities this Darkner has, kept the same way as its attacks.
func powers() -> Array[PowerData]:
	var result: Array[PowerData] = []
	for printed in _cards_in_effect():
		result.append_array(printed.powers)
	return result


## The card that prints an attack this Darkner can use, whose effect binding it resolves with.
func card_with_attack(attack: AttackData) -> CardData:
	for printed in _cards_in_effect():
		if printed.attacks.has(attack):
			return printed
	return card


## The card that prints an Ability this Darkner has.
func card_with_power(power: PowerData) -> CardData:
	for printed in _cards_in_effect():
		if printed.powers.has(power):
			return printed
	return card


## The cards whose attacks and Abilities apply, the oldest first: the top card, and below it
## every card a BREAK evolution was played on.
func _cards_in_effect() -> Array[CardData]:
	var cards: Array[CardData] = [card]
	var index := evolved_from.size() - 1
	while cards[0].stage == CardData.STAGE_BREAK and index >= 0:
		cards.push_front(evolved_from[index])
		index -= 1
	return cards


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