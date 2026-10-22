class_name WindowControls
extends Node
## Testing conveniences that leave the fork's project.godot untouched: Esc quits, and F11
## switches between the project's fullscreen and a centered window.

const WINDOWED_SIZE := Vector2i(1600, 900)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			quit()
		KEY_F11:
			get_viewport().set_input_as_handled()
			toggle_windowed()


func quit() -> void:
	get_tree().quit()


static func toggle_windowed() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.screen_get_usable_rect()
	var size := Vector2i(mini(WINDOWED_SIZE.x, screen.size.x), mini(WINDOWED_SIZE.y, screen.size.y))
	DisplayServer.window_set_size(size)
	var margin := screen.size - size
	DisplayServer.window_set_position(screen.position + Vector2i(floori(margin.x / 2.0), floori(margin.y / 2.0)))
