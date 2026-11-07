extends Control

@onready var name_input_screen: Control = $NameInputScreen
@onready var main_menu: Control = $MainMenu
@onready var line_edit: LineEdit = $NameInputScreen/LineEdit
@onready var welcome_label: Label = $MainMenu/WelcomeBack

func _ready() -> void:
	# Verifica se é a primeira vez
	if PlayerData.is_first_time:
		name_input_screen.visible = true
		main_menu.visible = false
	else:
		name_input_screen.visible = false
		main_menu.visible = true
		welcome_label.text = "Welcome back to Sylk's DTCG, " + PlayerData.player_name + "!"

# Conecte o sinal 'pressed' do seu ConfirmButton a esta função:
func _on_button_pressed() -> void:
	var entered_name = line_edit.text.strip_edges()
	
	if entered_name != "":
		PlayerData.player_name = entered_name
		PlayerData.is_first_time = false
		PlayerData.save_game()
		
		# Atualiza as visibilidades
		name_input_screen.visible = false
		main_menu.visible = true
		welcome_label.text = "Welcome to Sylk's DTCG, " + PlayerData.player_name + "!"
		print("Name saved sucessfuly: ", PlayerData.player_name)
	else:
		print("Please, put a valid name.")


#TESTE DE DARKDOLLARS

# Simulando vitória (+500 D$)
func _on_win_test_pressed() -> void:
	PlayerData.add_coins(500)


# Simulando derrota (+250 D$)
func _on_lose_test_pressed() -> void:
	PlayerData.add_coins(250)


# Simulando desistência (+50 D$)
func _on_give_up_test_pressed() -> void:
	PlayerData.add_coins(50)
