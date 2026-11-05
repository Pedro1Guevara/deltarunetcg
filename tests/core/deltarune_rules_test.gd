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


## Picks the card option with this label, then confirms the choice.
func pick(engine: MatchEngine, label: String) -> bool:
	return play(engine, label) and play(engine, "Confirm")


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
	expect(tp_round.players[0].tp == 4 and tp_round.players[1].tp == 4, "both players start the round at 100% TP")

	var tp_attack := battle("jevil", ["chaos_energy"], "guei")
	var tp_attacker := tp_attack.current_player()
	var tp_waiting := tp_attack.opponent_player()
	tp_attacker.tp = 1
	expect(attack(tp_attack, "Slash"), "Slash is legal with 1 Chaos")
	expect(tp_attacker.tp == 1, "attacking recovers nothing at the end of the turn")
	expect(tp_waiting.tp == 4, "TP never goes above 100%: a player at 100% stays there at the start of their turn")
	tp_attack.apply({"type": "end_turn", "label": "End turn"})
	expect(tp_attacker.tp == 2, "a player gains 25% at the start of their turn")
	tp_attacker.tp = 1
	tp_attack.apply({"type": "end_turn", "label": "End turn"})
	expect(tp_attacker.tp == 4, "passing refills TP to 100%")

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
	expect(play(items, "Play Glowshard (Item)") and pick(items, "Take Chaos Energy"), "an Item can be played")
	expect(play(items, "Play Glowshard (Item)") and pick(items, "Take Chaos Energy"), "Items have no per-turn limit")
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
	search_labels.clear()
	for action in search.legal_actions():
		search_labels.append(action["label"])
	expect(search_labels == ["Undo: Take Chaos Energy", "Confirm"] and searcher.deck.size() == deck_before, "a single pick also waits for confirmation and can be undone: %s" % [search_labels])
	play(search, "Confirm")
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
	expect(pick(knife, "Take Cyber City") and knife.current_player().hand.back().name == "Cyber City", "Sharp Knife finds an Area")

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
	pick(revive, "Take Guei")
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
				pick(buster, "Discard Fun Energy from Tenna (Field 1)")
				expect(target_side.bench[0].attached_energy.is_empty() and target_side.active.attached_energy.size() == 2, "the chosen Energy is discarded")
			heads_seen = true
		elif not tails_seen:
			tails_seen = true
			expect(not buster.is_waiting_for_choice() and target_side.active.attached_energy.size() == 2 and target_side.bench[0].attached_energy.size() == 1, "tails: nothing is discarded")
	expect(heads_seen and tails_seen, "both coin results were seen")

	var mint := battle("jevil", [], "guei")
	var minter := mint.current_player()
	minter.hand.assign(cards(["revive_mint"]))
	minter.discard.assign(cards(["chaos_energy"]))
	expect(not has_label(mint, "Play Revive Mint (Item)"), "Revive Mint cannot be played without a Darkner in the discard pile")
	minter.discard.append_array(cards(["guei"]))
	expect(play(mint, "Play Revive Mint (Item)") and minter.hand.back().name == "Guei" and minter.discard.size() == 2, "Revive Mint puts the only Darkner into the hand without asking; the Energy stays")

	var nap := battle("jevil", [], "guei")
	var napper := nap.current_player()
	napper.hand.assign(cards(["napstablook"]))
	napper.deck.assign(cards(["chaos_energy", "kris", "guei"]))
	expect(play(nap, "Play Napstablook (Lightner)"), "Napstablook can be played")
	var nap_labels: Array = []
	for action in nap.legal_actions():
		nap_labels.append(action["label"])
	expect(nap.choice_prompt() == "Search your deck for any card to discard (0/2 chosen)" and nap_labels == ["Discard Chaos Energy", "Discard Kris", "Discard Guei", "Discard nothing"], "Napstablook offers every card in the deck: %s" % [nap_labels])
	play(nap, "Discard Kris")
	nap_labels.clear()
	for action in nap.legal_actions():
		nap_labels.append(action["label"])
	expect(nap.choice_prompt().ends_with("(1/2 chosen)") and nap_labels == ["Discard Chaos Energy", "Undo: Discard Kris", "Discard Guei", "Confirm"], "a picked card can be undone, and the player may confirm fewer: %s" % [nap_labels])
	expect(napper.deck.size() == 3, "nothing leaves the deck before confirming")
	play(nap, "Undo: Discard Kris")
	play(nap, "Discard Guei")
	play(nap, "Discard Kris")
	nap_labels.clear()
	for action in nap.legal_actions():
		nap_labels.append(action["label"])
	expect(nap_labels == ["Undo: Discard Kris", "Undo: Discard Guei", "Confirm"], "with 2 picked, only undoing or confirming is left: %s" % [nap_labels])
	play(nap, "Confirm")
	expect(not nap.is_waiting_for_choice() and napper.deck.size() == 1, "up to 2 cards leave the deck")
	expect(napper.discard.map(func(card: CardData) -> String: return card.name) == ["Guei", "Kris", "Napstablook"], "they go to the discard pile in the order picked, then Napstablook")

	var sans := battle("jevil", [], "guei")
	var sanser := sans.current_player()
	sanser.hand.assign(cards(["sans", "chaos_energy", "guei"]))
	sanser.deck.assign(cards(["glowshard", "chaos_energy", "rude_buster", "kris"]))
	expect(play(sans, "Play Sans (Lightner)"), "Sans can be played")
	expect(sanser.hand.is_empty() and sanser.discard.size() == 2, "Sans discards the rest of the hand first")
	var sans_labels: Array = []
	for action in sans.legal_actions():
		sans_labels.append(action["label"])
	expect(sans.choice_prompt() == "Search your deck for ACT card (0/2 chosen)" and sans_labels == ["Take Glowshard", "Take Rude Buster", "Take Kris", "Take nothing"], "then searches for ACT cards: %s" % [sans_labels])
	play(sans, "Take Kris")
	play(sans, "Take Glowshard")
	play(sans, "Confirm")
	expect(sanser.hand.map(func(card: CardData) -> String: return card.name) == ["Kris", "Glowshard"] and sanser.deck.size() == 2, "up to 2 ACT cards go into the hand")
	var sans_empty := battle("jevil", [], "guei")
	sans_empty.current_player().hand.assign(cards(["sans"]))
	expect(has_label(sans_empty, "Play Sans (Lightner)"), "Sans can be played with nothing else in hand")

	var berdly := battle("jevil", [], "guei")
	var berdly_player := berdly.current_player()
	var berdly_opponent := berdly.opponent_player()
	berdly_player.hand.assign(cards(["berdly", "kris", "glowshard"]))
	berdly_opponent.hand.assign(cards(["guei"]))
	var top_card: CardData = berdly_player.deck.back()
	expect(play(berdly, "Play Berdly (Lightner)"), "Berdly can be played")
	expect(berdly_player.hand.size() == 4 and berdly_opponent.hand.size() == 4, "each player draws 4")
	var bottom := [berdly_player.deck[0].name, berdly_player.deck[1].name]
	bottom.sort()
	expect(bottom == ["Glowshard", "Kris"] and berdly_opponent.deck[0].name == "Guei", "each hand goes to the bottom of its owner's deck")
	expect(berdly_player.hand.has(top_card), "the new cards come from the top")

	var bagel := battle("jevil", [], "guei")
	var bagger := bagel.current_player()
	bagger.hand.assign(cards(["cd_bagel"]))
	bagger.deck.assign(cards(["chaos_energy", "chaos_energy", "holy_energy", "kris"]))
	expect(not has_label(bagel, "Play CD Bagel (Item)"), "CD Bagel cannot be played without another card in hand to discard")
	bagger.hand.append_array(cards(["cd_bagel"]))
	expect(has_label(bagel, "Play CD Bagel (Item)"), "another copy of CD Bagel counts as another card")
	bagger.hand.append_array(cards(["guei"]))
	play(bagel, "Play CD Bagel (Item)")
	var bagel_labels: Array = []
	for action in bagel.legal_actions():
		bagel_labels.append(action["label"])
	expect(bagel.choice_prompt() == "Choose a card to discard from your hand" and bagel_labels == ["Discard CD Bagel", "Discard Guei"], "the player chooses the card to discard: %s" % [bagel_labels])
	pick(bagel, "Discard Guei")
	bagel_labels.clear()
	for action in bagel.legal_actions():
		bagel_labels.append(action["label"])
	expect(bagel.choice_prompt() == "Search your deck for basic Energy (0/2 chosen)" and bagel_labels == ["Take Chaos Energy #1", "Take Chaos Energy #2", "Take Holy Energy", "Take nothing"], "then searches the deck; when picking several, every copy is its own option: %s" % [bagel_labels])
	play(bagel, "Take Holy Energy")
	play(bagel, "Take Chaos Energy #2")
	play(bagel, "Confirm")
	expect(bagger.hand.map(func(card: CardData) -> String: return card.name) == ["CD Bagel", "Holy Energy", "Chaos Energy"], "up to 2 basic Energy go into the hand")
	expect(bagger.discard.map(func(card: CardData) -> String: return card.name) == ["Guei", "CD Bagel"] and bagger.deck.size() == 2, "the discarded card, then CD Bagel, go to the discard pile")
	bagger.deck.clear()
	expect(not has_label(bagel, "Play CD Bagel (Item)"), "CD Bagel cannot be played with an empty deck")

	var manual := battle("jevil", [], "guei")
	var recruiter := manual.current_player()
	recruiter.hand.assign(cards(["recruit_manual", "chaos_energy"]))
	recruiter.deck.assign(cards(["guei", "kris"]))
	expect(not has_label(manual, "Play Recruit Manual (Item)"), "Recruit Manual needs 2 other cards in hand")
	recruiter.hand.append_array(cards(["chaos_energy"]))
	expect(play(manual, "Play Recruit Manual (Item)"), "Recruit Manual can be played with 2 other cards")
	expect(manual.choice_prompt() == "Search your deck for Darkner" and recruiter.discard.size() == 2 and recruiter.hand.is_empty(), "two copies of the same card are discarded without asking")
	pick(manual, "Take Guei")
	expect(recruiter.hand.size() == 1 and recruiter.hand[0].name == "Guei", "the Darkner goes into the hand")
	var choosy := battle("jevil", [], "guei")
	var chooser := choosy.current_player()
	chooser.hand.assign(cards(["recruit_manual", "holy_energy", "holy_energy", "sans"]))
	play(choosy, "Play Recruit Manual (Item)")
	var choosy_labels: Array = []
	for action in choosy.legal_actions():
		choosy_labels.append(action["label"])
	expect(choosy.choice_prompt() == "Choose 2 cards to discard from your hand (0/2 chosen)" and choosy_labels == ["Discard Holy Energy #1", "Discard Holy Energy #2", "Discard Sans"], "discarding 2: every card is its own option and there is nothing to confirm yet: %s" % [choosy_labels])
	play(choosy, "Discard Holy Energy #1")
	play(choosy, "Discard Holy Energy #2")
	choosy_labels.clear()
	for action in choosy.legal_actions():
		choosy_labels.append(action["label"])
	expect(choosy_labels == ["Undo: Discard Holy Energy #1", "Undo: Discard Holy Energy #2", "Confirm"], "with 2 picked: %s" % [choosy_labels])
	play(choosy, "Undo: Discard Holy Energy #2")
	play(choosy, "Discard Sans")
	expect(chooser.hand.size() == 3 and chooser.discard.is_empty(), "nothing is discarded before confirming")
	play(choosy, "Confirm")
	expect(chooser.discard.map(func(card: CardData) -> String: return card.name) == ["Holy Energy", "Sans"] and choosy.choice_prompt() == "Search your deck for Darkner", "confirming discards the 2 picked cards, then the search starts")

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
	expect(transit.events.any(func(line: String) -> bool: return line.begins_with("  10 damage to Tenna")), "Violent Transit deals its 10 damage")
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
	expect(splasher.bench[0].damage == 10 and splasher.tp == 0, "using it heals 20 from each Darkner on the Field and pays 25% TP")

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

	var recruit := battle("old_man", ["creative_energy"], "tenna")
	var recruiter_side := recruit.current_player()
	recruiter_side.deck.assign(cards(["guei", "kris", "jevil"]))
	expect(attack(recruit, "Recruit"), "Recruit is legal with 1 Energy")
	var recruit_labels: Array = []
	for action in recruit.legal_actions():
		recruit_labels.append(action["label"])
	expect(recruit.choice_prompt() == "Search your deck for Darkner" and recruit_labels == ["Take Guei", "Take Jevil", "Take nothing"], "Recruit searches the deck for a Darkner: %s" % [recruit_labels])
	pick(recruit, "Take Jevil")
	expect(recruiter_side.hand.back().name == "Jevil" and recruit.opponent_player().active.damage == 0, "the Darkner goes into the hand; an attack with no printed damage deals none")
	expect(not recruit.events.any(func(line: String) -> bool: return line.begins_with("  0 damage")), "and logs no damage")
	expect(recruit.current_player() != recruiter_side, "then the turn ends")

	var training := battle("dummy", ["fighting_energy"], "tenna")
	var trainer_side := training.current_player()
	trainer_side.bench.append(in_play("guei", []))
	trainer_side.bench.append(in_play("cuptain", []))
	trainer_side.hand.assign(cards(["holy_energy", "fighting_energy", "kris"]))
	trainer_side.energy_attached_this_turn = true
	expect(attack(training, "Helpful Training"), "Helpful Training is legal even after attaching Energy this turn")
	var training_labels: Array = []
	for action in training.legal_actions():
		training_labels.append(action["label"])
	expect(training.choice_prompt() == "Choose a card from your hand to attach" and training_labels == ["Attach Holy Energy", "Attach Fighting Energy"], "the player chooses a basic Energy from their hand: %s" % [training_labels])
	pick(training, "Attach Holy Energy")
	expect(play(training, "Attach Holy Energy to Cuptain (Field 2)"), "then a Darkner on the Field")
	expect(trainer_side.bench[1].attached_energy.size() == 1 and trainer_side.active.attached_energy.size() == 1 and trainer_side.hand.size() == 2, "the Energy goes from the hand to that Darkner")
	var lonely := battle("dummy", ["fighting_energy"], "tenna")
	var lonely_player := lonely.current_player()
	lonely_player.hand.assign(cards(["holy_energy"]))
	expect(attack(lonely, "Helpful Training") and not lonely.is_waiting_for_choice() and lonely_player.hand.size() == 1, "with nothing on the Field the attack can still be used, and does nothing")

	var lunge_heads := false
	var lunge_tails := false
	for seed in SEEDS:
		var lunge := battle("koody", ["fun_energy"], "tenna", seed)
		var lunge_target := lunge.opponent_player().active
		var start := lunge.events.size()
		attack(lunge, "Lunge")
		var heads := lunge.events.slice(start).has("  Coin flip: heads")
		var dealt := lunge_target.damage
		if heads and not lunge_heads:
			lunge_heads = true
			expect(dealt == 30, "Lunge: heads deals 30 (%d)" % dealt)
		elif not heads and not lunge_tails:
			lunge_tails = true
			expect(dealt == 0, "Lunge: tails does nothing (%d)" % dealt)
	expect(lunge_heads and lunge_tails, "both Lunge results were seen")

	var legacy := battle("hammer_of_justice", ["creative_energy", "creative_energy", "creative_energy"], "tenna")
	var legacy_target := legacy.opponent_player().active
	attack(legacy, "Colourful Legacy")
	expect(legacy_target.damage == 10, "Colourful Legacy with nothing on the Field deals 10 (%d)" % legacy_target.damage)
	var colourful := battle("hammer_of_justice", ["creative_energy", "creative_energy", "creative_energy"], "tenna")
	var colourful_target := colourful.opponent_player().active
	colourful.current_player().bench.append(in_play("jevil", []))
	colourful.current_player().bench.append(in_play("guei", []))
	colourful.current_player().bench.append(in_play("water_cooler", []))
	attack(colourful, "Colourful Legacy")
	expect(colourful_target.damage == 50, "Chaos, Holy and Holy on the Field are 2 different types: 10 + 40 (%d)" % colourful_target.damage)

	var selfie := battle("shuttah", ["chaos_energy", "chaos_energy"], "tenna")
	var selfie_player := selfie.current_player()
	var selfie_index := selfie.current_index
	var selfie_turn := selfie.turn
	selfie.opponent_player().bench.append(in_play("guei", []))
	expect(attack(selfie, "Quick Selfie"), "Quick Selfie is legal")
	var selfie_labels: Array = []
	for action in selfie.legal_actions():
		selfie_labels.append(action["label"])
	expect(selfie.choice_prompt() == "Choose one of your opponent's Darkners" and selfie_labels == ["Choose Tenna (Battle Zone, 100/100 HP)", "Choose Guei (Field 1, 80/80 HP)"], "the attacker chooses any of the opponent's Darkners: %s" % [selfie_labels])
	expect(selfie_player.active.attached_energy.is_empty() and selfie_player.discard.size() == 2, "Shuttah's Energy is discarded first")
	play(selfie, "Choose Guei (Field 1, 80/80 HP)")
	expect(selfie.players[1 - selfie_index].bench[0].damage == 20, "2 damage counters on the chosen Darkner, without Weakness or Resistance")
	expect(selfie.current_index != selfie_index and selfie.turn == selfie_turn + 1, "without a knockout the turn passes as usual")

	var again := battle("shuttah", ["chaos_energy", "chaos_energy"], "tenna")
	var again_index := again.current_index
	var again_turn := again.turn
	var again_opponent := again.opponent_player()
	again_opponent.bench.append(in_play("guei", []))
	again_opponent.bench[0].damage = 60
	attack(again, "Quick Selfie")
	play(again, "Choose Guei (Field 1, 20/80 HP)")
	expect(again.players[again_index].prizes.size() == 3 and again_opponent.bench.is_empty(), "the 2 damage counters knock out Guei on the Field: a Mercy Card")
	expect(again.current_index == again_index and again.turn == again_turn + 1 and again.events.has("Player %d takes another turn" % (again_index + 1)), "a knockout by Quick Selfie gives the attacker another turn")
	var again_player := again.current_player()
	again_player.active.attached_energy.append_array(cards(["chaos_energy", "chaos_energy"]))
	expect(not has_action(again, "attack"), "Quick Selfie cannot be used in the turn after it was used")
	again.apply({"type": "end_turn", "label": "End turn"})
	again.apply({"type": "end_turn", "label": "End turn"})
	expect(again.current_player() == again_player and has_action(again, "attack"), "after a turn without it, Quick Selfie can be used again")

	var zone := battle("shuttah", ["chaos_energy", "chaos_energy"], "tenna")
	var zone_index := zone.current_index
	var zone_opponent := zone.opponent_player()
	zone_opponent.bench.append(in_play("guei", []))
	zone_opponent.active.damage = 80
	attack(zone, "Quick Selfie")
	play(zone, "Choose Tenna (Battle Zone, 20/100 HP)")
	expect(zone_opponent.active.card.name == "Guei" and zone.current_index == zone_index, "a knockout in the Battle Zone: the opponent promotes, then the attacker takes another turn")

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
	pick(devotion, "Attach Holy Energy")
	expect(play(devotion, "Attach Holy Energy to Guei (Field 2)"), "then the Darkner on the Field")
	var mercy_before := devotion.opponent_player().prizes.size()
	expect(devotee.active == null and devotion.choice_prompt() == "Choose a new Battling Darkner" and devotion.choice_chooser() == devotion.current_index, "40 damage knocks Cuptain out; its owner chooses the new Battling Darkner")
	expect(mercy_before == 3, "the opponent takes a Mercy Card for it")
	play(devotion, "Promote Guei (Field 2, 80/80 HP)")
	expect(devotion.turn == devotion_turn and devotion.current_player() == devotee and devotee.active.card.name == "Guei", "the turn goes on after the promotion")

	var worm := battle("koody", [], "tenna")
	var wormer := worm.current_player()
	wormer.hand.assign(cards(["kris"]))
	expect(not has_label(worm, "Use Way of the Worm (Koody, Battle Zone)"), "Way of the Worm needs a basic Energy in hand")
	wormer.hand.append_array(cards(["fun_energy", "holy_energy"]))
	var worm_deck := wormer.deck.size()
	expect(play(worm, "Use Way of the Worm (Koody, Battle Zone)"), "it can be used with a basic Energy in hand")
	var worm_labels: Array = []
	for action in worm.legal_actions():
		worm_labels.append(action["label"])
	expect(worm.choice_prompt() == "Choose a basic Energy to discard from your hand" and worm_labels == ["Discard Fun Energy", "Discard Holy Energy"], "the player chooses a basic Energy, never another card: %s" % [worm_labels])
	pick(worm, "Discard Holy Energy")
	expect(wormer.discard.back().name == "Holy Energy" and wormer.hand.size() == 3 and wormer.deck.size() == worm_deck - 1, "the Energy is discarded, then 1 card is drawn")
	wormer.bench.append(in_play("koody", []))
	wormer.hand.append_array(cards(["fun_energy"]))
	expect(not has_action(worm, "use_power"), "only 1 Way of the Worm per turn, counting every Koody in play")
	worm.apply({"type": "end_turn", "label": "End turn"})
	worm.apply({"type": "end_turn", "label": "End turn"})
	wormer.hand.append_array(cards(["fun_energy"]))
	expect(worm.current_player() == wormer and has_label(worm, "Use Way of the Worm (Koody, Field 1)"), "the limit resets on the player's next turn")

	var lure := battle("jevil", [], "tenna")
	var lurer := lure.current_player()
	lurer.hand.assign(cards(["balthizard", "balthizard"]))
	lurer.deck.assign(cards(["balthizard", "miss_mizzle", "guei", "kris"]))
	expect(play(lure, "Put Balthizard on the Field"), "Balthizard is played from the hand")
	var lure_labels: Array = []
	for action in lure.legal_actions():
		lure_labels.append(action["label"])
	expect(lure.choice_prompt() == "Use Luring Incense?" and lure_labels == ["Use Luring Incense (Balthizard)", "Don't use Luring Incense"], "its owner may use Luring Incense: %s" % [lure_labels])
	play(lure, "Use Luring Incense (Balthizard)")
	lure_labels.clear()
	for action in lure.legal_actions():
		lure_labels.append(action["label"])
	expect(lure.choice_prompt() == "Search your deck for non-Evolution Darkner to put onto your Field (not Balthizard)" and lure_labels == ["Put Guei", "Put nothing"], "the search offers non-Evolution Darkners other than Balthizard: %s" % [lure_labels])
	pick(lure, "Put Guei")
	expect(lurer.bench.size() == 2 and lurer.bench[1].card.name == "Guei" and lurer.deck.size() == 3 and not lure.is_waiting_for_choice(), "Guei goes from the deck onto the Field")
	play(lure, "Put Balthizard on the Field")
	expect(not lure.is_waiting_for_choice() and lurer.bench.size() == 3, "only 1 Luring Incense per turn: the second Balthizard offers nothing")
	var declined := battle("jevil", [], "tenna")
	declined.current_player().hand.assign(cards(["balthizard"]))
	var declined_deck := declined.current_player().deck.size()
	play(declined, "Put Balthizard on the Field")
	play(declined, "Don't use Luring Incense")
	expect(not declined.is_waiting_for_choice() and declined.current_player().deck.size() == declined_deck, "declining it does nothing")
	var crowded := battle("jevil", [], "tenna")
	crowded.current_player().bench.append_array([in_play("guei", []), in_play("guei", []), in_play("guei", [])])
	crowded.current_player().hand.assign(cards(["balthizard"]))
	play(crowded, "Put Balthizard on the Field")
	expect(not crowded.is_waiting_for_choice(), "with the Field full, Luring Incense is not offered")

	var liberty := battle("jevil", [], "tenna")
	var liberal := liberty.current_player()
	liberal.hand.assign(cards(["old_man"]))
	play(liberty, "Put Old Man on the Field")
	expect(not liberty.is_waiting_for_choice(), "Creative Liberties cannot be used on the player's first turn")
	liberty.apply({"type": "end_turn", "label": "End turn"})
	liberty.apply({"type": "end_turn", "label": "End turn"})
	var liberty_opponent := liberty.opponent_player()
	liberal.hand.assign(cards(["old_man", "kris", "glowshard", "chaos_energy"]))
	liberty_opponent.hand.assign(cards(["guei"]))
	var liberal_total := liberal.hand.size() + liberal.deck.size()
	play(liberty, "Put Old Man on the Field")
	expect(play(liberty, "Use Creative Liberties (Old Man)"), "on a later turn its owner may use it")
	expect(liberal.hand.size() == 3 and liberty_opponent.hand.size() == 3, "both players shuffle their hands into their decks and draw 3")
	expect(liberal.hand.size() + liberal.deck.size() == liberal_total - 1, "no card is lost (Old Man is on the Field)")

	print("== triggered Abilities")
	var stampede_heads := false
	var stampede_tails := false
	for seed in SEEDS:
		var stampede := battle("jevil", ["chaos_energy", "chaos_energy"], "tenna", seed)
		stampede.current_player().bench.append(in_play("electro_dasher", []))
		var trampled := stampede.opponent_player()
		trampled.bench.append(in_play("guei", []))
		trampled.bench.append(in_play("water_cooler", []))
		var log_start := stampede.events.size()
		attack(stampede, "Chaos Bomb")
		var flips := stampede.events.slice(log_start).filter(func(line: String) -> bool: return line.contains("Coin flip"))
		if flips.size() == 1 and flips[0].contains("heads") and not stampede_heads:
			stampede_heads = true
			expect(trampled.bench[0].damage == 30 and trampled.bench[1].damage == 30 and trampled.active.damage == 0, "heads: 1 damage counter on each Darkner the attack damaged, from the Field, and none on the undamaged one")
		elif flips.size() == 1 and flips[0].contains("tails") and not stampede_tails:
			stampede_tails = true
			expect(trampled.bench[0].damage == 20 and trampled.bench[1].damage == 20, "tails: no damage counters")
	expect(stampede_heads and stampede_tails, "Relentless Stampede flips once per attack; both results were seen")

	var herd := battle("jevil", ["chaos_energy"], "tenna")
	herd.current_player().bench.append(in_play("electro_dasher", []))
	herd.current_player().bench.append(in_play("electro_dasher", []))
	var herd_start := herd.events.size()
	attack(herd, "Slash")
	var herd_flips := herd.events.slice(herd_start).filter(func(line: String) -> bool: return line.contains("Coin flip"))
	expect(herd_flips.size() == 2, "two Electro-Dasher in play flip a coin each (%d)" % herd_flips.size())

	var blocked := battle("jevil", ["chaos_energy"], "guei")
	blocked.current_player().bench.append(in_play("electro_dasher", []))
	var blocked_start := blocked.events.size()
	attack(blocked, "Slash")
	var blocked_flips := blocked.events.slice(blocked_start).filter(func(line: String) -> bool: return line.contains("Coin flip"))
	expect(blocked_flips.is_empty(), "an attack that deals no damage (Guei resists Chaos) sets off nothing")

	var trigger_heads := false
	var trigger_tails := false
	for seed in SEEDS:
		var trigger_ko := battle("electro_dasher", ["chaos_energy"], "tenna", seed)
		trigger_ko.opponent_player().bench.append(in_play("guei", []))
		trigger_ko.opponent_player().active.damage = 80
		var trigger_taker := trigger_ko.current_index
		var trigger_start := trigger_ko.events.size()
		attack(trigger_ko, "Violent Transit")
		var heads := trigger_ko.events.slice(trigger_start).has("  Coin flip: heads")
		var mercy := trigger_ko.players[trigger_taker].prizes.size()
		if heads and not trigger_heads:
			trigger_heads = true
			expect(mercy == 3 and trigger_ko.players[1 - trigger_taker].active.card.name == "Guei", "heads: the damage counter knocks out Tenna (90 + 10) before knockouts are checked; Guei is promoted")
		elif not heads and not trigger_tails:
			trigger_tails = true
			expect(mercy == 4 and trigger_ko.players[1 - trigger_taker].active.card.name == "Tenna", "tails: Tenna survives at 90 damage and the turn passes")
	expect(trigger_heads and trigger_tails, "both results were seen")

	print("== BREAK evolution")
	var growth := battle("jevil", [], "tenna")
	var grower := growth.current_player()
	grower.bench.append(in_play("old_man", ["creative_energy"]))
	grower.bench[0].damage = 30
	grower.hand.assign(cards(["hammer_of_justice", "old_man"]))
	expect(not has_label(growth, "Evolve Old Man into Hammer of Justice (Field 1)"), "no evolving during the player's first turn")
	growth.apply({"type": "end_turn", "label": "End turn"})
	growth.apply({"type": "end_turn", "label": "End turn"})
	play(growth, "Put Old Man on the Field")
	if growth.is_waiting_for_choice():
		play(growth, "Don't use Creative Liberties")
	expect(has_label(growth, "Evolve Old Man into Hammer of Justice (Field 1)") and not has_label(growth, "Evolve Old Man into Hammer of Justice (Field 2)"), "a later turn: Old Man can evolve, but not the one put on the Field this turn")
	play(growth, "Evolve Old Man into Hammer of Justice (Field 1)")
	var hammer := grower.bench[0]
	var hammer_attacks: Array = hammer.attacks().map(func(attack: AttackData) -> String: return attack.name)
	var hammer_powers: Array = hammer.powers().map(func(power: PowerData) -> String: return power.name)
	expect(hammer.card.name == "Hammer of Justice" and hammer.evolved_from.size() == 1 and hammer.damage == 30 and hammer.attached_energy.size() == 1, "Hammer of Justice goes on top; damage and Energy stay")
	expect(hammer.remaining_hp() == 90, "its HP replaces Old Man's: 120 - 30 (%d)" % hammer.remaining_hp())
	expect(hammer_attacks == ["Recruit", "Colourful Legacy"] and hammer_powers == ["Creative Liberties"], "it keeps Old Man's attacks and Abilities and adds its own: %s %s" % [hammer_attacks, hammer_powers])
	expect(hammer.base_card().name == "Old Man" and growth.retreat_cost(hammer).size() == 1, "it keeps Old Man's Weakness, Resistance and Flee cost")
	grower.hand.append_array(cards(["hammer_of_justice"]))
	expect(not has_action(growth, "evolve"), "a BREAK evolution does not evolve again")

	var inherited := battle("hammer_of_justice", ["creative_energy"], "tenna")
	var inherited_player := inherited.current_player()
	inherited_player.active.evolved_from.append(db.make("old_man"))
	inherited_player.deck.assign(cards(["guei"]))
	expect(has_label(inherited, "Attack: Recruit (0)"), "the kept attack can be used with its own cost")
	attack(inherited, "Recruit")
	expect(inherited.choice_prompt() == "Search your deck for Darkner", "and resolves with Old Man's effect")

	var mizzle := battle("hammer_of_justice", ["creative_energy", "creative_energy", "creative_energy"], "miss_mizzle")
	var mizzle_target := mizzle.opponent_player().active
	mizzle_target.evolved_from.append(db.make("water_cooler"))
	attack(mizzle, "Colourful Legacy")
	expect(mizzle_target.damage == 30, "Miss Mizzle keeps Water Cooler's Weakness to Creative: 10 + 20 (%d)" % mizzle_target.damage)

	print("== continuous Abilities")
	var vow := battle("jevil", ["chaos_energy", "chaos_energy"], "miss_mizzle")
	var vowed := vow.opponent_player()
	vowed.active.evolved_from.append(db.make("water_cooler"))
	vowed.bench.append(in_play("guei", []))
	vowed.bench.append(in_play("water_cooler", []))
	vow.current_player().bench.append(in_play("electro_dasher", []))
	var vow_start := vow.events.size()
	attack(vow, "Chaos Bomb")
	var vow_events := vow.events.slice(vow_start)
	expect(vowed.bench[0].damage == 0 and vowed.bench[1].damage == 0, "Vow of Majesty in the Battle Zone prevents attack damage to its owner's Field")
	expect(vow_events.has("  Vow of Majesty prevents the damage to Guei"), "the log says what prevented it")
	expect(not vow_events.any(func(line: String) -> bool: return line.contains("Coin flip")), "nothing was damaged, so Relentless Stampede does not flip")

	var unvowed := battle("jevil", ["chaos_energy", "chaos_energy"], "guei")
	var unvowed_side := unvowed.opponent_player()
	var resting := in_play("miss_mizzle", [])
	resting.evolved_from.append(db.make("water_cooler"))
	unvowed_side.bench.append(resting)
	unvowed_side.bench.append(in_play("water_cooler", []))
	attack(unvowed, "Chaos Bomb")
	expect(resting.damage == 20 and unvowed_side.bench[1].damage == 20, "on the Field, Vow of Majesty does nothing")

	var zone_hit := battle("jevil", ["chaos_energy"], "miss_mizzle")
	var zone_mizzle := zone_hit.opponent_player().active
	zone_mizzle.evolved_from.append(db.make("water_cooler"))
	attack(zone_hit, "Slash")
	expect(zone_mizzle.damage == 20, "it does not protect the Battling Darkner itself (%d)" % zone_mizzle.damage)

	var counters := battle("shuttah", ["chaos_energy", "chaos_energy"], "miss_mizzle")
	var counted := counters.opponent_player()
	counted.active.evolved_from.append(db.make("water_cooler"))
	counted.bench.append(in_play("guei", []))
	attack(counters, "Quick Selfie")
	play(counters, "Choose Guei (Field 1, 80/80 HP)")
	expect(counted.bench[0].damage == 20, "damage counters placed by an attack are not damage: Vow of Majesty does not stop them")

	print("== Area effects")
	var dark := battle("jevil", [], "tenna")
	var darker := dark.current_player()
	darker.hand.assign(cards(["dark_zone", "kris"]))
	expect(play(dark, "Play Dark Zone (Area)") and dark.stadium.name == "Dark Zone" and not dark.is_waiting_for_choice(), "Dark Zone can be played with 1 other card: playing it does nothing by itself")
	expect(not has_label(dark, "Use Dark Zone (Area)"), "its action needs 2 cards in hand")
	darker.hand.append_array(cards(["holy_energy", "guei"]))
	var dark_deck := darker.deck.size()
	expect(play(dark, "Use Dark Zone (Area)"), "with 2 cards in hand the player taking the turn may use it")
	var dark_labels: Array = []
	for action in dark.legal_actions():
		dark_labels.append(action["label"])
	expect(dark.choice_prompt() == "Choose 2 cards to discard from your hand (0/2 chosen)" and dark_labels == ["Discard Kris", "Discard Holy Energy", "Discard Guei"], "the player chooses 2 cards: %s" % [dark_labels])
	play(dark, "Discard Kris")
	play(dark, "Discard Guei")
	play(dark, "Confirm")
	expect(darker.discard.map(func(card: CardData) -> String: return card.name) == ["Kris", "Guei"] and darker.hand.size() == 2 and darker.deck.size() == dark_deck - 1, "they discard 2 cards and draw 1")
	darker.hand.append_array(cards(["kris", "kris"]))
	expect(not has_label(dark, "Use Dark Zone (Area)"), "once during each player's turn")
	dark.opponent_player().hand.append_array(cards(["guei", "guei"]))
	dark.apply({"type": "end_turn", "label": "End turn"})
	expect(has_label(dark, "Use Dark Zone (Area)"), "the opponent may use it during their own turn too")

	var cold := battle("jevil", [], "tenna")
	var cooler := cold.current_player()
	cooler.hand.assign(cards(["cold_place", "guei", "balthizard"]))
	cooler.deck.assign(cards(["water_cooler", "kris"]))
	play(cold, "Play Cold Place (Area)")
	play(cold, "Put Guei on the Field")
	expect(cooler.bench[0].damage == 10 and cold.events.has("Cold Place: Guei"), "Cold Place: 1 damage counter on a Darkner put onto the Field from the hand")
	play(cold, "Put Balthizard on the Field")
	play(cold, "Use Luring Incense (Balthizard)")
	pick(cold, "Put Water Cooler")
	expect(cooler.bench[1].damage == 10 and cooler.bench[2].card.name == "Water Cooler" and cooler.bench[2].damage == 10, "and on one put there from the deck, by Luring Incense")
	cold.opponent_player().hand.assign(cards(["guei"]))
	cold.apply({"type": "end_turn", "label": "End turn"})
	play(cold, "Put Guei on the Field")
	expect(cold.current_player().bench.back().damage == 10, "it applies to any player")
	var feathered := battle("jevil", [], "tenna")
	feathered.stadium = db.make("cold_place")
	feathered.current_player().bench.append(in_play("guei", []))
	feathered.current_player().hand.assign(cards(["petal_feather"]))
	play(feathered, "Play Petal Feather (Item)")
	expect(feathered.current_player().bench[0].card.name == "Jevil" and feathered.current_player().bench[0].damage == 0, "a Darkner moved from the Battle Zone to the Field gets nothing")

	print("== structured actions and choices")
	var setup_kinds := start_round(rules, 4)
	expect([PendingChoice.KIND_COIN_CALL, PendingChoice.KIND_BATTLING_DARKNER].has(setup_kinds.choice_kind()), "setup questions say what they ask (%s)" % setup_kinds.choice_kind())
	var by_fields := battle("jevil", [], "tenna")
	var by_fields_turn := by_fields.turn
	by_fields.apply({"type": "end_turn"})
	expect(by_fields.turn == by_fields_turn + 1, "an action is identified by its fields: no label needed")
	by_fields.apply({"type": "end_turn", "label": "Some other words"})
	expect(by_fields.turn == by_fields_turn + 2, "and the label is ignored")

	var glow := battle("jevil", [], "tenna")
	glow.current_player().hand.assign(cards(["glowshard"]))
	glow.current_player().deck.assign(cards(["chaos_energy", "kris"]))
	play(glow, "Play Glowshard (Item)")
	var glow_details := glow.choice_details()
	expect(glow.choice_kind() == PendingChoice.KIND_PICK_CARDS and glow_details["zone"] == PendingChoice.ZONE_DECK and glow_details["action"] == "take"
			and glow_details["minimum"] == 0 and glow_details["maximum"] == 1, "a search is a pick_cards question from the deck: %s" % [glow_details])
	expect(glow.choice_option(0)["pick"] == PendingChoice.PICK_ADD and glow.choice_option(1)["pick"] == PendingChoice.PICK_CONFIRM, "each option says whether it adds a card or confirms")
	glow.apply({"type": "choose", "option": 0.0})
	expect((glow.choice_details()["picked"] as Array).size() == 1 and glow.choice_option(0)["pick"] == PendingChoice.PICK_UNDO, "an option index that arrives as a float still matches; the picked card is listed and offered as undo")

	var manual_kind := battle("jevil", [], "tenna")
	manual_kind.current_player().hand.assign(cards(["recruit_manual", "kris", "glowshard", "guei"]))
	play(manual_kind, "Play Recruit Manual (Item)")
	var manual_details := manual_kind.choice_details()
	expect(manual_details["zone"] == PendingChoice.ZONE_HAND and manual_details["action"] == "discard" and manual_details["minimum"] == 2 and manual_details["maximum"] == 2,
			"discarding 2 from the hand: %s" % [manual_details])

	var switch_kind := battle("jevil", [], "tenna")
	switch_kind.current_player().bench.append_array([in_play("guei", []), in_play("koody", [])])
	switch_kind.opponent_player().bench.append_array([in_play("guei", []), in_play("koody", [])])
	switch_kind.current_player().hand.assign(cards(["petal_feather", "susie"]))
	play(switch_kind, "Play Petal Feather (Item)")
	expect(switch_kind.choice_kind() == PendingChoice.KIND_CHOOSE_DARKNER and switch_kind.choice_details() == {"side": PendingChoice.SIDE_OWN, "purpose": PendingChoice.PURPOSE_SWITCH_IN},
			"Petal Feather: choose one of your own Darkners to switch in")
	play(switch_kind, "Switch in Guei (Field 1)")
	play(switch_kind, "Play Susie (Lightner)")
	expect(switch_kind.choice_details()["side"] == PendingChoice.SIDE_OPPONENT, "Susie: one of the opponent's")

	var tp_kind := battle("water_cooler", ["holy_energy", "holy_energy"], "jevil")
	tp_kind.current_player().bench.append(in_play("guei", []))
	attack(tp_kind, "Refreshing Splash")
	expect(tp_kind.choice_kind() == PendingChoice.KIND_PAY_TP and tp_kind.choice_details() == {"amount": 1}, "Refreshing Splash asks whether to pay 1 quarter of TP")

	var ability_kind := battle("jevil", [], "tenna")
	ability_kind.current_player().hand.assign(cards(["balthizard"]))
	play(ability_kind, "Put Balthizard on the Field")
	expect(ability_kind.choice_kind() == PendingChoice.KIND_USE_ABILITY and ability_kind.choice_details() == {"power": "Luring Incense"}, "an on-play Ability names itself")

	var promote_kind := battle("jevil", ["chaos_energy"], "koody")
	promote_kind.opponent_player().bench.append_array([in_play("guei", []), in_play("water_cooler", [])])
	promote_kind.opponent_player().active.damage = 30
	attack(promote_kind, "Slash")
	expect(promote_kind.choice_kind() == PendingChoice.KIND_PROMOTE, "a promotion says so (%s)" % promote_kind.choice_kind())

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
	var mixed := {"jevil": 4, "tenna": 4, "guei": 4, "cuptain": 2, "chaos_energy": 8, "petal_feather": 2, "kris": 2, "rude_buster": 2, "cyber_city": 1, "mewers_live": 1,
			"cd_bagel": 2, "recruit_manual": 2, "revive_mint": 1, "napstablook": 1, "sans": 1, "berdly": 1,
			"old_man": 2, "balthizard": 2, "koody": 2, "hammer_of_justice": 2, "dark_zone": 1, "cold_place": 1}
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