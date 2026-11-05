## Headless checks for the CPU opponent (Design Document 8.7). Run from the project root:
##   godot --headless --path . --script res://tests/ai/cpu_player_test.gd
## Exits with code 0 when every check passes.
extends TestCase

const SEEDS := 10
const MAX_STEPS := 3000
const DECK_PAIRS := [["creative", "holy"], ["chaos", "holy"], ["creative", "chaos"], ["deltarune_chaos", "deltarune_holy"]]

var library: EffectLibrary
var cpu := CpuPlayer.new()


func start_round(seed: int) -> MatchEngine:
	var engine := MatchEngine.new()
	engine.effects = library
	var counts := {"jevil": 4, "tenna": 4, "guei": 4, "chaos_energy": 18}
	engine.start(db.build_deck({"cards": counts}), db.build_deck({"cards": counts}), MatchRules.deltarune(), Rng.new(seed))
	return engine


## Lets the CPU answer every setup question for both players.
func finish_setup(engine: MatchEngine) -> void:
	while engine.turn == 0 and engine.is_waiting_for_choice():
		engine.apply(cpu.choose(engine.view_for(engine.choice_chooser())))


## A round on turn 2 with the given Darkners in the Battle Zones, nothing on either Field and
## nothing in the hand of the player to act.
func battle(attacker_id: String, attached: Array, defender_id: String) -> MatchEngine:
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


func decide(engine: MatchEngine) -> Dictionary:
	var actor := engine.choice_chooser() if engine.is_waiting_for_choice() else engine.current_index
	return cpu.choose(engine.view_for(actor))


func _run() -> void:
	db = DataLoader.load_card_database()
	library = DataLoader.load_effect_library(db, DataLoader.CARD_EFFECTS_PATH)
	var decks := DataLoader.read_json(DataLoader.DECKS_PATH) as Dictionary

	print("== CPU against CPU")
	var illegal := ""
	var undone := ""
	var finished := 0
	var wins := [0, 0]
	var longest := 0
	for pair: Array in DECK_PAIRS:
		for seed in SEEDS:
			var engine := MatchEngine.new()
			engine.effects = library
			engine.start(db.build_deck(decks[pair[0]] as Dictionary), db.build_deck(decks[pair[1]] as Dictionary), MatchRules.deltarune(), Rng.new(seed))
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
				engine.apply(action)
	var rounds := DECK_PAIRS.size() * SEEDS
	expect(illegal.is_empty(), "the CPU only answers with legal actions: %s" % illegal)
	expect(undone.is_empty(), "and never undoes a pick: %s" % undone)
	expect(finished == rounds, "CPU against CPU finishes every round (%d of %d; wins %s; longest %d turns)" % [finished, rounds, wins, longest])

	print("== the CPU decides from its view")
	var waiting := start_round(2)
	var other := 1 - waiting.choice_chooser()
	expect(cpu.choose(waiting.view_for(other)).is_empty(), "a player who is not to act gets no action")

	print("== turn priorities")
	var bencher := battle("jevil", ["chaos_energy"], "tenna")
	bencher.current_player().hand.assign(cards(["chaos_energy", "guei"]))
	expect(decide(bencher)["type"] == "bench", "a Basic Darkner goes on the Field first")

	var attacher := battle("guei", [], "tenna")
	attacher.current_player().bench.append(in_play("jevil", ["chaos_energy"]))
	attacher.current_player().hand.assign(cards(["holy_energy"]))
	var attach := decide(attacher)
	expect(attach["type"] == "attach" and int(attach["slot"]) == -1, "Energy goes to the Darkner that still cannot attack (%s)" % attach)
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
	expect(decide(striker) == {"type": "attack", "attack_index": 0, "label": striker.legal_actions().filter(func(a: Dictionary) -> bool: return a["type"] == "attack" and a["attack_index"] == 0)[0]["label"]},
			"Slash (20) is chosen over Chaos Bomb (0)")
	var finisher := battle("guei", ["holy_energy", "holy_energy"], "koody")
	finisher.opponent_player().active.damage = 10
	expect(decide(finisher)["type"] == "attack", "an attack that knocks out is taken")
	var idle := battle("koody", [], "tenna")
	expect(decide(idle)["type"] == "end_turn", "with nothing to do, the turn ends")

	var fleer := battle("water_cooler", ["chaos_energy"], "guei")
	fleer.current_player().bench.append(in_play("jevil", ["chaos_energy"]))
	fleer.current_player().energy_attached_this_turn = true
	expect(decide(fleer)["type"] == "retreat", "a Battling Darkner that cannot attack flees to one that can")

	print("== answers")
	var promoter := battle("jevil", ["chaos_energy"], "koody")
	var loser := promoter.opponent_player()
	loser.bench.append_array([in_play("water_cooler", []), in_play("guei", [])])
	loser.bench[1].damage = 70
	loser.active.damage = 30
	promoter.apply({"type": "attack", "attack_index": 0})
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
	discarder.current_player().hand.assign(cards(["recruit_manual", "kris", "chaos_energy", "chaos_energy", "guei"]))
	discarder.apply({"type": "play_trainer", "hand_index": 0})
	var first_discard := decide(discarder)
	expect((discarder.choice_option(int(first_discard["option"]))["shows"] as CardData).id == "chaos_energy", "a discard starts with the card it holds most copies of")

	finish()