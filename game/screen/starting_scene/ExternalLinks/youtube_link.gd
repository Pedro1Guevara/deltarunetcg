extends Button


@export var url = "https: //youtube.com/@sylkwyrmlive?si=B5lcQx3ZyG1Q5QS3"

func _on_button_down() -> void:
	print("Indo para youtube...")
	OS.shell_open(url)
