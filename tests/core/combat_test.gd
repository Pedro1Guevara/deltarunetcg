## Headless checks for a combat, the best of three rounds (Design Document 2.1). Run from the
## project root:
##   godot --headless --path . --script res://tests/core/combat_test.gd
## Exits with code 0 when every check passes.
extends TestCase

const DECK := {"jevil": 4, "tenna": 4, "guei": 4, "chaos_energy": 18}

var library: EffectLibrary


func deck_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for card in db.build_deck({"cards": DECK}):
		ids.append(card.id)
	return ids


func new_combat(seed: int) -> Combat:
	var combat := Combat.new(db, library, deck_ids(), deck_ids(), MatchRules.deltarune(), seed)
	combat.start()
	return combat


## Ends the game being played with winner as its winner: the other player cannot draw at the
## start of their next turn. Changes the round by hand, so its replay does not play it again.
func win_game(combat: Combat, winner: int) -> void:
	var engine := combat.engine
	finish_setup(engine)
	if engine.current_index != winner:
		engine.apply({"type": "end_turn"})
	engine.players[1 - winner].deck.clear()
	engine.apply({"type": "end_turn"})


## Ends the game being played in Sudden Death, set by hand.
func tie_game(combat: Combat) -> void:
	finish_setup(combat.engine)
	combat.engine.winner = MatchEngine.SUDDEN_DEATH


func fresh_start(engine: MatchEngine, prizes: int) -> bool:
	for player in engine.players:
		if player.tp != engine.rules.tp_start or player.prizes.size() != prizes:
			return false
	return engine.turn == 0 and engine.is_waiting_for_choice() and engine.choice_kind() == PendingChoice.KIND_COIN_CALL


func _run() -> void:
	db = DataLoader.load_card_database()
	library = DataLoader.load_effect_library(db, DataLoader.CARD_EFFECTS_PATH)

	print("== a combat")
	var combat := new_combat(7)
	expect(combat.round_number == 1 and not combat.sudden_death and combat.score() == [0, 0] and not combat.is_over() and combat.winner() == -1,
			"a combat starts on round 1 with no rounds won")
	expect(fresh_start(combat.engine, 4), "the round starts from setup: a coin call, 100% TP, 4 Mercy Cards each")
	expect(combat.engine.rules != combat.rules and combat.engine.rules.to_dict() == combat.rules.to_dict(), "the round plays a copy of the combat's rules")
	expect(not combat.next_game() and combat.round_number == 1 and combat.games.is_empty(), "no next game while the round goes on")

	var first_engine := combat.engine
	win_game(combat, 0)
	expect(combat.score() == [1, 0] and not combat.is_over(), "player 1 wins round 1: 1-0, the combat goes on")
	expect(combat.next_game() and combat.round_number == 2 and combat.games.size() == 1 and combat.engine != first_engine,
			"the next round is a new game")
	expect(int(combat.games[0]["winner"]) == 0 and int(combat.games[0]["round"]) == 1 and not bool(combat.games[0]["sudden_death"]),
			"the combat keeps the game played: round 1, won by player 1")
	expect(fresh_start(combat.engine, 4), "round 2 starts from setup again: coin call, TP back to 100%, 4 Mercy Cards each")
	expect(combat.engine.replay().decks == combat.decks and combat.games[0]["replay"].decks == combat.decks, "both rounds are played with the same decks")
	expect(combat.engine.replay().rng_seed != (combat.games[0]["replay"] as MatchReplay).rng_seed, "each round has its own seed")

	print("== Sudden Death")
	tie_game(combat)
	expect(combat.score() == [1, 0] and combat.next_is_sudden_death(), "round 2 ends in Sudden Death: no one wins it yet")
	expect(combat.next_game() and combat.round_number == 2 and combat.sudden_death, "a Sudden Death game decides round 2")
	expect(fresh_start(combat.engine, Combat.SUDDEN_DEATH_PRIZE_COUNT) and combat.engine.rules.prize_count == 1 and combat.rules.prize_count == 4,
			"with 1 Mercy Card each; the combat's rules keep 4")
	tie_game(combat)
	expect(combat.next_game() and combat.round_number == 2 and combat.sudden_death, "Sudden Death again: another Sudden Death game, still round 2")
	win_game(combat, 1)
	expect(combat.score() == [1, 1] and not combat.is_over(), "player 2 wins it, and with it round 2: 1-1")
	expect(combat.next_game() and combat.round_number == 3 and not combat.sudden_death and fresh_start(combat.engine, 4),
			"round 3 is a normal game with 4 Mercy Cards each")
	win_game(combat, 1)
	expect(combat.is_over() and combat.winner() == 1 and combat.score() == [1, 2], "player 2 wins round 3 and the combat, 2-1")
	expect(not combat.next_game() and combat.round_number == 3 and combat.games.size() == 4, "no game after the combat is over")
	var rounds: Array = []
	for game in combat.games:
		rounds.append([int(game["round"]), bool(game["sudden_death"]), int(game["winner"])])
	expect(rounds == [[1, false, 0], [2, false, MatchEngine.SUDDEN_DEATH], [2, true, MatchEngine.SUDDEN_DEATH], [2, true, 1]],
			"the games played: round 1, round 2 and its two Sudden Death games (%s)" % [rounds])

	var short := new_combat(8)
	win_game(short, 1)
	short.next_game()
	win_game(short, 1)
	expect(short.is_over() and short.winner() == 1 and short.round_number == 2 and short.score() == [0, 2], "2-0 ends the combat after two rounds")

	print("== seeds")
	var again := new_combat(7)
	var other := new_combat(9)
	expect(again.engine.replay().rng_seed == (combat.games[0]["replay"] as MatchReplay).rng_seed, "the same combat seed gives the same round seeds")
	expect(other.engine.replay().rng_seed != again.engine.replay().rng_seed, "another combat seed, other round seeds")

	print("== replays")
	var record := combat.replay()
	expect(record.games.size() == 5 and record.combat_seed == 7 and record.decks == combat.decks, "a combat's replay holds every game, its seed and the decks")
	var code := record.to_code()
	expect(code.begins_with(CombatReplay.CODE_PREFIX) and not code.contains(" ") and code.length() * 3 < record.to_text().length(),
			"its code is one line, a third the length of the text or less (%d against %d)" % [code.length(), record.to_text().length()])
	expect(CombatReplay.from_text(code).to_text() == record.to_text() and CombatReplay.from_text(record.to_text()).to_text() == record.to_text(),
			"written as text or as a code it reads back as the same replay")
	expect(CombatReplay.from_text(CombatReplay.CODE_PREFIX + "not base64") == null and CombatReplay.from_text("{}") == null and MatchReplay.from_text(code) == null,
			"a broken code, empty JSON, or a combat read as a round read as null")
	var round_code := (combat.games[0]["replay"] as MatchReplay).to_code()
	expect(MatchReplay.from_text(round_code).to_text() == (combat.games[0]["replay"] as MatchReplay).to_text(), "a round's code still reads back as before")

	finish()
