extends RefCounted

const LAYOUT := preload("res://game/screen/board/board_layout.gd")
const EYE_FRAMES := preload("res://assets/ui/board/eye_frames.tres")
const DIALOGUE := preload("res://game/screen/board/board_dialogue.gd")
const CARD_VIEW := preload("res://game/screen/board/card_inspection.gd")
const COIN := preload("res://game/screen/board/board_coin.gd")
const SELECTION := preload("res://game/screen/board/board_selection.gd")
const WORDS := preload("res://game/presentation/board_text.gd")
var board
var selected: CardData
var targets: Array[Dictionary] = []
var marks: Control
var mercy_highlight: Panel
var overlay: ColorRect
var grid: HFlowContainer
var dialogue: DIALOGUE
var choice_card_view: CARD_VIEW
var choices_scroll: ScrollContainer
var coin: COIN
var selection: SELECTION
var eye_button: Button
var eye_sprite: AnimatedSprite2D
var menu_hidden := false
var menu_visibility: Dictionary = {}
var modal := false
var controls: HFlowContainer
var action_box: Control
var drag_card: Card
var dragging := false
var drag_z := 0
var press_at := Vector2.ZERO
var pressing_hand := false
var browsing := false
var cpu_clock := 0.0
var last_events: PackedStringArray = []
var paused_overlay := false
var paused_marks := false

func _init(owner: Control) -> void:
	board = owner
	marks = Control.new()
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.z_index = 500
	board.add_child(marks)
	_build_overlay()
	selection = SELECTION.new(self)
	coin = COIN.new(self)
	board.get_node("Interface/Pass").pressed.connect(pass_turn)

func _button(text: String, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = dimensions
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.BLACK
	normal.border_color = Color.WHITE
	normal.set_border_width_all(3)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color.YELLOW
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("292929")
	disabled.border_color = Color("808080")
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", Color("b0b0b0"))
	return button

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.size = LAYOUT.BOARD_SIZE
	overlay.z_index = 4020
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(overlay)
	dialogue = DIALOGUE.new()
	dialogue.size = LAYOUT.DIALOGUE_SIZE
	overlay.add_child(dialogue)
	choice_card_view = CARD_VIEW.new(board)
	overlay.add_child(choice_card_view)
	choices_scroll = ScrollContainer.new()
	choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(choices_scroll)
	grid = HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	choices_scroll.add_child(grid)
	controls = HFlowContainer.new()
	controls.size = LAYOUT.CONTROLS_SIZE
	controls.alignment = FlowContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("h_separation", 18)
	overlay.add_child(controls)
	eye_button = _button("", LAYOUT.EYE_SIZE)
	eye_button.size = LAYOUT.EYE_SIZE
	eye_button.pressed.connect(_toggle_menu)
	overlay.add_child(eye_button)
	eye_sprite = AnimatedSprite2D.new()
	eye_sprite.sprite_frames = EYE_FRAMES
	eye_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	eye_sprite.position = eye_button.size / 2.0
	eye_sprite.scale = Vector2.ONE * (52.0 / 592.0)
	eye_button.add_child(eye_sprite)
	_reset_choice_layout()
	_set_eye(true, false)
	overlay.hide()

func _set_eye(open: bool, animate: bool = true) -> void:
	var animation: StringName = &"opening" if open else &"closing"
	if animate:
		eye_sprite.play(animation)
		eye_sprite.set_frame_and_progress(0, 0.0)
	else:
		eye_sprite.stop()
		eye_sprite.animation = animation
		eye_sprite.frame = EYE_FRAMES.get_frame_count(animation) - 1

func _toggle_menu() -> void:
	menu_hidden = not menu_hidden
	if menu_hidden:
		menu_visibility.clear()
		for child: Node in overlay.get_children():
			if child is Control and child != eye_button:
				menu_visibility[child] = child.visible
				child.hide()
		overlay.color = Color.TRANSPARENT
		marks.hide()
		_set_eye(false)
		eye_button.tooltip_text = WORDS.SHOW_SELECTION
	else:
		for child: Control in menu_visibility:
			if is_instance_valid(child):
				child.visible = menu_visibility[child]
		overlay.color = Color(0, 0, 0, 0.55) if modal else Color.TRANSPARENT
		marks.show()
		_set_eye(true)
		eye_button.tooltip_text = WORDS.HIDE_SELECTION
	selection.set_menu_visible(not menu_hidden)

func blocks_board_at(point: Vector2) -> bool:
	if not overlay.visible:
		return false
	if eye_button.get_global_rect().has_point(point):
		return true
	if menu_hidden:
		return false
	if modal or dialogue.get_global_rect().has_point(point):
		return true
	for node: Node in grid.get_children() + controls.get_children():
		if node is Control and node.is_visible_in_tree() and node.get_global_rect().has_point(point):
			return true
	return false

func _open_choices(text: String, blocking: bool) -> void:
	menu_hidden = false
	menu_visibility.clear()
	_set_eye(true, false)
	eye_button.tooltip_text = WORDS.HIDE_SELECTION
	dialogue.show()
	choices_scroll.show()
	controls.show()
	marks.show()
	modal = blocking
	_reset_choice_layout()
	choice_card_view.signature = ""
	overlay.color = Color(0, 0, 0, 0.55) if modal else Color.TRANSPARENT
	dialogue.message(text)
	choice_card_view.hide()
	var resolving: CardData = board.player_view.resolving_trainer if board.player_view != null else null
	if resolving != null and not board.player_view.is_over and board.player_view.chooser == board.player_view.viewer:
		choice_card_view.show_card(resolving)
	overlay.show()

func _reset_choice_layout() -> void:
	dialogue.position = LAYOUT.DIALOGUE_ORIGIN
	choices_scroll.position = LAYOUT.CHOICES_ORIGIN
	choices_scroll.size = LAYOUT.CHOICES_SIZE
	eye_button.position = LAYOUT.EYE_ORIGIN
	choice_card_view.area = LAYOUT.CHOICE_CARD_AREA
	controls.position = LAYOUT.CONTROLS_ORIGIN

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func reset_round() -> void:
	browsing = false
	cpu_clock = 0.0
	menu_hidden = false
	menu_visibility.clear()
	selection.reset_choice()
	choice_card_view.hide()
	overlay.hide()

func refresh(events: Array[MatchEvent]) -> void:
	selection.reset()
	_clear(grid)
	_clear(controls)
	_clear(action_box)
	overlay.hide()
	browsing = false
	last_events = EventText.lines(events, board.session.cards)
	board.get_node("Interface/Status").tooltip_text = "\n".join(last_events)
	var view: PlayerView = board.player_view
	var pass_button := board.get_node("Interface/Pass") as Button
	pass_button.text = (WORDS.ENEMY_TURN if view.current != view.viewer else WORDS.PASS).to_upper()
	pass_button.disabled = true
	if view.is_over:
		_show_result()
		return
	if view.choice_kind == PendingChoice.KIND_COIN_CALL:
		var local_tosser := view.chooser == view.viewer
		var action := COIN.heads_action(view)
		coin.present(local_tosser, submit.bind(action) if local_tosser else Callable(), WORDS.COIN_FIRST_PURPOSE, action)
		return
	if not board.session.is_human_turn():
		return
	if view.chooser == view.viewer:
		_show_choice()
	else:
		for action: Dictionary in view.legal_actions:
			if action["type"] == "end_turn":
				pass_button.disabled = false

func _sync_card_targets() -> void:
	for target: Dictionary in targets:
		var card := target.get("card") as Card
		if not is_instance_valid(card):
			continue
		var rect: Rect2 = board.get_node("CardManager/PlayerHand")._visual_rect(card)
		target["rect"] = rect
		if target["panel"] != null:
			target["panel"].position = rect.position
			target["panel"].size = rect.size
	if is_instance_valid(mercy_highlight):
		var pile_rect := Rect2()
		for target: Dictionary in targets:
			if target.has("card"):
				pile_rect = pile_rect.merge(target["rect"]) if pile_rect.has_area() else target["rect"]
		mercy_highlight.position = pile_rect.position - Vector2(4, 4)
		mercy_highlight.size = pile_rect.size + Vector2(8, 8)

func tick(delta: float) -> void:
	_sync_card_targets()
	if pressing_hand:
		_update_drag(board.get_global_mouse_position())
	if board.session == null or board.player_view == null or board.player_view.is_over:
		return
	if board.story_battle and board.get_node("Pause").visible:
		return
	if board.player_view.choice_kind == PendingChoice.KIND_COIN_CALL and board.player_view.chooser != board.player_view.viewer:
		if dialogue.body.visible_characters >= 0 and dialogue.body.visible_characters < dialogue.body.get_total_character_count():
			return
	if not board.session.is_waiting_for_resume():
		cpu_clock = 0.0
		return
	cpu_clock += delta * board.animation_speed
	if cpu_clock >= LAYOUT.CPU_ACTION_DELAY:
		cpu_clock = 0.0
		board.session.resume()

func submit(action: Dictionary) -> bool:
	if board.player_view == null or not board.player_view.legal_actions.has(action):
		return false
	if board.player_view.choice_kind == PendingChoice.KIND_TAKE_PRIZE and action["type"] == "choose":
		board._remember_mercy(int(board.player_view.choice_options[int(action["option"])]["value"]))
	board.close_inspection()
	return board.session.submit(action)

func cancel_selection() -> void:
	var hand := board.get_node("CardManager/PlayerHand") as Hand
	hand.set("external_drag_card", null)
	if is_instance_valid(drag_card) and drag_card.is_inside_tree():
		drag_card.z_index = drag_z
		var pose := hand.get_target_pose_for(drag_card)
		if not pose.is_empty():
			drag_card.call("snap_to_pose", pose.position, pose.rotation)
	drag_card = null
	dragging = false
	selected = null
	pressing_hand = false
	targets.clear()
	mercy_highlight = null
	_clear(marks)
	if board.player_view != null and board.session != null:
		board.get_node("Interface/Status").text = WORDS.status_text(board.player_view, board.session.cards)

func _update_drag(point: Vector2) -> void:
	if not pressing_hand or not is_instance_valid(drag_card):
		return
	if not dragging and press_at.distance_to(point) >= LAYOUT.DRAG_THRESHOLD:
		var hand := board.get_node("CardManager/PlayerHand") as Hand
		hand.clear_hover()
		hand.set("external_drag_card", drag_card)
		drag_card.call("_stop_hover_tween")
		drag_card.scale = Vector2.ONE * (LAYOUT.DRAG_CARD_WIDTH / drag_card.card_size.x)
		drag_card.rotation = 0.0
		drag_card.z_index = 1000
		dragging = true
	if dragging:
		drag_card.global_position = point - drag_card.card_size * drag_card.scale / 2.0
	_update_highlights(point)

func _marker(rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 0, 0.08)
	style.border_color = Color.YELLOW
	style.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = selected == null
	marks.add_child(panel)
	return panel

func _mark(rect: Rect2, action: Dictionary, minimum_drag: float = LAYOUT.DRAG_THRESHOLD, highlight: bool = true) -> void:
	var panel := _marker(rect) if highlight else null
	targets.append({"rect": rect, "action": action, "minimum_drag": minimum_drag, "panel": panel})

func _update_highlights(point: Vector2) -> void:
	for target: Dictionary in targets:
		var panel := target["panel"] as Control
		if panel == null:
			continue
		panel.visible = selected == null or (dragging and selected.is_pokemon() and target["rect"].has_point(point))

func _slot_rect(side: String, slot: int) -> Rect2:
	var suffix := "Battle" if slot == -1 else "Field" + str(slot + 1)
	return board.get_node("CardManager/" + side + suffix).get_global_rect()

func _next_field() -> Rect2:
	return _slot_rect("Player", board.player_view.me().bench.size())

func _choice_action(index: int) -> Dictionary:
	return {"type": "choose", "option": index}

func _show_choice() -> void:
	var view: PlayerView = board.player_view
	if selection.present(view):
		return
	match view.choice_kind:
		PendingChoice.KIND_BATTLING_DARKNER, PendingChoice.KIND_SETUP_BENCH:
			for index: int in range(view.choice_options.size()):
				if view.choice_options[index].get("value") == null:
					board.get_node("Interface/Pass").text = WORDS.DONE.to_upper()
					board.get_node("Interface/Pass").disabled = false
		PendingChoice.KIND_PROMOTE, PendingChoice.KIND_CHOOSE_DARKNER:
			var side := "Opponent" if view.choice_details.get("side") == PendingChoice.SIDE_OPPONENT else "Player"
			for index: int in range(view.choice_options.size()):
				_mark(_slot_rect(side, int(view.choice_options[index]["value"])), _choice_action(index))
		PendingChoice.KIND_TAKE_PRIZE:
			for index: int in range(view.choice_options.size()):
				var number := int(view.choice_options[index]["value"])
				var pile := board.get_node("CardManager/PlayerMercy") as CardContainer
				var card: Card = pile._held_cards[number]
				_mark(board.get_node("CardManager/PlayerHand")._visual_rect(card), _choice_action(index), 20.0, false)
				targets.back()["card"] = card
			mercy_highlight = _marker(Rect2())
			_sync_card_targets()
		_:
			_show_options()
			return
	_show_board_options()

func _show_board_options() -> void:
	var view: PlayerView = board.player_view
	_open_choices(ActionText.prompt(view, board.session.cards), false)
	if view.choice_details.get("side") == PendingChoice.SIDE_OPPONENT:
		var top: float = board.get_node("CardManager/PlayerField1").position.y - 64.0
		dialogue.position.y = top
		eye_button.position.y = top
	choice_card_view.hide()

func _show_options() -> void:
	var view: PlayerView = board.player_view
	var prompt := ActionText.prompt(view, board.session.cards)
	if view.choice_kind == PendingChoice.KIND_SPARE_FIGHT:
		prompt = WORDS.SPARE_FIGHT_PROMPT
	_open_choices(prompt, true)
	for index: int in range(view.choice_options.size()):
		var option: Dictionary = view.choice_options[index]
		var action := _choice_action(index)
		var shown: Variant = option.get("shows", option.get("value"))
		var data: CardData = ActionText.card_of(shown, board.session.cards)
		var text := ActionText.option_label(view.choice_kind, view.choice_details, option, view, board.session.cards)
		if view.choice_kind == PendingChoice.KIND_SPARE_FIGHT:
			text = WORDS.SPARE if option["value"] == PendingChoice.SPARE else WORDS.FIGHT
		if data != null:
			var button := _card_option(data, text, shown as CardInPlay if shown is CardInPlay else null)
			if option.get("pick") == PendingChoice.PICK_UNDO:
				button.modulate = Color(1, 1, 0.3)
			button.set_meta("action", action)
			button.pressed.connect(submit.bind(action))
			grid.add_child(button)
		else:
			var button := _energy_option(option["value"] as Array, text) if view.choice_kind == PendingChoice.KIND_FLEE_PAYMENT else _button(text, Vector2(320, 85))
			button.set_meta("action", action)
			button.pressed.connect(submit.bind(action))
			grid.add_child(button)
	if view.choice_kind == PendingChoice.KIND_USE_ABILITY:
		_layout_ability_choice()
	overlay.show()

func _layout_ability_choice() -> void:
	choice_card_view.area = CARD_VIEW.AREA
	choice_card_view.signature = ""
	for option: Dictionary in board.player_view.choice_options:
		var shown: Variant = option.get("shows")
		var data: CardData = ActionText.card_of(shown, board.session.cards)
		if data != null:
			choice_card_view.show_card(data, shown as CardInPlay if shown is CardInPlay else null)
			break
	var bounds: Rect2 = choice_card_view.bounds
	var x := maxf(24.0, bounds.position.x - 876.0)
	var top := bounds.get_center().y - 160.0
	dialogue.position = Vector2(x, top)
	choices_scroll.position = Vector2(x, top + 230)
	choices_scroll.size = Vector2(800, 100)
	eye_button.position = Vector2(x + 812, top)
	for button: Button in grid.get_children():
		var option: Dictionary = board.player_view.choice_options[int(button.get_meta("action")["option"])]
		button.text = WORDS.YES if bool(option["value"]) else WORDS.NO

func pause_overlay(open: bool) -> void:
	if open:
		paused_overlay = overlay.visible
		paused_marks = marks.visible
		overlay.hide()
		marks.hide()
	else:
		overlay.visible = paused_overlay
		marks.visible = paused_marks

func _energy_option(energies: Array, text: String) -> Button:
	var width := minf(maxf(energies.size() * 120.0 + 20.0, 360.0), 780.0)
	var button := _button("", Vector2(width, 290))
	var spacing := (width - 20.0) / maxf(energies.size(), 1)
	for index: int in range(energies.size()):
		var image := TextureRect.new()
		image.position = Vector2(10 + index * spacing, 10)
		image.size = Vector2(spacing - 8, 225)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture = board.get_node("CardManager").card_factory.call("texture_for", ActionText.card_of(energies[index], board.session.cards))
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(image)
	var label := Label.new()
	label.position = Vector2(10, 240)
	label.size = Vector2(width - 20, 45)
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	if not energies.is_empty():
		var data := ActionText.card_of(energies[0], board.session.cards)
		if data != null:
			button.mouse_entered.connect(func() -> void: choice_card_view.show_card(data))
			if not choice_card_view.visible:
				choice_card_view.show_card(data)
	return button

func _card_option(data: CardData, text: String, state: CardInPlay = null) -> Button:
	var button := _button(text, Vector2(380, 90))
	button.mouse_entered.connect(func() -> void: choice_card_view.show_card(data, state))
	if not choice_card_view.visible:
		choice_card_view.show_card(data, state)
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			board.inspect_data(data)
			button.accept_event())
	return button

func hand_card_at(point: Vector2) -> Card:
	var hand := board.get_node("CardManager/PlayerHand") as Hand
	if is_instance_valid(hand.selected_card) and hand._visual_rect(hand.selected_card).has_point(point):
		return hand.selected_card
	return hand._pick_card_at(point)

func select_hand(card: Card) -> void:
	if board.player_view.chooser >= 0 and board.player_view.choice_kind not in [PendingChoice.KIND_BATTLING_DARKNER, PendingChoice.KIND_SETUP_BENCH]:
		return
	cancel_selection()
	var data: CardData = card.card_info["data"]
	var view: PlayerView = board.player_view
	selected = data
	drag_card = card
	drag_z = card.stored_z_index
	if view.chooser == view.viewer:
		for index: int in range(view.choice_options.size()):
			var value: Variant = view.choice_options[index].get("value")
			if value is CardData and value.id == data.id:
				var rect := _slot_rect("Player", -1) if view.choice_kind == PendingChoice.KIND_BATTLING_DARKNER else _next_field()
				_mark(rect, _choice_action(index))
				break
	else:
		for action: Dictionary in view.legal_actions:
			if not action.has("hand_index") or view.me().hand[int(action["hand_index"])].id != data.id:
				continue
			match str(action["type"]):
				"bench":
					_mark(_next_field(), action)
				"attach", "evolve":
					_mark(_slot_rect("Player", int(action["slot"])), action)
				"play_trainer":
					if data.trainer_type == CardData.TRAINER_STADIUM:
						_mark(board.get_node("CardManager/Area").get_global_rect(), action)
					else:
						var field_top: float = board.get_node("CardManager/PlayerField1").position.y
						_mark(Rect2(200, 0, 1520, field_top), action, LAYOUT.TRAINER_DRAG_THRESHOLD)

func _choose_target(point: Vector2, released_drag: bool = false, distance: float = 0.0) -> bool:
	_sync_card_targets()
	if selected != null and not released_drag:
		return false
	for index: int in range(targets.size() - 1, -1, -1):
		var target: Dictionary = targets[index]
		if released_drag and distance < float(target.get("minimum_drag", LAYOUT.DRAG_THRESHOLD)):
			continue
		if target["rect"].has_point(point):
			return submit(target["action"])
	return false

func handle_pointer(click: InputEventMouseButton) -> bool:
	if click.button_index == MOUSE_BUTTON_RIGHT and click.pressed and (selected != null or (not targets.is_empty() and board.player_view.chooser < 0)):
		cancel_selection()
		return true
	if click.button_index == MOUSE_BUTTON_RIGHT and click.pressed and not board.is_board_input_blocked(click.global_position):
		for side: String in ["Player", "Opponent"]:
			if board.get_node("CardManager/" + side + "Discard").get_global_rect().has_point(click.global_position):
				show_discard(side)
				return true
	if click.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not click.pressed and pressing_hand:
		var blocked: bool = board.is_board_input_blocked(click.global_position)
		var accepted := false
		if not blocked:
			_update_drag(click.global_position)
			if dragging:
				accepted = _choose_target(click.global_position, true, press_at.distance_to(click.global_position))
		if not accepted:
			cancel_selection()
		return true
	if board.is_board_input_blocked(click.global_position) or not click.pressed:
		return false
	if board.session == null:
		return false
	if overlay.visible and menu_hidden:
		return false
	if targets.is_empty() and selected == null:
		for side: String in ["Player", "Opponent"]:
			if board.get_node("CardManager/" + side + "Discard").get_global_rect().has_point(click.global_position):
				show_discard(side)
				return true
	if not board.session.is_human_turn() and (board.player_view.chooser >= 0 or board.player_view.is_over):
		return false
	if selection.hand_mode:
		return selection.click_hand(click.global_position)
	if _choose_target(click.global_position):
		return true
	var card := hand_card_at(click.global_position)
	if card != null:
		select_hand(card)
		press_at = click.global_position
		pressing_hand = selected != null
		return true
	return false

func begin_flee() -> void:
	board.close_inspection()
	cancel_selection()
	for action: Dictionary in board.player_view.legal_actions:
		if action["type"] == "retreat":
			_mark(_slot_rect("Player", int(action["slot"])), action)
	board.get_node("Interface/Status").text = WORDS.SELECT_FLEE

func pass_turn() -> void:
	for action: Dictionary in board.player_view.legal_actions:
		if action["type"] == "end_turn":
			submit(action)
			return
	if board.player_view.choice_kind == PendingChoice.KIND_SETUP_BENCH:
		for index: int in range(board.player_view.choice_options.size()):
			if board.player_view.choice_options[index].get("value") == null:
				submit(_choice_action(index))
				return

func _show_result() -> void:
	board.close_inspection()
	_open_choices(WORDS.result_text(board.player_view, board.session.combat.is_over()), true)
	choice_card_view.hide()
	controls.position = LAYOUT.CHOICES_ORIGIN
	var restart := _button(WORDS.PLAY_AGAIN, Vector2(380, 90))
	restart.pressed.connect(func() -> void: board._start_session())
	controls.add_child(restart)
	if not board.session.combat.is_over():
		var next := _button(WORDS.NEXT_ROUND, Vector2(380, 90))
		next.pressed.connect(func() -> void: board.session.next_game())
		controls.add_child(next)
	overlay.show()

func show_discard(side: String) -> void:
	board.close_inspection()
	cancel_selection()
	selection.browse_discard(side)
	browsing = true

func close_browser() -> void:
	board.close_inspection()
	browsing = false
	selection.reset()
	var events: Array[MatchEvent] = []
	refresh(events)
