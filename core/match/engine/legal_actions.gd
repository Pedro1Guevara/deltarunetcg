class_name LegalActions
extends RefCounted
## The actions the player taking the turn may choose when no question is open (Design Document
## 4.2 and 8.4). Static functions of the engine's public state: they only read it, and keep
## nothing, so they never hold the engine.


## Every legal action of the player taking the turn. The engine answers an open question itself.
static func for_turn(engine: MatchEngine) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var player := engine.current_player()
	var opponent := engine.opponent_player()

	# Copies of the same card are interchangeable: one set of actions per distinct card.
	var offered := {}
	for hand_index in player.hand.size():
		var card := player.hand[hand_index]
		if offered.has(card.id):
			continue
		offered[card.id] = true
		if card.is_basic_pokemon() and player.bench.size() < engine.rules.bench_limit:
			actions.append({
				"type": "bench",
				"hand_index": hand_index,
				"label": "Put %s on the Field" % card.name,
			})
		elif card.is_energy() and not player.energy_attached_this_turn:
			for slot in range(-1, player.bench.size()):
				var target := MatchEngine.in_play_at(player, slot)
				if target == null:
					continue
				actions.append({
					"type": "attach",
					"hand_index": hand_index,
					"slot": slot,
					"label": "Attach %s to %s (%s)" % [card.name, target.card.name, MatchEngine.slot_name(slot)],
				})
		elif card.is_trainer() and can_play_trainer(engine, player, card):
			actions.append({
				"type": "play_trainer",
				"hand_index": hand_index,
				"label": trainer_label(engine, card),
			})

	var offered_evolutions := {}
	for hand_index in player.hand.size():
		var evolution := player.hand[hand_index]
		if not is_evolution_card(evolution) or offered_evolutions.has(evolution.id):
			continue
		offered_evolutions[evolution.id] = true
		for slot in range(-1, player.bench.size()):
			var target := MatchEngine.in_play_at(player, slot)
			if target != null and can_evolve(engine, player, target, evolution):
				actions.append({
					"type": "evolve",
					"hand_index": hand_index,
					"slot": slot,
					"label": "Evolve %s into %s (%s)" % [target.card.name, evolution.name, MatchEngine.slot_name(slot)],
				})

	for slot in range(-1, player.bench.size()):
		var user := MatchEngine.in_play_at(player, slot)
		if user == null:
			continue
		for power in user.powers():
			if EffectBindings.power_usable(engine, user, power):
				actions.append({
					"type": "use_power",
					"slot": slot,
					"power": power.name,
					"label": "Use %s (%s, %s)" % [power.name, user.card.name, MatchEngine.slot_name(slot)],
				})

	if EffectBindings.area_action_usable(engine):
		actions.append({
			"type": "use_area",
			"label": "Use %s (Area)" % engine.stadium.name,
		})

	if player.active != null and not player.retreated_this_turn and player.active.can_pay(engine.retreat_cost(player.active)):
		for slot in player.bench.size():
			actions.append({
				"type": "retreat",
				"slot": slot,
				"label": "Flee %s for %s (%s)" % [player.active.card.name, player.bench[slot].card.name, MatchEngine.slot_name(slot)],
			})

	if player.active != null and opponent.active != null and _attacks_allowed(engine):
		var attacks := player.active.attacks()
		for attack_index in attacks.size():
			var attack := attacks[attack_index]
			if player.active.can_pay(engine.attack_cost(player.active, attack)) and EffectBindings.attack_requirements_met(engine, attack):
				actions.append({
					"type": "attack",
					"attack_index": attack_index,
					"label": "Attack: %s (%d)" % [attack.name, attack.damage],
				})

	actions.append({"type": "end_turn", "label": "End turn"})
	return actions


## Evolution rules (Design Document 3.2): the card evolves from the target's name; a BREAK
## evolution goes on anything but another BREAK, a classic one goes one stage at a time; the
## target has been in play since before this turn; and it is not the player's first turn.
static func can_evolve(engine: MatchEngine, player: PlayerState, target: CardInPlay, evolution: CardData) -> bool:
	if not is_evolution_card(evolution) or evolution.evolve_from != target.card.name:
		return false
	if evolution.stage == CardData.STAGE_BREAK:
		if target.card.stage == CardData.STAGE_BREAK:
			return false
	else:
		var expected_stage := "Stage1" if target.card.stage == CardData.STAGE_BASIC else "Stage2" if target.card.stage == "Stage1" else ""
		if evolution.stage != expected_stage:
			return false
	return player.turns_started > 1 and target.turn_played < engine.turn


static func is_evolution_card(card: CardData) -> bool:
	return card.is_pokemon() and not card.is_basic_pokemon() and not card.evolve_from.is_empty()


## Trainer cards are played freely; one Supporter per turn, never on the
## first player's first turn; one Stadium per turn, never one with the name of the Stadium in play;
## Spells while the player has the TP. A Trainer with no ACT subtype (legacy data) is not
## playable.
static func can_play_trainer(engine: MatchEngine, player: PlayerState, card: CardData) -> bool:
	var allowed := false
	match card.trainer_type:
		CardData.TRAINER_ITEM:
			allowed = true
		CardData.TRAINER_SUPPORTER:
			allowed = not player.supporter_played_this_turn and _supporters_allowed(engine)
		CardData.TRAINER_STADIUM:
			allowed = not player.stadium_played_this_turn and (engine.stadium == null or engine.stadium.name != card.name)
		CardData.TRAINER_SPELL:
			allowed = engine.operations.can_spend_tp(player, engine.spell_cost(card))
	# A card that is known to have no effect cannot be played.
	return allowed and EffectBindings.trainer_requirements_met(engine, card)


## The player going first cannot play a Supporter
## on their first turn, which is always turn 1.
static func _supporters_allowed(engine: MatchEngine) -> bool:
	return engine.rules.first_player_can_play_supporter or engine.turn > 1


static func trainer_label(engine: MatchEngine, card: CardData) -> String:
	match card.trainer_type:
		CardData.TRAINER_SUPPORTER:
			return "Play %s (Lightner)" % card.name
		CardData.TRAINER_STADIUM:
			return "Play %s (Area)" % card.name
		CardData.TRAINER_SPELL:
			return "Cast %s (%d%% TP)" % [card.name, engine.spell_cost(card) * 25]
	return "Play %s (Item)" % card.name


## Current standard rule (Design Document 4.2): the player going first cannot attack on
## their first turn. Turn 1 is always that turn, since start() resets the counter.
static func _attacks_allowed(engine: MatchEngine) -> bool:
	return engine.rules.first_player_can_attack or engine.turn > 1