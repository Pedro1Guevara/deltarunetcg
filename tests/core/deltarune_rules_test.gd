## Headless checks for the round rules of Deltarune TCG (Design Document 4). Run from the
## project root:
##   godot --headless --path . --script res://tests/deltarune_rules_test.gd
## Exits with code 0 when every check passes.
extends TestCase

const SEEDS := 40


func deck(counts: Dictionary) -> Array[CardData]:
	return db.build_deck({"cards": counts})


func test_deck() -> Array[CardData]:
	return deck({"jevil": 4, "tenna": 4, "guei": 4, "chaos_energy": 18})


func start_round(rules: MatchRules, seed: int) -> MatchEngine:
	var engine := MatchEngine.new()
	engine.start(test_deck(), test_deck(), rules, Rng.new(seed))
	return engine


## A round on turn 2 with the given Darkners in the Battle Zone of the player to act and of
## their opponent, and nothing on either Field.
func battle(attacker_id: String, attached: Array, defender_id: String) -> MatchEngine:
	var engine := start_round(MatchRules.deltarune(), 1)
	finish_setup(engine)
	engine.apply({"type": "end_turn", "label": "End turn"})
	var player := engine.current_player()
	var opponent := engine.opponent_player()
	player.bench.clear()
	opponent.bench.clear()
	player.active = in_play(attacker_id, attached)
	opponent.active = in_play(defender_id, [])
	return engine


func has_action(engine: MatchEngine, type: String) -> bool:
	for action in engine.legal_actions():
		if action["type"] == type:
			return true
	return false


func attack(engine: MatchEngine, name: String) -> bool:
	for action in engine.legal_actions():
		if action["type"] == "attack" and str(action["label"]).begins_with("Attack: %s " % name):
			engine.apply(action)
			return true
	return false


func _run() -> void:
	db = DataLoader.load_card_database()
	var rules := MatchRules.deltarune()

	print("== setup")
	var setup := start_round(rules, 3)
	expect(setup.players[0].hand.size() == 10 and setup.players[1].hand.size() == 10, "both players draw 10")
	expect(setup.players[0].prizes.size() == 4 and setup.players[1].prizes.size() == 4, "4 Mercy Cards each")

	print("== coin flip")
	var callers := {}
	var first_players := {}
	var asked_first := true
	for seed in SEEDS:
		var engine := start_round(rules, seed)
		var labels: Array = []
		for action in engine.legal_actions():
			labels.append(action["label"])
		if not (engine.choice_prompt().begins_with("Call the coin flip") and labels == ["Heads", "Tails"]):
			asked_first = false
		callers[engine.choice_chooser()] = true
		finish_setup(engine)
		first_players[engine.current_index] = true
	expect(asked_first, "the coin call is the first question, Heads or Tails")
	expect(callers.size() == 2, "either player may call the flip")
	expect(first_players.size() == 2, "either player may go first")
	var legacy_round := start_round(MatchRules.legacy(), 5)
	finish_setup(legacy_round)
	expect(legacy_round.current_index == 0, "legacy rules: no coin call, player 1 goes first")

	print("== first turn")
	var first := start_round(rules, 2)
	finish_setup(first)
	first.current_player().active = in_play("jevil", ["chaos_energy"])
	expect(first.turn == 1 and not has_action(first, "attack"), "the first player cannot attack on turn 1")
	first.apply({"type": "end_turn", "label": "End turn"})
	first.current_player().active = in_play("jevil", ["chaos_energy"])
	expect(first.turn == 2 and has_action(first, "attack"), "the second player can attack on turn 2")

	print("== field limit")
	var field := battle("jevil", [], "guei")
	var player := field.current_player()
	player.hand.append(db.make("tenna"))
	for _i in 3:
		player.bench.append(in_play("guei", []))
	expect(has_action(field, "bench"), "a Darkner can join a Field of 3")
	player.bench.append(in_play("guei", []))
	expect(not has_action(field, "bench"), "no Darkner can join a Field of 4")

	print("== weakness and resistance")
	var jevil := db.make("jevil")
	var tenna := db.make("tenna")
	var guei := db.make("guei")
	expect(Damage.apply_modifiers(tenna, jevil, 70) == 90, "Fun against Jevil: weakness +20 (70 -> 90)")
	expect(Damage.apply_modifiers(jevil, guei, 20) == 0, "Chaos against Guei: resistance -20 (20 -> 0)")
	expect(Damage.apply_modifiers(jevil, guei, 10) == 0, "resistance never goes below 0 (10 -> 0)")
	expect(Damage.apply_modifiers(jevil, tenna, 20) == 20, "no Weakness or Resistance: damage unchanged")

	print("== energy payment")
	var pool: Array[String] = ["Chaos", "Chaos", "Colorless", "Colorless"]
	expect(EnergyPayment.can_pay(pool, ["Chaos", "Colorless", "Colorless"]), "2 Chaos + 2 Colorless units pay Chaos + 2 Colorless")
	expect(not EnergyPayment.can_pay(pool, ["Chaos", "Chaos", "Chaos"]), "Colorless units never pay a typed requirement")
	expect(pool.size() == 4, "can_pay leaves the pool unchanged")
	var three_chaos := energies(["chaos_energy", "chaos_energy", "chaos_energy"])
	var flee_two := EnergyPayment.discard_options(three_chaos, 2)
	expect(flee_two.size() == 1 and str(flee_two[0]["label"]) == "Discard Chaos Energy + Chaos Energy", "copies are one option, with no card to spare")
	expect(EnergyPayment.discard_options(three_chaos, 0).is_empty(), "nothing owed: no options")
	
	print("== knockouts and Mercy Cards")
	var ko := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	ko.opponent_player().bench.append(in_play("guei", []))
	var taker := ko.current_index
	expect(attack(ko, "Showtime!"), "Showtime! is legal with 5 Fun")
	expect(ko.players[taker].prizes.size() == 3, "a knockout takes 1 Mercy Card (4 -> 3)")
	expect(not ko.is_over(), "the round goes on while the loser has a Darkner on the Field")

	var double_rules := MatchRules.deltarune()
	double_rules.prizes_per_knockout = 2
	var double := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	double.rules = double_rules
	double.opponent_player().bench.append(in_play("guei", []))
	var double_taker := double.current_index
	attack(double, "Showtime!")
	expect(double.players[double_taker].prizes.size() == 2, "prizes_per_knockout 2 takes 2 Mercy Cards")

	print("== how a round ends")
	var last := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	last.opponent_player().bench.append(in_play("guei", []))
	var last_taker := last.current_index
	while last.players[last_taker].prizes.size() > 1:
		last.players[last_taker].prizes.pop_back()
	attack(last, "Showtime!")
	expect(last.winner == last_taker, "taking the last Mercy Card wins the round")

	var empty_field := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	var empty_taker := empty_field.current_index
	attack(empty_field, "Showtime!")
	expect(empty_field.winner == empty_taker, "an opponent with nothing on the Field to promote loses")

	var deck_out := battle("jevil", [], "guei")
	var drawer := 1 - deck_out.current_index
	deck_out.players[drawer].deck.clear()
	deck_out.apply({"type": "end_turn", "label": "End turn"})
	expect(deck_out.winner == 1 - drawer, "a player who cannot draw loses the round")

	var legacy_out := start_round(MatchRules.legacy(), 4)
	finish_setup(legacy_out)
	var legacy_drawer := 1 - legacy_out.current_index
	var legacy_prizes := legacy_out.players[1 - legacy_drawer].prizes.size()
	legacy_out.players[legacy_drawer].deck.clear()
	legacy_out.apply({"type": "end_turn", "label": "End turn"})
	expect(not legacy_out.is_over() and legacy_out.players[1 - legacy_drawer].prizes.size() == legacy_prizes - 1, "legacy rules: deck-out costs a prize instead")

	print("== deck validation")
	var legal := deck({"jevil": 4, "tenna": 4, "guei": 4, "kris": 4, "chaos_energy": 34})
	expect(DeckValidator.validate(legal, rules).is_empty(), "50 cards, 4 copies at most, 34 Basic Energy: legal")
	var short := deck({"jevil": 4, "chaos_energy": 26})
	expect(DeckValidator.validate(short, rules) == ["has 30 cards; the rules require 50"], "a 30-card deck is reported")
	var copies := deck({"jevil": 5, "chaos_energy": 45})
	expect(DeckValidator.validate(copies, rules) == ["has 5 copies of Jevil; at most 4 are allowed"], "a fifth copy is reported")
	var no_basic := deck({"kris": 4, "chaos_energy": 46})
	expect(DeckValidator.validate(no_basic, rules) == ["has no Basic Darkner"], "a deck without Basic Darkners is reported")
	expect(DeckValidator.validate(short, MatchRules.legacy()).is_empty(), "legacy rules: no size or copy limit")

	finish()