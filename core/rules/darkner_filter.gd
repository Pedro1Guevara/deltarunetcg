class_name DarknerFilter
extends RefCounted
## Which Darkners in play an effect may choose, as a list of names from a closed set. Unlike a
## CardFilter, a Darkner matches the list only when it matches every name in it: Workshop's "a
## non-Evolution Darkner that doesn't have an ability or any energy cards attached" is
## ["unevolved", "no_abilities", "no_energy"]. A name is added here when a card first needs it.

## Its top card is not an Evolution card (Design Document 3.2).
const UNEVOLVED := "unevolved"
## It has no Ability, printed or kept from the card it evolved from.
const NO_ABILITIES := "no_abilities"
## No Energy card is attached to it.
const NO_ENERGY := "no_energy"
const ANY := "any"
const NAMES := [UNEVOLVED, NO_ABILITIES, NO_ENERGY, ANY]


## True for a non-empty list of known names.
static func is_valid(filters: Variant) -> bool:
	if not filters is Array or (filters as Array).is_empty():
		return false
	for name: Variant in filters as Array:
		if not NAMES.has(name):
			return false
	return true


static func matches(darkner: CardInPlay, filters: Array) -> bool:
	for name: Variant in filters:
		match str(name):
			UNEVOLVED:
				if not darkner.card.is_basic_pokemon():
					return false
			NO_ABILITIES:
				if not darkner.powers().is_empty():
					return false
			NO_ENERGY:
				if not darkner.attached_energy.is_empty():
					return false
	return true


## The slots of darkners that match, in order.
static func matching_slots(darkners: Array[CardInPlay], filters: Array) -> Array[int]:
	var slots: Array[int] = []
	for slot in darkners.size():
		if matches(darkners[slot], filters):
			slots.append(slot)
	return slots
