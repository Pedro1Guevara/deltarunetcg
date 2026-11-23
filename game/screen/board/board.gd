@tool
extends Control

const LAYOUT := preload("res://game/screen/board/board_layout.gd")
const CARD_VIEW := preload("res://game/screen/board/card_inspection.gd")
const REGIONS := preload("res://game/screen/board/card_regions.gd")
const INTERACTION := preload("res://game/screen/board/board_interaction.gd")
const WORDS := preload("res://game/presentation/board_text.gd")
const ENERGY_SYMBOLS := {
	"Darkness": preload("res://assets/ui/energy/DarknessEnergy.png"),
	"Flower": preload("res://assets/ui/energy/FlowerEnergy.png"),
	"Fighting": preload("res://assets/ui/energy/FightingEnergy.png"),
	"Electric": preload("res://assets/ui/energy/EletricEnergy.png"),
	"Fun": preload("res://assets/ui/energy/FunEnergy.png"),
	"Virus": preload("res://assets/ui/energy/VirusEnergy.png"),
	"Order": preload("res://assets/ui/energy/OrderEnergy.png"),
	"Holy": preload("res://assets/ui/energy/HolyEnergy.png"),
	"Chaos": preload("res://assets/ui/energy/ChaosEnergy.png"),
	"Creative": preload("res://assets/ui/energy/CreativeEnergy.png"),
}
const NEUTRAL_SYMBOL := preload("res://assets/ui/energy/Neutral_Blank.png")
@export var story_battle: bool = true
@export var player_deck: String = "creative"
@export var opponent_deck: String = "holy"
@export var session_seed: int = -1

var session: CombatSession
var shown_round := -1
var player_view: PlayerView
var cards: Array[Card] = []
var preserve_hand := false
var mercy_pick: Dictionary = {}
var mercy_in_flight: Dictionary = {}
var inspected: CardData = null
var interaction: INTERACTION
var animation_speed: float = 1.0
var hover_view: CARD_VIEW
var pinned_view: CARD_VIEW
var inspected_zone: String = ""
var hover_key: String = ""
var hover_elapsed: float = 0.0

func _ready() -> void:
	_apply_layout()
	if Engine.is_editor_hint():
		return
	$Inspection.gui_input.connect(_inspection_input)
	$Pause/Panel/Resume.pressed.connect(func() -> void: _set_pause(false))
	$Pause/Panel/Settings.pressed.connect(_open_settings)
	$Pause/Panel/Exit.pressed.connect(_exit_game)
	$Pause/Panel/Back.pressed.connect(_close_settings)
	$Pause/Panel/Speed.value_changed.connect(func(value: float) -> void: animation_speed = value)
	$CardManager/PlayerHand.allow_drag = false
	$CardManager/PlayerHand.inspect_requested.connect(_inspect)
	interaction = INTERACTION.new(self)
	_create_inspection_views()
	_start_session.call_deferred()

func _start_session() -> void:
	shown_round = -1
	if session != null and session.updated.is_connected(_on_session_updated):
		session.updated.disconnect(_on_session_updated)
	session = CombatSession.new([player_deck, opponent_deck], [CombatSession.HUMAN, CombatSession.CPU], session_seed)
	session.updated.connect(_on_session_updated)
	if not session.start():
		$Interface/Status.text = WORDS.SESSION_ERROR % session.error

func _on_session_updated(view: PlayerView, events: Array[MatchEvent]) -> void:
	if shown_round != session.combat.round_number:
		shown_round = session.combat.round_number
		close_inspection()
		interaction.reset_round()
		mercy_pick.clear()
		for flight: Control in mercy_in_flight.values():
			if is_instance_valid(flight):
				flight.hide()
		mercy_in_flight.clear()
	player_view = view
	_clear_cards()
	_render_side("Player", view.me())
	_render_side("Opponent", view.opponent())
	if view.stadium != null:
		_add_visible(view.stadium, $CardManager/Area)
	for card: Card in cards:
		if preserve_hand and card.card_container == $CardManager/PlayerHand:
			continue
		var pose := card.card_container.get_target_pose_for(card)
		card.call("snap_to_pose", pose.position, pose.rotation)
	var score := session.combat.score()
	$Interface/Score.text = WORDS.score_text(session.combat.round_number, score[view.viewer], score[1 - view.viewer]).to_upper()
	$Interface/Status.text = WORDS.status_text(view, session.cards)
	_update_counts()
	interaction.refresh(events)
	_refresh_pinned()
	_refresh_hover_snapshot()
	_animate_mercy_pick()

func _hand_matches(view: PlayerView.SideView) -> bool:
	var hand := $CardManager/PlayerHand as Hand
	if hand._held_cards.size() != view.hand.size():
		return false
	for index: int in range(view.hand.size()):
		if hand._held_cards[index].card_info.get("data") != view.hand[index]:
			return false
	return true

func _clear_cards() -> void:
	preserve_hand = _hand_matches(player_view.me())
	if interaction != null:
		interaction.cancel_selection()
	if not preserve_hand:
		$CardManager/PlayerHand.cancel_drag()
		$CardManager/PlayerHand.clear_hover()
	for container: Node in $CardManager.get_children():
		if container is CardContainer and (container != $CardManager/PlayerHand or not preserve_hand):
			container.clear_cards()
	cards.clear()
	if preserve_hand:
		cards.assign($CardManager/PlayerHand._held_cards)
	$CardManager.reset_history()

func _render_side(side: String, state: PlayerView.SideView) -> void:
	var hand := $CardManager.get_node(side + "Hand") as CardContainer
	if side == "Player":
		if not preserve_hand:
			for data: CardData in state.hand:
				var card := _add_visible(data, hand)
				if mercy_in_flight.has(data):
					card.hide()
	else:
		_add_backs(hand, state.hand_size)
	_add_backs($CardManager.get_node(side + "Deck"), mini(state.deck_size, 4))
	_add_backs($CardManager.get_node(side + "Mercy"), state.prize_count)
	if not state.discard.is_empty():
		_add_visible(state.discard.back(), $CardManager.get_node(side + "Discard"))
	_render_darkner(state.active, $CardManager.get_node(side + "Battle"))
	for index: int in range(state.bench.size()):
		_render_darkner(state.bench[index], $CardManager.get_node(side + "Field" + str(index + 1)))
	$Interface.get_node(side + "TP").set("value", state.tp * 25.0)

func _add_visible(data: CardData, target: CardContainer) -> Card:
	var card := $CardManager.card_factory.call("create_from_data", data, target) as Card
	cards.append(card)
	card.gui_input.connect(_card_input.bind(card))
	return card

func _add_backs(target: CardContainer, count: int) -> void:
	for index: int in range(count):
		var card := $CardManager.card_factory.call("create_hidden", target) as Card
		cards.append(card)

func _render_darkner(state: CardInPlay, target: CardContainer) -> void:
	if state == null:
		return
	for previous: CardData in state.evolved_from:
		_add_visible(previous, target)
	var card := _add_visible(state.card, target)
	card.card_info["in_play"] = state
	if state.card.stage == CardData.STAGE_BREAK:
		var portrait: Vector2 = target.get_meta("display_size")
		card.card_size = Vector2(portrait.y, portrait.x)
		card.size = card.card_size
		var previous := state.evolved_from.back() as CardData if not state.evolved_from.is_empty() else state.card
		var vertical := portrait.y * REGIONS.content_start(previous.id) - card.card_size.y
		card.set_meta("display_offset", Vector2((portrait.x - card.card_size.x) / 2.0, vertical))
		target.update_card_ui()
		_layout_card_art(card.front_face_texture, state.card, card.front_face_texture.texture, Rect2(Vector2.ZERO, card.card_size))
	var label := Label.new()
	label.name = "CurrentHP"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = str(state.remaining_hp())
	label.position = Vector2(card.card_size.x - 52, 0)
	label.size = Vector2(48, 26)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	card.add_child(label)
	_render_energy_symbols(card, state)

func _remember_mercy(index: int) -> void:
	var pile := $CardManager/PlayerMercy as CardContainer
	var card: Card = pile._held_cards[index]
	var positions: Array[Vector2] = []
	for back: Card in pile._held_cards:
		positions.append(back.global_position)
	mercy_pick = {"index": index, "positions": positions, "origin": card.global_position,
		"angle": card.rotation, "size": card.card_size, "centre": $CardManager/PlayerHand._visual_rect(card).get_center(),
		"hand": player_view.me().hand.duplicate()}

func _animate_mercy_pick() -> void:
	if mercy_pick.is_empty():
		return
	var picked := mercy_pick
	mercy_pick = {}
	var remaining: Array = (picked["positions"] as Array).duplicate()
	remaining.remove_at(int(picked["index"]))
	var pile := $CardManager/PlayerMercy as CardContainer
	if pile._held_cards.size() != remaining.size():
		return
	for index: int in range(remaining.size()):
		var card: Card = pile._held_cards[index]
		var destination := card.global_position
		card.global_position = remaining[index]
		create_tween().tween_property(card, "global_position", destination, 0.3 / animation_speed)
	var destination: Card = null
	for card: Card in $CardManager/PlayerHand._held_cards:
		if not (picked["hand"] as Array).has(card.card_info["data"]):
			destination = card
			break
	if destination == null:
		return
	var flight := Control.new()
	flight.name = "MercyToHand"
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.z_index = 4000
	add_child(flight)
	flight.global_position = picked["centre"]
	var image := TextureRect.new()
	image.texture = $CardManager.card_factory.call("texture_for", destination.card_info["data"])
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.add_child(image)
	image.size = picked["size"]
	image.pivot_offset = image.size / 2.0
	image.position = -image.size / 2.0
	image.rotation = picked["angle"]
	var data := destination.card_info["data"] as CardData
	mercy_in_flight[data] = flight
	destination.hide()
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var duration := 0.4 / animation_speed
	tween.tween_property(flight, "global_position", $CardManager/PlayerHand._visual_rect(destination).get_center(), duration)
	tween.tween_property(image, "rotation", destination.rotation, duration)
	tween.tween_property(image, "scale", destination.card_size / image.size, duration)
	tween.chain().tween_callback(func() -> void:
		mercy_in_flight.erase(data)
		for card: Card in $CardManager/PlayerHand._held_cards:
			if card.card_info.get("data") == data:
				card.show()
		flight.queue_free())

func _render_energy_symbols(card: Card, state: CardInPlay) -> void:
	if state.attached_energy.is_empty():
		return
	var row := _create_energy_row(card, "EnergySymbols")
	row.position = Vector2(4, card.card_size.y - 28)
	row.size = Vector2(card.card_size.x - 8, 24)
	_fill_energy_row(row, state, LAYOUT.FIELD_ENERGY_SIZE)

func _create_energy_row(parent: Node, row_name: String) -> Control:
	var row := Control.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row

func _fill_energy_row(row: Control, state: CardInPlay, icon_size: float) -> void:
	var units: Array[Dictionary] = []
	var signature := str(row.size.x) + ":" + str(icon_size)
	for energy: CardData in state.attached_energy:
		signature += ":" + energy.id + ":" + ",".join(energy.provides)
		if energy.provides.is_empty():
			units.append({"type": "", "energy": energy})
		else:
			for kind: String in energy.provides:
				units.append({"type": kind, "energy": energy})
	if row.get_meta("signature", "") == signature:
		return
	row.set_meta("signature", signature)
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var spacing := minf(icon_size + 2.0, (row.size.x - icon_size) / maxf(units.size() - 1, 1))
	for index: int in range(units.size()):
		var unit: Dictionary = units[index]
		var energy: CardData = unit["energy"]
		var icon := TextureRect.new()
		icon.name = "Energy" + str(index + 1)
		icon.position = Vector2(index * spacing, 0)
		icon.size = Vector2.ONE * icon_size
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.texture = ENERGY_SYMBOLS.get(str(unit["type"]), NEUTRAL_SYMBOL)
		icon.set_meta("energy_id", energy.id)
		row.add_child(icon)

func _show_inspection_energy(row: Control, state: CardInPlay, region: Rect2, icon_size: float) -> void:
	row.hide()
	if state == null or state.attached_energy.is_empty():
		return
	row.position = Vector2(region.position.x + 8.0, region.end.y - icon_size - 8.0)
	row.size = Vector2(region.size.x - 16.0, icon_size)
	_fill_energy_row(row, state, icon_size)
	row.show()

func _mirror(at: Vector2, dimensions: Vector2) -> Vector2:
	return LAYOUT.BOARD_SIZE - at - dimensions

func _apply_layout() -> void:
	if not has_node("CardManager"):
		return
	if not Engine.is_editor_hint():
		$CardManager/PlayerHand.cancel_drag()
		$CardManager/PlayerHand.clear_hover()
		$Inspection.hide()
		inspected = null
	for index: int in range(LAYOUT.FIELD_COUNT):
		var at := LAYOUT.FIELD_ORIGIN + Vector2(index * LAYOUT.FIELD_SPACING, 0)
		_place("PlayerField" + str(index + 1), at)
		_place("OpponentField" + str(index + 1), _mirror(at, LAYOUT.FIELD_CARD_SIZE) + LAYOUT.OPPONENT_FIELD_OFFSET)
	_place("PlayerBattle", LAYOUT.BATTLE_ORIGIN)
	_place("OpponentBattle", _mirror(LAYOUT.BATTLE_ORIGIN, LAYOUT.BATTLE_CARD_SIZE))
	var deck := LAYOUT.DECK_ORIGIN
	var discard := LAYOUT.DISCARD_ORIGIN
	var mercy := LAYOUT.MERCY_ORIGIN
	for entry: Array in [["Deck", deck, LAYOUT.FIELD_CARD_SIZE], ["Discard", discard, LAYOUT.FIELD_CARD_SIZE], ["Mercy", mercy, LAYOUT.MERCY_CARD_SIZE]]:
		_place("Player" + str(entry[0]), entry[1])
		var upper_offset := LAYOUT.OPPONENT_PILE_OFFSET if entry[0] in ["Deck", "Discard"] else Vector2.ZERO
		_place("Opponent" + str(entry[0]), _mirror(entry[1], entry[2]) + upper_offset)
	_place("Area", LAYOUT.AREA_ORIGIN)
	_style_pass_button()
	$Interface/Pass.position = LAYOUT.PASS_ORIGIN
	$Interface/Score.position = LAYOUT.SCORE_ORIGIN
	$Interface/Score.size = LAYOUT.SCORE_SIZE
	$Interface/Score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for side: String in ["Player", "Opponent"]:
		var own := side == "Player"
		for suffix: String in ["Battle", "Field1", "Field2", "Field3", "Field4", "Deck", "Discard", "Mercy"]:
			var slot := $CardManager.get_node(side + suffix) as CardContainer
			slot.set("face_rotation", (90.0 if own else 270.0) if suffix == "Mercy" else 0.0)
			if suffix.begins_with("Field"):
				var outline := slot.get_node("LandscapeOutline") as Control
				outline.position = LAYOUT.BREAK_OUTLINE_OFFSET
				outline.size = LAYOUT.BREAK_OUTLINE_SIZE
		var tp := $Interface.get_node(side + "TP") as Control
		tp.set("horizontal", false)
		tp.size = LAYOUT.TP_SIZE
		var tp_at := LAYOUT.TP_ORIGIN
		tp.position = tp_at if own else _mirror(tp_at, tp.size)
		tp.pivot_offset = tp.size / 2.0
		tp.rotation = 0.0
	$CardManager/PlayerHand.reveal = 0.0
	$CardManager/PlayerHand.expanded = false
	$CardManager/OpponentHand.reveal = 0.0
	_refresh_text()
	if not Engine.is_editor_hint():
		for container: Node in $CardManager.get_children():
			if container is CardContainer:
				container.update_card_ui()

func _style_pass_button() -> void:
	var button := $Interface/Pass as Button
	var active := StyleBoxFlat.new()
	active.bg_color = Color.BLACK
	active.border_color = Color.YELLOW
	active.set_border_width_all(3)
	button.add_theme_stylebox_override("normal", active)
	var hover := active.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.14, 0, 1)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled := active.duplicate() as StyleBoxFlat
	disabled.border_color = Color("666666")
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color.YELLOW)
	button.add_theme_color_override("font_hover_color", Color.YELLOW)
	button.add_theme_color_override("font_pressed_color", Color.YELLOW)
	button.add_theme_color_override("font_disabled_color", Color("999999"))

func _place(node_name: String, at: Vector2) -> void:
	var container := $CardManager.get_node(node_name) as Control
	container.position = at

func _refresh_text() -> void:
	if not has_node("Interface"):
		return
	$Interface/Score.text = ""
	$Interface/Pass.text = WORDS.PASS.to_upper()
	$Interface/PlayerName.text = WORDS.PLAYER
	$Interface/OpponentName.text = WORDS.ENEMY
	for side: String in ["Player", "Opponent"]:
		var avatar := $Interface.get_node(side + "Avatar") as Control
		var label := $Interface.get_node(side + "Name") as Label
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position.x = avatar.position.x + avatar.size.x / 2.0 - label.size.x / 2.0
	for name: String in ["PlayerAvatar", "OpponentAvatar", "PlayerName", "OpponentName"]:
		$Interface.get_node(name).visible = true
	$Interface/Status.hide()
	_refresh_pause_menu()
	$Pause/Panel/Resume.text = WORDS.RESUME.to_upper()
	$Pause/Panel/Settings.text = WORDS.SETTINGS.to_upper()
	$Pause/Panel/Exit.text = WORDS.EXIT_GAME.to_upper()
	$Pause/Panel/Concede.text = WORDS.CONCEDE.to_upper()
	$Pause/Panel/Concede.tooltip_text = WORDS.CONCEDE_NOTE
	$Pause/Panel/Back.text = WORDS.BACK.to_upper()
	$Pause/Panel/SpeedLabel.text = WORDS.ANIMATION_SPEED
	for container: Node in $CardManager.get_children():
		if container is CardContainer:
			var zone := container.get_node_or_null("ZoneLabel") as Label
			if zone != null:
				zone.text = str(WORDS.ZONES.get(str(container.get_meta("zone_kind", "")), "")).to_upper()

func _update_counts() -> void:
	if player_view == null:
		return
	for side: String in ["Player", "Opponent"]:
		var state: PlayerView.SideView = player_view.me() if side == "Player" else player_view.opponent()
		var deck := $CardManager.get_node(side + "Deck") as CardContainer
		var label := deck.get_node("Count") as Label
		label.text = "%d | %d" % [state.deck_size, state.hand_size]
		label.tooltip_text = WORDS.COUNT_HINT
		label.position.y = 198.0
		if side == "Opponent":
			label.position.y += 2.0 * maxi(mini(state.deck_size, deck.get("max_stack_display")) - 1, 0) * float(deck.get("stack_display_gap"))

func _exit_game() -> void:
	get_tree().quit()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and interaction != null:
		_update_hover_inspection(delta, get_global_mouse_position())
		interaction.tick(delta)

func is_board_input_blocked(at: Vector2) -> bool:
	if interaction != null and interaction.blocks_board_at(at):
		return true
	return inspected != null or $Pause.visible

func _set_pause(open: bool) -> void:
	$Pause.visible = open
	if interaction != null:
		interaction.pause_overlay(open)
	_close_settings()
	if open:
		$CardManager/PlayerHand.clear_hover()

func _open_settings() -> void:
	for name: String in ["Resume", "Settings", "Concede", "Exit"]:
		$Pause/Panel.get_node(name).hide()
	for name: String in ["SpeedLabel", "Speed", "Back"]:
		$Pause/Panel.get_node(name).show()
	$Pause/Panel/Title.text = WORDS.SETTINGS.to_upper()

func _close_settings() -> void:
	for name: String in ["Settings", "Concede", "Exit"]:
		$Pause/Panel.get_node(name).show()
	for name: String in ["SpeedLabel", "Speed", "Back"]:
		$Pause/Panel.get_node(name).hide()
	_refresh_pause_menu()

func _refresh_pause_menu() -> void:
	$Pause/Panel/Title.text = WORDS.PAUSED.to_upper() if story_battle else WORDS.MENU.to_upper()
	$Pause/Panel/Resume.visible = story_battle
	$Pause/Panel/Resume.position.y = LAYOUT.PAUSE_RESUME_Y
	var offset := 0.0 if story_battle else LAYOUT.MULTIPLAYER_MENU_OFFSET
	$Pause/Panel/Settings.position.y = LAYOUT.PAUSE_SETTINGS_Y + offset
	$Pause/Panel/Concede.position.y = LAYOUT.PAUSE_CONCEDE_Y + offset
	$Pause/Panel/Exit.position.y = LAYOUT.PAUSE_EXIT_Y + offset

func _card_input(event: InputEvent, card: Card) -> void:
	if not event is InputEventMouseButton or $Pause.visible:
		return
	var click := event as InputEventMouseButton
	if click.button_index == MOUSE_BUTTON_RIGHT and click.pressed and card.show_front:
		_inspect(card)
		get_viewport().set_input_as_handled()

func _inspect(card: Card) -> void:
	card = _top_darkner_card(card)
	_reset_hover_inspection()
	$CardManager/PlayerHand.clear_hover()
	inspected = card.card_info["data"] as CardData
	inspected_zone = str(card.card_container.name)
	pinned_view.show_card(inspected as CardData, card.card_info.get("in_play") as CardInPlay, inspected_zone, true)
	$Inspection.show()

func inspect_data(data: CardData) -> void:
	_reset_hover_inspection()
	$CardManager/PlayerHand.clear_hover()
	inspected = data
	inspected_zone = ""
	pinned_view.show_card(data)
	$Inspection.show()

func close_inspection() -> void:
	_reset_hover_inspection()
	$Inspection.hide()
	if is_instance_valid(pinned_view):
		pinned_view.hide()
	inspected = null
	inspected_zone = ""

func _refresh_pinned() -> void:
	if inspected == null:
		return
	if player_view.is_over:
		close_inspection()
		return
	if inspected_zone.is_empty():
		return
	for card: Card in cards:
		if str(card.card_container.name) == inspected_zone and card.card_info.has("data") and card.card_info["data"].id == (inspected as CardData).id:
			inspected = card.card_info["data"]
			pinned_view.show_card(inspected as CardData, card.card_info.get("in_play") as CardInPlay, inspected_zone, true)
			return
	close_inspection()

func _inspection_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not _inspection_contains(click.global_position):
			close_inspection()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or (event is InputEventKey and event.echo):
		return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and not $Pause.visible and interaction != null and interaction.dialogue.skip_typing():
			get_viewport().set_input_as_handled()
			return
		if click.pressed:
			_reset_hover_inspection()
		if interaction != null and interaction.handle_pointer(click):
			get_viewport().set_input_as_handled()
			return
		if click.button_index == MOUSE_BUTTON_RIGHT and click.pressed and not is_board_input_blocked(click.global_position):
			if $CardManager/PlayerHand.inspect_at(click.global_position):
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_cancel"):
		if interaction != null and interaction.browsing and inspected == null:
			interaction.close_browser()
			get_viewport().set_input_as_handled()
			return
		if interaction != null and (interaction.selected != null or (not interaction.targets.is_empty() and player_view != null and player_view.chooser < 0)) and inspected == null:
			interaction.cancel_selection()
			get_viewport().set_input_as_handled()
			return
		if $CardManager/PlayerHand.cancel_drag():
			get_viewport().set_input_as_handled()
			return
		_set_pause(not $Pause.visible)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and interaction != null and interaction.pressing_hand:
		interaction.cancel_selection()

func _create_inspection_views() -> void:
	hover_view = CARD_VIEW.new(self)
	hover_view.z_index = 3990
	add_child(hover_view)
	pinned_view = CARD_VIEW.new(self)
	$Inspection.add_child(pinned_view)
	$Inspection.color = Color.TRANSPARENT
	interaction.action_box = pinned_view.hotspots

func _reset_hover_inspection() -> void:
	hover_key = ""
	hover_elapsed = 0.0
	if is_instance_valid(hover_view):
		hover_view.hide()

func _refresh_hover_snapshot() -> void:
	if not hover_view.visible:
		return
	for card: Card in cards:
		if card.card_info.has("data") and str(card.card_container.name) + ":" + card.card_info["data"].id == hover_key:
			hover_view.show_card(card.card_info["data"] as CardData, card.card_info.get("in_play") as CardInPlay)
			return
	_reset_hover_inspection()

func _board_card_at(point: Vector2) -> Card:
	var hand := $CardManager/PlayerHand as Hand
	if is_instance_valid(hand.selected_card) and hand._visual_rect(hand.selected_card).has_point(point):
		return null
	if hand._pick_card_at(point) != null:
		return null
	for index: int in range(cards.size() - 1, -1, -1):
		var card: Card = cards[index]
		if not is_instance_valid(card) or not card.show_front or card.card_container is Hand or not card.card_info.has("data"):
			continue
		if hand._visual_rect(card).has_point(point):
			return _top_darkner_card(card)
	return null

func _top_darkner_card(card: Card) -> Card:
	var zone := str(card.card_container.name)
	if zone.ends_with("Battle") or zone.contains("Field"):
		var top := card.card_container._held_cards.back() as Card
		if top.card_info.has("in_play"):
			return top
	return card

func _update_hover_inspection(delta: float, point: Vector2) -> void:
	if is_board_input_blocked(point) or interaction.pressing_hand or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_reset_hover_inspection()
		return
	var card := _board_card_at(point)
	if card == null:
		_reset_hover_inspection()
		return
	var data: CardData = card.card_info["data"]
	var key := str(card.card_container.name) + ":" + data.id
	if key != hover_key:
		hover_key = key
		hover_elapsed = 0.0
		hover_view.hide()
	hover_elapsed += delta
	if hover_elapsed >= LAYOUT.BOARD_HOVER_DELAY:
		hover_view.show_card(data, card.card_info.get("in_play") as CardInPlay)

func _layout_card_art(art: TextureRect, data: CardData, texture: Texture2D, region: Rect2) -> void:
	var sideways := data.stage == CardData.STAGE_BREAK
	art.rotation = 0.0
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.size = Vector2(region.size.y, region.size.x) if sideways else region.size
	art.pivot_offset = art.size / 2.0
	art.position = region.get_center() - art.size / 2.0
	art.rotation = -PI / 2.0 if sideways else 0.0

func _inspection_contains(point: Vector2) -> bool:
	return pinned_view.contains(point)

func _displayed_art_bounds(data: CardData, texture: Texture2D, region: Rect2) -> Rect2:
	var dimensions := texture.get_size()
	if data.stage == CardData.STAGE_BREAK:
		dimensions = Vector2(dimensions.y, dimensions.x)
	var factor := minf(region.size.x / dimensions.x, region.size.y / dimensions.y)
	var displayed := dimensions * factor
	return Rect2(region.get_center() - displayed / 2.0, displayed)
