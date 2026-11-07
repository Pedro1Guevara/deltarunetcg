extends Control

# Referências aos nós de texto e imagem 
@onready var name_label: Label = $TopBar/NameLabel
@onready var coins_label: Label = $TopBar/CoinsLabel
@onready var profile_pic_button: TextureButton = $TopBar/ProfileCut/ProfileButton

func _ready() -> void:
	# Atualiza os elementos da HUD (textos e avatar) assim que o menu abre
	update_hud()

func update_hud() -> void:
	# Puxa o nome e as moedas do Autoload PlayerData
	name_label.text = PlayerData.player_name
	coins_label.text = "D$: " + str(PlayerData.coins)
	
	# Carrega e exibe a imagem de perfil salva no PlayerData
	var avatar_path = PlayerData.equipped_avatar
	if ResourceLoader.exists(avatar_path):
		profile_pic_button.texture_normal = load(avatar_path)

# --- CONEXÕES DOS BOTÕES ---

# 1. Botão de Perfil (ProfileButt)
func _on_profile_button_pressed() -> void:
	print("Abrindo perfil de: ", PlayerData.player_name)
	# Mudar para a cena de perfil (exemplo):
	get_tree().change_scene_to_file("res://game/ui/Cenas/ProfileScene.tscn")

# 2. Botão de Configurações (ConfigButt)
func _on_config_button_pressed() -> void:
	print("Abrindo configurações...")



# 3. Botão de Boosters (BoostersButt)
func _on_boosters_button_pressed() -> void:
	print("Abrindo a área de Boosters...")

# 4. Botão de Shop (ShopButt)
func _on_shop_button_pressed() -> void:
	print("Loja em breve!")

# 5. Botão de Decks (DecksButt)
func _on_decks_button_pressed() -> void:
	print("Montador de decks em breve!")


# 6. Barra de Navegação Inferior
func _on_home_button_pressed() -> void:
	print("Você já está na Home.")

func _on_dex_button_pressed() -> void:
	print("Dex em breve!")

func _on_trade_button_pressed() -> void:
	print("Trade em breve!")

func _on_battle_button_pressed() -> void:
	print("Battle em breve!")

func _on_story_button_pressed() -> void:
	print("Story em breve!")
