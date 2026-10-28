## Headless checks for the round rules of Deltarune TCG (Design Document 4). Run from the
## project root:
##   godot --headless --path . --script res://tests/core/deltarune_rules_test.gd
## Exits with code 0 when every check passes.
extends TestCase

const SEEDS := 40

var library: EffectLibrary


func deck(counts: Dictionary) -> Array[CardData]:
	return db.build_deck({"cards": counts})


func test_deck() -> Array[CardData]:
	return deck({"jevil": 4, "tenna": 4, "guei": 4, "chaos_energy": 18})


func start_round(rules: MatchRules, seed: int) -> MatchEngine:
	var engine := MatchEngine.new()
	engine.effects = library
	engine.start(test_deck(), test_deck(), rules, Rng.new(seed))
	return engine


## A round on turn 2 with the given Darkners in the Battle Zone of the player to act and of
## their opponent, and nothing on either Field. seed changes the shuffles and coin flips.
func battle(attacker_id: String, attached: Array, defender_id: String, seed: int = 1) -> MatchEngine:
	var engine := start_round(MatchRules.deltarune(), seed)
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


func has_label(engine: MatchEngine, label: String) -> bool:
	for action in engine.legal_actions():
		if action["label"] == label:
			return true
	return false


## Applies the legal action with this label. False when there is none.
func play(engine: MatchEngine, label: String) -> bool:
	for action in engine.legal_actions():
		if action["label"] == label:
			engine.apply(action)
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
	library = DataLoader.load_effect_library(db, DataLoader.CARD_EFFECTS_PATH)
	var rules := MatchRules.deltarune()

	print("== setup")
	var setup := start_round(rules, 3)
	expect(setup.players[0].hand.size() == 10 and setup.players[1].hand.size() == 10, "both players draw 10")
	expect(setup.players[0].prizes.size() == 4 and setup.players[1].prizes.size() == 4, "4 Mercy Cards each")
	expect(setup.choice_option_shows(0) == null, "the coin call is about no card, so it shows none")
	
	var single := MatchEngine.new()
	single.effects = library
	single.start(deck({"jevil": 1, "chaos_energy": 29}), deck({"jevil": 1, "chaos_energy": 29}), rules, Rng.new(3))
	single.apply(single.legal_actions()[0])
	expect(single.choice_prompt() == "Choose your Battling Darkner" and single.legal_actions().size() == 1, "with one Basic Darkner the player is still asked, not skipped")

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

	print("== TP")
	var tp_round := start_round(rules, 2)
	expect(tp_round.players[0].tp == 0 and tp_round.players[1].tp == 0, "both players start the round at 0% TP")
	finish_setup(tp_round)
	var opener := tp_round.current_index
	tp_round.apply({"type": "end_turn", "label": "End turn"})
	expect(tp_round.players[opener].tp == 4, "the first player cannot attack on turn 1, so ending it is a pass: 100%")

	var tp_attack := battle("jevil", ["chaos_energy"], "guei")
	var tp_attacker := tp_attack.current_index
	expect(attack(tp_attack, "Slash"), "Slash is legal with 1 Chaos")
	expect(tp_attack.players[tp_attacker].tp == 1, "attacking recovers 25%")

	var tp_full := battle("jevil", ["chaos_energy"], "guei")
	var tp_full_player := tp_full.current_player()
	tp_full_player.tp = 4
	attack(tp_full, "Slash")
	expect(tp_full_player.tp == 4, "TP never goes above 100%")

	var tp_legacy := start_round(MatchRules.legacy(), 5)
	finish_setup(tp_legacy)
	tp_legacy.apply({"type": "end_turn", "label": "End turn"})
	expect(tp_legacy.players[0].tp == 0, "legacy rules have no TP")

	var flee_jevil := in_play("jevil", [])
	expect(tp_attack.retreat_cost(flee_jevil).size() == flee_jevil.card.retreat_cost, "the effective Flee cost is the printed one until continuous effects exist")

	print("== ACT cards")
	var items := battle("jevil", [], "guei")
	var item_player := items.current_player()
	item_player.hand.append_array(cards(["glowshard", "glowshard"]))
	expect(play(items, "Play Glowshard (Item)") and play(items, "Take Chaos Energy"), "an Item can be played")
	expect(play(items, "Play Glowshard (Item)") and play(items, "Take Chaos Energy"), "Items have no per-turn limit")
	expect(item_player.discard.size() == 2, "a played Item goes to the discard pile")

	var first_lightner := start_round(rules, 2)
	finish_setup(first_lightner)
	first_lightner.current_player().hand.append_array(cards(["kris", "kris"]))
	expect(not has_label(first_lightner, "Play Kris (Lightner)"), "the first player cannot play a Lightner on turn 1")
	first_lightner.apply({"type": "end_turn", "label": "End turn"})
	first_lightner.current_player().hand.append_array(cards(["kris", "kris"]))
	expect(play(first_lightner, "Play Kris (Lightner)"), "the second player can play a Lightner on turn 2")
	expect(not has_label(first_lightner, "Play Kris (Lightner)"), "one Lightner per turn")

	var areas := battle("jevil", [], "guei")
	var area_owner := areas.current_index
	areas.current_player().hand.append_array(cards(["cyber_city", "cyber_city", "mewers_live"]))
	expect(play(areas, "Play Cyber City (Area)"), "an Area can be played")
	expect(areas.stadium.name == "Cyber City" and areas.stadium_owner == area_owner, "the Area takes the shared slot")
	expect(not has_label(areas, "Play Mewers Live (Area)"), "one Area per turn")
	areas.apply({"type": "end_turn", "label": "End turn"})
	areas.current_player().hand.append_array(cards(["cyber_city", "mewers_live"]))
	expect(not has_label(areas, "Play Cyber City (Area)"), "an Area with the name of the one in play cannot be played")
	expect(play(areas, "Play Mewers Live (Area)"), "the opponent can replace the Area")
	expect(areas.stadium.name == "Mewers Live" and areas.players[area_owner].discard.back().name == "Cyber City", "the replaced Area goes to its owner's discard pile")

	var spells := battle("jevil", [], "guei")
	var caster := spells.current_player()
	caster.hand.append_array(cards(["rude_buster"]))
	spells.opponent_player().active.attached_energy.append_array(cards(["holy_energy"]))
	caster.tp = 0
	expect(not has_label(spells, "Cast Rude Buster (25% TP)"), "a Spell needs its TP")
	caster.tp = 1
	expect(play(spells, "Cast Rude Buster (25% TP)"), "a Spell is cast with enough TP")
	expect(caster.tp == 0 and caster.discard.back().name == "Rude Buster", "casting pays the TP and discards the Spell")

	print("== ACT card effects")
	var feather := battle("jevil", [], "guei")
	var feather_player := feather.current_player()
	feather_player.hand.append_array(cards(["petal_feather"]))
	expect(not has_label(feather, "Play Petal Feather (Item)"), "Petal Feather cannot be played with nothing on your Field")
	feather_player.bench.append(in_play("guei", []))
	feather_player.bench.append(in_play("tenna", []))
	expect(play(feather, "Play Petal Feather (Item)"), "Petal Feather can be played with Darkners on your Field")
	expect(feather.is_waiting_for_choice() and feather.choice_chooser() == feather.current_index, "the player chooses which Darkner to switch in")
	expect(feather.resolving_trainer.name == "Petal Feather" and not feather_player.hand.any(func(card: CardData) -> bool: return card.name == "Petal Feather") and feather_player.discard.is_empty(), "while it resolves, the card is beside the Battle Zone: in neither the hand nor the discard pile")
	expect(feather.choice_option_shows(1) == feather_player.bench[1], "each option shows the Darkner it would switch in")
	expect(play(feather, "Switch in Tenna (Field 2)"), "every Darkner on the Field is an option")
	expect(feather_player.active.card.name == "Tenna" and feather_player.bench[1].card.name == "Jevil", "the two Darkners trade places")
	expect(not feather_player.retreated_this_turn and feather_player.discard.back().name == "Petal Feather" and feather.resolving_trainer == null, "it is not a Flee, and the card is discarded once resolved")

	var gust := battle("jevil", [], "guei")
	var gust_player := gust.current_index
	gust.current_player().hand.append_array(cards(["susie"]))
	expect(not has_label(gust, "Play Susie (Lightner)"), "Susie cannot be played with nothing on the opponent's Field")
	gust.opponent_player().bench.append(in_play("jevil", []))
	gust.opponent_player().bench.append(in_play("tenna", []))
	expect(play(gust, "Play Susie (Lightner)"), "Susie can be played with Darkners on the opponent's Field")
	expect(gust.choice_chooser() == gust_player, "the player of Susie chooses, not the opponent")
	play(gust, "Switch in Tenna (Field 2)")
	expect(gust.opponent_player().active.card.name == "Tenna", "the chosen Darkner is the opponent's new Battling Darkner")

	var shuffle := battle("jevil", [], "guei")
	var shuffler := shuffle.current_player()
	shuffler.hand.append_array(cards(["kris", "chaos_energy", "chaos_energy"]))
	var cards_before := shuffler.hand.size() + shuffler.deck.size()
	expect(play(shuffle, "Play Kris (Lightner)"), "Kris can be played")
	expect(shuffler.hand.size() == 6, "Kris: the hand is shuffled into the deck and 6 cards are drawn")
	expect(shuffler.hand.size() + shuffler.deck.size() == cards_before - 1 and shuffler.discard.back().name == "Kris", "no card is lost; Kris itself is discarded")


	var search := battle("jevil", [], "guei")
	var searcher := search.current_player()
	searcher.hand.append_array(cards(["glowshard", "glowshard"]))
	var deck_before := searcher.deck.size()
	expect(play(search, "Play Glowshard (Item)"), "Glowshard can be played")
	var search_labels: Array = []
	for action in search.legal_actions():
		search_labels.append(action["label"])
	expect(search.choice_prompt() == "Search your deck for basic Energy" and search_labels == ["Take Chaos Energy", "Take nothing"], "Glowshard offers each basic Energy once, and finding nothing: %s" % [search_labels])
	var shown := search.choice_revealed()
	expect(shown.size() == searcher.deck.size() and shown[0] == searcher.deck.back() and shown.back() == searcher.deck[0], "the whole deck is shown during the search, in its real order, top card first")
	play(search, "Take Chaos Energy")
	expect(searcher.deck.size() == deck_before - 1 and searcher.hand.back().name == "Chaos Energy", "the Energy found goes into the hand")
	var darkners_only: Array[CardData] = []
	for card in searcher.deck:
		if card.is_pokemon():
			darkners_only.append(card)
	searcher.deck.assign(darkners_only)
	expect(play(search, "Play Glowshard (Item)") and has_label(search, "Take nothing") and search.legal_actions().size() == 1, "with no basic Energy in the deck, Glowshard still asks, so the deck can be looked at")
	expect(search.choice_revealed().size() == searcher.deck.size(), "the deck is shown even when nothing matches")
	expect(play(search, "Take nothing") and not search.is_waiting_for_choice(), "taking nothing finishes the search")
	searcher.deck.clear()
	searcher.hand.append_array(cards(["glowshard"]))
	expect(not has_label(search, "Play Glowshard (Item)"), "Glowshard cannot be played with an empty deck")

	var knife := battle("jevil", [], "guei")
	knife.current_player().deck.append_array(cards(["cyber_city"]))
	knife.current_player().hand.append_array(cards(["sharp_knife"]))
	play(knife, "Play Sharp Knife (Item)")
	expect(play(knife, "Take Cyber City") and knife.current_player().hand.back().name == "Cyber City", "Sharp Knife finds an Area")

	var revive := battle("jevil", [], "guei")
	var reviver := revive.current_player()
	reviver.tp = 4
	reviver.hand.append_array(cards(["revive_song"]))
	expect(not has_label(revive, "Cast Revive Song (25% TP)"), "Revive Song cannot be cast with nothing to recover")
	reviver.discard.append_array(cards(["kris", "chaos_energy", "guei"]))
	expect(play(revive, "Cast Revive Song (25% TP)"), "Revive Song can be cast with a basic Energy or a Darkner in the discard pile")
	var revive_labels: Array = []
	for action in revive.legal_actions():
		revive_labels.append(action["label"])
	expect(revive_labels == ["Take Chaos Energy", "Take Guei"], "the options are the basic Energy and the Darkner, not Kris: %s" % [revive_labels])
	play(revive, "Take Guei")
	expect(reviver.hand.back().name == "Guei" and not reviver.discard.any(func(card: CardData) -> bool: return card.name == "Guei"), "the chosen card leaves the discard pile for the hand")

	var buster_blocked := battle("jevil", [], "guei")
	buster_blocked.current_player().tp = 4
	buster_blocked.current_player().hand.append_array(cards(["rude_buster"]))
	expect(not has_label(buster_blocked, "Cast Rude Buster (25% TP)"), "Rude Buster cannot be cast when the opponent has no basic Energy in play")

	var heads_seen := false
	var tails_seen := false
	for seed in SEEDS:
		var buster := battle("jevil", [], "guei", seed)
		var buster_player := buster.current_index
		var target_side := buster.opponent_player()
		target_side.active.attached_energy.append_array(cards(["holy_energy", "holy_energy"]))
		target_side.bench.append(in_play("tenna", ["fun_energy"]))
		buster.current_player().tp = 4
		buster.current_player().hand.append_array(cards(["rude_buster"]))
		play(buster, "Cast Rude Buster (25% TP)")
		if buster.events.has("  Coin flip: heads"):
			var buster_labels: Array = []
			for action in buster.legal_actions():
				buster_labels.append(action["label"])
			if not heads_seen:
				expect(buster.choice_chooser() == buster_player and buster_labels == ["Discard Holy Energy from Guei (Battle Zone)", "Discard Fun Energy from Tenna (Field 1)"], "heads: the caster chooses among the opponent's Darkners, copies once: %s" % [buster_labels])
				play(buster, "Discard Fun Energy from Tenna (Field 1)")
				expect(target_side.bench[0].attached_energy.is_empty() and target_side.active.attached_energy.size() == 2, "the chosen Energy is discarded")
			heads_seen = true
		elif not tails_seen:
			tails_seen = true
			expect(not buster.is_waiting_for_choice() and target_side.active.attached_energy.size() == 2 and target_side.bench[0].attached_energy.size() == 1, "tails: nothing is discarded")
	expect(heads_seen and tails_seen, "both coin results were seen")

	print("== Darkner attack effects")
	var bomb := battle("jevil", ["chaos_energy", "chaos_energy"], "guei")
	var bomber := bomb.current_index
	var bombed := bomb.opponent_player()
	bombed.bench.append(in_play("tenna", []))
	bombed.bench.append(in_play("water_cooler", []))
	bombed.bench[1].damage = 50
	expect(attack(bomb, "Chaos Bomb"), "Chaos Bomb is legal with Chaos + 1 more")
	expect(bombed.active.damage == 0, "Chaos Bomb does no damage to the Battling Darkner")
	expect(bombed.bench.size() == 1 and bombed.bench[0].damage == 20, "20 damage to each Darkner on the Field, without Weakness or Resistance")
	expect(bomb.players[bomber].prizes.size() == 3 and not bomb.is_over(), "a Darkner knocked out on the Field gives a Mercy Card; the round goes on")
	expect(bombed.discard.any(func(card: CardData) -> bool: return card.name == "Water Cooler"), "the knocked out Darkner goes to the discard pile")

	var transit := battle("electro_dasher", ["chaos_energy"], "tenna")
	var transit_player := transit.current_player()
	var transit_target := transit.opponent_player().active
	transit_player.bench.append(in_play("jevil", []))
	attack(transit, "Violent Transit")
	expect(transit_target.damage == 10, "Violent Transit deals its 10 damage")
	expect(transit_player.active.card.name == "Jevil" and transit_player.bench[0].card.name == "Electro-Dasher", "then the attacker switches with the Darkner on the Field")

	var splash := battle("water_cooler", ["holy_energy", "holy_energy"], "jevil")
	var splasher := splash.current_player()
	splasher.bench.append(in_play("guei", []))
	splasher.bench[0].damage = 30
	splasher.tp = 1
	attack(splash, "Refreshing Splash")
	var splash_labels: Array = []
	for action in splash.legal_actions():
		splash_labels.append(action["label"])
	expect(splash.choice_chooser() == splash.current_index and splash_labels == ["Use 25% TP", "Don't use TP"], "Refreshing Splash: the player chooses whether to use 25%% TP: %s" % [splash_labels])
	play(splash, "Use 25% TP")
	expect(splasher.bench[0].damage == 10 and splasher.tp == 1, "using it heals 20 from each Darkner on the Field (TP: 25% - 25% + 25% at the end of the turn)")

	var dry := battle("water_cooler", ["holy_energy", "holy_energy"], "jevil")
	var dry_player := dry.current_player()
	var dry_target := dry.opponent_player().active
	dry_player.bench.append(in_play("guei", []))
	dry_player.bench[0].damage = 30
	dry_player.tp = 0
	attack(dry, "Refreshing Splash")
	expect(not dry.is_waiting_for_choice() and dry_player.bench[0].damage == 30 and dry_target.damage == 30, "without TP nothing is asked and it only deals its 30 damage")

	var melt := battle("guei", ["holy_energy", "holy_energy", "holy_energy", "holy_energy", "holy_energy"], "tenna")
	var melter := melt.current_player()
	var melt_target := melt.opponent_player().active
	var deck_size := melter.deck.size()
	attack(melt, "Flash Melt")
	expect(melt_target.damage == 120, "Flash Melt with 5 Energy units: 40 + 80 (%d)" % melt_target.damage)
	expect(melter.active.attached_energy.is_empty() and melter.deck.size() == deck_size + 5, "the attached Energy is shuffled into the deck")

	var small_melt := battle("guei", ["holy_energy", "holy_energy"], "tenna")
	var small_melter := small_melt.current_player()
	var small_target := small_melt.opponent_player().active
	attack(small_melt, "Flash Melt")
	expect(small_target.damage == 40 and small_melter.active.attached_energy.is_empty(), "with fewer than 5 units: 40 damage, and the Energy is still shuffled away")

	var overrun := battle("cuptain", ["chaos_energy"], "tenna")
	overrun.current_player().bench.append(in_play("cuptain", []))
	overrun.current_player().bench.append(in_play("cuptain", []))
	overrun.current_player().bench.append(in_play("jevil", []))
	var overrun_target := overrun.opponent_player().active
	attack(overrun, "Overrun")
	expect(overrun_target.damage == Damage.apply_modifiers(db.make("cuptain"), overrun_target.card, 30), "Overrun: 10 for each of the 3 Cuptain in play (%d)" % overrun_target.damage)

	print("== Abilities")
	var devotion := battle("cuptain", [], "tenna")
	var devotee := devotion.current_player()
	var devotion_turn := devotion.turn
	expect(not has_action(devotion, "use_power"), "Selfless Devotion cannot be used with nothing on the Field and no Energy in the discard pile")
	devotee.bench.append(in_play("jevil", []))
	expect(not has_action(devotion, "use_power"), "nor with a Darkner on the Field but no basic Energy in the discard pile")
	devotee.discard.append_array(cards(["chaos_energy"]))
	expect(play(devotion, "Use Selfless Devotion (Cuptain, Battle Zone)"), "it can be used with a basic Energy in the discard pile and a Darkner on the Field")
	expect(devotee.active.damage == 20 and devotee.bench[0].attached_energy.size() == 1 and devotee.discard.is_empty(), "2 damage counters on Cuptain, then the Energy goes to the Darkner on the Field")
	expect(not devotee.energy_attached_this_turn, "it does not use the once-per-turn attachment")

	devotee.bench.append(in_play("guei", []))
	devotee.discard.append_array(cards(["chaos_energy", "holy_energy"]))
	expect(play(devotion, "Use Selfless Devotion (Cuptain, Battle Zone)"), "it can be used again in the same turn")
	var energy_labels: Array = []
	for action in devotion.legal_actions():
		energy_labels.append(action["label"])
	expect(energy_labels == ["Attach Chaos Energy", "Attach Holy Energy"], "the player chooses the Energy: %s" % [energy_labels])
	play(devotion, "Attach Holy Energy")
	expect(play(devotion, "Attach Holy Energy to Guei (Field 2)"), "then the Darkner on the Field")
	var mercy_before := devotion.opponent_player().prizes.size()
	expect(devotee.active == null and devotion.choice_prompt() == "Choose a new Battling Darkner" and devotion.choice_chooser() == devotion.current_index, "40 damage knocks Cuptain out; its owner chooses the new Battling Darkner")
	expect(mercy_before == 3, "the opponent takes a Mercy Card for it")
	play(devotion, "Promote Guei (Field 2, 80/80 HP)")
	expect(devotion.turn == devotion_turn and devotion.current_player() == devotee and devotee.active.card.name == "Guei", "the turn goes on after the promotion")

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
	var three_chaos := cards(["chaos_energy", "chaos_energy", "chaos_energy"])
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
	expect(ko.turn == 3 and ko.current_index != taker, "the attack ends the turn")

	var promotion := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	promotion.opponent_player().bench.append(in_play("guei", []))
	promotion.opponent_player().bench.append(in_play("tenna", []))
	var promoter := 1 - promotion.current_index
	attack(promotion, "Showtime!")
	expect(promotion.is_waiting_for_choice() and promotion.choice_chooser() == promoter and promotion.turn == 2, "with two Darkners on the Field the loser chooses, and the turn waits")
	promotion.apply(promotion.legal_actions()[0])
	expect(promotion.turn == 3 and promotion.current_index == promoter, "the turn ends once the new Battling Darkner is chosen")

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

	print("== legal actions")
	# Random play with two kinds of deck: Darkners with ACT cards of every subtype, and one
	# Darkner in four copies, which fills the Field with identical Darkners.
	var picker := RandomNumberGenerator.new()
	var mixed := {"jevil": 4, "tenna": 4, "guei": 4, "cuptain": 2, "chaos_energy": 8, "petal_feather": 2, "kris": 2, "rude_buster": 2, "cyber_city": 1, "mewers_live": 1}	
	var same_darkner := {"jevil": 4, "chaos_energy": 26}
	var repeated := ""
	var rounds_finished := 0
	for seed in SEEDS:
		picker.seed = seed
		var counts: Dictionary = same_darkner if seed % 2 == 1 else mixed
		var game := MatchEngine.new()
		game.effects = library
		game.start(deck(counts), deck(counts), rules, Rng.new(seed))
		for _step in 400:
			if game.is_over():
				rounds_finished += 1
				break
			var actions := game.legal_actions()
			if repeated.is_empty() and not labels_distinct(actions):
				repeated = "seed %d, turn %d: %s" % [seed, game.turn, actions]
			game.apply(actions[picker.randi_range(0, actions.size() - 1)])
	expect(repeated.is_empty(), "no two legal actions share a label: %s" % repeated)
	expect(rounds_finished > 0, "random play finishes rounds (%d of %d)" % [rounds_finished, SEEDS])

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