extends Control

@onready var name_input_screen: Control = $NameInputScreen
@onready var line_edit: LineEdit = $NameInputScreen/LineEdit

func _ready() -> void:
	name_input_screen.visible = true
	line_edit.max_length = 25

func _on_confirm_button_pressed() -> void:
	var entered_name = line_edit.text.strip_edges()
	
	if entered_name != "":
		PlayerData.player_name = entered_name
		PlayerData.is_first_time = false
		
		PlayerData.show_first_time_popup = true
		
		PlayerData.save_player_game()
		print("Nome salvo com sucesso: ", PlayerData.player_name)
		
		get_tree().change_scene_to_file("res://game/screen/main_scene/main_scene.tscn")
	else:
		print("Por favor, insira um nome válido.")
