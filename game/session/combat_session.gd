class_name CombatSession
extends RefCounted
## Drives a combat (Design Document 8.8): one seat per player, human or CPU. The board, or any
## screen, shows what updated() hands it and talks to the session only: submit() for the human's
## actions, resume() when it is ready for the CPU's next decision, next_game() when a game is
## over. The session never decides a rule; the engine does, through legal_actions() and apply().
##
## The view and the events go to one player, the viewer: the human, or player 1 when both
## seats are CPUs. With two humans the viewer is whoever acts. A CPU decides only when resume()
## is called, so the board can play its animations first; each decision needs its own resume().
## resume() and submit() may be called from inside a handler of updated() or human_turn(): the
## session goes on once the handler returns, so a long CPU-against-CPU combat never nests calls.

const HUMAN := "human"
const CPU := "cpu"
## A CPU turn that takes more decisions than this is ended, as a safety net.
const CPU_DECISIONS_PER_TURN := 300

## After every change: the viewer's view and the events since their last update, as they see
## them (MatchEngine.events_for()). A new game starts its events from the beginning.
signal updated(view: PlayerView, events: Array[MatchEvent])
## A human must act: their turn, or a question they answer. Emitted after updated().
signal human_turn()

## The combat being played: round, score, Sudden Death, winner and replay. Read it; do not
## change it.
var combat: Combat = null
## Each player's deck, by decks.json id.
var deck_ids: Array[String] = []
## Each seat: HUMAN or CPU.
var seats: Array[String] = []
## The cards of the combat, for the words of labels, prompts and the log (game/presentation).
var cards: CardDatabase = null
## Why start() failed, or empty.
var error: String = ""

var _seed: int
var _effects: EffectLibrary = null
var _deck_defs: Dictionary = {}
var _cpus: Array[CpuPlayer] = []
## Where each player's events were read up to, in the game being played.
var _cursors: Array[int] = [0, 0]
## The CPU to act waits for resume().
var _waiting_for_resume := false
var _resume_requested := false
## _advance() is running: a submit() or a game change asks it to go round again.
var _advancing := false
var _again := false
var _cpu_turn := -1
var _cpu_decisions := 0


## deck_ids and seats by player. seed is the combat's seed; -1 picks one at random.
func _init(player_decks: Array[String], player_seats: Array[String], seed: int = -1) -> void:
	deck_ids = player_decks.duplicate()
	seats = player_seats.duplicate()
	_seed = seed if seed != -1 else randi()


## Loads the cards, effects and decks and starts the combat; then the first updated(). False,
## with error set, when the data or a deck is missing. Connect to the signals before calling it.
func start() -> bool:
	if deck_ids.size() != 2 or seats.size() != 2 or seats.any(func(seat: String) -> bool: return seat != HUMAN and seat != CPU):
		error = "A combat needs two decks and two seats, each \"%s\" or \"%s\"." % [HUMAN, CPU]
		return false
	cards = DataLoader.load_card_database()
	var decks: Variant = DataLoader.read_json(DataLoader.DECKS_PATH)
	if cards.card_count() == 0 or not decks is Dictionary:
		error = "Could not load data/cards/cards.json or data/decks/decks.json. See the Output panel."
		return false
	_deck_defs = decks as Dictionary
	for id in deck_ids:
		if not _deck_defs.has(id):
			error = "decks.json has no deck '%s'." % id
			return false
	var rules := MatchRules.deltarune()
	var lists: Array[PackedStringArray] = []
	for id in deck_ids:
		var deck := cards.build_deck(_deck_defs[id] as Dictionary)
		# Test decks are smaller than the rules require on purpose: report, do not block.
		for problem in DeckValidator.validate(deck, rules):
			push_warning("Deck %s %s" % [id, problem])
		var listed := PackedStringArray()
		for card in deck:
			listed.append(card.id)
		lists.append(listed)
	_effects = DataLoader.load_effect_library(cards, DataLoader.CARD_EFFECTS_PATH)
	combat = Combat.new(cards, _effects, lists[0], lists[1], rules, _seed)
	combat.start()
	_start_game()
	return true


## The human's action, one of their view's legal actions. False, and nothing happens, when no
## human is to act or the action is not legal now.
func submit(action: Dictionary) -> bool:
	if combat == null or engine().is_over() or not is_human_turn() or not engine().is_legal(action):
		push_warning("CombatSession: not accepted now: %s" % action)
		return false
	engine().apply(action)
	_advance()
	return true


## The board is ready: the CPU waiting to act takes its next decision. Does nothing when no CPU
## is waiting.
func resume() -> void:
	if _advancing:
		_resume_requested = true
		return
	if not _waiting_for_resume:
		return
	_play_cpu()
	_advance()


## Starts the next round, or the Sudden Death game that decides this one, once the game is over
## and the combat is not. Then updated() with the new game.
func next_game() -> bool:
	if combat == null or not combat.next_game():
		return false
	_start_game()
	return true


## The game being played.
func engine() -> MatchEngine:
	return combat.engine


## The player the view and events go to.
func viewer() -> int:
	var humans := seats.count(HUMAN)
	if humans == 2:
		return actor()
	return seats.find(HUMAN) if humans == 1 else 0


## The player who answers the open question, or else the player taking the turn.
func actor() -> int:
	return engine().choice_chooser() if engine().is_waiting_for_choice() else engine().current_index


func is_human_turn() -> bool:
	return not engine().is_over() and seats[actor()] == HUMAN


## Whether a CPU is to act and waits for resume().
func is_waiting_for_resume() -> bool:
	return _waiting_for_resume


func _start_game() -> void:
	_cursors = [0, 0]
	_waiting_for_resume = false
	_resume_requested = false
	_cpu_turn = -1
	# Each CPU gets its decklist and the deck's plan, if decks.json writes one, for every game.
	_cpus.clear()
	for index in 2:
		var plan_data := (_deck_defs[deck_ids[index]] as Dictionary).get("plan", {}) as Dictionary
		_cpus.append(CpuPlayer.new(_effects, combat.decklist(index), plan_data))
	_advance()


## Tells the viewer what changed, then whoever acts next: the human, or the CPU once resume()
## is called. Calls made from inside a handler only ask for another round of this loop.
func _advance() -> void:
	if _advancing:
		_again = true
		return
	_advancing = true
	_again = true
	while _again:
		_again = false
		# Set before updated(), so its handler can already tell that the CPU waits for resume().
		_waiting_for_resume = not engine().is_over() and seats[actor()] == CPU
		_emit_update()
		if engine().is_over():
			break
		if is_human_turn():
			_resume_requested = false
			human_turn.emit()
			continue
		if _again:
			continue
		if _resume_requested:
			_resume_requested = false
			_play_cpu()
			_again = true
	_resume_requested = false
	_advancing = false


func _emit_update() -> void:
	var player := viewer()
	var events := engine().events_for(player, _cursors[player])
	_cursors[player] = engine().match_log.entries.size()
	updated.emit(engine().view_for(player), events)


## The CPU to act decides from its own view (PlayerView) and its action is applied.
func _play_cpu() -> void:
	_waiting_for_resume = false
	if engine().is_over() or seats[actor()] != CPU:
		return
	if engine().turn != _cpu_turn:
		_cpu_turn = engine().turn
		_cpu_decisions = 0
	_cpu_decisions += 1
	var player := actor()
	var action := _cpus[player].choose(engine().view_for(player))
	if _cpu_decisions > CPU_DECISIONS_PER_TURN and engine().is_legal({"type": "end_turn"}):
		push_warning("CombatSession: the CPU took more than %d decisions this turn; ending it" % CPU_DECISIONS_PER_TURN)
		action = {"type": "end_turn"}
	engine().apply(action)
