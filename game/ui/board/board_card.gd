extends Card

func snap_to_pose(at: Vector2, angle: float) -> void:
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
	move_tween = null
	is_moving_to_destination = false
	if current_state == DraggableState.MOVING:
		change_state(DraggableState.IDLE)
	settle_at(at, angle)

func settle_at(at: Vector2, angle: float) -> void:
	_stop_hover_tween()
	scale = Vector2.ONE
	position = get_parent().get_global_transform().affine_inverse() * at
	rotation = angle
	original_scale = Vector2.ONE
	original_position = position
	original_hover_rotation = angle
	original_destination = at
	original_rotation = angle

func _stop_hover_tween() -> void:
	if hover_tween != null and hover_tween.is_valid():
		hover_tween.kill()
	hover_tween = null

func _start_hover_animation() -> void:
	_stop_hover_tween()
	var pose := card_container.get_target_pose_for(self)
	if pose.is_empty():
		return
	original_scale = Vector2.ONE
	original_position = get_parent().get_global_transform().affine_inverse() * pose.position
	original_hover_rotation = pose.rotation
	var factor := 1.8
	var data := card_info.get("data") as CardData
	var sideways := data != null and data.stage == CardData.STAGE_BREAK
	var dimensions := Vector2(card_size.y, card_size.x) * factor if sideways else card_size * factor
	var centre_x := clampf(pose.position.x + card_size.x / 2.0, dimensions.x / 2.0, 1920.0 - dimensions.x / 2.0)
	var centre := Vector2(centre_x, 980.0 - dimensions.y / 2.0)
	var target: Vector2 = get_parent().get_global_transform().affine_inverse() * centre - card_size / 2.0
	hover_tween = create_tween().set_parallel(true)
	hover_tween.tween_property(self, "position", target, hover_duration)
	hover_tween.tween_property(self, "scale", Vector2.ONE * factor, hover_duration)
	hover_tween.tween_property(self, "rotation", -PI / 2.0 if sideways else 0.0, hover_duration)
	current_hover_position = position

func _stop_hover_animation() -> void:
	var pose := card_container.get_target_pose_for(self)
	if not pose.is_empty():
		settle_at(pose.position, pose.rotation)

func _preserve_hover_position() -> void:
	_stop_hover_tween()
	current_hover_position = position

func _enter_state(state: DraggableState, from_state: DraggableState) -> void:
	super._enter_state(state, from_state)
	if state == DraggableState.HOLDING:
		_stop_hover_tween()
		scale = Vector2.ONE
		original_scale = Vector2.ONE
		rotation = 0.0
		current_holding_mouse_position = card_size / 2.0
		global_position = get_global_mouse_position() - current_holding_mouse_position

func _on_move_done() -> void:
	scale = Vector2.ONE
	original_scale = Vector2.ONE
	super._on_move_done()
