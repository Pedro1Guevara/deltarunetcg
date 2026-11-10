extends Control

const DECK_SELECT_SCENE := "res://game/screen/debug/deck_select/deck_select.tscn"
## The decks played when the scene is run on its own, without the deck select screen.
const DEFAULT_DECKS: Array[String] = ["creative", "holy"]
## Which players the CPU plays when the scene is run on its own: player 2.
const DEFAULT_CPU_SEATS: Array[bool] = [false, true]
## Seconds between two CPU decisions, so each one can be followed on the board.
const CPU_DELAY := 1.2
## A CPU turn that takes more decisions than this is ended, as a safety net.
const CPU_DECISIONS_PER_TURN := 300
const FONT_SIZE := 22
## The ways to copy a replay, as ids of the Copy replay menu.
const REPLAY_AS_TEXT := 0
const REPLAY_AS_CODE := 1

## The combat being played (best of three) and the engine of its game being played.
var _combat: Combat = null
var _engine := MatchEngine.new()
## The cards of the combat, for the words of labels, prompts and the log (game/presentation).
var _database: CardDatabase = null

var _status_label: Label
## The status line as _refresh() wrote it, before any notice is added to it.
var _status_text: String = ""
## The Area in play and the ACT card being played, as cards to hover.
var _shared_row: HBoxContainer
var _player_panels: Array[VBoxContainer] = []
var _actions_box: VBoxContainer
var _log_label: Label
var _open_group: String = ""
## Whether each player's discard pile is shown. Public information, so either can be opened.
var _discard_open: Array[bool] = [false, false]
## Each player's deck, by decks.json id, and its display name.
var _deck_ids: Array[String] = DEFAULT_DECKS.duplicate()
var _deck_names: Array[String] = []
## Whether the CPU plays each seat.
var _cpu_seats: Array[bool] = DEFAULT_CPU_SEATS.duplicate()
## One CPU per seat, since each remembers what it saw; made for each round with its deck.
var _cpus: Array[CpuPlayer] = []
## A CPU decision is waiting for its pause to end.
var _cpu_waiting := false
## Bumped by every new game, so a pause started in the previous game does nothing.
var _game_number := 0
var _cpu_turn := -1
var _cpu_decisions := 0


## Called by the deck select screen before the scene enters the tree: each player's deck, and
## whether the CPU plays it.
func setup(deck_ids: Array[String], cpu_seats: Array[bool]) -> void:
	_deck_ids = deck_ids.duplicate()
	_cpu_seats = cpu_seats.duplicate()

func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = FONT_SIZE
	theme = ui_theme
	_build_ui()
	_start_combat()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	margin.add_child(columns)

	# Left column: match status and both players.
	var board := VBoxContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_stretch_ratio = 2.0
	columns.add_child(board)

	_status_label = Label.new()
	# A long prompt wraps onto more lines instead of widening the board past the window.
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_child(_status_label)

	_shared_row = HBoxContainer.new()
	_shared_row.add_theme_constant_override("separation", 16)
	board.add_child(_shared_row)

	# Player 2 on top, player 1 at the bottom.
	_player_panels.resize(2)
	_player_panels[1] = _make_panel()
	board.add_child(_player_panels[1])
	board.add_child(HSeparator.new())
	_player_panels[0] = _make_panel()
	board.add_child(_player_panels[0])

	# Right column: legal actions, log, new match.
	var side_panel := VBoxContainer.new()
	side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(side_panel)

	var actions_title := Label.new()
	actions_title.text = "Legal actions"
	side_panel.add_child(actions_title)

	var actions_scroll := ScrollContainer.new()
	actions_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(actions_scroll)

	_actions_box = VBoxContainer.new()
	_actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_scroll.add_child(_actions_box)

	var log_title := Label.new()
	log_title.text = "Log (newest first)"
	side_panel.add_child(log_title)

	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(log_scroll)

	_log_label = Label.new()
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_scroll.add_child(_log_label)

	var controls := WindowControls.new()
	add_child(controls)

	# Buttons wrap onto a second line instead of widening the column.
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 12)
	buttons.add_theme_constant_override("v_separation", 12)
	side_panel.add_child(buttons)
	for entry: Array in [
		["New combat", _start_combat],
		["Change decks", _change_decks],
		["Copy replay ▾", Callable()],
		["Window / Fullscreen (F11)", WindowControls.toggle_windowed],
		["Quit (Esc)", controls.quit],
	]:
		var callback := entry[1] as Callable
		var button: Button = Button.new() if callback.is_valid() else _make_replay_menu()
		button.text = str(entry[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if callback.is_valid():
			button.pressed.connect(callback)
		buttons.add_child(button)


func _make_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _start_combat() -> void:
	var database := DataLoader.load_card_database()
	_database = database
	var decks: Variant = DataLoader.read_json(DataLoader.DECKS_PATH)
	if database.card_count() == 0 or not decks is Dictionary:
		_show_error("Could not load data/cards.json or data/decks.json. See the Output panel.")
		return

	var deck_defs := decks as Dictionary
	for id in _deck_ids:
		if not deck_defs.has(id):
			_show_error("decks.json has no deck '%s'." % id)
			return
	_deck_names.clear()
	for id in _deck_ids:
		_deck_names.append(str((deck_defs[id] as Dictionary).get("name", id)))

	var rules := MatchRules.deltarune()
	var deck_ids: Array[PackedStringArray] = []
	for id in _deck_ids:
		var deck := database.build_deck(deck_defs[id] as Dictionary)
		# Test decks are smaller than the rules require on purpose: report, do not block.
		for problem in DeckValidator.validate(deck, rules):
			push_warning("Deck %s %s" % [id, problem])
		var listed := PackedStringArray()
		for card in deck:
			listed.append(card.id)
		deck_ids.append(listed)
	var effects := DataLoader.load_effect_library(database, DataLoader.CARD_EFFECTS_PATH)
	_combat = Combat.new(database, effects, deck_ids[0], deck_ids[1], rules, randi())
	_combat.start()
	_start_game()


## Starts playing the game the combat just started: a new round or a Sudden Death game.
func _start_game() -> void:
	_engine = _combat.engine
	_game_number += 1
	_cpu_waiting = false
	_cpu_turn = -1
	_open_group = ""
	# Each CPU gets its decklist and the deck's plan, if decks.json writes one, for every game.
	var deck_defs := DataLoader.read_json(DataLoader.DECKS_PATH) as Dictionary
	_cpus.clear()
	for index in 2:
		var plan_data := (deck_defs[_deck_ids[index]] as Dictionary).get("plan", {}) as Dictionary
		_cpus.append(CpuPlayer.new(_engine.effects, _combat.decklist(index), plan_data))
	_refresh()


## Ends the game that is over and plays the next one.
func _next_game() -> void:
	if _combat.next_game():
		_start_game()


## A button that opens the two ways to copy the replay.
func _make_replay_menu() -> MenuButton:
	var menu := MenuButton.new()
	menu.flat = false
	var popup := menu.get_popup()
	popup.add_item("Copy replay as legible text", REPLAY_AS_TEXT)
	popup.add_item("Copy replay as compressed code", REPLAY_AS_CODE)
	popup.id_pressed.connect(_copy_replay)
	return menu


## Puts the combat's replay (CombatReplay, every game so far) on the clipboard, to paste into a
## bug report: as legible JSON, or as a short code. Both paste back the same way.
func _copy_replay(format: int) -> void:
	var replay := _combat.replay()
	var text := replay.to_code() if format == REPLAY_AS_CODE else replay.to_text()
	DisplayServer.clipboard_set(text)
	# Only the latest notice: it replaces the previous one, and the next action clears it.
	_status_label.text = _status_text + "  |  Replay copied as %s (%d characters)" % ["compressed code" if format == REPLAY_AS_CODE else "legible text", text.length()]


## Goes back to the deck select screen, with this match's decks selected.
func _change_decks() -> void:
	var deck_select: Node = (load(DECK_SELECT_SCENE) as PackedScene).instantiate()
	deck_select.call("setup", _deck_ids, _cpu_seats)
	var tree := get_tree()
	tree.root.add_child(deck_select)
	tree.current_scene = deck_select
	queue_free()


func _refresh() -> void:
	var score := _combat.score()
	var game := "Round %d%s  |  Score %d-%d  |  Turn %d  |  Seed %d" % [_combat.round_number, " (Sudden Death)" if _combat.sudden_death else "",
			score[0], score[1], _engine.turn, _combat.combat_seed]
	if _engine.fighting != -1 and not _engine.is_over():
		game += "  |  Player %d is fighting" % (_engine.fighting + 1)
	var extra_note := ""
	for player in _engine.extra_draws_next_round.size():
		if _engine.extra_draws_next_round[player] > 0:
			extra_note += "  |  Player %d draws %d extra cards next round" % [player + 1, _engine.extra_draws_next_round[player]]
	if _combat.is_over():
		_status_label.text = "%s  |  Player %d wins the combat %d-%d" % [game, _combat.winner() + 1, score[_combat.winner()], score[1 - _combat.winner()]]
	elif _engine.winner == MatchEngine.SUDDEN_DEATH:
		_status_label.text = "%s  |  Both players won: Sudden Death decides the round" % game
	elif _engine.is_over():
		_status_label.text = "%s  |  Player %d wins round %d%s" % [game, _engine.winner + 1, _combat.round_number, extra_note]
	elif _engine.is_waiting_for_choice() and _is_hidden(_engine.choice_chooser()):
		_status_label.text = "%s  |  Player %d (CPU) is choosing" % [game, _engine.choice_chooser() + 1]
	elif _engine.is_waiting_for_choice():
		var prompt := ActionText.prompt(_engine.view_for(_engine.choice_chooser()), _database)
		_status_label.text = "%s  |  Player %d: %s" % [game, _engine.choice_chooser() + 1, prompt]
	else:
		_status_label.text = "%s  |  Player %d to act" % [game, _engine.current_index + 1]
	_status_text = _status_label.text
	_fill_shared_row()
	
	for index in 2:
		_fill_player_panel(index)

	for child in _actions_box.get_children():
		_actions_box.remove_child(child)
		child.queue_free()


	if _cpu_seats[_actor()] and not _engine.is_over():
		_add_text(_actions_box, "Player %d (CPU) is thinking..." % (_actor() + 1))
		_finish_refresh()
		return

	var revealed := _engine.choice_revealed()
	if not revealed.is_empty():
		var shown := HFlowContainer.new()
		shown.add_theme_constant_override("h_separation", 16)
		_add_text(shown, "Deck (%d):" % revealed.size())
		for card in revealed:
			shown.add_child(CardChip.for_card(card))
		_actions_box.add_child(shown)

	var order: Array[String] = []
	var groups := {}
	for action in _engine.legal_actions():
		var key := _group_key(action)
		if key.is_empty():
			key = "single:%d" % order.size()
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(action)

	for key in order:
		var members := groups[key] as Array
		if members.size() == 1:
			_add_action_button(members[0] as Dictionary, "")
			continue
		var first := members[0] as Dictionary
		var header := _make_button(_engine.current_player().active if first["type"] == "retreat" else _shown_for(first))
		header.text = "%s  %s" % [key, "▾" if key == _open_group else "▸"]
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.pressed.connect(_on_group_pressed.bind(key))
		_actions_box.add_child(header)
		if key == _open_group:
			for action: Dictionary in members:
				_add_action_button(action, "      ↳ ")

	if _engine.is_over():
		var next := Button.new()
		next.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if _combat.is_over():
			next.text = "New combat"
			next.pressed.connect(_start_combat)
		elif _combat.next_is_sudden_death():
			next.text = "Play Sudden Death (%d Mercy Card each)" % Combat.SUDDEN_DEATH_PRIZE_COUNT
			next.pressed.connect(_next_game)
		else:
			next.text = "Next round (round %d)" % (_combat.round_number + 1)
			next.pressed.connect(_next_game)
		_actions_box.add_child(next)

	_finish_refresh()


## The log (as the human sees it, against the CPU), then the CPU's next decision if it is to
## act.
func _finish_refresh() -> void:
	# Against the CPU, the log is the human's: the CPU's draws, Mercy Cards and answers show as
	# the human sees them (MatchEvent). Otherwise it is everything.
	var events := _engine.match_log.entries
	if _cpu_seats.count(false) == 1:
		events = _engine.events_for(_cpu_seats.find(false), 0)
	var lines := EventText.lines(events, _database)
	lines.reverse()
	_log_label.text = "\n".join(lines)
	_schedule_cpu()


## The player who answers the open question, or else the player taking the turn.
func _actor() -> int:
	return _engine.choice_chooser() if _engine.is_waiting_for_choice() else _engine.current_index


## Whether a player's hidden cards are hidden on screen: the CPU's, when a human plays
## against it. With two humans or two CPUs, everything is shown.
func _is_hidden(index: int) -> bool:
	return _cpu_seats[index] and not _cpu_seats[1 - index]


## Starts the pause before the CPU's next decision, once.
func _schedule_cpu() -> void:
	if _cpu_waiting or _engine.is_over() or not _cpu_seats[_actor()]:
		return
	_cpu_waiting = true
	get_tree().create_timer(CPU_DELAY).timeout.connect(_play_cpu.bind(_game_number))


## Whether the mouse is on a control that shows a card's text (CardChip, CardButton).
func _is_reading_a_card() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and not hovered.tooltip_text.is_empty()


## The CPU decides from its own view of the round (PlayerView) and its action is applied.
func _play_cpu(game_number: int) -> void:
	if game_number != _game_number:
		return
	_cpu_waiting = false
	if _engine.is_over() or not _cpu_seats[_actor()]:
		return
	# While the mouse is on a card, the CPU waits: acting would rebuild the board and close
	# the card's text.
	if _is_reading_a_card():
		_schedule_cpu()
		return
	if _engine.turn != _cpu_turn:
		_cpu_turn = _engine.turn
		_cpu_decisions = 0
	_cpu_decisions += 1
	var action := _cpus[_actor()].choose(_engine.view_for(_actor()))
	if _cpu_decisions > CPU_DECISIONS_PER_TURN and _engine.is_legal({"type": "end_turn"}):
		push_warning("Hotseat: the CPU took more than %d decisions this turn; ending it" % CPU_DECISIONS_PER_TURN)
		action = {"type": "end_turn"}
	_open_group = ""
	_engine.apply(action)
	_refresh()


## Actions that share a first choice (which card) and differ in a second (which target)
## are grouped under one button. Ungrouped actions return an empty key.
func _group_key(action: Dictionary) -> String:
	var player := _engine.current_player()
	match str(action["type"]):
		"attach":
			return "Attach %s" % player.hand[int(action["hand_index"])].name
		"evolve":
			return "Evolve into %s" % player.hand[int(action["hand_index"])].name
		"retreat":
			return "Flee %s" % player.active.card.name
	return ""


func _add_action_button(action: Dictionary, prefix: String) -> void:
	var button := _make_button(_shown_for(action))
	button.text = prefix + ActionText.label(_engine.view_for(_actor()), action, _database)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_on_action_pressed.bind(action))
	_actions_box.add_child(button)

## What an action is about: the card it plays, attaches or evolves into, the Darkner that
## attacks or is fled to, or what a choice option shows. Null when it is about no card.
func _shown_for(action: Dictionary) -> Object:
	var player := _engine.current_player()
	match str(action["type"]):
		"bench", "attach", "evolve", "play_trainer":
			return player.hand[int(action["hand_index"])]
		"attack":
			return player.active
		"retreat":
			return player.bench[int(action["slot"])]
		"use_power":
			return player.active if int(action["slot"]) == -1 else player.bench[int(action["slot"])]
		"use_area":
			return _engine.stadium
		"choose":
			return _engine.choice_option_shows(int(action["option"]))
	return null


## A button that shows a card's text on hover when the action is about a card, and a plain
## button otherwise, so Heads, Take nothing or End turn show no popup.
func _make_button(shown: Object) -> Button:
	if shown is CardData:
		var card_button := CardButton.new()
		card_button.show_card(shown as CardData)
		return card_button
	if shown is CardInPlay:
		var in_play_button := CardButton.new()
		in_play_button.show_in_play(shown as CardInPlay)
		return in_play_button
	return Button.new()


func _fill_shared_row() -> void:
	for child in _shared_row.get_children():
		_shared_row.remove_child(child)
		child.queue_free()
	if _engine.stadium != null:
		_add_text(_shared_row, "Area:")
		_shared_row.add_child(CardChip.for_card(_engine.stadium))
		_add_text(_shared_row, "(Player %d)" % (_engine.stadium_owner + 1))
	if _engine.resolving_trainer != null:
		_add_text(_shared_row, "Playing:")
		_shared_row.add_child(CardChip.for_card(_engine.resolving_trainer))

func _on_discard_pressed(index: int) -> void:
	_discard_open[index] = not _discard_open[index]
	_refresh()

func _on_group_pressed(key: String) -> void:
	_open_group = "" if key == _open_group else key
	_refresh()


func _on_action_pressed(action: Dictionary) -> void:
	_open_group = ""
	_engine.apply(action)
	_refresh()


func _fill_player_panel(index: int) -> void:
	var panel := _player_panels[index]
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()

	var player := _engine.players[index]
	var header := "PLAYER %d (%s)%s" % [index + 1, _deck_names[index], "  CPU" if _cpu_seats[index] else ""]
	if not _engine.is_over() and _actor() == index:
		header += "   <- to act"
	_add_text(panel, header)
	var counters := HBoxContainer.new()
	counters.add_theme_constant_override("separation", 16)
	_add_text(counters, "TP: %d%%   Mercy Cards left: %d   Deck: %d   Hand: %d" % [
		player.tp * 25, player.prizes.size(), player.deck.size(), player.hand.size(),
	])
	var discard_button := Button.new()
	discard_button.text = "Discard pile: %d  %s" % [player.discard.size(), "▾" if _discard_open[index] else "▸"]
	discard_button.disabled = player.discard.is_empty()
	discard_button.pressed.connect(_on_discard_pressed.bind(index))
	counters.add_child(discard_button)
	panel.add_child(counters)
	if _discard_open[index] and not player.discard.is_empty():
		var pile := HFlowContainer.new()
		pile.add_theme_constant_override("h_separation", 16)
		_add_text(pile, "Top first:")
		for depth in range(player.discard.size() - 1, -1, -1):
			pile.add_child(CardChip.for_card(player.discard[depth]))
		panel.add_child(pile)

	var battle_zone := HBoxContainer.new()
	_add_text(battle_zone, "Battle Zone:")
	if player.active != null:
		battle_zone.add_child(CardChip.for_in_play(player.active))
	else:
		_add_text(battle_zone, "none")
	panel.add_child(battle_zone)

	_add_text(panel, "Field:" if not player.bench.is_empty() else "Field: empty")
	for slot in player.bench.size():
		var row := HBoxContainer.new()
		_add_text(row, "   %d)" % (slot + 1))
		row.add_child(CardChip.for_in_play(player.bench[slot]))
		panel.add_child(row)

	var hand := HFlowContainer.new()
	hand.add_theme_constant_override("h_separation", 16)
	if _is_hidden(index):
		_add_text(hand, "Hand: %d card%s" % [player.hand.size(), "" if player.hand.size() == 1 else "s"])
	else:
		_add_text(hand, "Hand:")
		for card in player.hand:
			hand.add_child(CardChip.for_card(card))
	panel.add_child(hand)


func _add_text(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


func _show_error(message: String) -> void:
	_status_label.text = message
	for panel in _player_panels:
		for child in panel.get_children():
			child.queue_free()