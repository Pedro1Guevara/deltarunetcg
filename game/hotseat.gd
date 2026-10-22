extends Control

const DECK_PLAYER_1 := "deltarune_chaos"
const DECK_PLAYER_2 := "deltarune_holy"
const FONT_SIZE := 22

var _engine := MatchEngine.new()
var _seed: int = 0

var _status_label: Label
var _player_panels: Array[VBoxContainer] = []
var _actions_box: VBoxContainer
var _log_label: Label
var _open_group: String = ""

func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = FONT_SIZE
	theme = ui_theme
	_build_ui()
	_start_match()


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
	board.add_child(_status_label)

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

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	side_panel.add_child(buttons)
	for entry: Array in [
		["New match", _start_match],
		["Window / Fullscreen (F11)", WindowControls.toggle_windowed],
		["Quit (Esc)", controls.quit],
	]:
		var button := Button.new()
		button.text = str(entry[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1] as Callable)
		buttons.add_child(button)


func _make_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _start_match() -> void:
	_start_with_rules(MatchRules.deltarune())


func _start_with_rules(match_rules: MatchRules) -> void:
	var database := DataLoader.load_card_database()
	var decks: Variant = DataLoader.read_json(DataLoader.DECKS_PATH)
	if database.card_count() == 0 or not decks is Dictionary:
		_show_error("Could not load data/cards.json or data/decks.json. See the Output panel.")
		return

	var deck_defs := decks as Dictionary
	if not deck_defs.has(DECK_PLAYER_1) or not deck_defs.has(DECK_PLAYER_2):
		_show_error("decks.json must define '%s' and '%s'." % [DECK_PLAYER_1, DECK_PLAYER_2])
		return


	_seed = randi()
	_engine = MatchEngine.new()
	_engine.effects = DataLoader.load_effect_library(database, DataLoader.CARD_EFFECTS_PATH)

	var deck_1 := database.build_deck(deck_defs[DECK_PLAYER_1] as Dictionary)
	var deck_2 := database.build_deck(deck_defs[DECK_PLAYER_2] as Dictionary)
	# Test decks are smaller than the rules require on purpose: report, do not block.
	for entry: Array in [[DECK_PLAYER_1, deck_1], [DECK_PLAYER_2, deck_2]]:
		for problem in DeckValidator.validate(entry[1] as Array[CardData], match_rules):
			push_warning("Deck %s %s" % [entry[0], problem])
	_engine.start(deck_1, deck_2, match_rules, Rng.new(_seed))
	_refresh()


func _refresh() -> void:
	if _engine.winner == MatchEngine.SUDDEN_DEATH:
		_status_label.text = "Turn %d  |  Seed %d  |  Both players won: Sudden Death" % [_engine.turn, _seed]
	elif _engine.is_over():
		_status_label.text = "Turn %d  |  Seed %d  |  Player %d wins" % [_engine.turn, _seed, _engine.winner + 1]
	elif _engine.is_waiting_for_choice():
		_status_label.text = "Turn %d  |  Seed %d  |  Player %d: %s" % [_engine.turn, _seed, _engine.choice_chooser() + 1, _engine.choice_prompt()]
	else:
		_status_label.text = "Turn %d  |  Seed %d  |  Player %d to act" % [_engine.turn, _seed, _engine.current_index + 1]

	for index in 2:
		_fill_player_panel(index)

	for child in _actions_box.get_children():
		_actions_box.remove_child(child)
		child.queue_free()

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
		var header := Button.new()
		header.text = "%s  %s" % [key, "▾" if key == _open_group else "▸"]
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.pressed.connect(_on_group_pressed.bind(key))
		_actions_box.add_child(header)
		if key == _open_group:
			for action: Dictionary in members:
				_add_action_button(action, "      ↳ ")

	if _engine.winner == MatchEngine.SUDDEN_DEATH:
		var sudden_death := Button.new()
		sudden_death.text = "Play Sudden Death (1 Prize each)"
		sudden_death.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sudden_death.pressed.connect(_start_with_rules.bind(_engine.rules.with_prize_count(1)))
		_actions_box.add_child(sudden_death)

	var lines := PackedStringArray(_engine.events)
	lines.reverse()
	_log_label.text = "\n".join(lines)


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
	var button := Button.new()
	button.text = prefix + str(action["label"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_on_action_pressed.bind(action))
	_actions_box.add_child(button)


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
	var header := "PLAYER %d" % (index + 1)
	var actor := _engine.choice_chooser() if _engine.is_waiting_for_choice() else _engine.current_index
	if not _engine.is_over() and actor == index:
		header += "   <- to act"
	_add_text(panel, header)
	_add_text(panel, "Mercy Cards left: %d   Deck: %d   Discard: %d   Hand: %d" % [
		player.prizes.size(), player.deck.size(), player.discard.size(), player.hand.size(),
	])

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