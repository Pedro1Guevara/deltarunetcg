extends Button


@export var url = "https://x.com/deltarunetcg?s=11"

func _on_button_down() -> void:
	print("Indo para Twitter...")
	OS.shell_open(url)
