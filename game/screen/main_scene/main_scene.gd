extends Control

# Reference to the text and image nodes
@onready var name_label: Button = $TopBar/NameLabel
@onready var dark_dollars_label: Label = $TopBar/DarkDollarsLabel
@onready var profile_pic_button: TextureButton = $TopBar/ProfileCut/ProfileButton

@onready var welcome_popup: Control = $WelcomePopup
@onready var welcome_text: Label = $WelcomePopup/WelcomeText

func _ready() -> void:
	update_hud()
	if not PlayerData.session_welcome_shown:
		PlayerData.session_welcome_shown = true 
		
		if PlayerData.show_first_time_popup:
			PlayerData.show_first_time_popup = false # Reseta a flag
			
			show_timed_popup("Welcome to DTCG, " + PlayerData.player_name + "!")
		else:
			show_timed_popup("Welcome Back, " + PlayerData.player_name + "!")
	else:
		if welcome_popup:
			welcome_popup.visible = false


# Popup actions
func show_timed_popup(message: String) -> void:
	if welcome_popup:
		if welcome_text:
			welcome_text.text = message
		
		welcome_popup.visible = true
		
		# Desapears in 3 seconds
		await get_tree().create_timer(3.0).timeout
		welcome_popup.visible = false




# Top Bar
func update_hud() -> void:
	# Grabs Name and Darkdollars from the PlayerData Autoload
	name_label.text = PlayerData.player_name
	$TopBar/DarkDollarsLabel.text = "D$: " + str(PlayerData.darkdollars)
	
	# Load and shows the saved avatar in PlayerData
	var avatar_path = PlayerData.equipped_avatar
	if ResourceLoader.exists(avatar_path):
		profile_pic_button.texture_normal = load(avatar_path)


# Buttons Conections
# Top Bar Buttons
func _on_profile_button_pressed() -> void:
	print("Abrindo perfil de: ", PlayerData.player_name)
	get_tree().change_scene_to_file("res://game/screen/profile_scene/ProfileScene.tscn")

func _on_name_label_pressed() -> void:
	print("Abrindo perfil de: ", PlayerData.player_name)
	get_tree().change_scene_to_file("res://game/screen/profile_scene/ProfileScene.tscn")

func _on_config_button_pressed() -> void:
	print("Abrindo configurações...")


# Homepage stuff
func _on_boosters_button_pressed() -> void:
	print("Abrindo a área de Boosters...")

func _on_shop_button_pressed() -> void:
	print("Loja em breve!")

func _on_decks_button_pressed() -> void:
	print("Montador de decks em breve!")


# Navigation Bar
func _on_home_button_pressed() -> void:
	print("Você já está na Home.")

func _on_dex_button_pressed() -> void:
	print("Dex em breve!")

func _on_trade_button_pressed() -> void:
	print("Trade em breve!")

func _on_battle_button_pressed() -> void:
	print("Abrindo Battle...")
	get_tree().change_scene_to_file("res://game/screen/battle_page/battle_page.tscn")

func _on_story_button_pressed() -> void:
	print("Story em breve!")
