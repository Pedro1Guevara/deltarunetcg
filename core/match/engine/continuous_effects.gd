class_name ContinuousEffects
extends RefCounted
## The continuous-effects layer (Design Document 7.8): rule changes that apply while their
## condition holds, such as Vow of Majesty. A continuous Ability's function names modifiers;
## this reads the ones in force when the engine needs to know. Static functions of the engine's
## public state; they keep nothing, so they never hold the engine.


## Every modifier in force: [{"name", "args", "source": CardInPlay, "power": PowerData}] for a
## continuous Ability, [{"name", "args", "area": CardData}] for the Area in play.
static func active(engine: MatchEngine) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if engine.effects == null:
		return result
	var area := EffectBindings.area_binding(engine, EffectLibrary.TIMING_CONTINUOUS)
	if not area.is_empty():
		var area_resolver := EffectResolver.new(engine.effects, EffectBindings.area_context(engine, null))
		for modifier in area_resolver.modifiers(str(area["function"]), area["args"] as Dictionary):
			modifier["area"] = engine.stadium
			result.append(modifier)
	for owner_index in engine.players.size():
		var side := engine.players[owner_index]
		for darkner: CardInPlay in [side.active] + side.bench:
			if darkner == null:
				continue
			for power in darkner.powers():
				var binding := EffectBindings.power_binding(engine, darkner, power)
				if binding.get(EffectLibrary.TIMING_KEY) != EffectLibrary.TIMING_CONTINUOUS:
					continue
				var resolver := EffectResolver.new(engine.effects, EffectBindings.continuous_context(engine, darkner, owner_index))
				for modifier in resolver.modifiers(str(binding["function"]), binding["args"] as Dictionary):
					modifier["source"] = darkner
					modifier["power"] = power
					result.append(modifier)
	return result


## The Ability that prevents attack damage to this Darkner, or null. Vow of Majesty: damage
## from the opponent's attacks to a Darkner on its owner's Field.
static func attack_damage_preventer(engine: MatchEngine, target: CardInPlay) -> PowerData:
	var owner := engine.operations.owner_of(target)
	if owner == null or owner == engine.current_player() or not owner.bench.has(target):
		return null
	for modifier in active(engine):
		if modifier["name"] == "prevent_attack_damage_to_bench" and (modifier["args"] as Dictionary)["player"] == owner:
			return modifier["power"] as PowerData
	return null


## The Energy an attack costs attacker now: its printed cost, less what the attack's own
## modifiers take off (Showtime!: 1 less for each Darkner on its owner's Field). Colorless
## symbols go first, then the others from the end. attacker is the current player's Battling
## Darkner.
static func attack_cost(engine: MatchEngine, attacker: CardInPlay, attack: AttackData) -> Array[String]:
	var cost := attack.cost.duplicate()
	if engine.effects == null:
		return cost
	var binding := engine.effects.binding_for(attacker.card_with_attack(attack).id, EffectLibrary.SECTION_ATTACKS, attack.name)
	if binding.is_empty():
		return cost
	var context := EffectBindings.attack_context(engine, attack)
	context.source = attacker
	var resolver := EffectResolver.new(engine.effects, context)
	var less := 0
	for modifier in resolver.modifiers(str(binding["function"]), binding["args"] as Dictionary):
		if modifier["name"] == "attack_cost_less_per_benched":
			var args := modifier["args"] as Dictionary
			less += (args["player"] as PlayerState).bench.size() * int(args["per_benched"])
	for _i in mini(less, cost.size()):
		var colorless := cost.rfind(CardTypes.COLORLESS)
		cost.remove_at(colorless if colorless != -1 else cost.size() - 1)
	return cost


## How many Energy more fleeing costs darkner (Cyber City: 1 more, except Electric Darkners).
static func retreat_cost_more(engine: MatchEngine, darkner: CardInPlay) -> int:
	var more := 0
	for modifier in active(engine):
		if modifier["name"] == "retreat_cost_more_except_type":
			var args := modifier["args"] as Dictionary
			if not darkner.base_card().types.has(str(args["except_type"])):
				more += int(args["amount"])
	return more


## The TP, in quarters, a Spell costs now (Mewers Live: 25% more for a Spell of 50% or less).
static func spell_cost(engine: MatchEngine, spell: CardData) -> int:
	var cost := spell.tp_cost
	for modifier in active(engine):
		if modifier["name"] == "spell_tp_cost_more":
			var args := modifier["args"] as Dictionary
			if spell.tp_cost <= int(args["up_to"]):
				cost += int(args["amount"])
	return cost


## Whether player cannot put Basic Darkners onto their Field from their hand (Captive Audience).
## Setup never asks this: during setup Darkners are placed as usual.
static func bench_from_hand_blocked(engine: MatchEngine, player: PlayerState) -> bool:
	for modifier in active(engine):
		if modifier["name"] == "cannot_bench_basic_from_hand" and (modifier["args"] as Dictionary)["player"] == player:
			return true
	return false


## Whether the Battling Darkners have their Weakness and Resistance swapped (Second Sanctuary).
static func swaps_weakness_resistance(engine: MatchEngine) -> bool:
	return active(engine).any(func(modifier: Dictionary) -> bool: return modifier["name"] == "swap_battling_weakness_resistance")
