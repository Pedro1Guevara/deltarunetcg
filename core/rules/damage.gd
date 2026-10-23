class_name Damage
extends RefCounted
## Damage calculation (Design Document 4.3). Pure functions of the cards involved: they read
## no match state and change nothing.


## Weakness before Resistance, each applied once, floored at zero. The modifier is read from
## the defending card, so WOTC cards (×2, -30) and Deltarune cards (+20, -20) both work.
static func apply_modifiers(attacker: CardData, defender: CardData, base_damage: int) -> int:
	if base_damage <= 0:
		return 0
	var result := base_damage
	if _shares_type(attacker.types, defender.weakness_types):
		result = _modified(result, defender.weakness_modifier, defender.id)
	if _shares_type(attacker.types, defender.resistance_types):
		result = _modified(result, defender.resistance_modifier, defender.id)
	return maxi(result, 0)


## Applies a printed modifier: "×2" or "x2" multiplies, "+20" adds, "-20" subtracts.
## An unreadable modifier changes nothing and is reported.
static func _modified(damage: int, modifier: String, card_id: String) -> int:
	if modifier.length() < 2 or not modifier.substr(1).is_valid_int():
		push_error("Damage: %s has an unreadable modifier '%s'" % [card_id, modifier])
		return damage
	var amount := modifier.substr(1).to_int()
	match modifier[0]:
		"\u00d7", "x":
			return damage * amount
		"+":
			return damage + amount
		"-":
			return damage - amount
	push_error("Damage: %s has an unreadable modifier '%s'" % [card_id, modifier])
	return damage


static func _shares_type(attacker_types: Array[String], target_types: Array[String]) -> bool:
	for attacker_type in attacker_types:
		if target_types.has(attacker_type):
			return true
	return false