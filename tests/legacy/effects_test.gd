## Headless checks for the card effect system. Run from the project root:
##   godot --headless --path . --script res://tests/effects_test.gd
## Exits with code 0 when every check passes.
extends TestCase

var lib: EffectLibrary

## Player 1 (index 0) to act with attacker vs defender.
func setup(attacker_id: String, attached: Array, defender_id: String, defender_attached: Array = []) -> MatchEngine:
	var decks := DataLoader.read_json(DataLoader.LEGACY_DECKS_PATH) as Dictionary
	var engine := MatchEngine.new()
	engine.effects = lib
	engine.start(db.build_deck(decks["fighting_starter"]), db.build_deck(decks["lightning_starter"]), MatchRules.legacy(), Rng.new(7))
	finish_setup(engine)
	engine.current_index = 0
	for p in engine.players:
		p.bench.clear()
		p.reset_turn_flags()
	engine.players[0].active = in_play(attacker_id, attached)
	engine.players[1].active = in_play(defender_id, defender_attached)
	return engine

var last_defender: CardInPlay
var last_attacker: CardInPlay

func attack(engine: MatchEngine, name: String) -> bool:
	last_defender = engine.players[1].active
	last_attacker = engine.players[0].active
	for action in engine.legal_actions():
		if action["type"] == "attack" and str(action["label"]).begins_with("Attack: %s " % name):
			engine.apply(action)
			return true
	return false


func _run() -> void:
	db = DataLoader.load_legacy_card_database()
	lib = DataLoader.load_effect_library(db, DataLoader.LEGACY_CARD_EFFECTS_PATH)
	print("== load")
	expect(lib.errors.is_empty(), "no validation errors: %s" % [lib.errors])
	expect(lib.valid_binding_count() == 74, "74 card effect entries in use (%d)" % lib.valid_binding_count())
	print("  warnings: ", lib.warnings)

	print("== scenarios")
	var W := "base1-102"; var F := "base1-98"; var L := "base1-100"; var P := "base1-101"; var G := "base1-97"

	# Ember: Charmander with Fire + Lightning, defender Voltorb (no W/R vs Fire)
	var e := setup("base1-46", [F, L], "base1-67")
	expect(attack(e, "Ember"), "Ember is legal")
	var voltorb := e.players[1].active
	expect(voltorb.damage == 30, "Ember deals 30 (%d)" % voltorb.damage)
	var charmander_energy := e.players[0].active.energy_pool()
	expect(charmander_energy == ["Lightning"], "Ember discarded the Fire Energy (%s)" % [charmander_energy])
	expect(e.players[0].discard.size() == 1, "discarded card is in the discard pile")

	# Requirement: discard_own_energy needs a Fire Energy
	var r := setup("base1-46", [L, L], "base1-67")
	var ctx := EffectContext.new()
	ctx.engine = r; ctx.source = r.players[0].active; ctx.defender = r.players[1].active
	ctx.player = r.players[0]; ctx.opponent = r.players[1]; ctx.attack = ctx.source.card.attacks[1]
	var resolver := EffectResolver.new(lib, ctx)
	expect(not resolver.requirements_met("discard_energy_cards_then_damage", {"energy_type": "Fire", "count": 1}), "requirement fails without Fire Energy")
	r.players[0].active.attached_energy.assign(energies([F]))
	expect(resolver.requirements_met("discard_energy_cards_then_damage", {"energy_type": "Fire", "count": 1}), "requirement passes with one Fire Energy")
	expect(not resolver.requirements_met("discard_energy_cards_then_damage", {"energy_type": "Fire", "count": 2}), "requirement fails asking for two")

	# Karate Chop: Machoke 50 minus 10 per counter
	var k := setup("base1-34", [G, G, G], "base1-26")
	k.players[0].active.damage = 30
	expect(attack(k, "Karate Chop"), "Karate Chop is legal")
	expect(last_defender.damage == 20, "Karate Chop with 3 counters deals 20 (%d)" % last_defender.damage)

	# Flail: Magikarp times own counters
	var fl := setup("base1-35", [W], "base1-67")
	fl.players[0].active.damage = 20
	expect(attack(fl, "Flail"), "Flail is legal")
	expect(last_defender.damage == 20, "Flail with 2 counters deals 20 (%d)" % last_defender.damage)

	# Hydro Pump: Blastoise 40 + 10 per unpaid Water, max 2
	var hp := setup("base1-2", [W, W, W, W, G], "base2-11")
	expect(attack(hp, "Hydro Pump"), "Hydro Pump is legal")
	expect(last_defender.damage == 50, "Hydro Pump with one extra Water and one Fighting deals 50 (%d)" % last_defender.damage)
	var hp2 := setup("base1-2", [W, W, W, W, W, W], "base2-11")
	attack(hp2, "Hydro Pump")
	expect(last_defender.damage == 60, "Hydro Pump caps at two extra Water: 60 (%d)" % last_defender.damage)

	# Psychic: Mewtwo 10 + 10 per Energy on the defender
	var ps := setup("base1-10", [P, P], "base1-67", [L, L, L])
	expect(attack(ps, "Psychic"), "Psychic is legal")
	expect(last_defender.damage == 40, "Psychic against 3 Energy deals 40 (%d)" % last_defender.damage)

	# Thunderbolt: Zapdos discards all
	var tb := setup("base1-16", [L, L, L, L, F], "base1-52")
	expect(attack(tb, "Thunderbolt"), "Thunderbolt is legal")
	expect(tb.players[0].active.attached_energy.is_empty(), "Thunderbolt discarded every Energy")
	expect(tb.players[0].discard.size() == 5, "five Energy in the discard pile")

	# Fetch draws a card and deals nothing
	var fe := setup("base2-5", [G], "base1-67")
	var hand_before := fe.players[0].hand.size()
	expect(attack(fe, "Fetch"), "Fetch is legal")
	expect(fe.players[0].hand.size() == hand_before + 1, "Fetch drew one card")
	expect(last_defender.damage == 0, "Fetch dealt no damage")

	var DCE := "base1-96"

	print("== energy cards and units")
	expect(db.make(DCE).provides == ["Colorless", "Colorless"], "Double Colorless Energy provides two Colorless")
	expect(db.warnings.size() == 4 and "\n".join(PackedStringArray(db.warnings)).contains("no evolveFrom"), "the only parse warnings are the four fossil evolutions without evolveFrom: %s" % [db.warnings])
	expect(db.make("base2-11").evolve_from.is_empty(), "a WOTC Basic keeps no evolveFrom even when TCGdex names a later baby Pokemon")
	var ps2 := setup("base1-10", [P, P], "base1-65", [DCE, L])
	attack(ps2, "Psychic")
	expect(last_defender.damage == 30, "Psychic counts Energy cards: DCE + Lightning is 2, deals 30 (%d)" % last_defender.damage)
	var egg := setup("base2-35", [DCE, G], "base2-11")
	attack(egg, "Big Eggsplosion")
	var flips := 0
	for line in egg.events:
		if line.contains("Coin flip"):
			flips += 1
	expect(flips == 3, "Big Eggsplosion counts Energy units: DCE + Fighting flips 3 coins (%d)" % flips)
	var wg := setup("base1-13", [W, W, W, DCE], "base2-11")
	attack(wg, "Water Gun")
	expect(last_defender.damage == 40, "Water Gun: DCE pays the Colorless, so the third Water is unpaid, deals 40 (%d)" % last_defender.damage)
	var rt := setup("base1-7", [G, DCE], "base2-11")
	rt.players[0].bench.append(CardInPlay.new(db.make("base1-26"), 0))
	for action in rt.legal_actions():
		if action["type"] == "retreat":
			rt.apply(action)
			break
	expect(rt.players[0].bench[0].energy_pool() == ["Fighting"], "retreat cost 2 is paid by the DCE alone, without asking")
	var rc := setup("base1-7", [G, G, DCE], "base2-11")
	rc.players[0].bench.append(CardInPlay.new(db.make("base1-26"), 0))
	for action in rc.legal_actions():
		if action["type"] == "retreat":
			rc.apply(action)
			break
	var retreat_labels: Array = []
	for action in rc.legal_actions():
		retreat_labels.append(action["label"])
	expect(retreat_labels == ["Discard Double Colorless Energy", "Discard Fighting Energy + Fighting Energy"], "retreat offers only payments without spare cards: %s" % [retreat_labels])
	for action in rc.legal_actions():
		if str(action["label"]).contains("Fighting Energy + Fighting Energy"):
			rc.apply(action)
	expect(rc.players[0].bench[0].energy_pool() == ["Colorless", "Colorless"], "paying with two Fighting keeps the DCE")
	expect(rc.players[0].active.card.id == "base1-26" and rc.players[0].retreated_this_turn, "the retreat completed after the choice")

	print("== promotion and setup choices")
	var pr := setup("base1-7", [G, G, G], "base1-67")
	pr.players[1].bench.append(CardInPlay.new(db.make("base1-61"), 0))
	pr.players[1].bench.append(CardInPlay.new(db.make("base1-26"), 0))
	expect(attack(pr, "Special Punch"), "Special Punch is legal")
	expect(pr.is_waiting_for_choice() and pr.choice_chooser() == 1, "the knocked out player chooses the replacement")
	expect(pr.current_index == 0, "the turn does not pass before the promotion")
	for action in pr.legal_actions():
		if str(action["label"]).contains("Dratini"):
			pr.apply(action)
	expect(pr.players[1].active.card.id == "base1-26" and pr.players[1].bench.size() == 1, "Dratini was promoted by choice")
	expect(pr.current_index == 1, "the turn passed after the promotion")

	var decks_for_setup := DataLoader.read_json(DataLoader.LEGACY_DECKS_PATH) as Dictionary
	var asked := false
	for trial in 20:
		var st := MatchEngine.new()
		st.effects = lib
		st.start(db.build_deck(decks_for_setup["fighting_starter"]), db.build_deck(decks_for_setup["lightning_starter"]), MatchRules.legacy(), Rng.new(trial))
		if not (st.is_waiting_for_choice() and st.choice_prompt() == "Choose your Battling Darkner"):
			continue
		asked = true
		var first_chooser := st.choice_chooser()
		expect(st.turn == 0 and st.players[first_chooser].active == null, "setup waits before turn 1 with no Battling Darkner")
		var hand_before_choice := st.players[first_chooser].hand.size()
		st.apply(st.legal_actions()[0])
		expect(st.players[first_chooser].active != null and st.players[first_chooser].hand.size() == hand_before_choice - 1, "the chosen Basic left the hand and became Active")
		while st.is_waiting_for_choice():
			st.apply(st.legal_actions()[0])
		expect(st.turn == 1 and st.players[0].active != null and st.players[1].active != null, "turn 1 starts once both have chosen")
		break
	expect(asked, "at least one of 20 setups asked for an Battling Darkner")

	print("== setup bench and mulligan draws")
	var benched_in_setup := false
	for trial in 20:
		var sb := MatchEngine.new()
		sb.start(db.build_deck(decks_for_setup["fighting_starter"]), db.build_deck(decks_for_setup["lightning_starter"]), MatchRules.legacy(), Rng.new(trial))
		if sb.is_waiting_for_choice() and sb.choice_prompt() == "Choose your Battling Darkner":
			sb.apply(sb.legal_actions()[0])
		if not (sb.is_waiting_for_choice() and sb.choice_prompt().begins_with("Put Basic Darkners on the Field before the game starts") and sb.choice_chooser() == 0):
			continue
		var hand_size := sb.players[0].hand.size()
		sb.apply(sb.legal_actions()[0])
		for action in sb.legal_actions():
			if str(action["label"]).begins_with("Finish"):
				sb.apply(action)
				break
		expect(sb.players[0].bench.size() == 1 and sb.players[0].hand.size() == hand_size - 1, "a Basic benched during setup left the hand")
		finish_setup(sb)
		expect(sb.turn == 1 and sb.players[0].bench.size() == 1, "the setup bench is still there on turn 1")
		benched_in_setup = true
		break
	expect(benched_in_setup, "a setup offered benching")

	var one_basic := {"cards": {"base1-52": 1, "base1-97": 29}}
	var compensated := false
	for trial in 200:
		var mg := MatchEngine.new()
		mg.start(db.build_deck(one_basic), db.build_deck(decks_for_setup["lightning_starter"]), MatchRules.legacy(), Rng.new(trial))
		if mg.players[0].mulligans <= mg.players[1].mulligans:
			continue
		var extra := mg.players[0].mulligans - mg.players[1].mulligans
		while mg.is_waiting_for_choice() and not mg.choice_prompt().contains("more mulligan"):
			var actions := mg.legal_actions()
			var pick := actions[0]
			for action in actions:
				if str(action["label"]).begins_with("Finish"):
					pick = action
			mg.apply(pick)
		expect(mg.is_waiting_for_choice() and mg.choice_chooser() == 1, "the player with fewer mulligans is offered the draws (%d extra)" % extra)
		var draw_options := mg.legal_actions()
		expect(draw_options.size() == extra + 1, "options run from %d cards down to 0" % extra)
		var hand_before_draws := mg.players[1].hand.duplicate()
		mg.apply(draw_options[0])
		expect(mg.players[1].hand.size() == hand_before_draws.size() + extra, "drew %d cards" % extra)
		if mg.is_waiting_for_choice() and mg.choice_prompt().begins_with("Put Basic Darkners on the Field before the game starts"):
			var only_drawn := true
			for action in mg.legal_actions():
				var label := str(action["label"])
				if label.begins_with("Bench"):
					var in_old_hand := false
					for card: CardData in hand_before_draws:
						if label == "Put %s on the Field" % card.name:
							in_old_hand = true
					var drawn_same_name := false
					for card in mg.players[1].hand:
						if not hand_before_draws.has(card) and label == "Put %s on the Field" % card.name:
							drawn_same_name = true
					if in_old_hand and not drawn_same_name:
						only_drawn = false
			expect(only_drawn, "benching after the draws offers only Basic Pokemon drawn for mulligans")
		finish_setup(mg)
		expect(mg.turn == 1, "turn 1 starts after the mulligan draws")
		compensated = true
		break
	expect(compensated, "found a setup where only one player took extra mulligans")

	print("== evolution")
	var ev := setup("base1-46", [F, F, F], "base2-11")
	ev.players[0].active.damage = 20
	var charmeleon := db.make("base1-24")
	var charizard := db.make("base1-4")
	ev.players[0].hand.append(charmeleon)
	ev.players[0].hand.append(charizard)
	ev.turn = 5
	ev.players[0].turns_started = 3
	var evolve_labels: Array = []
	for action in ev.legal_actions():
		if action["type"] == "evolve":
			evolve_labels.append(action["label"])
	expect(evolve_labels == ["Evolve Charmander into Charmeleon (Battle Zone)"], "Charmeleon can evolve Charmander; Charizard cannot skip a stage: %s" % [evolve_labels])
	for action in ev.legal_actions():
		if action["type"] == "evolve":
			ev.apply(action)
	var evolved := ev.players[0].active
	expect(evolved.card.id == "base1-24" and evolved.evolved_from.size() == 1, "the active is now Charmeleon with Charmander under it")
	expect(evolved.damage == 20 and evolved.attached_energy.size() == 3, "damage and Energy stay after evolving")
	var twice := false
	for action in ev.legal_actions():
		if action["type"] == "evolve":
			twice = true
	expect(not twice, "a Pokemon cannot evolve twice in the same turn")
	expect(attack(ev, "Flamethrower"), "the evolved Pokemon uses its new attacks")

	var ev2 := setup("base1-46", [F], "base2-11")
	ev2.players[0].hand.append(db.make("base1-24"))
	ev2.turn = 5
	ev2.players[0].turns_started = 3
	ev2.players[0].active.turn_played = 5
	var blocked := true
	for action in ev2.legal_actions():
		if action["type"] == "evolve":
			blocked = false
	expect(blocked, "a Pokemon put into play this turn cannot evolve")
	ev2.players[0].active.turn_played = 3
	ev2.players[0].turns_started = 1
	blocked = true
	for action in ev2.legal_actions():
		if action["type"] == "evolve":
			blocked = false
	expect(blocked, "nothing evolves during a player's first turn")
	ev2.players[0].turns_started = 2
	var allowed := false
	for action in ev2.legal_actions():
		if action["type"] == "evolve":
			allowed = true
	expect(allowed, "evolution is allowed from the player's second turn")

	var ko_stack := setup("base1-7", [G, G, G], "base1-24")
	ko_stack.players[1].active.evolved_from.append(db.make("base1-46"))
	ko_stack.players[1].active.damage = 70
	ko_stack.players[1].bench.append(CardInPlay.new(db.make("base1-61"), 0))
	var discard_before := ko_stack.players[1].discard.size()
	attack(ko_stack, "Jab")
	expect(ko_stack.players[1].discard.size() == discard_before + 2, "a knocked out evolved Pokemon discards the cards under it too")

	print("== choosing Energy to discard")
	var fs := setup("base1-4", [F, F, F, F, DCE], "base1-3")
	expect(attack(fs, "Fire Spin"), "Fire Spin is legal")
	expect(fs.is_waiting_for_choice() and fs.choice_chooser() == 0, "Fire Spin waits for the attacker's choice")
	var choices := fs.legal_actions()
	var labels: Array = []
	for action in choices:
		labels.append(action["label"])
	expect(choices.size() == 2, "two options, Fire Energy and DCE, not five: %s" % [labels])
	expect(fs.players[0].discard.is_empty() and last_defender.damage == 0, "nothing happens before the choice")
	for action in choices:
		if str(action["label"]).contains("Double Colorless"):
			fs.apply(action)
	expect(not fs.is_waiting_for_choice(), "the second card is the only kind left and needs no choice")
	var discarded_names: Array = []
	for card in fs.players[0].discard:
		discarded_names.append(card.name)
	discarded_names.sort()
	expect(discarded_names == ["Double Colorless Energy", "Fire Energy"], "discarded DCE and one Fire Energy: %s" % [discarded_names])
	expect(last_defender.damage == 100, "Fire Spin dealt 100 after the choice (%d)" % last_defender.damage)
	var fs2 := setup("base1-4", [F, F, F, F, F, F], "base1-3")
	attack(fs2, "Fire Spin")
	expect(not fs2.is_waiting_for_choice() and fs2.players[0].discard.size() == 2, "identical Fire Energy need no choice")

	print("== simultaneous knockouts")
	var both := setup("base1-3", [G, G, G, G], "base1-7")
	both.players[0].active.damage = 50
	both.players[0].bench.append(CardInPlay.new(db.make("base1-26"), 0))
	both.players[1].bench.append(CardInPlay.new(db.make("base1-61"), 0))
	var p0 := both.players[0].prizes.size()
	var p1 := both.players[1].prizes.size()
	attack(both, "Double-edge")
	expect(both.players[0].prizes.size() == p0 - 1 and both.players[1].prizes.size() == p1 - 1, "both players took a prize")
	expect(not both.is_over() and both.players[0].active.card.id == "base1-26" and both.players[1].active.card.id == "base1-61", "both promoted and the match goes on")
	var sd := setup("base1-3", [G, G, G, G], "base1-7")
	sd.players[0].active.damage = 50
	sd.players[0].bench.append(CardInPlay.new(db.make("base1-26"), 0))
	sd.players[1].bench.append(CardInPlay.new(db.make("base1-61"), 0))
	while sd.players[0].prizes.size() > 1: sd.players[0].prizes.pop_back()
	while sd.players[1].prizes.size() > 1: sd.players[1].prizes.pop_back()
	attack(sd, "Double-edge")
	expect(sd.winner == MatchEngine.SUDDEN_DEATH, "both take their last prize: Sudden Death")
	var two := setup("base1-3", [G, G, G, G], "base1-7")
	two.players[0].active.damage = 50
	two.players[0].bench.append(CardInPlay.new(db.make("base1-26"), 0))
	while two.players[0].prizes.size() > 1: two.players[0].prizes.pop_back()
	while two.players[1].prizes.size() > 1: two.players[1].prizes.pop_back()
	attack(two, "Double-edge")
	expect(two.winner == 0, "player 1 wins in two ways, player 2 in one: player 1 wins")

	# Double-edge: Chansey 80 to defender and 80 to itself; knocked out if already damaged
	var de := setup("base1-3", [G, G, G, G], "base1-7")
	expect(attack(de, "Double-edge"), "Double-edge is legal")
	expect(last_attacker.damage == 80, "Chansey took 80 (%d)" % last_attacker.damage)
	var ko := setup("base1-3", [G, G, G, G], "base2-11")
	ko.players[0].active.damage = 50
	ko.players[0].bench.append(CardInPlay.new(db.make("base1-26"), 0))
	var prizes_before := ko.players[1].prizes.size()
	attack(ko, "Double-edge")
	expect(ko.players[1].prizes.size() == prizes_before - 1, "opponent took a prize for Chansey knocking itself out")
	expect(ko.players[0].active.card.id == "base1-26", "Dratini was promoted")

	# Coin-based: Comet Punch = 20 x heads, Thunder Jolt self-damage only on tails
	var consistent := true
	var jolt_ok := true
	for trial in 60:
		var cp := setup("base2-5", [G, G, G, G], "base2-11")
		cp.set("_rng", Rng.new(trial))
		attack(cp, "Comet Punch")
		var heads := 0
		for line in cp.events:
			if line.ends_with("heads"): heads += 1
		if last_defender.damage != 20 * heads:
			consistent = false
		var tj := setup("base1-58", [L, L], "base1-7")
		tj.set("_rng", Rng.new(trial))
		attack(tj, "Thunder Jolt")
		var tails := tj.events.has("  Coin flip: tails")
		if (last_attacker.damage == 10) != tails:
			jolt_ok = false
	expect(consistent, "Comet Punch deals 20 per heads across 60 seeds")
	expect(jolt_ok, "Thunder Jolt damages Pikachu only on tails across 60 seeds")

	print("== validator")
	var bad_functions := {
		"flip_coins": {"params": {}, "steps": [{"call": "draw_cards", "args": {"player": "$player", "count": 1}}]},
		"unknown_call": {"params": {}, "steps": [{"call": "does_not_exist", "args": {}}]},
		"missing_arg": {"params": {}, "steps": [{"call": "multiply", "args": {"a": 1}}]},
		"extra_arg": {"params": {}, "steps": [{"call": "multiply", "args": {"a": 1, "b": 2, "c": 3}}]},
		"wrong_literal": {"params": {}, "steps": [{"call": "multiply", "args": {"a": "Fire", "b": 2}}]},
		"undefined_ref": {"params": {}, "steps": [{"call": "multiply", "args": {"a": "$nope", "b": 2}}]},
		"output_reuses_param": {"params": {"x": "int"}, "steps": [{"call": "multiply", "args": {"a": "$x", "b": 2}, "as": "x"}]},
		"conditional_output": {"params": {}, "steps": [{"call": "multiply", "args": {"a": 1, "b": 2}, "as": "y", "when": {"value": 1, "eq": 1}}]},
		"requires_under_when": {"params": {}, "steps": [{"call": "discard_own_energy_cards", "args": {"energy_type": "Fire", "count": 1}, "when": {"value": 1, "eq": 1}}]},
		"output_to_requires": {"params": {}, "steps": [{"call": "flip_coins", "args": {"count": 1}, "as": "h"}, {"call": "discard_own_energy_cards", "args": {"energy_type": "Fire", "count": "$h"}}]},
		"cycle_a": {"params": {}, "steps": [{"call": "cycle_b", "args": {}}]},
		"cycle_b": {"params": {}, "steps": [{"call": "cycle_a", "args": {}}]},
		"wrong_ref_type": {"params": {}, "steps": [{"call": "multiply", "args": {"a": "$self", "b": 2}}]},
	}
	var functions := (DataLoader.read_json(DataLoader.FUNCTIONS_PATH) as Dictionary).duplicate(true)
	functions.merge(bad_functions)
	var bad_cards := {
		"base1-91": {"trainer": {"function": "damage_times_heads", "args": {"coins": 1}}},
		"base1-92": {"trainer": {"function": "damage_self", "args": {"amount": 10}}},
		"base1-46": {"attacks": {"Flamethrower": {"function": "draw", "args": {"count": 1}}, "Ember": {"function": "discard_energy_cards_then_damage", "args": {"energy_type": "$self", "count": 1}}}},
		"base1-58": {"attacks": {"Thunder Jolt": {"function": "damage_then_damage_self_on_tails", "args": {}}}},
		"base1-24": {"attacks": {"Flamethrower": {"function": "draw", "args": {"count": 1}}}},
		"base1-36": {"attacks": {"Flamethrower": {"function": "discard_energy_cards_then_damage", "args": {"energy_type": "Purple", "count": 1}}}},
		"nope-1": {"attacks": {}},
	}
	var bad := EffectLibrary.new()
	bad.load_data(functions, bad_cards, db)
	var all_errors := "\n".join(PackedStringArray(bad.errors))
	for needle: String in [
		"functions flip_coins: the name is also an atomic effect",
		"'does_not_exist', which is neither a function nor an atomic effect",
		"is missing argument 'b'",
		"has extra argument 'c'",
		"argument 'a' has a value that is not a valid int",
		"refers to undefined '$nope'",
		"output 'x' reuses a parameter name",
		"is conditional and may not publish an output",
		"which has requirements, under when",
		"passes output '$h' to a function with requirements",
		"call cycle",
		"argument 'a' is pokemon, expected int",
		"only works while an attack resolves",
		"uses $self, which a Trainer does not have",
		"'Flamethrower': the card does not print it",
		"is a reference; card effects take literal values only",
		"missing argument 'amount'",
		"argument 'energy_type' is not a valid energy_type_or_any",
		"card_effects nope-1: no such card",
	]:
		expect(all_errors.contains(needle), "error: %s" % needle)
	expect("\n".join(PackedStringArray(bad.warnings)).contains("attacks 'Flamethrower' is bound to different functions"), "warning: same name, different functions")
	expect(bad.binding_for("base1-58", "attacks", "Thunder Jolt").is_empty(), "an invalid entry is never resolved")
	expect(not bad.binding_for("base1-24", "attacks", "Flamethrower").is_empty(), "a valid entry in the same file still resolves")

	print("== simulation")
	var decks := DataLoader.read_json(DataLoader.LEGACY_DECKS_PATH) as Dictionary
	var picker := RandomNumberGenerator.new()
	picker.seed = 99
	var wins := [0, 0]
	var warnings_seen := 0
	var evolutions_seen := 0
	for game in 300:
		var engine := MatchEngine.new()
		engine.effects = lib
		var pairing := ["effects_fire_lightning", "effects_colorless"] if game % 2 == 0 else ["evolution_fire", "evolution_fighting_grass"]
		engine.start(db.build_deck(decks[pairing[0]]), db.build_deck(decks[pairing[1]]), MatchRules.legacy(), Rng.new(game))
		var steps := 0
		while not engine.is_over() and steps < 5000:
			var actions := engine.legal_actions()
			var chosen := actions[picker.randi_range(0, actions.size() - 1)]
			for a in actions:
				if a["type"] == "attack" and picker.randf() < 0.7:
					chosen = a
					break
			engine.apply(chosen)
			steps += 1
			for p in engine.players:
				var n := p.deck.size() + p.hand.size() + p.discard.size() + p.prizes.size() + p.bench.size()
				if p.active != null:
					n += 1 + p.active.attached_energy.size() + p.active.evolved_from.size()
				for b in p.bench:
					n += b.attached_energy.size() + b.evolved_from.size()
				if n != 30:
					push_error("card count %d" % n)
					failures += 1
					quit(1)
					return
		if not engine.is_over():
			failures += 1
		wins[engine.winner] += 1
		for line in engine.events:
			if line.contains("[effect warning]"):
				warnings_seen += 1
			if line.contains(" evolves "):
				evolutions_seen += 1
	expect(true, "300 games finished with 30 cards per side; wins %s" % [wins])
	expect(warnings_seen == 0, "no runtime effect warnings (%d)" % warnings_seen)
	expect(evolutions_seen > 0, "the evolution decks evolved during the simulation (%d times)" % evolutions_seen)

	finish()
