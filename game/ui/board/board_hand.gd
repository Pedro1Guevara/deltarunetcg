@tool
extends Hand

signal inspect_requested(card: Card)
@export var opponent: bool = false
@export var allow_drag: bool = true
var expanded: bool = false
var reveal: float = 0.0
var selected_card: Card = null
var external_drag_card: Card = null

func _ready() -> void:
	enable_drop_zone = false
	super._ready()

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or card_manager == null:
		return
	if opponent:
		_update_target_positions()
		return
	var board := get_tree().current_scene
	var mouse := get_global_mouse_position()
	var blocked: bool = board.is_board_input_blocked(mouse)
	if is_instance_valid(external_drag_card):
		expanded = false
		reveal = move_toward(reveal, 0.0, delta * 7.0 * float(board.animation_speed))
		_update_target_positions()
		return
	var held := held_card()
	if held == null:
		expanded = not blocked and (Rect2(490, 780 if expanded else 990, 940, 300 if expanded else 90).has_point(mouse) or (selected_card != null and _visual_rect(selected_card).has_point(mouse)))
		reveal = move_toward(reveal, 1.0 if expanded else 0.0, delta * 7.0 * float(board.animation_speed))
	_update_target_positions()
	if held != null:
		return
	var next: Card = null
	if not blocked and expanded and reveal > 0.65:
		next = _pick_card_at(mouse)
		if next == null and selected_card != null and _visual_rect(selected_card).has_point(mouse):
			next = selected_card
	_select(next)

func _pick_card_at(point: Vector2) -> Card:
	for index: int in range(_held_cards.size() - 1, -1, -1):
		var card: Card = _held_cards[index]
		if card == external_drag_card:
			continue
		var pose := get_target_pose_for(card)
		var angle: float = pose.rotation
		var centre: Vector2 = pose.position + card.card_size / 2.0
		var local := (point - centre).rotated(-angle) + card.card_size / 2.0
		if Rect2(Vector2.ZERO, card.card_size).has_point(local):
			return card
	return null

func _select(next: Card) -> void:
	if selected_card == next:
		return
	if is_instance_valid(selected_card) and selected_card.current_state == DraggableObject.DraggableState.HOVERING:
		selected_card.change_state(DraggableObject.DraggableState.IDLE)
	selected_card = next
	if selected_card != null and selected_card.current_state == DraggableObject.DraggableState.IDLE:
		selected_card.is_mouse_inside = true
		selected_card.change_state(DraggableObject.DraggableState.HOVERING)

func _update_target_positions() -> void:
	if Engine.is_editor_hint():
		return
	for card: Card in _held_cards:
		if card == external_drag_card:
			continue
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if card.current_state == DraggableObject.DraggableState.IDLE:
			var pose := get_target_pose_for(card)
			card.call("settle_at", pose.position, pose.rotation)

func _update_card_states() -> void:
	for card: Card in _held_cards:
		card.show_front = not opponent
		card.can_be_interacted_with = not opponent
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE

func get_target_pose_for(card: Card) -> Dictionary:
	var visible_cards := _held_cards.duplicate()
	visible_cards.erase(external_drag_card)
	var index := visible_cards.find(card)
	if index < 0:
		return {}
	var count := visible_cards.size()
	var spread := minf(maxf(count - 1, 0) * 62.0, 720.0)
	var fraction := float(index) / maxf(count - 1, 1)
	var t := fraction - 0.5 if count > 1 else 0.0
	var left := 960.0 - spread / 2.0 + fraction * spread - card.card_size.x / 2.0
	var top := lerpf(1040.0, 900.0, reveal) + t * t * 88.0
	var angle := deg_to_rad(t * 18.0)
	if opponent:
		return {"position": Vector2(1920.0 - left - card.card_size.x, 8.0 - card.card_size.y - t * t * 16.0), "rotation": angle + PI}
	return {"position": Vector2(left, top), "rotation": angle}

func held_card() -> Card:
	for card: Card in _held_cards:
		if card.current_state == DraggableObject.DraggableState.HOLDING:
			return card
	return null

func cancel_drag() -> bool:
	var card := held_card()
	if card == null:
		return false
	card._handle_mouse_released()
	card.return_card()
	selected_card = null
	return true

func clear_hover() -> void:
	_select(null)

func _visual_rect(card: Card) -> Rect2:
	var transform := card.get_global_transform()
	var bounds := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for corner: Vector2 in [Vector2(card.size.x, 0), card.size, Vector2(0, card.size.y)]:
		bounds = bounds.expand(transform * corner)
	return bounds

func inspect_at(point: Vector2) -> bool:
	if cancel_drag():
		return true
	var card: Card = null
	if is_instance_valid(selected_card) and _visual_rect(selected_card).has_point(point):
		card = selected_card
	else:
		card = _pick_card_at(point)
	if card == null:
		return false
	inspect_requested.emit(card)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if opponent or Engine.is_editor_hint() or not event is InputEventMouseButton:
		return
	var click := event as InputEventMouseButton
	if get_tree().current_scene.is_board_input_blocked(click.global_position):
		return
	if click.button_index == MOUSE_BUTTON_RIGHT and click.pressed:
		if cancel_drag():
			get_viewport().set_input_as_handled()
		elif selected_card != null:
			inspect_requested.emit(selected_card)
			get_viewport().set_input_as_handled()
	elif click.button_index == MOUSE_BUTTON_LEFT and allow_drag:
		if click.pressed and selected_card != null:
			selected_card._handle_mouse_pressed()
			get_viewport().set_input_as_handled()
		elif not click.pressed:
			var held := held_card()
			if held != null:
				held._handle_mouse_released()
				selected_card = null
				get_viewport().set_input_as_handled()
