## Headless checks for CombatSession (Design Document 8.8). Run from the project root:
##   godot --headless --path . --script res://tests/game/combat_session_test.gd
## Exits with code 0 when every check passes.
extends TestCase

const DECKS: Array[String] = ["creative", "holy"]
const CPUS: Array[String] = [CombatSession.CPU, CombatSession.CPU]
const HUMAN_FIRST: Array[String] = [CombatSession.HUMAN, CombatSession.CPU]

## What a session told its screen, and how the screen answers.
class Screen:
	var session: CombatSession
	var updates := 0
	var human_turns := 0
	var events: Array[MatchEvent] = []
	var viewers: Array[int] = []
	var auto_resume := false
	## Plays the human's seat in place of a person: a CPU deciding from the same view.
	var human_cpu: CpuPlayer = null
	var last_view: PlayerView = null
	## is_waiting_for_resume() as each handler of updated saw it.
	var waiting_seen: Array[bool] = []

	func _init(watched: CombatSession) -> void:
		session = watched
		session.updated.connect(_on_updated)
		session.human_turn.connect(_on_human_turn)

	func _on_updated(view: PlayerView, new_events: Array[MatchEvent]) -> void:
		updates += 1
		waiting_seen.append(session.is_waiting_for_resume())
		last_view = view
		viewers.append(view.viewer)
		events.append_array(new_events)
		if auto_resume:
			session.resume()

	func _on_human_turn() -> void:
		human_turns += 1
		if human_cpu != null:
			session.submit(human_cpu.choose(last_view))

	## Starts the next game and forgets the events of the last one.
	func next_game() -> bool:
		events.clear()
		return session.next_game()


func _run() -> void:
	db = DataLoader.load_card_database()

	print("== two CPU seats, paced by resume()")
	var paced := CombatSession.new(DECKS, CPUS, 7)
	var paced_screen := Screen.new(paced)
	expect(paced.start() and paced.error.is_empty(), "a session starts a combat")
	expect(paced_screen.updates == 1 and paced.is_waiting_for_resume() and paced_screen.human_turns == 0 and paced.combat.round_number == 1,
			"the first update, then the CPU waits for resume()")
	var log_size := paced.engine().match_log.entries.size()
	expect(paced.engine().match_log.entries.size() == log_size and paced_screen.updates == 1, "nothing happens until resume() is called")
	paced.resume()
	expect(paced_screen.updates == 2 and paced.is_waiting_for_resume(), "each resume() is one CPU decision and one update")
	paced.resume()
	paced.resume()
	expect(paced_screen.updates == 4, "and so on, one at a time")
	expect(not paced.submit({"type": "end_turn"}), "no human seat: submit() is refused")
	expect(paced_screen.viewers.all(func(viewer: int) -> bool: return viewer == 0), "with two CPUs the view is player 1's")
	expect(paced_screen.waiting_seen.all(func(waiting: bool) -> bool: return waiting), "inside updated the screen can already tell that the CPU waits for resume()")

	print("== a whole combat")
	var whole := CombatSession.new(DECKS, CPUS, 7)
	var whole_screen := Screen.new(whole)
	whole_screen.auto_resume = true
	whole.start()
	var games := 1
	var events_match := true
	while true:
		expect(whole.engine().is_over() and not whole.is_waiting_for_resume(), "game %d plays to its end when the screen resumes from inside updated" % games)
		events_match = events_match and whole_screen.events.size() == whole.engine().events_for(0, 0).size()
		if not whole_screen.next_game():
			break
		games += 1
		if games > 8:
			break
	expect(whole.combat.is_over() and games == whole.combat.games.size() + 1, "next_game() goes on until the combat is over (%d games, score %s)" % [games, whole.combat.score()])
	expect(events_match, "each game's updates carry every event once, as player 1 sees them")
	expect(not whole.next_game(), "no game after the combat")
	var again := CombatSession.new(DECKS, CPUS, 7)
	var again_screen := Screen.new(again)
	again_screen.auto_resume = true
	again.start()
	while again_screen.next_game():
		pass
	expect(again.combat.replay().to_text() == whole.combat.replay().to_text(), "the same seed plays the same combat")
	var replayed := whole.combat.replay().play(whole.cards, DataLoader.load_effect_library(whole.cards, DataLoader.CARD_EFFECTS_PATH))
	expect(replayed.winner() == whole.combat.winner() and replayed.score() == whole.combat.score(), "its replay plays back to the same result")

	print("== a human seat")
	var human := CombatSession.new(DECKS, HUMAN_FIRST, 11)
	var human_screen := Screen.new(human)
	human_screen.auto_resume = true
	human.start()
	expect(human_screen.human_turns >= 1 and human.is_human_turn() and not human.is_waiting_for_resume(), "the session stops for the human")
	expect(not human.submit({"type": "no_such_action"}), "an illegal action is refused")
	var cpu_answer: Dictionary = {}
	for action in human_screen.last_view.legal_actions:
		cpu_answer = action
		break
	var before := human_screen.updates
	expect(human.submit(cpu_answer) and human_screen.updates > before, "a legal action is applied and the screen updated")
	human_screen.human_cpu = CpuPlayer.new(DataLoader.load_effect_library(human.cards, DataLoader.CARD_EFFECTS_PATH), human.combat.decklist(0), {})
	if human.is_human_turn():
		human.submit(human_screen.human_cpu.choose(human_screen.last_view))
	expect(human.engine().is_over(), "a human seat answered from human_turn plays the game to its end")
	expect(human_screen.viewers.all(func(viewer: int) -> bool: return viewer == 0), "every view is the human's")
	var hidden_ok := true
	for event in human_screen.events:
		if event.player == 1 and event.type == MatchEvent.DREW and event.data.has("cards"):
			hidden_ok = false
	expect(hidden_ok, "the CPU's draws reach the human without their cards")

	print("== two human seats")
	var two := CombatSession.new(DECKS, [CombatSession.HUMAN, CombatSession.HUMAN] as Array[String], 3)
	var two_screen := Screen.new(two)
	two.start()
	expect(two.viewer() == two.actor() and two_screen.last_view.viewer == two.actor() and two_screen.human_turns == 1, "with two humans the view is whoever acts")

	print("== errors")
	var missing := CombatSession.new(["creative", "no_such_deck"] as Array[String], CPUS, 1)
	expect(not missing.start() and missing.error.contains("no_such_deck"), "an unknown deck: start() fails and says why")
	var bad_seat := CombatSession.new(DECKS, ["cpu", "robot"] as Array[String], 1)
	expect(not bad_seat.start() and not bad_seat.error.is_empty(), "an unknown seat kind: start() fails")

	finish()
