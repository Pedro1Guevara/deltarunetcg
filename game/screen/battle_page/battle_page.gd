extends Control



# Navigation Bar
func _on_home_button_pressed() -> void:
	print("Abrindo Home...")
	get_tree().change_scene_to_file("res://game/screen/main_scene/main_scene.tscn")

func _on_dex_button_pressed() -> void:
	print("Dex em breve!")

func _on_trade_button_pressed() -> void:
	print("Trade em breve!")

func _on_battle_button_pressed() -> void:
	print("Você já está na Battle.")

func _on_story_button_pressed() -> void:
	print("Story em breve!")
