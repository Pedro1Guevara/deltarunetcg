extends Control


# Credits Button
func _on_credits_button_pressed() -> void:
	print("Abrindo os creditos...")
	var popup = preload("res://game/screen/credits/credits.tscn").instantiate()
	get_tree().current_scene.add_child(popup)


# Main buttons
func _on_play_button_pressed() -> void:
	print("Abrindo o jogo...")
	get_tree().change_scene_to_file("res://game/screen/main_scene/main_scene.tscn")

func _on_exit_button_pressed() -> void:
	print("Saindo do jogo...")
	get_tree().quit()
