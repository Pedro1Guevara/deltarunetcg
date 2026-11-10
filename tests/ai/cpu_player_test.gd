## Headless checks for the CPU opponent (Design Document 8.7). Run from the project root:
##   godot --headless --path . --script res://tests/ai/cpu_player_test.gd
## Exits with code 0 when every check passes.
extends TestCase

const SEEDS := 10
const MAX_STEPS := 3000
const DECK_PAIRS := [["creative", "holy"], ["chaos", "holy"], ["creative", "chaos"], ["deltarune_chaos", "deltarune_holy"]]
## The deck both players use in the scenarios below.
const TEST_DECK := {"jevil": 4, "tenna": 4, "guei": 4, "chaos_energy": 18}

var library: EffectLibrary
var decks: Dictionary
## One CPU per seat in the rounds below; each remembers what it saw.
var cpus: Array[CpuPlayer] = []


func start_round(seed: int) -> MatchEngine:
	var engine := MatchEngine.new()
	engine.effects = library
	engine.start(db.build_deck({"cards": TEST_DECK}), db.build_deck({"cards": TEST_DECK}), MatchRules.deltarune(), Rng.new(seed))
	return engine


func test_cpus() -> void:
	cpus.assign([CpuPlayer.new(library, db.build_deck({"cards": TEST_DECK}), {}), CpuPlayer.new(library, db.build_deck({"cards": TEST_DECK}), {})])


## Lets the CPU answer every setup question for both players.
func finish_setup(engine: MatchEngine) -> void:
	while engine.turn == 0 and engine.is_waiting_for_choice():
		engine.apply(cpus[engine.choice_chooser()].choose(engine.view_for(engine.choice_chooser())))


## A round on turn 2 with the given Darkners in the Battle Zones, nothing on either Field and
## nothing in the hand of the player to act. Fresh CPUs too, so nothing one scenario
## remembers carries into the next.
func battle(attacker_id: String, attached: Array, defender_id: String) -> MatchEngine:
	test_cpus()
	var engine := start_round(1)
	finish_setup(engine)
	engine.apply({"type": "end_turn"})
	var player := engine.current_player()
	var opponent := engine.opponent_player()
	player.bench.clear()
	opponent.bench.clear()
	player.hand.clear()
	player.active = in_play(attacker_id, attached)
	opponent.active = in_play(defender_id, [])
	return engine


## Lets the CPU of the player who picks take every open Mercy Card pick.
func take_mercy_cards(engine: MatchEngine) -> void:
	while engine.is_waiting_for_choice() and engine.choice_kind() == PendingChoice.KIND_TAKE_PRIZE:
		engine.apply(decide(engine))


func decide(engine: MatchEngine) -> Dictionary:
	var actor := engine.choice_chooser() if engine.is_waiting_for_choice() else engine.current_index
	return cpus[actor].choose(engine.view_for(actor))


func decide_with(engine: MatchEngine, player: CpuPlayer) -> Dictionary:
	var actor := engine.choice_chooser() if engine.is_waiting_for_choice() else engine.current_index
	return player.choose(engine.view_for(actor))


## Every card a player owns, wherever it is: the decklist a CPU knows.
func owned(player: PlayerState) -> Array[CardData]:
	var all: Array[CardData] = []
	all.append_array(player.hand)
	all.append_array(player.deck)
	all.append_array(player.prizes)
	all.append_array(player.discard)
	for darkner in ([player.active] if player.active != null else []) + player.bench:
		all.append((darkner as CardInPlay).card)
		all.append_array((darkner as CardInPlay).evolved_from)
		all.append_array((darkner as CardInPlay).attached_energy)
	return all


func deck_cards(id: String) -> Array[CardData]:
	return db.build_deck(decks[id] as Dictionary)


func plan_data(id: String) -> Dictionary:
	return (decks[id] as Dictionary).get("plan", {}) as Dictionary


func side(active: CardInPlay, bench: Array) -> PlayerView.SideView:
	var built := PlayerView.SideView.new()
	built.active = active
	for darkner: CardInPlay in bench:
		built.bench.append(darkner)
	return built


func _run() -> void:
	db = DataLoader.load_card_database()
	library = DataLoader.load_effect_library(db, DataLoader.CARD_EFFECTS_PATH)
	decks = DataLoader.read_json(DataLoader.DECKS_PATH) as Dictionary
	test_cpus()
	var reader := EffectReader.new(library)

	print("== CPU against CPU")
	var illegal := ""
	var undone := ""
	var finished := 0
	var wins := [0, 0]
	var longest := 0
	var answers := {PendingChoice.SPARE: 0, PendingChoice.FIGHT: 0}
	for pair: Array in DECK_PAIRS:
		for seed in SEEDS:
			var engine := MatchEngine.new()
			engine.effects = library
			engine.start(deck_cards(pair[0]), deck_cards(pair[1]), MatchRules.deltarune(), Rng.new(seed))
			cpus.assign([CpuPlayer.new(library, deck_cards(pair[0]), plan_data(pair[0])), CpuPlayer.new(library, deck_cards(pair[1]), plan_data(pair[1]))])
			for step in MAX_STEPS:
				if engine.is_over():
					finished += 1
					if engine.winner >= 0:
						wins[engine.winner] += 1
					longest = maxi(longest, engine.turn)
					break
				var action := decide(engine)
				if not engine.is_legal(action):
					illegal = "%s seed %d step %d: %s" % [pair, seed, step, action]
					break
				if action["type"] == "choose" and engine.choice_option(int(action["option"])).get("pick") == PendingChoice.PICK_UNDO:
					undone = "%s seed %d step %d" % [pair, seed, step]
				if engine.choice_kind() == PendingChoice.KIND_SPARE_FIGHT:
					answers[engine.choice_option(int(action["option"]))["value"]] += 1
				engine.apply(action)
	var rounds := DECK_PAIRS.size() * SEEDS
	expect(illegal.is_empty(), "the CPU only answers with legal actions: %s" % illegal)
	expect(undone.is_empty(), "and never undoes a pick: %s" % undone)
	expect(finished == rounds, "CPU against CPU finishes every round (%d of %d; wins %s; longest %d turns; Spare %d, Fight %d)" % [finished, rounds, wins, longest,
			int(answers[PendingChoice.SPARE]), int(answers[PendingChoice.FIGHT])])

	print("== CPU against CPU in combats")
	var combats_over := 0
	var combat_rounds: Array = []
	var combat_mismatch := ""
	for pair: Array in DECK_PAIRS:
		var ids: Array[PackedStringArray] = []
		for deck_id: String in pair:
			var listed := PackedStringArray()
			for card in deck_cards(deck_id):
				listed.append(card.id)
			ids.append(listed)
		var combat := Combat.new(db, library, ids[0], ids[1], MatchRules.deltarune(), 11)
		combat.start()
		for game_index in 8:
			cpus.assign([CpuPlayer.new(library, combat.decklist(0), plan_data(pair[0])), CpuPlayer.new(library, combat.decklist(1), plan_data(pair[1]))])
			for step in MAX_STEPS:
				if combat.is_game_over():
					break
				combat.engine.apply(decide(combat.engine))
			if not combat.next_game():
				break
		if combat.is_over():
			combats_over += 1
		combat_rounds.append(combat.round_number)
		var record := combat.replay()
		for written in [record.to_text(), record.to_code()]:
			var replayed := CombatReplay.from_text(str(written)).play(db, library)
			var same := replayed.score() == combat.score() and replayed.round_number == combat.round_number and replayed.games.size() == combat.games.size() \
					and log_lines(replayed.engine) == log_lines(combat.engine)
			for index in combat.games.size():
				same = same and int(replayed.games[index]["winner"]) == int(combat.games[index]["winner"]) \
						and (replayed.games[index]["replay"] as MatchReplay).to_text() == (combat.games[index]["replay"] as MatchReplay).to_text()
			if combat_mismatch.is_empty() and not same:
				combat_mismatch = "%s" % [pair]
	expect(combats_over == DECK_PAIRS.size(), "every CPU combat ends with a player on 2 rounds won (%d of %d; rounds played %s)" % [combats_over, DECK_PAIRS.size(), combat_rounds])
	expect(combat_mismatch.is_empty(), "and its replay, as text or as a code, plays again as the same combat, game by game: %s" % combat_mismatch)

	print("== the CPU decides from its view")
	var waiting := start_round(2)
	var other := 1 - waiting.choice_chooser()
	expect(cpus[other].choose(waiting.view_for(other)).is_empty(), "a player who is not to act gets no action")

	print("== damage after effects")
	var jevil := in_play("jevil", ["chaos_energy", "chaos_energy"])
	var chaos_bomb := jevil.attacks()[1]
	var three_on_field := side(in_play("koody", []), [in_play("koody", []), in_play("koody", []), in_play("koody", [])])
	var alone := reader.estimate_attack(jevil, chaos_bomb, side(jevil, []), three_on_field)
	expect(is_equal_approx(float(alone["total"]), 60.0) and is_equal_approx(float(alone["active"]), 0.0), "Chaos Bomb: 20 to each of 3 Darkners on the Field, none to the Battling one (%s)" % alone)
	var dashers := [in_play("electro_dasher", []), in_play("electro_dasher", []), in_play("electro_dasher", []), in_play("electro_dasher", [])]
	var stampede := reader.estimate_attack(jevil, chaos_bomb, side(jevil, dashers), three_on_field)
	expect(is_equal_approx(float(stampede["bench_each"]), 40.0) and is_equal_approx(float(stampede["total"]), 120.0),
			"with 4 Electro-Dasher on the Field, each flips for 1 counter on every Darkner it damaged: 40 each, 120 in all (%s)" % stampede)
	var vowed := side(in_play("miss_mizzle", []), [in_play("koody", []), in_play("koody", [])])
	vowed.active.evolved_from.assign(cards(["water_cooler"]))
	expect(is_equal_approx(float(reader.estimate_attack(jevil, chaos_bomb, side(jevil, dashers), vowed)["total"]), 0.0), "Vow of Majesty in the opponent's Battle Zone makes Chaos Bomb worth nothing")
	var hammer := in_play("old_man", ["creative_energy", "creative_energy", "creative_energy"])
	hammer.evolve(db.make("hammer_of_justice"), 0)
	var legacy := hammer.attacks().filter(func(attack: AttackData) -> bool: return attack.name == "Colourful Legacy")[0] as AttackData
	var mixed_field := side(hammer, [in_play("koody", []), in_play("dummy", []), in_play("balthizard", []), in_play("old_man", [])])
	var same_field := side(hammer, [in_play("old_man", []), in_play("old_man", [])])
	var target := side(in_play("tenna", []), [])
	expect(is_equal_approx(float(reader.estimate_attack(hammer, legacy, mixed_field, target)["active"]), 90.0)
			and is_equal_approx(float(reader.estimate_attack(hammer, legacy, same_field, target)["active"]), 30.0),
			"Colourful Legacy grows with the types on the Field: 90 with four types, 30 with one")
	var overrun := in_play("cuptain", ["holy_energy"])
	var crew := side(overrun, [in_play("cuptain", []), in_play("cuptain", [])])
	expect(is_equal_approx(float(reader.estimate_attack(overrun, overrun.attacks()[0], crew, target)["active"]), 30.0), "Overrun counts the Cuptain in play: 30 with three")
	var lunge := in_play("koody", ["chaos_energy"])
	expect(is_equal_approx(float(reader.estimate_attack(lunge, lunge.attacks()[0], side(lunge, []), target)["active"]), 15.0), "a coin flip counts at its expected value: Lunge 30 on heads is worth 15")

	print("== deck plans")
	var creative_plan := DeckPlan.build(deck_cards("creative"), reader, 4, {})
	var creative_types := {}
	for line: Array in creative_plan.field_lines:
		for type in db.make(line[line.size() - 1]).types:
			creative_types[type] = true
	expect(creative_plan.source == DeckPlan.SOURCE_AUTOMATIC and creative_plan.attacker_line == ["old_man", "hammer_of_justice"] and creative_plan.attack_name == "Colourful Legacy"
			and creative_types.size() == 4,
			"Creative, automatic: Hammer of Justice with Colourful Legacy, and a Field of four types (%s %s, %s)" % [creative_plan.attacker_line, creative_plan.attack_name, creative_plan.field_lines])
	var chaos_auto := DeckPlan.build(deck_cards("chaos"), reader, 4, {})
	expect(chaos_auto.attacker_line == ["jevil"] and chaos_auto.attack_name == "Chaos Bomb" and chaos_auto.field_lines == [["electro_dasher"], ["electro_dasher"], ["electro_dasher"], ["electro_dasher"]],
			"Chaos, automatic: Jevil's Chaos Bomb with every Electro-Dasher on the Field (%s %s, %s; %.0f damage)" % [chaos_auto.attacker_line, chaos_auto.attack_name, chaos_auto.field_lines, chaos_auto.expected_damage])
	var chaos_written := DeckPlan.build(deck_cards("chaos"), reader, 4, plan_data("chaos"))
	expect(chaos_written.source == DeckPlan.SOURCE_PREDEFINED and chaos_written.attack_name == "Chaos Bomb" and chaos_written.field_lines.size() == 4 and is_equal_approx(chaos_written.expected_damage, 120.0),
			"Chaos, written in decks.json: the same board, read as a predefined plan (%.0f damage)" % chaos_written.expected_damage)
	var broken := DeckPlan.build(deck_cards("chaos"), reader, 4, {"battle_zone": "tenna", "attack": "Chaos Bomb", "field": []})
	expect(broken.source == DeckPlan.SOURCE_AUTOMATIC and not broken.warnings.is_empty(), "a written plan naming a Darkner the deck lacks gives way to the automatic one (%s)" % [broken.warnings])
	var incomplete := DeckPlan.build(deck_cards("chaos"), reader, 4, {"battle_zone": "jevil", "attack": "Chaos Bomb"})
	expect(incomplete.source == DeckPlan.SOURCE_AUTOMATIC and incomplete.warnings == ["plan has no 'field'"], "and so does one missing a key: nothing is assumed")
	var holy_plan := DeckPlan.build(deck_cards("holy"), reader, 4, {})
	expect(holy_plan.attacker_line == ["guei"] and holy_plan.attack_name == "Flash Melt", "Holy, automatic: Guei's Flash Melt (%s %s)" % [holy_plan.attacker_line, holy_plan.attack_name])
	expect(holy_plan.energy_goal == 5 and creative_plan.energy_goal == 3 and chaos_written.energy_goal == 2,
			"the Energy the attacker wants: 5 for Flash Melt, whose 80 more comes with 5 Energy; the cost for the others (%d, %d, %d)" % [holy_plan.energy_goal, creative_plan.energy_goal, chaos_written.energy_goal])
	expect(holy_plan.support_line == ["water_cooler", "miss_mizzle"] and creative_plan.support_line == ["dummy"] and chaos_written.support_line.is_empty(),
			"the support, automatic: Miss Mizzle for Holy (protects and heals the Field, where Selfless Devotion feeds Guei), Dummy for Creative (Helpful Training feeds the Field), none for Chaos (%s, %s, %s)" % [holy_plan.support_line, creative_plan.support_line, chaos_written.support_line])
	var holy_written := DeckPlan.build(deck_cards("holy"), reader, 4, plan_data("holy"))
	expect(holy_written.source == DeckPlan.SOURCE_PREDEFINED and holy_written.support_line == ["water_cooler", "miss_mizzle"],
			"Holy, written in decks.json: Guei's Flash Melt with Miss Mizzle as the support (%s)" % [holy_written.support_line])
	var off_field := DeckPlan.build(deck_cards("holy"), reader, 4, {"battle_zone": "guei", "attack": "Flash Melt", "field": ["cuptain", "cuptain"], "support": "miss_mizzle"})
	expect(off_field.source == DeckPlan.SOURCE_AUTOMATIC and off_field.warnings == ["plan support 'miss_mizzle' is not one of the plan's field"],
			"a written support that is not on the plan's Field gives way to the automatic plan (%s)" % [off_field.warnings])

	var view_round := battle("jevil", [], "tenna")
	var missing := chaos_written.missing(view_round.view_for(view_round.current_index).me())
	expect(missing == {"electro_dasher": 4}, "what the plan lacks: Jevil is in play, the four Electro-Dasher are not (%s)" % missing)

	print("== turn priorities")
	var bencher := battle("jevil", ["chaos_energy"], "tenna")
	bencher.current_player().hand.assign(cards(["chaos_energy", "guei"]))
	expect(decide(bencher)["type"] == "bench", "a Basic Darkner goes on the Field first")

	var attacher := battle("guei", [], "tenna")
	attacher.current_player().bench.append(in_play("jevil", ["chaos_energy"]))
	attacher.current_player().hand.assign(cards(["holy_energy"]))
	var attach := decide(attacher)
	expect(attach["type"] == "attach" and int(attach["slot"]) == 0, "Energy goes to the plan's attacker while its attack is not paid: Jevil on the Field, for Chaos Bomb (%s)" % attach)
	attacher.current_player().active.attached_energy.assign(cards(["holy_energy"]))
	attacher.current_player().hand.assign(cards(["chaos_energy"]))
	var enabling := decide(attacher)
	expect(enabling["type"] == "attach" and int(enabling["slot"]) == -1, "above all to the Battle Zone when it lets that Darkner attack (%s)" % enabling)
	attacher.current_player().active.attached_energy.assign(cards(["holy_energy", "holy_energy"]))
	attacher.current_player().bench[0].attached_energy.clear()
	var benched := decide(attacher)
	expect(benched["type"] == "attach" and int(benched["slot"]) == 0, "and to the Field when the Battling Darkner can already pay for everything (%s)" % benched)
	var useless := battle("tenna", [], "guei")
	useless.current_player().bench.append(in_play("jevil", []))
	useless.current_player().hand.assign(cards(["chaos_energy"]))
	var off_type := decide(useless)
	expect(off_type["type"] == "attach" and int(off_type["slot"]) == 0, "Chaos Energy is not given to Tenna, whose attack needs Fun (%s)" % off_type)

	var striker := battle("jevil", ["chaos_energy", "chaos_energy"], "koody")
	expect(decide(striker) == {"type": "attack", "attack_index": 0},
			"Slash (20) is chosen over Chaos Bomb (0)")
	var finisher := battle("guei", ["holy_energy", "holy_energy"], "koody")
	finisher.opponent_player().active.damage = 10
	expect(decide(finisher)["type"] == "attack", "an attack that knocks out is taken")
	var idle := battle("koody", [], "tenna")
	expect(decide(idle)["type"] == "end_turn", "with nothing to do, the turn ends")

	var fleer := battle("tenna", ["chaos_energy", "chaos_energy"], "koody")
	fleer.current_player().bench.append(in_play("jevil", ["chaos_energy"]))
	fleer.current_player().energy_attached_this_turn = true
	expect(decide(fleer)["type"] == "retreat", "a Battling Darkner far from attacking flees to one that can (Tenna, 3 Energy short)")
	var stranded := battle("guei", ["chaos_energy", "chaos_energy"], "koody")
	stranded.current_player().bench.append(in_play("jevil", ["chaos_energy"]))
	stranded.current_player().energy_attached_this_turn = true
	expect(decide(stranded)["type"] == "retreat",
			"Energy of a type its deck never gives is not almost an attack: Guei, with 2 Chaos Energy for Flash Melt (Holy), flees")
	var resisted := battle("tenna", ["chaos_energy", "chaos_energy"], "guei")
	resisted.current_player().bench.append(in_play("jevil", ["chaos_energy"]))
	resisted.current_player().energy_attached_this_turn = true
	expect(decide(resisted)["type"] == "end_turn", "it does not flee to a Darkner whose attack would do nothing: Slash against Guei, which resists Chaos")
	var empty_training := battle("dummy", ["chaos_energy"], "koody")
	empty_training.current_player().bench.append(in_play("jevil", []))
	expect(decide(empty_training)["type"] == "end_turn",
			"an attack that would do nothing is not used, the turn ends instead: Helpful Training with no Energy in hand")
	empty_training.current_player().hand.assign(cards(["chaos_energy"]))
	empty_training.current_player().energy_attached_this_turn = true
	expect(decide(empty_training) == {"type": "attack", "attack_index": 0}, "with an Energy in hand to attach, Helpful Training is used")
	print("== the support")
	var support_cpu := CpuPlayer.new(library, deck_cards("holy"), plan_data("holy"))
	var to_charge := battle("guei", ["holy_energy", "holy_energy"], "jevil")
	var mizzle := in_play("water_cooler", ["holy_energy"])
	mizzle.evolve(db.make("miss_mizzle"), 0)
	to_charge.current_player().bench.append_array([in_play("cuptain", []), mizzle])
	to_charge.current_player().energy_attached_this_turn = true
	expect(decide_with(to_charge, support_cpu) == {"type": "retreat", "slot": 1},
			"Guei, charging (2 of 5 Energy) and with no knockout this turn, flees to Miss Mizzle to charge on the Field")
	support_cpu = CpuPlayer.new(library, deck_cards("holy"), plan_data("holy"))
	var feeding := battle("water_cooler", [], "jevil")
	feeding.current_player().active.evolve(db.make("miss_mizzle"), 0)
	feeding.current_player().bench.append(in_play("guei", ["holy_energy", "holy_energy"]))
	feeding.current_player().hand.assign(cards(["holy_energy"]))
	expect(decide_with(feeding, support_cpu) == {"type": "attach", "hand_index": 0, "slot": -1},
			"while Guei charges, the Energy goes first to Miss Mizzle, battling, so she can attack and heal the Field")
	support_cpu = CpuPlayer.new(library, deck_cards("holy"), plan_data("holy"))
	var charged := battle("water_cooler", ["holy_energy", "holy_energy"], "jevil")
	charged.current_player().active.evolve(db.make("miss_mizzle"), 0)
	charged.current_player().bench.append_array([in_play("cuptain", []), in_play("guei", ["holy_energy", "holy_energy", "holy_energy", "holy_energy", "holy_energy"])])
	charged.current_player().energy_attached_this_turn = true
	expect(decide_with(charged, support_cpu) == {"type": "retreat", "slot": 1}, "once Guei has its 5 Energy, Miss Mizzle flees for it")

	print("== Holy against Chaos")
	support_cpu = CpuPlayer.new(library, deck_cards("holy"), plan_data("holy"))
	var gust := battle("guei", ["holy_energy", "holy_energy"], "jevil")
	var hurt := in_play("electro_dasher", [])
	hurt.damage = 30
	gust.opponent_player().bench.append_array([in_play("electro_dasher", []), hurt])
	gust.current_player().hand.assign(cards(["susie"]))
	gust.current_player().energy_attached_this_turn = true
	var play_susie := decide_with(gust, support_cpu)
	expect(play_susie["type"] == "play_trainer", "Susie is played when Flash Melt can knock out a Darkner of the opponent's Field once it is switched in (%s)" % play_susie)
	gust.apply(play_susie)
	var pulled := decide_with(gust, support_cpu)
	expect(pulled["type"] == "choose" and gust.view_for(gust.current_index).choice_options[int(pulled["option"])]["shows"].damage == 30,
			"and it switches in the Electro-Dasher with 30 HP left, the one Flash Melt knocks out")
	support_cpu = CpuPlayer.new(library, deck_cards("holy"), plan_data("holy"))
	var exposed := battle("guei", ["holy_energy"], "jevil")
	exposed.opponent_player().active.attached_energy.assign(cards(["chaos_energy", "chaos_energy"]))
	exposed.current_player().bench.append(in_play("cuptain", []))
	exposed.current_player().discard.assign(cards(["holy_energy"]))
	exposed.current_player().energy_attached_this_turn = true
	var devotion := exposed.view_for(exposed.current_index).legal_actions.filter(func(action: Dictionary) -> bool: return action["type"] == "use_power")
	expect(not devotion.is_empty() and decide_with(exposed, support_cpu)["type"] != "use_power",
			"with no Miss Mizzle battling, Selfless Devotion is not used: it would leave Cuptain at 20 HP, which Chaos Bomb knocks out")
	exposed.current_player().active = in_play("water_cooler", ["holy_energy"])
	exposed.current_player().active.evolve(db.make("miss_mizzle"), 0)
	exposed.current_player().bench.append(in_play("guei", []))
	support_cpu = CpuPlayer.new(library, deck_cards("holy"), plan_data("holy"))
	var feed := decide_with(exposed, support_cpu)
	expect(feed["type"] == "use_power", "with Miss Mizzle battling, Selfless Devotion is used to charge Guei on the Field (%s)" % feed)
	exposed.apply(feed)
	var fed_darkner := decide_with(exposed, support_cpu)
	expect(exposed.view_for(exposed.current_index).choice_options[int(fed_darkner["option"])]["shows"].card.id == "guei", "and its Energy goes to Guei, not to Cuptain")

	var lunger := battle("koody", ["chaos_energy"], "cuptain")
	var lunge_view := lunger.view_for(lunger.current_index)
	var lunge_estimate := EffectReader.new(library).estimate_attack(lunge_view.me().active, lunge_view.me().active.attacks()[0], lunge_view.me(), lunge_view.opponent())
	expect(is_equal_approx(float(lunge_estimate["active"]), 5.0) and decide(lunger)["type"] == "attack",
			"Resistance applies to the damage of a heads, not to the average: Lunge against Cuptain is 10 on heads, 5 expected, and is used (%s)" % lunge_estimate)
	var stayer := battle("guei", ["holy_energy"], "tenna")
	stayer.current_player().bench.append(in_play("cuptain", ["holy_energy"]))
	stayer.current_player().energy_attached_this_turn = true
	expect(decide(stayer)["type"] == "end_turn", "one Energy away from attacking, it keeps its Energy instead of paying it to Flee (Guei)")

	print("== answers")
	var promoter := battle("jevil", ["chaos_energy"], "koody")
	var loser := promoter.opponent_player()
	loser.bench.append_array([in_play("water_cooler", []), in_play("guei", [])])
	loser.bench[1].damage = 70
	loser.active.damage = 30
	promoter.apply({"type": "attack", "attack_index": 0})
	expect(promoter.choice_kind() == PendingChoice.KIND_TAKE_PRIZE and int(decide(promoter)["option"]) == 0, "it takes the first face-down Mercy Card: they are all alike to it")
	take_mercy_cards(promoter)
	var promote := decide(promoter)
	expect(promoter.choice_kind() == PendingChoice.KIND_PROMOTE and promoter.choice_option(int(promote["option"]))["value"] == 0,
			"the healthiest Darkner is promoted: Water Cooler, not Guei at 10 HP")

	var searcher := battle("jevil", [], "tenna")
	searcher.current_player().hand.assign(cards(["recruit_manual", "kris", "susie"]))
	searcher.current_player().deck.assign(cards(["chaos_energy", "hammer_of_justice", "old_man"]))
	searcher.apply({"type": "play_trainer", "hand_index": 0})
	while searcher.choice_details().get("zone") == PendingChoice.ZONE_HAND:
		searcher.apply(decide(searcher))
	var take := decide(searcher)
	expect(searcher.choice_details().get("zone") == PendingChoice.ZONE_DECK and (searcher.choice_option(int(take["option"]))["shows"] as CardData).id == "old_man",
			"a search takes a Basic Darkner before an evolution")
	searcher.apply(take)
	expect(searcher.choice_option(int(decide(searcher)["option"]))["pick"] == PendingChoice.PICK_CONFIRM, "and confirms once it has all it may take")

	var discarder := battle("jevil", [], "tenna")
	discarder.current_player().hand.assign(cards(["recruit_manual", "chaos_energy", "kris", "hammer_of_justice", "chaos_energy", "guei", "sans", "sans"]))
	discarder.apply({"type": "play_trainer", "hand_index": 0})
	var discarded: Array[String] = []
	while discarder.choice_details().get("zone") == PendingChoice.ZONE_HAND:
		var answer := decide(discarder)
		var shown: Variant = discarder.choice_option(int(answer["option"])).get("shows")
		if shown is CardData:
			discarded.append((shown as CardData).id)
		discarder.apply(answer)
	expect(discarded == ["hammer_of_justice", "sans"], "a discard starts with what it cannot use: an evolution with nothing to evolve, then the ACT card it holds most copies of (%s)" % [discarded])

	var spare_or_fight := func(bench_id: String, bench_energy: Array, battling_damage: int) -> String:
		var engine := battle("tenna", ["fun_energy", "fun_energy", "fun_energy", "fun_energy", "fun_energy"], "jevil")
		var taker := engine.current_index
		engine.opponent_player().bench.append(in_play(bench_id, bench_energy))
		engine.current_player().active.damage = battling_damage
		while engine.players[taker].prizes.size() > 1:
			engine.players[taker].prizes.pop_back()
		engine.apply({"type": "attack", "attack_index": 0})
		take_mercy_cards(engine)
		if engine.choice_kind() != PendingChoice.KIND_SPARE_FIGHT:
			return "no question"
		return str(engine.choice_option(int(decide(engine)["option"]))["value"])
	expect(spare_or_fight.call("koody", [], 0) == PendingChoice.FIGHT,
			"it Fights when nothing the opponent has can knock out its Darkners next turn and it can knock out whatever they battle with")
	expect(spare_or_fight.call("jevil", ["chaos_energy"], 90) == PendingChoice.SPARE, "it Spares when the opponent could knock out one of its Darkners first")
	expect(spare_or_fight.call("guei", [], 0) == PendingChoice.SPARE, "and when it could not knock out what they battle with next (Guei, 80 HP, against Showtime!'s 70)")

	print("== a cheaper knockout")
	var melt_or_overrun := func(holy: int, koody_damage: int) -> Dictionary:
		var energy: Array = []
		for _i in holy:
			energy.append("holy_energy")
		var engine := battle("guei", energy, "koody")
		engine.current_player().bench.append(in_play("cuptain", ["holy_energy"]))
		engine.current_player().bench.append(in_play("cuptain", []))
		engine.opponent_player().active.damage = koody_damage
		return decide(engine)
	var cheap_ko := melt_or_overrun.call(4, 30) as Dictionary
	expect(cheap_ko["type"] == "retreat" and int(cheap_ko["slot"]) == 0,
			"Guei would give up 4 Energy to knock out a Koody with 10 HP left: it flees (1 Energy) to the Cuptain that can pay Overrun, which knocks it out")
	var melt := melt_or_overrun.call(4, 0) as Dictionary
	expect(melt["type"] == "attack", "not when Overrun (20) cannot knock the Koody out: Flash Melt it is")
	var two := melt_or_overrun.call(2, 30) as Dictionary
	expect(two["type"] == "retreat", "with 2 Energy on Guei fleeing still gives up less")
	expect(reader.energy_given_up(in_play("guei", ["holy_energy", "holy_energy", "holy_energy"]), db.make("guei").attacks[0]) == 3
			and reader.energy_given_up(in_play("cuptain", ["holy_energy"]), db.make("cuptain").attacks[0]) == 0, "Flash Melt gives up every Energy on Guei; Overrun none")

	print("== damage to its own Darkners")
	var devoted := battle("jevil", [], "tenna")
	var devotee := in_play("cuptain", [])
	devoted.current_player().bench.append_array([devotee, in_play("guei", [])])
	devoted.current_player().discard.assign(cards(["holy_energy"]))
	var uses_devotion := func() -> bool:
		var action := decide(devoted)
		return action["type"] == "use_power"
	expect(uses_devotion.call(), "Selfless Devotion is used while Cuptain survives its 2 damage counters")
	devotee.damage = 20
	expect(not uses_devotion.call(), "and not when they would knock Cuptain out (20 HP left)")

	var sacrifice := func(opponent_prizes: int, defender_damage: int) -> MatchEngine:
		var round := battle("cuptain", [], "koody")
		var player := round.current_player()
		player.active.damage = 20
		player.bench.append_array([in_play("water_cooler", []), in_play("guei", ["holy_energy"])])
		player.discard.assign(cards(["holy_energy"]))
		player.energy_attached_this_turn = true
		round.opponent_player().active.damage = defender_damage
		while round.opponent_player().prizes.size() > opponent_prizes:
			round.opponent_player().prizes.pop_back()
		return round
	var sacrificed := sacrifice.call(4, 0) as MatchEngine
	var taker := sacrificed.current_index
	var defender := sacrificed.opponent_player().active
	var steps := 0
	while not sacrificed.is_over() and sacrificed.current_index == taker and steps < 20:
		sacrificed.apply(decide(sacrificed))
		steps += 1
	expect(sacrificed.players[taker].active != null and sacrificed.players[taker].active.card.id == "guei" and sacrificed.players[1 - taker].active != defender,
			"as a last option it gives up Cuptain: the Energy goes to Guei, Guei is promoted and knocks out Koody")
	var no_knockout := sacrifice.call(4, 0) as MatchEngine
	no_knockout.opponent_player().active = in_play("tenna", [])
	expect(decide(no_knockout)["type"] == "end_turn", "not when the Energy gives no knockout")
	var losing := sacrifice.call(1, 0) as MatchEngine
	expect(decide(losing)["type"] == "end_turn", "and not when the Mercy Card for Cuptain would win the round for the opponent")

	print("== memory of its deck")
	var forgetful := battle("jevil", [], "tenna")
	var holder := forgetful.current_player()
	holder.hand.assign(cards(["glowshard", "glowshard", "chaos_energy"]))
	holder.deck.assign(cards(["hammer_of_justice", "hammer_of_justice", "hammer_of_justice", "hammer_of_justice", "hammer_of_justice", "hammer_of_justice"]))
	holder.prizes.assign(cards(["chaos_energy", "chaos_energy", "chaos_energy", "chaos_energy"]))
	holder.energy_attached_this_turn = true
	var remembering := CpuPlayer.new(library, owned(holder), {})
	var blind := CpuPlayer.new(library, owned(holder), {})
	expect((decide_with(forgetful, blind) as Dictionary)["type"] == "play_trainer", "before searching, its Mercy Cards could be in its deck: the unseen Energy makes Glowshard worth playing")
	var searched_turn := forgetful.turn
	while forgetful.turn == searched_turn:
		var action := decide_with(forgetful, remembering)
		if action["type"] == "end_turn":
			break
		forgetful.apply(action)
	expect(holder.hand.filter(func(card: CardData) -> bool: return card.id == "glowshard").size() == 1,
			"after a search showed no Energy in its deck, it knows the unseen Energy are its Mercy Cards and keeps the second Glowshard")
	var returned := holder.hand.filter(func(card: CardData) -> bool: return card.id == "chaos_energy")[0] as CardData
	holder.hand.erase(returned)
	holder.deck.append(returned)
	expect((decide_with(forgetful, remembering) as Dictionary)["type"] == "play_trainer", "an Energy that goes back from its hand into its deck is counted in its deck: now the search would find it")
	holder.deck.erase(returned)
	holder.hand.append(returned)
	expect((decide_with(forgetful, remembering) as Dictionary)["type"] == "end_turn", "and once it is back in its hand, out again")
	forgetful.apply({"type": "end_turn"})
	forgetful.apply({"type": "end_turn"})
	holder.energy_attached_this_turn = true
	expect((decide_with(forgetful, remembering) as Dictionary)["type"] == "end_turn", "it still remembers on its next turn (memory_turns 2)")
	forgetful.apply({"type": "end_turn"})
	forgetful.apply({"type": "end_turn"})
	holder.energy_attached_this_turn = true
	expect((decide_with(forgetful, remembering) as Dictionary)["type"] == "play_trainer", "two turns later it has forgotten which cards are its Mercy Cards, and tries again")
	var short_memory := CpuPlayer.new(library, owned(holder), {})
	short_memory.memory.memory_turns = 0
	short_memory.choose(forgetful.view_for(forgetful.current_index))
	expect(not short_memory.memory.remembers(), "memory_turns 0 forgets at once")

	print("== what effects are worth")
	var ledger := battle("jevil", [], "tenna")
	var keeper := ledger.current_player()
	keeper.hand.assign(cards(["recruit_manual", "chaos_energy", "chaos_energy"]))
	keeper.energy_attached_this_turn = true
	var circler := CpuPlayer.new(library, owned(keeper), {})
	# It sees the board once before the card is played for it, as it would when playing it.
	circler.choose(ledger.view_for(ledger.current_index))
	ledger.apply({"type": "play_trainer", "hand_index": 0})
	while ledger.is_waiting_for_choice() and ledger.choice_details().get("zone") == PendingChoice.ZONE_HAND:
		ledger.apply(decide_with(ledger, circler))
	while ledger.is_waiting_for_choice():
		ledger.apply(decide_with(ledger, circler))
	# Only Revive Song in hand, so nothing else comes first.
	keeper.hand.assign(cards(["revive_song"]))
	var fresh := CpuPlayer.new(library, owned(keeper), {})
	expect((decide_with(ledger, fresh) as Dictionary)["type"] == "play_trainer", "Revive Song is worth playing to take back a Chaos Energy for Jevil")
	expect((decide_with(ledger, circler) as Dictionary)["type"] != "play_trainer", "but not the Energy it discarded itself this turn: no moving cards in circles")

	var strong_hand := battle("jevil", [], "tenna")
	strong_hand.current_player().hand.assign(cards(["sans", "guei", "guei", "tenna", "chaos_energy", "chaos_energy"]))
	strong_hand.current_player().bench.append_array([in_play("guei", []), in_play("tenna", []), in_play("tenna", []), in_play("guei", [])])
	strong_hand.current_player().energy_attached_this_turn = true
	expect((decide(strong_hand) as Dictionary)["type"] == "end_turn", "Sans is not worth discarding a hand of Darkners and Energy for two ACT cards")
	var dark_zone := battle("jevil", [], "tenna")
	dark_zone.current_player().hand.assign(cards(["kris", "kris", "hammer_of_justice"]))
	dark_zone.stadium = db.make("dark_zone")
	dark_zone.stadium_owner = dark_zone.current_index
	dark_zone.current_player().supporter_played_this_turn = true
	expect((decide(dark_zone) as Dictionary)["type"] == "use_area", "Dark Zone is worth using when the two cards it discards are worth less than a draw")
	var precious := battle("jevil", [], "tenna")
	precious.current_player().hand.assign(cards(["guei", "tenna", "chaos_energy"]))
	precious.current_player().bench.append_array([in_play("guei", []), in_play("tenna", []), in_play("tenna", []), in_play("guei", [])])
	precious.current_player().energy_attached_this_turn = true
	precious.stadium = db.make("dark_zone")
	precious.stadium_owner = precious.current_index
	expect((decide(precious) as Dictionary)["type"] == "end_turn", "and not when they are worth more")

	print("== Energy for the plan")
	var holy_cpu := CpuPlayer.new(library, deck_cards("holy"), {})
	var devotion_round := battle("water_cooler", ["holy_energy"], "tenna")
	var holy_side := devotion_round.current_player()
	holy_side.bench.append_array([in_play("cuptain", []), in_play("cuptain", []), in_play("guei", ["holy_energy", "holy_energy"])])
	holy_side.discard.assign(cards(["holy_energy"]))
	holy_side.energy_attached_this_turn = true
	devotion_round.apply({"type": "use_power", "slot": 0, "power": "Selfless Devotion"})
	while devotion_round.is_waiting_for_choice() and devotion_round.choice_kind() == PendingChoice.KIND_PICK_CARDS:
		devotion_round.apply(decide_with(devotion_round, holy_cpu))
	var devotion_target := decide_with(devotion_round, holy_cpu)
	expect(devotion_round.choice_kind() == PendingChoice.KIND_CHOOSE_DARKNER and int(devotion_round.choice_option(int(devotion_target["option"]))["value"]) == 2,
			"Selfless Devotion gives its Energy to Guei, who can already attack, not to a Cuptain: Flash Melt wants 5")
	var hand_round := battle("water_cooler", ["holy_energy", "holy_energy"], "tenna")
	hand_round.current_player().bench.append_array([in_play("cuptain", []), in_play("guei", ["holy_energy", "holy_energy", "holy_energy"])])
	hand_round.current_player().hand.assign(cards(["holy_energy"]))
	var hand_attach := decide_with(hand_round, CpuPlayer.new(library, deck_cards("holy"), {}))
	expect(hand_attach["type"] == "attach" and int(hand_attach["slot"]) == 1, "and so does the Energy from the hand, up to the fifth (%s)" % hand_attach)

	print("== switching in")
	var feather := battle("guei", [], "tenna")
	feather.current_player().bench.append_array([in_play("guei", []), in_play("guei", ["holy_energy", "holy_energy"])])
	feather.current_player().hand.assign(cards(["petal_feather"]))
	feather.apply({"type": "play_trainer", "hand_index": 0})
	var switch := decide(feather)
	expect(feather.choice_kind() == PendingChoice.KIND_CHOOSE_DARKNER and int(feather.choice_option(int(switch["option"]))["value"]) == 1,
			"its own switch brings in a Darkner that can attack, not an identical one without Energy")

	finish()