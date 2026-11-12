class_name PlayConditions
extends RefCounted
## Whether a Darkner card may be played from the hand onto the Field, or placed during setup
## (Design Document 7.4): its play_condition Ability names modifiers that say when (Pure
## Darkness: 3 or more Titan Spawn in play). Static and pure: it reads the card's binding and
## its owner's side, and never holds the engine. Effects that put a Darkner onto the Field from
## the deck do not play it, so they never ask.


## Whether owner may play card now. Cards with no play condition always may.
static func allows(effects: EffectLibrary, owner: PlayerState, card: CardData) -> bool:
	if effects == null or not card.is_pokemon():
		return true
	for power in card.powers:
		var binding := effects.binding_for(card.id, EffectLibrary.SECTION_POWERS, power.name)
		if binding.get(EffectLibrary.TIMING_KEY) != EffectLibrary.TIMING_PLAY_CONDITION:
			continue
		var args := binding["args"] as Dictionary
		var definition := effects.functions.get(str(binding["function"]), {}) as Dictionary
		for step: Variant in definition.get("steps", []) as Array:
			var call := str((step as Dictionary)["call"])
			if call != "play_only_with_in_play":
				continue
			var step_args := (step as Dictionary)["args"] as Dictionary
			var card_id := str(_value(step_args["card_id"], args))
			if _in_play(owner, card_id) < int(_value(step_args["count"], args)):
				return false
	return true


## How many of owner's Darkners in play have card_id as their card or one under it.
static func _in_play(owner: PlayerState, card_id: String) -> int:
	var found := 0
	for darkner: CardInPlay in [owner.active] + owner.bench:
		if darkner == null:
			continue
		for card in [darkner.card] + darkner.evolved_from:
			if (card as CardData).id == card_id:
				found += 1
				break
	return found


## A step argument: a literal, or "$name" read from the binding's arguments.
static func _value(raw: Variant, args: Dictionary) -> Variant:
	if raw is String and (raw as String).begins_with("$"):
		return args.get((raw as String).substr(1))
	return raw
