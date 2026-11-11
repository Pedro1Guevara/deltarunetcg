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
	for action in labeled(engine):
		if action["type"] == type:
			return true
	return false


func has_label(engine: MatchEngine, label: String) -> bool:
	for action in labeled(engine):
		if action["label"] == label:
			return true
	return false


## Applies the legal action with this label. False when there is none.
func play(engine: MatchEngine, label: String) -> bool:
	for action in labeled(engine):
		if action["label"] == label:
			engine.apply(action)
			take_mercy_cards(engine)
			return true
	return false


## Answers every Mercy Card pick that is open with the first card of the pile (Design Document
## 4.4), as play() and attack() do after their action, so checks after a knockout read its result.
func take_mercy_cards(engine: MatchEngine) -> void:
	while engine.is_waiting_for_choice() and engine.choice_kind() == PendingChoice.KIND_TAKE_PRIZE:
		engine.apply({"type": "choose", "option": 0})


## Picks the card option with this label, then confirms the choice.
func pick(engine: MatchEngine, label: String) -> bool:
	return play(engine, label) and play(engine, "Confirm")


## A round where the player to act took their last Mercy Card with Tenna's Showtime! and chose
## to Fight; their opponent promoted Guei and is taking their turn.
func fight_round() -> MatchEngine:
	var engine := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	engine.opponent_player().bench.append(in_play("guei", []))
	var taker := engine.current_index
	while engine.players[taker].prizes.size() > 1:
		engine.players[taker].prizes.pop_back()
	attack(engine, "Showtime!")
	choose_label(engine, "Fight")
	return engine


func option_labels(engine: MatchEngine) -> Array[String]:
	var labels: Array[String] = []
	for action in labeled(engine):
		labels.append(str(action["label"]))
	return labels


## Answers the open question with the option whose label begins with prefix.
func choose_label(engine: MatchEngine, prefix: String) -> void:
	for action in labeled(engine):
		if str(action["label"]).begins_with(prefix):
			engine.apply(action)
			return
	push_error("no option begins with %s" % prefix)


func attack(engine: MatchEngine, name: String) -> bool:
	for action in labeled(engine):
		if action["type"] == "attack" and str(action["label"]).begins_with("Attack: %s " % name):
			engine.apply(action)
			take_mercy_cards(engine)
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
	single.apply(labeled(single)[0])
	expect(prompt_of(single) == "Choose your Battling Darkner" and labeled(single).size() == 1, "with one Basic Darkner the player is still asked, not skipped")

	print("== coin flip")
	var callers := {}
	var first_players := {}
	var asked_first := true
	for seed in SEEDS:
		var engine := start_round(rules, seed)
		var labels: Array = []
		for action in labeled(engine):
			labels.append(action["label"])
		if not (prompt_of(engine).begins_with("Call the coin flip") and labels == ["Heads", "Tails"]):
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
	for action in labeled(search):
		search_labels.append(action["label"])
	expect(prompt_of(search) == "Search your deck for basic Energy" and search_labels == ["Take Chaos Energy", "Take nothing"], "Glowshard offers each basic Energy once, and finding nothing: %s" % [search_labels])
	var shown := search.choice_revealed()
	expect(shown.size() == searcher.deck.size() and shown[0] == searcher.deck.back() and shown.back() == searcher.deck[0], "the whole deck is shown during the search, in its real order, top card first")
	play(search, "Take Chaos Energy")
	search_labels.clear()
	for action in labeled(search):
		search_labels.append(action["label"])
	expect(search_labels == ["Undo: Take Chaos Energy", "Confirm"] and searcher.deck.size() == deck_before, "a single pick also waits for confirmation and can be undone: %s" % [search_labels])
	play(search, "Confirm")
	expect(searcher.deck.size() == deck_before - 1 and searcher.hand.back().name == "Chaos Energy", "the Energy found goes into the hand")
	var darkners_only: Array[CardData] = []
	for card in searcher.deck:
		if card.is_pokemon():
			darkners_only.append(card)
	searcher.deck.assign(darkners_only)
	expect(play(search, "Play Glowshard (Item)") and has_label(search, "Take nothing") and labeled(search).size() == 1, "with no basic Energy in the deck, Glowshard still asks, so the deck can be looked at")
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
	for action in labeled(revive):
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
		if log_lines(buster).has("  Coin flip: heads"):
			var buster_labels: Array = []
			for action in labeled(buster):
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
	for action in labeled(nap):
		nap_labels.append(action["label"])
	expect(prompt_of(nap) == "Search your deck for any card to discard (0/2 chosen)" and nap_labels == ["Discard Chaos Energy", "Discard Kris", "Discard Guei", "Discard nothing"], "Napstablook offers every card in the deck: %s" % [nap_labels])
	play(nap, "Discard Kris")
	nap_labels.clear()
	for action in labeled(nap):
		nap_labels.append(action["label"])
	expect(prompt_of(nap).ends_with("(1/2 chosen)") and nap_labels == ["Discard Chaos Energy", "Undo: Discard Kris", "Discard Guei", "Confirm"], "a picked card can be undone, and the player may confirm fewer: %s" % [nap_labels])
	expect(napper.deck.size() == 3, "nothing leaves the deck before confirming")
	play(nap, "Undo: Discard Kris")
	play(nap, "Discard Guei")
	play(nap, "Discard Kris")
	nap_labels.clear()
	for action in labeled(nap):
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
	for action in labeled(sans):
		sans_labels.append(action["label"])
	expect(prompt_of(sans) == "Search your deck for ACT card (0/2 chosen)" and sans_labels == ["Take Glowshard", "Take Rude Buster", "Take Kris", "Take nothing"], "then searches for ACT cards: %s" % [sans_labels])
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
	for action in labeled(bagel):
		bagel_labels.append(action["label"])
	expect(prompt_of(bagel) == "Choose a card to discard from your hand" and bagel_labels == ["Discard CD Bagel", "Discard Guei"], "the player chooses the card to discard: %s" % [bagel_labels])
	pick(bagel, "Discard Guei")
	bagel_labels.clear()
	for action in labeled(bagel):
		bagel_labels.append(action["label"])
	expect(prompt_of(bagel) == "Search your deck for basic Energy (0/2 chosen)" and bagel_labels == ["Take Chaos Energy #1", "Take Chaos Energy #2", "Take Holy Energy", "Take nothing"], "then searches the deck; when picking several, every copy is its own option: %s" % [bagel_labels])
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
	expect(prompt_of(manual) == "Search your deck for Darkner" and recruiter.discard.size() == 2 and recruiter.hand.is_empty(), "two copies of the same card are discarded without asking")
	pick(manual, "Take Guei")
	expect(recruiter.hand.size() == 1 and recruiter.hand[0].name == "Guei", "the Darkner goes into the hand")
	var choosy := battle("jevil", [], "guei")
	var chooser := choosy.current_player()
	chooser.hand.assign(cards(["recruit_manual", "holy_energy", "holy_energy", "sans"]))
	play(choosy, "Play Recruit Manual (Item)")
	var choosy_labels: Array = []
	for action in labeled(choosy):
		choosy_labels.append(action["label"])
	expect(prompt_of(choosy) == "Choose 2 cards to discard from your hand (0/2 chosen)" and choosy_labels == ["Discard Holy Energy #1", "Discard Holy Energy #2", "Discard Sans"], "discarding 2: every card is its own option and there is nothing to confirm yet: %s" % [choosy_labels])
	play(choosy, "Discard Holy Energy #1")
	play(choosy, "Discard Holy Energy #2")
	choosy_labels.clear()
	for action in labeled(choosy):
		choosy_labels.append(action["label"])
	expect(choosy_labels == ["Undo: Discard Holy Energy #1", "Undo: Discard Holy Energy #2", "Confirm"], "with 2 picked: %s" % [choosy_labels])
	play(choosy, "Undo: Discard Holy Energy #2")
	play(choosy, "Discard Sans")
	expect(chooser.hand.size() == 3 and chooser.discard.is_empty(), "nothing is discarded before confirming")
	play(choosy, "Confirm")
	expect(chooser.discard.map(func(card: CardData) -> String: return card.name) == ["Holy Energy", "Sans"] and prompt_of(choosy) == "Search your deck for Darkner", "confirming discards the 2 picked cards, then the search starts")

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
	expect(log_lines(transit).any(func(line: String) -> bool: return line.begins_with("  10 damage to Tenna")), "Violent Transit deals its 10 damage")
	expect(transit_player.active.card.name == "Jevil" and transit_player.bench[0].card.name == "Electro-Dasher", "then the attacker switches with the Darkner on the Field")

	var splash := battle("water_cooler", ["holy_energy", "holy_energy"], "jevil")
	var splasher := splash.current_player()
	splasher.bench.append(in_play("guei", []))
	splasher.bench[0].damage = 30
	splasher.tp = 1
	attack(splash, "Refreshing Splash")
	var splash_labels: Array = []
	for action in labeled(splash):
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
	for action in labeled(recruit):
		recruit_labels.append(action["label"])
	expect(prompt_of(recruit) == "Search your deck for Darkner" and recruit_labels == ["Take Guei", "Take Jevil", "Take nothing"], "Recruit searches the deck for a Darkner: %s" % [recruit_labels])
	pick(recruit, "Take Jevil")
	expect(recruiter_side.hand.back().name == "Jevil" and recruit.opponent_player().active.damage == 0, "the Darkner goes into the hand; an attack with no printed damage deals none")
	expect(not log_lines(recruit).any(func(line: String) -> bool: return line.begins_with("  0 damage")), "and logs no damage")
	expect(recruit.current_player() != recruiter_side, "then the turn ends")

	var training := battle("dummy", ["fighting_energy"], "tenna")
	var trainer_side := training.current_player()
	trainer_side.bench.append(in_play("guei", []))
	trainer_side.bench.append(in_play("cuptain", []))
	trainer_side.hand.assign(cards(["holy_energy", "fighting_energy", "kris"]))
	trainer_side.energy_attached_this_turn = true
	expect(attack(training, "Helpful Training"), "Helpful Training is legal even after attaching Energy this turn")
	var training_labels: Array = []
	for action in labeled(training):
		training_labels.append(action["label"])
	expect(prompt_of(training) == "Choose a card from your hand to attach" and training_labels == ["Attach Holy Energy", "Attach Fighting Energy"], "the player chooses a basic Energy from their hand: %s" % [training_labels])
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
		var start := log_lines(lunge).size()
		attack(lunge, "Lunge")
		var heads := log_lines(lunge).slice(start).has("  Coin flip: heads")
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
	for action in labeled(selfie):
		selfie_labels.append(action["label"])
	expect(prompt_of(selfie) == "Choose one of your opponent's Darkners" and selfie_labels == ["Choose Tenna (Battle Zone, 100/100 HP)", "Choose Guei (Field 1, 80/80 HP)"], "the attacker chooses any of the opponent's Darkners: %s" % [selfie_labels])
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
	expect(again.current_index == again_index and again.turn == again_turn + 1 and log_lines(again).has("Player %d takes another turn" % (again_index + 1)), "a knockout by Quick Selfie gives the attacker another turn")
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
	for action in labeled(devotion):
		energy_labels.append(action["label"])
	expect(energy_labels == ["Attach Chaos Energy", "Attach Holy Energy"], "the player chooses the Energy: %s" % [energy_labels])
	pick(devotion, "Attach Holy Energy")
	expect(play(devotion, "Attach Holy Energy to Guei (Field 2)"), "then the Darkner on the Field")
	var mercy_before := devotion.opponent_player().prizes.size()
	expect(devotee.active == null and prompt_of(devotion) == "Choose a new Battling Darkner" and devotion.choice_chooser() == devotion.current_index, "40 damage knocks Cuptain out; its owner chooses the new Battling Darkner")
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
	for action in labeled(worm):
		worm_labels.append(action["label"])
	expect(prompt_of(worm) == "Choose a basic Energy to discard from your hand" and worm_labels == ["Discard Fun Energy", "Discard Holy Energy"], "the player chooses a basic Energy, never another card: %s" % [worm_labels])
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
	for action in labeled(lure):
		lure_labels.append(action["label"])
	expect(prompt_of(lure) == "Use Luring Incense?" and lure_labels == ["Use Luring Incense (Balthizard)", "Don't use Luring Incense"], "its owner may use Luring Incense: %s" % [lure_labels])
	play(lure, "Use Luring Incense (Balthizard)")
	lure_labels.clear()
	for action in labeled(lure):
		lure_labels.append(action["label"])
	expect(prompt_of(lure) == "Search your deck for non-Evolution Darkner to put onto your Field (not Balthizard)" and lure_labels == ["Put Guei", "Put nothing"], "the search offers non-Evolution Darkners other than Balthizard: %s" % [lure_labels])
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
		var log_start := log_lines(stampede).size()
		attack(stampede, "Chaos Bomb")
		var flips := log_lines(stampede).slice(log_start).filter(func(line: String) -> bool: return line.contains("Coin flip"))
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
	var herd_start := log_lines(herd).size()
	attack(herd, "Slash")
	var herd_flips := log_lines(herd).slice(herd_start).filter(func(line: String) -> bool: return line.contains("Coin flip"))
	expect(herd_flips.size() == 2, "two Electro-Dasher in play flip a coin each (%d)" % herd_flips.size())

	var blocked := battle("jevil", ["chaos_energy"], "guei")
	blocked.current_player().bench.append(in_play("electro_dasher", []))
	var blocked_start := log_lines(blocked).size()
	attack(blocked, "Slash")
	var blocked_flips := log_lines(blocked).slice(blocked_start).filter(func(line: String) -> bool: return line.contains("Coin flip"))
	expect(blocked_flips.is_empty(), "an attack that deals no damage (Guei resists Chaos) sets off nothing")

	var trigger_heads := false
	var trigger_tails := false
	for seed in SEEDS:
		var trigger_ko := battle("electro_dasher", ["chaos_energy"], "tenna", seed)
		trigger_ko.opponent_player().bench.append(in_play("guei", []))
		trigger_ko.opponent_player().active.damage = 80
		var trigger_taker := trigger_ko.current_index
		var trigger_start := log_lines(trigger_ko).size()
		attack(trigger_ko, "Violent Transit")
		var heads := log_lines(trigger_ko).slice(trigger_start).has("  Coin flip: heads")
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
	expect(prompt_of(inherited) == "Search your deck for Darkner", "and resolves with Old Man's effect")

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
	var vow_start := log_lines(vow).size()
	attack(vow, "Chaos Bomb")
	var vow_events := log_lines(vow).slice(vow_start)
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
	for action in labeled(dark):
		dark_labels.append(action["label"])
	expect(prompt_of(dark) == "Choose 2 cards to discard from your hand (0/2 chosen)" and dark_labels == ["Discard Kris", "Discard Holy Energy", "Discard Guei"], "the player chooses 2 cards: %s" % [dark_labels])
	play(dark, "Discard Kris")
	play(dark, "Discard Guei")
	play(dark, "Confirm")
	expect(darker.discard.map(func(card: CardData) -> String: return card.name) == ["Kris", "Guei"] and darker.hand.size() == 2 and darker.deck.size() == dark_deck - 1, "they discard 2 cards and draw 1")
	darker.hand.append_array(cards(["kris", "kris"]))
	expect(not has_label(dark, "Use Dark Zone (Area)"), "once during each player's turn")
	dark.opponent_player().hand.append_array(cards(["guei", "guei"]))
	dark.apply({"type": "end_turn", "label": "End turn"})
	expect(has_label(dark, "Use Dark Zone (Area)"), "the opponent may use it during their own turn too")

	var cold := battle("jevil", [], "koody")
	var cooler := cold.current_player()
	cooler.hand.assign(cards(["cold_place", "guei", "balthizard"]))
	cooler.deck.assign(cards(["water_cooler", "kris"]))
	play(cold, "Play Cold Place (Area)")
	play(cold, "Put Guei on the Field")
	expect(cooler.bench[0].damage == 10 and log_lines(cold).has("Cold Place: Guei"), "Cold Place: 1 damage counter on a Darkner put onto the Field from the hand")
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

	print("== player views")
	var seen_round := battle("jevil", ["chaos_energy"], "tenna")
	seen_round.current_player().hand.assign(cards(["kris", "glowshard"]))
	seen_round.opponent_player().hand.assign(cards(["guei", "guei", "susie"]))
	var me_index := seen_round.current_index
	var my_view := seen_round.view_for(me_index)
	var their_view := seen_round.view_for(1 - me_index)
	expect(my_view.viewer == me_index and my_view.current == me_index and my_view.me().index == me_index and my_view.opponent().index == 1 - me_index, "a view knows whose it is and whose turn it is")
	expect(my_view.me().hand.size() == 2 and my_view.me().hand[0].id == "kris", "the viewer sees their own hand")
	expect(my_view.opponent().hand.is_empty() and my_view.opponent().hand_size == 3, "and only how many cards the opponent holds")
	expect(their_view.me().hand.size() == 3 and their_view.opponent().hand.is_empty() and their_view.opponent().hand_size == 2, "the opponent's view is the mirror")
	expect(my_view.me().deck_size == seen_round.current_player().deck.size() and my_view.me().prize_count == seen_round.current_player().prizes.size(), "decks and Mercy Cards are counts only")
	expect(my_view.me().tp == seen_round.current_player().tp and my_view.opponent().active.card.id == "tenna", "both boards and TP are public")
	expect(not my_view.legal_actions.is_empty() and their_view.legal_actions.is_empty(), "only the player taking the turn sees legal actions")
	my_view.me().hand.clear()
	my_view.me().active.damage = 50
	my_view.me().active.attached_energy.clear()
	my_view.opponent().discard.append(db.make("guei"))
	my_view.rules.prizes_per_knockout = 3
	expect(seen_round.rules.prizes_per_knockout == 1 and my_view.rules.prize_count == seen_round.rules.prize_count, "the view holds a copy of the rules")
	expect(seen_round.current_player().hand.size() == 2 and seen_round.current_player().active.damage == 0 and seen_round.current_player().active.attached_energy.size() == 1
			and seen_round.opponent_player().discard.is_empty(), "changing a view changes nothing in the round")

	var search_view := battle("jevil", [], "tenna")
	search_view.current_player().hand.assign(cards(["glowshard"]))
	search_view.current_player().deck.assign(cards(["chaos_energy", "kris"]))
	play(search_view, "Play Glowshard (Item)")
	var view_chooser := search_view.view_for(search_view.current_index)
	var view_watcher := search_view.view_for(1 - search_view.current_index)
	expect(view_chooser.chooser == search_view.current_index and view_chooser.choice_kind == PendingChoice.KIND_PICK_CARDS and view_chooser.revealed.size() == 2
			and view_chooser.choice_options.size() == labeled(search_view).size() and ActionText.prompt(view_chooser, db) != "", "the chooser sees the question, its options and the cards it shows")
	expect(view_watcher.chooser == search_view.current_index and view_watcher.choice_kind == PendingChoice.KIND_PICK_CARDS and view_watcher.choice_options.is_empty()
			and view_watcher.choice_details.is_empty() and ActionText.prompt(view_watcher, db) == "" and view_watcher.revealed.is_empty() and view_watcher.legal_actions.is_empty(),
			"the other player sees only that a search is open")
	expect(view_chooser.resolving_trainer != null and view_chooser.resolving_trainer.id == "glowshard" and view_watcher.resolving_trainer == view_chooser.resolving_trainer,
			"both see the ACT card being played")
	view_chooser.choice_details["picked"].append(db.make("kris"))
	expect((search_view.choice_details()["picked"] as Array).is_empty(), "changing the question in a view changes nothing")

	var target_view := battle("jevil", [], "tenna")
	target_view.current_player().bench.append_array([in_play("guei", []), in_play("koody", [])])
	target_view.current_player().hand.assign(cards(["petal_feather"]))
	play(target_view, "Play Petal Feather (Item)")
	var shown_copy := target_view.view_for(target_view.current_index).choice_options[0]["shows"] as CardInPlay
	expect(shown_copy != null and shown_copy.card.id == "guei" and shown_copy != target_view.current_player().bench[0], "a Darkner an option is about is shown as a copy")

	var promote_view := battle("jevil", ["chaos_energy"], "koody")
	promote_view.opponent_player().bench.append_array([in_play("guei", []), in_play("water_cooler", [])])
	promote_view.opponent_player().active.damage = 30
	var view_promoter := promote_view.current_index ^ 1
	attack(promote_view, "Slash")
	expect(promote_view.view_for(view_promoter).legal_actions.size() == 2 and promote_view.view_for(1 - view_promoter).legal_actions.is_empty(),
			"the player who answers sees the legal actions, even when it is not their turn")
	expect(promote_view.view_for(view_promoter).me().active == null, "an empty Battle Zone shows as empty")

	print("== events")
	var watched := battle("jevil", ["chaos_energy"], "koody")
	var actor_index := watched.current_index
	var opponent_index := 1 - actor_index
	# Every event has a line in the log but a turn's draw, which the board shows.
	var lines_match := func(engine: MatchEngine) -> bool:
		var worded := engine.match_log.entries.filter(func(event: MatchEvent) -> bool:
			return not (event.type == MatchEvent.DREW and bool(event.data["at_turn_start"])))
		for event: MatchEvent in worded:
			if EventText.line(event, db).is_empty():
				return false
		return worded.size() == log_lines(engine).size()
	expect(lines_match.call(watched), "every event has a line in the log, but a turn's draw")
	var turn_draws := watched.events_for(actor_index, 0).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.DREW and event.player == actor_index and bool(event.data["at_turn_start"]))
	var opponent_draws := watched.events_for(opponent_index, 0).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.DREW and event.player == actor_index and bool(event.data["at_turn_start"]))
	expect(not turn_draws.is_empty() and (turn_draws.back() as MatchEvent).data["cards"].size() == 1 and (opponent_draws.back() as MatchEvent).data == {"count": 1, "at_turn_start": true, "extra": false},
			"a turn's draw is an event without a line: the player sees the card, the opponent only that one was drawn")
	watched.opponent_player().active.damage = 20
	var before_attack := watched.match_log.entries.size()
	watched.apply({"type": "attack", "attack_index": 0})
	take_mercy_cards(watched)
	var attack_events := watched.events_for(opponent_index, before_attack)
	var damage := attack_events.filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.DAMAGE)[0] as MatchEvent
	expect(attack_events[0].type == MatchEvent.ATTACK_USED and attack_events[0].data["attack"] == "Slash"
			and damage.data == {"darkner": {"side": opponent_index, "slot": -1, "card": "koody"}, "amount": 20, "kind": MatchOperations.DAMAGE_ATTACK, "hp_left": 0},
			"an attack is events with data: who attacked with what, and 20 damage to Koody in the Battle Zone, 0 HP left (%s)" % damage.data)
	var knockout := attack_events.filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.KNOCKED_OUT)
	var prize_seen := watched.events_for(actor_index, before_attack).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.PRIZE_TAKEN)
	var prize_hidden := attack_events.filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.PRIZE_TAKEN)
	expect(knockout.size() == 1 and prize_seen.size() == 1 and (prize_seen[0] as MatchEvent).data.has("card") and not (prize_hidden[0] as MatchEvent).data.has("card"),
			"the Mercy Card taken is shown to its taker only")

	var revealing := battle("jevil", [], "tenna")
	revealing.current_player().hand.assign(cards(["glowshard"]))
	revealing.current_player().deck.assign(cards(["chaos_energy", "kris"]))
	var searcher_index := revealing.current_index
	var before_search := revealing.match_log.entries.size()
	play(revealing, "Play Glowshard (Item)")
	var chooser_sees := revealing.events_for(searcher_index, before_search)
	var watcher_sees := revealing.events_for(1 - searcher_index, before_search)
	pick(revealing, "Take Chaos Energy")
	var taken := revealing.events_for(1 - searcher_index, before_search).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.CARD_MOVED)
	expect(taken.size() == 1 and (taken[0] as MatchEvent).data == {"card": "chaos_energy", "from": MatchEvent.ZONE_DECK, "to": MatchEvent.ZONE_HAND},
			"a search for a kind of card shows the opponent the card taken, as in the Pokémon TCG")
	var answers_seen := revealing.events_for(searcher_index, before_search).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.CHOICE_ANSWERED)
	var answers_hidden := revealing.events_for(1 - searcher_index, before_search).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.CHOICE_ANSWERED)
	expect(answers_seen.size() == 2 and answers_hidden.is_empty() and chooser_sees.size() == watcher_sees.size(),
			"the answers to a question are the chooser's alone: the opponent sees what they lead to")
	var unrevealed := battle("jevil", [], "tenna")
	var holder := unrevealed.current_player()
	holder.deck.assign(cards(["kris", "guei"]))
	var before_take := unrevealed.match_log.entries.size()
	unrevealed.operations.take_from_deck(holder, [holder.deck[0]] as Array[CardData], false)
	var owner_view := unrevealed.events_for(unrevealed.current_index, before_take)[0]
	var other_view := unrevealed.events_for(1 - unrevealed.current_index, before_take)[0]
	var other_line := EventText.line(other_view, db)
	expect(owner_view.data["card"] == "kris" and not other_view.data.has("card") and other_line.contains("a card") and not other_line.contains("Kris"),
			"a card taken by a search for any card is hidden from the opponent, in data and in text")

	var leaks := ""
	for seed in 6:
		var leaky := MatchEngine.new()
		leaky.effects = library
		leaky.start(deck({"jevil": 4, "tenna": 4, "guei": 4, "cuptain": 2, "chaos_energy": 8, "kris": 2, "cd_bagel": 2, "recruit_manual": 2, "sans": 1, "berdly": 1}),
				deck({"jevil": 4, "tenna": 4, "guei": 4, "chaos_energy": 18}), rules, Rng.new(seed))
		var event_picker := RandomNumberGenerator.new()
		event_picker.seed = seed
		for _step in 300:
			if leaky.is_over():
				break
			var options := labeled(leaky)
			leaky.apply(options[event_picker.randi_range(0, options.size() - 1)])
		for viewer in 2:
			for event in leaky.events_for(viewer, 0):
				var private_type := [MatchEvent.DREW, MatchEvent.PRIZE_TAKEN, MatchEvent.MULLIGAN_DRAWS].has(event.type)
				if event.player != viewer and ((private_type and (event.data.has("cards") or event.data.has("card"))) or event.type == MatchEvent.CHOICE_ANSWERED):
					leaks = "seed %d viewer %d: %s %s" % [seed, viewer, event.type, event.data]
		if not lines_match.call(leaky):
			leaks = "seed %d: the log lines and the events differ" % seed
	expect(leaks.is_empty(), "in random rounds no player's view of the events holds the other's draws, Mercy Cards or answers: %s" % leaks)

	print("== replays")
	var recorded := start_round(MatchRules.deltarune().with_prize_count(1), 12)
	finish_setup(recorded)
	recorded.apply({"type": "end_turn"})
	var record := recorded.replay()
	expect(record.rng_seed == 12 and record.decks.size() == 2 and record.decks[0].size() == 30 and record.decks[0][0] == "jevil",
			"a replay holds the seed and both decks as card ids, in the order they were handed in")
	expect(MatchRules.from_dict(record.rules).prize_count == 1 and MatchRules.from_dict(record.rules).hand_size == 10, "and the rules the round started with")
	expect(not record.actions.is_empty() and record.actions.back() == {"type": "end_turn"} and record.actions.all(func(action: Dictionary) -> bool: return not action.has("label")),
			"and every action applied, without labels")
	record.actions.clear()
	expect(not recorded.replay().actions.is_empty(), "a replay is a copy")
	var code := recorded.replay().to_code()
	expect(code.begins_with(MatchReplay.CODE_PREFIX) and not code.contains(" ") and code.length() * 3 < recorded.replay().to_text().length(),
			"a code is one line, a third the length of the text or less (%d against %d)" % [code.length(), recorded.replay().to_text().length()])
	expect(MatchReplay.from_text(code).to_text() == recorded.replay().to_text() and MatchReplay.from_text("  %s\n" % code) != null, "and reads back as the same replay, spaces around it ignored")
	var odd_power := {"type": "use_power", "slot": -1, "power": "Way of the Worm, | 100%"}
	expect(MatchReplay._token_action(MatchReplay._action_token(odd_power)) == odd_power, "an Ability name with commas, bars or percent signs survives its token")
	expect(MatchReplay.from_text(MatchReplay.CODE_PREFIX + "not base64 at all") == null, "a broken code reads as null")
	var big_seed := MatchReplay.new()
	big_seed.rng_seed = 9007199254740993
	big_seed.rules = MatchRules.deltarune().to_dict()
	big_seed.decks.assign([PackedStringArray(["jevil"]), PackedStringArray(["guei"])])
	var big_seed_back := MatchReplay.from_text(big_seed.to_text())
	expect(big_seed_back != null and big_seed_back.rng_seed == 9007199254740993, "a seed too big for a JSON number survives the text")
	expect(MatchReplay.from_text("not a replay") == null and MatchReplay.from_text("{\"format\": 1}") == null, "text that is not a replay reads as null")
	var rules_missing := MatchRules.deltarune().to_dict()
	rules_missing.erase("tp_max")
	expect(MatchRules.from_dict(rules_missing) == null, "rules with a missing value are refused, not filled with a default")
	var diverged := recorded.replay()
	diverged.actions.insert(diverged.actions.size() - 1, {"type": "attack", "attack_index": 7})
	print("  (a warning about action %d is expected)" % (diverged.actions.size() - 1))
	expect(diverged.play(db, library).replay().actions.size() == diverged.actions.size() - 2, "playing again stops at the first action that is not legal")

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
	expect(flee_two.size() == 1 and ActionText.option_label(PendingChoice.KIND_FLEE_PAYMENT, {}, flee_two[0], null, db) == "Discard Chaos Energy + Chaos Energy", "copies are one option, with no card to spare")
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
	promotion.apply(labeled(promotion)[0])
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
	expect(not last.is_over() and last.choice_kind() == PendingChoice.KIND_SPARE_FIGHT and last.choice_chooser() == last_taker,
			"taking the last Mercy Card does not end the round: its taker chooses to Spare or to Fight")
	var spare_labels := option_labels(last)
	expect(spare_labels == ["Spare: win the round; your opponent draws 3 extra cards next round",
			"Fight: knock out a Darkner to win with no extra cards; lose one and you lose the round"], "Spare or Fight, worded for the taker (%s)" % [spare_labels])
	expect(ActionText.prompt(last.view_for(last_taker), db) == "You took your last Mercy Card: Spare or Fight?" and ActionText.prompt(last.view_for(1 - last_taker), db).is_empty()
			and last.view_for(1 - last_taker).choice_kind == PendingChoice.KIND_SPARE_FIGHT, "the opponent sees that the question is open, but not its options")
	choose_label(last, "Spare")
	expect(last.winner == last_taker and last.extra_draws_next_round[1 - last_taker] == 3 and last.extra_draws_next_round[last_taker] == 0,
			"Spare wins the round; the opponent will draw 3 extra cards next round")
	expect(log_lines(last).has("Player %d spares the opponent, who draws 3 extra cards next round" % (last_taker + 1)) and log_lines(last).back() == "Player %d wins" % (last_taker + 1),
			"the log says who spared and who won")

	var last_and_empty := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	var last_and_empty_taker := last_and_empty.current_index
	while last_and_empty.players[last_and_empty_taker].prizes.size() > 1:
		last_and_empty.players[last_and_empty_taker].prizes.pop_back()
	attack(last_and_empty, "Showtime!")
	expect(last_and_empty.winner == last_and_empty_taker and not last_and_empty.is_waiting_for_choice(),
			"the last Mercy Card and an opponent with nothing to promote: the round ends at once, no Spare or Fight")

	var at_match_point := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	var match_point_taker := at_match_point.current_index
	at_match_point.opponent_player().bench.append(in_play("guei", []))
	at_match_point.rules.match_point[match_point_taker] = true
	while at_match_point.players[match_point_taker].prizes.size() > 1:
		at_match_point.players[match_point_taker].prizes.pop_back()
	attack(at_match_point, "Showtime!")
	expect(at_match_point.winner == match_point_taker and not at_match_point.is_waiting_for_choice() and at_match_point.extra_draws_next_round == [0, 0],
			"at match point the last Mercy Card wins at once: Spare would win the combat, so there is nothing to choose")

	print("== Fight")
	var lost_fight := fight_round()
	var fighter := lost_fight.fighting
	expect(fighter != -1 and not lost_fight.is_over() and lost_fight.current_index == 1 - fighter and lost_fight.turn == 3,
			"Fight: the round goes on, the opponent promotes and takes their turn")
	expect(lost_fight.view_for(1 - fighter).fighting == fighter and log_lines(lost_fight).has("Player %d chooses to Fight: the next knockout decides the round" % (fighter + 1)),
			"both players see who is fighting")
	lost_fight.current_player().active = in_play("jevil", ["chaos_energy"])
	lost_fight.players[fighter].active.damage = 90
	attack(lost_fight, "Slash")
	expect(lost_fight.winner == 1 - fighter and lost_fight.extra_draws_next_round[1 - fighter] == 3 and lost_fight.extra_draws_next_round[fighter] == 0,
			"one of the fighter's Darkners knocked out: the opponent wins the round and still draws 3 extra cards next round")
	expect(log_lines(lost_fight).has("Player %d loses the Fight; the opponent draws 3 extra cards next round" % (fighter + 1)), "the log says the Fight was lost")

	var won_fight := fight_round()
	var winner_fighter := won_fight.fighting
	won_fight.apply({"type": "end_turn", "label": "End turn"})
	won_fight.current_player().active = in_play("jevil", ["chaos_energy", "chaos_energy"])
	won_fight.opponent_player().bench.append(in_play("koody", []))
	won_fight.opponent_player().bench[0].damage = 30
	attack(won_fight, "Chaos Bomb")
	expect(won_fight.current_index == winner_fighter and won_fight.winner == winner_fighter and won_fight.extra_draws_next_round == [0, 0],
			"a Darkner of the opponent knocked out, even on their Field: the fighter wins the round, and no one draws extra")
	expect(log_lines(won_fight).has("Player %d wins the Fight" % (winner_fighter + 1)), "the log says the Fight was won")

	var both := fight_round()
	var both_fighter := both.fighting
	both.players[both_fighter].active.damage = 100
	both.players[1 - both_fighter].active.damage = 80
	var both_resolver := KnockoutResolver.new(both.players, both.match_log)
	var both_result := both_resolver.resolve(both.current_index, both.rules, both_fighter)
	while both_resolver.has_prize_choice():
		both_resolver.take_prize_at(0)
	if both_result == KnockoutResolver.CHOOSING_PRIZES:
		both_result = both_resolver.settle(both.rules, both_fighter)
	expect(both_result == MatchEngine.SUDDEN_DEATH, "a Darkner on each side knocked out during a Fight: Sudden Death")

	var legacy_last := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	var legacy_taker := legacy_last.current_index
	legacy_last.opponent_player().bench.append(in_play("guei", []))
	legacy_last.players[legacy_taker].prizes.resize(0)
	legacy_last.opponent_player().active.damage = 80
	var legacy_result := KnockoutResolver.new(legacy_last.players, legacy_last.match_log).resolve(1 - legacy_taker, MatchRules.legacy(), -1)
	expect(legacy_result == legacy_taker, "legacy rules: the last Mercy Card wins at once")

	print("== Temmie, Workshop, Reckless Shatter, Bump, Close Tab, Click Here!")
	var g1_tem := battle("jevil", [], "guei")
	var g1_temmer := g1_tem.current_player()
	g1_temmer.hand.assign(cards(["temmie"]))
	var g1_tem_deck := g1_temmer.deck.size()
	expect(play(g1_tem, "Play Temmie (Lightner)") and g1_temmer.hand.size() == 3 and g1_temmer.deck.size() == g1_tem_deck - 3 and g1_temmer.discard.back().name == "Temmie",
			"Temmie: draw 3 cards")

	var g1_shop := battle("jevil", [], "guei")
	var g1_shopper := g1_shop.current_player()
	g1_shopper.tp = 4
	g1_shopper.hand.assign(cards(["workshop"]))
	g1_shopper.bench.append(in_play("cuptain", []))
	g1_shopper.bench.append(in_play("guei", ["holy_energy"]))
	g1_shopper.bench.append(in_play("hammer_of_justice", []))
	g1_shopper.discard.assign(cards(["holy_energy"]))
	expect(not has_label(g1_shop, "Cast Workshop (50% TP)"), "Workshop cannot be cast with no Darkner it may target: one has an Ability, one has Energy, one is an Evolution")
	g1_shopper.discard.clear()
	g1_shopper.bench.append(in_play("water_cooler", []))
	expect(not has_label(g1_shop, "Cast Workshop (50% TP)"), "nor without a Basic Energy in the discard pile")
	g1_shopper.discard.assign(cards(["holy_energy"]))
	expect(play(g1_shop, "Cast Workshop (50% TP)") and g1_shopper.bench[3].attached_energy.size() == 1 and g1_shopper.discard.size() == 1 and g1_shopper.discard[0].name == "Workshop" and g1_shopper.tp == 2,
			"the Energy goes to the only Darkner it may target, Water Cooler, for 50% TP")
	var g1_shop_two := battle("jevil", [], "guei")
	var g1_two_shopper := g1_shop_two.current_player()
	g1_two_shopper.tp = 4
	g1_two_shopper.hand.assign(cards(["workshop"]))
	g1_two_shopper.discard.assign(cards(["holy_energy"]))
	g1_two_shopper.bench.append_array([in_play("cuptain", []), in_play("water_cooler", []), in_play("dummy", [])])
	play(g1_shop_two, "Cast Workshop (50% TP)")
	var g1_shop_slots: Array = []
	for option in g1_shop_two.view_for(g1_shop_two.current_index).choice_options:
		g1_shop_slots.append(int((option as Dictionary)["value"]))
	expect(g1_shop_two.choice_kind() == PendingChoice.KIND_CHOOSE_DARKNER and g1_shop_slots == [1, 2], "with two it may target, the choice offers those two only (%s)" % [g1_shop_slots])

	var g1_shatter := battle("titan", ["darkness_energy", "darkness_energy"], "tenna")
	var g1_shatterer := g1_shatter.current_player()
	var g1_shattered := g1_shatter.opponent_player()
	var g1_own_top := g1_shatterer.deck.back() as CardData
	var g1_their_top: Array = [g1_shattered.deck[g1_shattered.deck.size() - 1], g1_shattered.deck[g1_shattered.deck.size() - 2]]
	attack(g1_shatter, "Reckless Shatter")
	expect(g1_shattered.active.damage == 80 and g1_shatterer.discard.has(g1_own_top) and g1_shattered.discard.has(g1_their_top[0]) and g1_shattered.discard.has(g1_their_top[1]) and g1_shattered.discard.size() == 2,
			"Reckless Shatter: 80 damage, the top card of its owner's deck discarded, then the top 2 of the opponent's")
	var g1_dry := battle("titan", ["darkness_energy", "darkness_energy"], "tenna")
	g1_dry.current_player().deck.clear()
	attack(g1_dry, "Reckless Shatter")
	expect(g1_dry.opponent_player().discard.is_empty(), "with nothing to discard from its own deck, the opponent discards nothing")

	var g1_bump := battle("titan_spawn", ["darkness_energy"], "jevil")
	var g1_bumper := g1_bump.current_index
	var g1_bumped := g1_bump.opponent_player()
	g1_bumped.bench.append_array([in_play("guei", []), in_play("tenna", [])])
	attack(g1_bump, "Bump")
	expect(g1_bump.choice_kind() == PendingChoice.KIND_CHOOSE_DARKNER and g1_bump.choice_chooser() == 1 - g1_bumper and g1_bump.choice_details()["side"] == PendingChoice.SIDE_OWN,
			"Bump: the opponent chooses their new Battling Darkner")
	g1_bump.apply({"type": "choose", "option": 1})
	expect(g1_bumped.active.card.name == "Tenna" and g1_bumped.bench.any(func(darkner: CardInPlay) -> bool: return darkner.card.name == "Jevil" and darkner.damage == 20)
			and g1_bump.current_index != g1_bumper, "after 20 damage, Jevil goes to the Field and Tenna comes in; then the turn passes")
	var g1_lone := battle("titan_spawn", ["darkness_energy"], "jevil")
	var g1_lone_turn := g1_lone.turn
	var g1_lone_side := g1_lone.opponent_player()
	attack(g1_lone, "Bump")
	expect(g1_lone_side.active.card.name == "Jevil" and g1_lone_side.active.damage == 20 and g1_lone.turn == g1_lone_turn + 1,
			"with nothing on their Field the Darkner stays and the turn passes")

	var g1_tab := battle("addison", ["chaos_energy", "chaos_energy", "chaos_energy"], "jevil")
	var g1_tabber := g1_tab.current_player()
	var g1_tab_index := g1_tab.current_index
	g1_tabber.bench.append_array([in_play("guei", []), in_play("tenna", [])])
	var g1_tab_cards := g1_tabber.deck.size()
	attack(g1_tab, "Close Tab")
	expect(g1_tab.opponent_player().active.damage == 50 and g1_tabber.active == null and g1_tabber.deck.size() == g1_tab_cards + 4 and g1_tab.players[1 - g1_tab_index].prizes.size() == 4,
			"Close Tab: 50 damage, then Addison and its 3 Energy go into the deck; no Mercy Card for it")
	expect(log_lines(g1_tab).has("  Addison goes back into the deck and 3 cards with it"), "the log says so (%s)" % [log_lines(g1_tab).slice(-4)])
	expect(g1_tab.choice_kind() == PendingChoice.KIND_PROMOTE and g1_tab.choice_chooser() == g1_tab_index, "its owner then chooses their new Battling Darkner, as after a knockout")
	play(g1_tab, "Promote Tenna (Field 2, 100/100 HP)")
	expect(g1_tabber.active.card.name == "Tenna" and g1_tab.current_index != g1_tab_index, "and the turn passes")
	var g1_tab_alone := battle("addison", ["chaos_energy", "chaos_energy", "chaos_energy"], "jevil")
	var g1_tab_alone_index := g1_tab_alone.current_index
	attack(g1_tab_alone, "Close Tab")
	expect(g1_tab_alone.winner == 1 - g1_tab_alone_index, "with an empty Field its owner has no Darkner in play and loses the round")

	var g1_click := battle("jevil", [], "guei")
	var g1_clicker := g1_click.current_player()
	g1_clicker.tp = 4
	g1_clicker.hand.assign(cards(["addison", "addison"]))
	g1_clicker.deck.assign(cards(["guei", "kris", "chaos_energy"]))
	play(g1_click, "Put Addison on the Field")
	expect(prompt_of(g1_click) == "Use Click Here!?", "Click Here!: its owner may use it when Addison is played (%s)" % prompt_of(g1_click))
	play(g1_click, "Use Click Here! (Addison)")
	var g1_click_labels := option_labels(g1_click)
	expect(g1_clicker.tp == 3 and g1_click_labels.has("Take Kris") and not g1_click_labels.has("Take Guei"), "it costs 25%% TP and searches the deck for a Lightner (%s)" % [g1_click_labels])
	pick(g1_click, "Take Kris")
	expect(g1_clicker.hand.any(func(card: CardData) -> bool: return card.name == "Kris"), "Kris goes to the hand")
	play(g1_click, "Put Addison on the Field")
	expect(not g1_click.is_waiting_for_choice() and g1_clicker.bench.size() == 2, "only 1 Click Here! per turn")
	var g1_broke := battle("jevil", [], "guei")
	g1_broke.current_player().tp = 0
	g1_broke.current_player().hand.assign(cards(["addison"]))
	play(g1_broke, "Put Addison on the Field")
	expect(not g1_broke.is_waiting_for_choice(), "without 25% TP it is not offered")

	print("== Showtime!, Captive Audience, Mewers Live, Cyber City, Second Sanctuary")
	var g2_show := battle("tenna", ["fun_energy", "fun_energy"], "titan")
	var g2_shower := g2_show.current_player()
	g2_shower.bench.append_array([in_play("koody", []), in_play("guei", [])])
	expect(not has_action(g2_show, "attack") and g2_show.attack_cost(g2_shower.active, g2_shower.active.attacks()[0]).size() == 3,
			"Showtime!: 1 Energy less for each Darkner on the Field, so 3 with two there; 2 Fun is not enough")
	g2_shower.bench.append(in_play("dummy", []))
	var g2_shown := g2_show.opponent_player()
	expect(g2_show.attack_cost(g2_shower.active, g2_shower.active.attacks()[0]) == ["Fun", "Fun"] and attack(g2_show, "Showtime!") and g2_shown.active.damage == 70,
			"with three it costs 2 Fun, and Tenna attacks for 70")

	var g2_captive := battle("tenna", [], "jevil")
	var g2_captor := g2_captive.current_player()
	g2_captor.hand.assign(cards(["guei", "miss_mizzle"]))
	g2_captor.bench.append(in_play("water_cooler", []))
	expect(not has_label(g2_captive, "Put Guei on the Field"), "Captive Audience: with Tenna in the Battle Zone no Basic Darkner goes onto the Field from the hand")
	g2_captive.apply({"type": "end_turn"})
	g2_captive.apply({"type": "end_turn"})
	expect(not has_label(g2_captive, "Put Guei on the Field") and has_action(g2_captive, "evolve"), "evolving still does, on a later turn")
	g2_captor.active = in_play("jevil", [])
	g2_captor.bench.append(in_play("tenna", []))
	expect(has_label(g2_captive, "Put Guei on the Field"), "with Tenna on the Field it does not apply")
	var g2_their := battle("jevil", [], "tenna")
	g2_their.current_player().hand.assign(cards(["guei"]))
	expect(has_label(g2_their, "Put Guei on the Field"), "nor to the opponent of Tenna's owner")
	var g2_setup := MatchEngine.new()
	g2_setup.effects = library
	g2_setup.start(deck({"tenna": 4, "guei": 4, "chaos_energy": 22}), deck({"tenna": 4, "guei": 4, "chaos_energy": 22}), rules, Rng.new(5))
	var g2_tenna_set := false
	var g2_setup_labels: Array[String] = []
	while g2_setup.is_waiting_for_choice() and g2_setup.turn == 0:
		var g2_options := option_labels(g2_setup)
		if g2_setup.choice_kind() == PendingChoice.KIND_BATTLING_DARKNER and g2_options.has("Make Tenna the Battling Darkner"):
			g2_tenna_set = true
			play(g2_setup, "Make Tenna the Battling Darkner")
			continue
		if g2_setup.choice_kind() == PendingChoice.KIND_SETUP_BENCH and g2_tenna_set and g2_setup_labels.is_empty():
			g2_setup_labels = g2_options
		var g2_pick := 0
		for g2_index in g2_options.size():
			if g2_options[g2_index].begins_with("Finish") or g2_options[g2_index].begins_with("Draw 0"):
				g2_pick = g2_index
		g2_setup.apply({"type": "choose", "option": g2_pick})
	expect(g2_tenna_set and g2_setup_labels.has("Put Guei on the Field"), "during setup Darkners go onto the Field as usual, Tenna or not (%s)" % [g2_setup_labels])

	var g2_mewers := battle("jevil", [], "guei")
	var g2_caster := g2_mewers.current_player()
	g2_caster.tp = 4
	g2_caster.hand.assign(cards(["rude_buster", "workshop"]))
	g2_mewers.opponent_player().active.attached_energy.append(db.make("holy_energy"))
	g2_caster.bench.append(in_play("dummy", []))
	g2_caster.discard.assign(cards(["chaos_energy"]))
	expect(has_label(g2_mewers, "Cast Rude Buster (25% TP)") and has_label(g2_mewers, "Cast Workshop (50% TP)"), "without Mewers Live: 25% and 50%")
	g2_mewers.stadium = db.make("mewers_live")
	g2_mewers.stadium_owner = 1 - g2_mewers.current_index
	expect(has_label(g2_mewers, "Cast Rude Buster (50% TP)") and has_label(g2_mewers, "Cast Workshop (75% TP)"), "Mewers Live: each costs 25% more, and says so")
	play(g2_mewers, "Cast Workshop (75% TP)")
	expect(g2_caster.tp == 1, "casting Workshop takes 75%")
	g2_caster.tp = 1
	expect(not has_action(g2_mewers, "play_trainer"), "Rude Buster cannot be cast with 25% left")

	var g2_cyber := battle("tenna", [], "jevil")
	var g2_cyber_side := g2_cyber.current_player()
	g2_cyber_side.bench.append(in_play("addison", []))
	expect(g2_cyber.retreat_cost(g2_cyber_side.active).size() == 2 and g2_cyber.retreat_cost(g2_cyber_side.bench[0]).size() == 1, "Flee costs as printed: Tenna 2, Addison 1")
	g2_cyber.stadium = db.make("cyber_city")
	g2_cyber.stadium_owner = g2_cyber.current_index
	expect(g2_cyber.retreat_cost(g2_cyber_side.active).size() == 3 and g2_cyber.retreat_cost(g2_cyber_side.bench[0]).size() == 1,
			"Cyber City: 1 more for Tenna, none more for Addison, an Electric Darkner")
	g2_cyber_side.active.attached_energy.assign(cards(["fun_energy", "fun_energy"]))
	expect(not has_action(g2_cyber, "retreat"), "so Tenna cannot flee with 2 Energy")

	var g2_swap := battle("jevil", ["chaos_energy"], "guei")
	var g2_swapped := g2_swap.opponent_player()
	g2_swap.stadium = db.make("second_sanctuary")
	g2_swap.stadium_owner = g2_swap.current_index
	g2_swapped.bench.append(in_play("balthizard", []))
	attack(g2_swap, "Slash")
	expect(g2_swapped.active.damage == 40, "Second Sanctuary: Guei resists Chaos, so Slash does 20 + 20 to it (%d)" % g2_swapped.active.damage)
	var g2_plain := battle("jevil", ["chaos_energy"], "guei")
	var g2_unswapped := g2_plain.opponent_player()
	attack(g2_plain, "Slash")
	expect(g2_unswapped.active.damage == 0, "without it, 20 - 20")
	var g2_bench_swap := battle("jevil", ["chaos_energy", "chaos_energy"], "koody")
	var g2_bench_side := g2_bench_swap.opponent_player()
	g2_bench_swap.stadium = db.make("second_sanctuary")
	g2_bench_swap.stadium_owner = g2_bench_swap.current_index
	g2_bench_side.bench.append(in_play("guei", []))
	attack(g2_bench_swap, "Chaos Bomb")
	expect(g2_bench_side.bench[0].damage == 20, "only Battling Darkners swap: Chaos Bomb's 20 on the Field are untouched")

	print("== Pure Darkness, Hazy Memory")
	var g3_titan := battle("titan_spawn", [], "jevil")
	var g3_titaner := g3_titan.current_player()
	g3_titaner.hand.assign(cards(["titan", "titan_spawn"]))
	g3_titaner.bench.append(in_play("titan_spawn", []))
	expect(not has_label(g3_titan, "Put Titan on the Field") and has_label(g3_titan, "Put Titan Spawn on the Field"), "Pure Darkness: with 2 Titan Spawn in play Titan cannot be played")
	play(g3_titan, "Put Titan Spawn on the Field")
	expect(play(g3_titan, "Put Titan on the Field") and g3_titaner.bench.back().card.name == "Titan", "with 3 in play, Battle Zone and Field together, it can")
	var g3_setup := MatchEngine.new()
	g3_setup.effects = library
	g3_setup.start(deck({"titan": 4, "titan_spawn": 4, "darkness_energy": 22}), deck({"titan": 4, "titan_spawn": 4, "darkness_energy": 22}), rules, Rng.new(9))
	var g3_never_first := true
	var g3_bench_ok := true
	while g3_setup.is_waiting_for_choice() and g3_setup.turn == 0:
		var g3_chooser := g3_setup.players[g3_setup.choice_chooser()]
		var g3_labels := option_labels(g3_setup)
		if g3_setup.choice_kind() == PendingChoice.KIND_BATTLING_DARKNER and g3_labels.has("Make Titan the Battling Darkner"):
			g3_never_first = false
		if g3_setup.choice_kind() == PendingChoice.KIND_SETUP_BENCH:
			var g3_spawns := ([g3_chooser.active] + g3_chooser.bench).filter(func(darkner: Variant) -> bool: return darkner != null and (darkner as CardInPlay).card.id == "titan_spawn").size()
			if g3_labels.has("Put Titan on the Field") != (g3_spawns >= 3 and g3_chooser.hand.any(func(card: CardData) -> bool: return card.id == "titan")):
				g3_bench_ok = false
		var g3_pick := 0
		for g3_index in g3_labels.size():
			if g3_labels[g3_index] == "Put Titan Spawn on the Field":
				g3_pick = g3_index
				break
			if g3_labels[g3_index].begins_with("Finish") or g3_labels[g3_index].begins_with("Draw 0"):
				g3_pick = g3_index
		g3_setup.apply({"type": "choose", "option": g3_pick})
	expect(g3_never_first, "Titan is never offered as the Battling Darkner at setup")
	expect(g3_bench_ok, "during setup it may go onto the Field only once 3 Titan Spawn are in play")
	var g3_mulligan := MatchEngine.new()
	g3_mulligan.effects = library
	g3_mulligan.start(deck({"titan": 4, "titan_spawn": 1, "darkness_energy": 25}), test_deck(), rules, Rng.new(4))
	var g3_mulligan_hand := g3_mulligan.players[0].hand
	expect(g3_mulligan_hand.any(func(card: CardData) -> bool: return card.id == "titan_spawn"), "a hand whose only Basic Darkners are Titans is a mulligan: the hand kept has the Titan Spawn")

	var g3_hazy := battle("jevil", ["chaos_energy"], "titan_spawn")
	var g3_hazy_owner := 1 - g3_hazy.current_index
	var g3_hazy_side := g3_hazy.opponent_player()
	g3_hazy_side.tp = 4
	g3_hazy_side.active.attached_energy.assign(cards(["darkness_energy"]))
	g3_hazy_side.active.damage = 50
	g3_hazy_side.bench.append_array([in_play("guei", []), in_play("koody", [])])
	g3_hazy.apply({"type": "attack", "attack_index": 0})
	expect(g3_hazy.choice_kind() == PendingChoice.KIND_USE_ABILITY and g3_hazy.choice_chooser() == g3_hazy_owner and prompt_of(g3_hazy) == "Use Hazy Memory?",
			"Hazy Memory: knocked out during the opponent's turn, its owner is asked (%s)" % prompt_of(g3_hazy))
	play(g3_hazy, "Use Hazy Memory (Titan Spawn)")
	expect(g3_hazy_side.hand.any(func(card: CardData) -> bool: return card.id == "titan_spawn") and g3_hazy_side.tp == 3 and g3_hazy_side.discard.size() == 1 and g3_hazy_side.discard[0].id == "darkness_energy",
			"for 25% TP Titan Spawn goes to the hand and its Energy to the discard pile")
	expect(g3_hazy.players[1 - g3_hazy_owner].prizes.size() == 3, "it is still a knockout: the attacker took a Mercy Card")
	expect(g3_hazy.choice_kind() == PendingChoice.KIND_PROMOTE and g3_hazy.choice_chooser() == g3_hazy_owner, "and its owner promotes a new Battling Darkner")
	var g3_hazy_lines := log_lines(g3_hazy)
	expect(g3_hazy_lines.has("Titan Spawn is knocked out") and g3_hazy_lines.has("  Titan Spawn goes back to its owner's hand; 1 attached card to the discard pile")
			and g3_hazy_lines.count("Titan Spawn is knocked out") == 1, "the log tells the knockout once, then where it went")
	var g3_declined := battle("jevil", ["chaos_energy"], "titan_spawn")
	var g3_declined_side := g3_declined.opponent_player()
	g3_declined_side.tp = 4
	g3_declined_side.active.damage = 50
	g3_declined_side.bench.append(in_play("guei", []))
	g3_declined.apply({"type": "attack", "attack_index": 0})
	play(g3_declined, "Don't use Hazy Memory")
	expect(g3_declined_side.discard.any(func(card: CardData) -> bool: return card.id == "titan_spawn") and g3_declined_side.tp == 4, "declined, it is discarded as usual")
	var g3_broke := battle("jevil", ["chaos_energy"], "titan_spawn")
	g3_broke.opponent_player().tp = 0
	g3_broke.opponent_player().active.damage = 50
	g3_broke.opponent_player().bench.append(in_play("guei", []))
	g3_broke.apply({"type": "attack", "attack_index": 0})
	expect(g3_broke.choice_kind() != PendingChoice.KIND_USE_ABILITY, "without 25% TP it is not offered")
	var g3_own := battle("titan_spawn", [], "jevil")
	var g3_own_side := g3_own.current_player()
	g3_own_side.tp = 4
	g3_own_side.active.damage = 70
	g3_own_side.bench.append(in_play("guei", []))
	g3_own_side.hand.assign(cards(["koody"]))
	play(g3_own, "Put Koody on the Field")
	expect(g3_own.choice_kind() != PendingChoice.KIND_USE_ABILITY and g3_own_side.discard.any(func(card: CardData) -> bool: return card.id == "titan_spawn"),
			"knocked out during its owner's own turn, it is not offered")

	print("== picking Mercy Cards")
	var mc_picked := battle("jevil", ["chaos_energy", "chaos_energy"], "koody")
	var mc_picker := mc_picked.current_index
	var mc_picker_turn := mc_picked.turn
	mc_picked.opponent_player().bench.append(in_play("guei", []))
	mc_picked.opponent_player().bench.append(in_play("tenna", []))
	mc_picked.opponent_player().active.damage = 20
	mc_picked.apply({"type": "attack", "attack_index": 0})
	expect(mc_picked.choice_kind() == PendingChoice.KIND_TAKE_PRIZE and mc_picked.choice_chooser() == mc_picker and mc_picked.players[mc_picker].prizes.size() == 4
			and mc_picked.current_index == mc_picker and mc_picked.turn == mc_picker_turn, "a knockout does not take a Mercy Card by itself: its taker picks one, before the turn ends")
	expect(option_labels(mc_picked) == ["Take Mercy Card #1", "Take Mercy Card #2", "Take Mercy Card #3", "Take Mercy Card #4"]
			and ActionText.prompt(mc_picked.view_for(mc_picker), db) == "Take a Mercy Card", "one option per face-down card, by position (%s)" % [option_labels(mc_picked)])
	var mc_watcher_view := mc_picked.view_for(1 - mc_picker)
	expect(mc_watcher_view.choice_kind == PendingChoice.KIND_TAKE_PRIZE and mc_watcher_view.choice_options.is_empty()
			and mc_picked.view_for(mc_picker).choice_options.all(func(option: Dictionary) -> bool: return not option.has("shows")),
			"the opponent sees the pick is open; no option shows a card")
	var mc_third: CardData = mc_picked.players[mc_picker].prizes[2]
	var mc_before_pick := mc_picked.match_log.entries.size()
	play(mc_picked, "Take Mercy Card #3")
	var mc_pick_events := mc_picked.events_for(mc_picker, mc_before_pick).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.PRIZE_TAKEN)
	expect(mc_picked.players[mc_picker].hand.has(mc_third) and not mc_picked.players[mc_picker].prizes.has(mc_third) and mc_picked.players[mc_picker].prizes.size() == 3,
			"Take Mercy Card #3 puts that card in the hand")
	expect(mc_pick_events.size() == 1 and int((mc_pick_events[0] as MatchEvent).data["slot"]) == 2 and (mc_pick_events[0] as MatchEvent).data["card"] == mc_third.id,
			"the event says which position it came from")
	expect(mc_picked.choice_kind() == PendingChoice.KIND_PROMOTE and mc_picked.choice_chooser() == 1 - mc_picker, "then the opponent promotes, as before")

	var mc_two_picks := battle("jevil", ["chaos_energy", "chaos_energy"], "guei")
	var mc_two_picker := mc_two_picks.current_index
	for id in ["koody", "koody"]:
		mc_two_picks.opponent_player().bench.append(in_play(id, []))
		mc_two_picks.opponent_player().bench.back().damage = 30
	mc_two_picks.apply({"type": "attack", "attack_index": 1})
	expect(mc_two_picks.choice_kind() == PendingChoice.KIND_TAKE_PRIZE and ActionText.prompt(mc_two_picks.view_for(mc_two_picker), db) == "Take a Mercy Card (2 to take)",
			"two knockouts at once: two picks, the prompt counts them")
	mc_two_picks.apply({"type": "choose", "option": 0})
	expect(mc_two_picks.choice_kind() == PendingChoice.KIND_TAKE_PRIZE and option_labels(mc_two_picks).size() == 3 and ActionText.prompt(mc_two_picks.view_for(mc_two_picker), db) == "Take a Mercy Card",
			"then one more, from the three left")
	mc_two_picks.apply({"type": "choose", "option": 2})
	expect(mc_two_picks.players[mc_two_picker].prizes.size() == 2 and not mc_two_picks.is_waiting_for_choice() and mc_two_picks.current_index != mc_two_picker,
			"after the last pick the turn ends as usual")

	var mc_last_pick := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
	var mc_last_picker := mc_last_pick.current_index
	mc_last_pick.opponent_player().bench.append(in_play("guei", []))
	while mc_last_pick.players[mc_last_picker].prizes.size() > 1:
		mc_last_pick.players[mc_last_picker].prizes.pop_back()
	mc_last_pick.apply({"type": "attack", "attack_index": 0})
	expect(mc_last_pick.choice_kind() == PendingChoice.KIND_TAKE_PRIZE and option_labels(mc_last_pick) == ["Take Mercy Card #1"], "the last Mercy Card is mc_picked too")
	play(mc_last_pick, "Take Mercy Card #1")
	expect(mc_last_pick.choice_kind() == PendingChoice.KIND_SPARE_FIGHT, "and only then come Spare or Fight")

	var mc_auto_round := battle("jevil", ["chaos_energy"], "koody")
	mc_auto_round.rules.choose_prizes = false
	var mc_auto_taker := mc_auto_round.current_index
	var mc_top: CardData = mc_auto_round.players[mc_auto_taker].prizes.back()
	mc_auto_round.opponent_player().bench.append(in_play("guei", []))
	mc_auto_round.opponent_player().active.damage = 20
	mc_auto_round.apply({"type": "attack", "attack_index": 0})
	expect(mc_auto_round.choice_kind() != PendingChoice.KIND_TAKE_PRIZE and mc_auto_round.players[mc_auto_taker].hand.has(mc_top) and mc_auto_round.players[mc_auto_taker].prizes.size() == 3,
			"without choose_prizes (legacy rules, older replays) the mc_top card is taken at once")
	expect(not MatchRules.legacy().choose_prizes and MatchRules.deltarune().choose_prizes, "Deltarune rules pick; legacy rules do not")

	print("== extra cards after a Spare")
	var extra_rules := MatchRules.deltarune()
	var extra_round := start_round(extra_rules, 3)
	extra_round.rules.first_turn_extra_draws = [3, 0]
	finish_setup(extra_round)
	var extra_first := extra_round.current_index
	var extra_draws := extra_round.events_for(0, 0).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.DREW and bool(event.data["extra"]))
	expect(extra_draws.size() == (1 if extra_first == 0 else 0), "player 1 draws their extra cards at the start of their first turn, not before")
	if extra_first != 0:
		extra_round.apply({"type": "end_turn", "label": "End turn"})
		extra_draws = extra_round.events_for(0, 0).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.DREW and bool(event.data["extra"]))
	expect(extra_draws.size() == 1 and int((extra_draws[0] as MatchEvent).data["count"]) == 3 and ((extra_draws[0] as MatchEvent).data["cards"] as Array).size() == 3,
			"three extra cards, after the turn's draw")
	expect(log_lines(extra_round).has("Player 1 draws 3 extra cards"), "the log says so")
	var hidden_extra := extra_round.events_for(1, 0).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.DREW and bool(event.data["extra"]))
	expect(hidden_extra.size() == 1 and not (hidden_extra[0] as MatchEvent).data.has("cards"), "the opponent sees how many, not which")
	extra_round.apply({"type": "end_turn", "label": "End turn"})
	extra_round.apply({"type": "end_turn", "label": "End turn"})
	var later_extra := extra_round.events_for(0, 0).filter(func(event: MatchEvent) -> bool: return event.type == MatchEvent.DREW and bool(event.data["extra"]))
	expect(later_extra.size() == 1, "only on the first turn")
	var old_rules := MatchRules.deltarune().to_dict()
	for added in ["spare_fight", "spare_extra_draws", "first_turn_extra_draws", "match_point", "choose_prizes"]:
		old_rules.erase(added)
	var read_old := MatchRules.from_dict(old_rules)
	expect(read_old != null and not read_old.spare_fight and read_old.first_turn_extra_draws == [0, 0] and read_old.match_point == [false, false] and not read_old.choose_prizes,
			"rules recorded before Spare and Fight read back without them, so old replays play as they were played")

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
	var replay_mismatch := ""
	var code_mismatch := ""
	var action_types := {}
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
			var actions := labeled(game)
			if repeated.is_empty() and not labels_distinct(actions):
				repeated = "seed %d, turn %d: %s" % [seed, game.turn, actions]
			game.apply(actions[picker.randi_range(0, actions.size() - 1)])
		var from_text := MatchReplay.from_text(game.replay().to_text())
		var replayed := from_text.play(db, library)
		if replay_mismatch.is_empty() and (log_lines(replayed) != log_lines(game) or replayed.turn != game.turn or replayed.winner != game.winner
				or replayed.replay().actions.size() != game.replay().actions.size()):
			replay_mismatch = "seed %d" % seed
		var from_code := MatchReplay.from_text(game.replay().to_code())
		if code_mismatch.is_empty() and (from_code == null or from_code.to_text() != game.replay().to_text() or from_text.to_text() != game.replay().to_text()):
			code_mismatch = "seed %d" % seed
		for action in game.replay().actions:
			action_types[action["type"]] = true
	expect(repeated.is_empty(), "no two legal actions share a label: %s" % repeated)
	expect(replay_mismatch.is_empty(), "every random round, written as text and played again, gives the same log, turn and winner: %s" % replay_mismatch)
	expect(code_mismatch.is_empty(), "and written as text or as a code it reads back as the same replay: %s" % code_mismatch)
	var untokened := action_types.keys().filter(func(type: Variant) -> bool: return not MatchReplay.TOKENS.has(type))
	expect(untokened.is_empty() and action_types.size() == MatchReplay.TOKENS.size(), "random play used every action type, and each has a token (%s; missing %s)" % [action_types.keys(), untokened])
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