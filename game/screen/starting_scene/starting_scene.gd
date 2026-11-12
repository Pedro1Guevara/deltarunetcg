extends Control

# Credits & News Buttons
func _on_credits_button_pressed() -> void:
	print("Abrindo os creditos...")
	var popup = preload("res://game/screen/credits/credits.tscn").instantiate()
	get_tree().current_scene.add_child(popup)

func _on_news_button_pressed() -> void:
	print("Abrindo ss notícias...")
	var popup = preload("res://game/screen/News/news.tscn").instantiate()
	get_tree().current_scene.add_child(popup)


# Main buttons
func _on_play_button_pressed() -> void:
	print("Verificando status do jogador...")
	if PlayerData.is_first_time:
		print("Indo para main_ui...")
		get_tree().change_scene_to_file("res://game/screen/main_ui/main_ui.tscn")
	else:
		print("indo para main_scene...")
		get_tree().change_scene_to_file("res://game/screen/main_scene/main_scene.tscn")


func _on_exit_button_pressed() -> void:
	print("Saindo do jogo...")
	get_tree().quit()


# Very Cool Self Destruction 
func _on_player_data_reset_button_pressed() -> void:
		PlayerData.reset_game_data()
		get_tree().reload_current_scene()
