class_name ContinuousEffects
extends RefCounted
## The continuous-effects layer (Design Document 7.8): rule changes that apply while their
## condition holds, such as Vow of Majesty. A continuous Ability's function names modifiers;
## this reads the ones in force when the engine needs to know. Static functions of the engine's
## public state; they keep nothing, so they never hold the engine.


## Every modifier in force: [{"name", "args", "source": CardInPlay, "power": PowerData}].
static func active(engine: MatchEngine) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if engine.effects == null:
		return result
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