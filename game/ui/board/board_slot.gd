@tool
extends Pile

@export var face_rotation: float = 0.0

func _update_target_positions() -> void:
	for card: Card in _held_cards:
		var pose := get_target_pose_for(card)
		card.call("snap_to_pose", pose.position, pose.rotation)

func get_target_pose_for(card: Card) -> Dictionary:
	var index := _held_cards.find(card)
	if index < 0:
		return {}
	var at := global_position + _calculate_offset(index)
	if fmod(absf(face_rotation), 180.0) > 1.0:
		at += Vector2(card.card_size.y - card.card_size.x, card.card_size.x - card.card_size.y) / 2.0
	at += card.get_meta("display_offset", Vector2.ZERO)
	return {"position": at, "rotation": deg_to_rad(face_rotation)}
