extends Control


# To close the popup when the background dimmer is clicked
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var panel = $PanelContainer
		
		if not panel.get_global_rect().has_point(event.position):
			queue_free()
