extends Button


@export var url = "https://discord.gg/4GZSjc6xc"

func _on_button_down() -> void:
	print("Indo para Discord...")
	OS.shell_open(url)
