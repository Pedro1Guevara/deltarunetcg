class_name CardFilter
extends RefCounted
## Which cards an effect may pick, as a list of names from a closed set. A card matches the
## list when it matches any name in it, so Revive Song's "a basic Energy card or a Darkner" is
## ["basic_energy", "pokemon"]. A name is added here when a card first needs it.

const BASIC_ENERGY := "basic_energy"
const POKEMON := "pokemon"
const BASIC_POKEMON := "basic_pokemon"
const STADIUM := "stadium"
const TRAINER := "trainer"
const ANY := "any"
const NAMES := [BASIC_ENERGY, POKEMON, BASIC_POKEMON, STADIUM, TRAINER, ANY]

## What the player reads for each name.
const DESCRIPTIONS := {
	BASIC_ENERGY: "basic Energy",
	POKEMON: "Darkner",
	BASIC_POKEMON: "non-Evolution Darkner",
	STADIUM: "Area",
	TRAINER: "ACT card",
	ANY: "any card",
}


## True for a non-empty list of known names.
static func is_valid(filters: Variant) -> bool:
	if not filters is Array or (filters as Array).is_empty():
		return false
	for name: Variant in filters as Array:
		if not NAMES.has(name):
			return false
	return true


static func matches(card: CardData, filters: Array) -> bool:
	for name: Variant in filters:
		match str(name):
			BASIC_ENERGY:
				if card.is_energy() and card.energy_kind == CardData.ENERGY_NORMAL:
					return true
			POKEMON:
				if card.is_pokemon():
					return true
			BASIC_POKEMON:
				if card.is_basic_pokemon():
					return true
			STADIUM:
				if card.trainer_type == CardData.TRAINER_STADIUM:
					return true
			TRAINER:
				if card.is_trainer():
					return true
			ANY:
				return true
	return false


## The cards in cards that match, leaving out those in exclude.
static func select(cards: Array[CardData], filters: Array, exclude: Array) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in cards:
		if matches(card, filters) and not exclude.has(card):
			result.append(card)
	return result


## "basic Energy or Darkner", for prompts.
static func describe(filters: Array) -> String:
	var words: Array[String] = []
	for name: Variant in filters:
		words.append(str(DESCRIPTIONS.get(name, name)))
	return " or ".join(PackedStringArray(words))