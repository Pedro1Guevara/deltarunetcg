extends Control

# Sets whether the profile is being viewed by you(true) or by another players(false)
# ^ This will allow you to remove some commands when another player is checking your profile
# Ex: The other player will not be able to change your Avatar or your Title 
var is_owner: bool = true 

@onready var back_button: Button = $ScrollContainer/VBoxContainer/TopHeaderBar/BackButton

# Identity (Avatar & Name)
@onready var profile_pic_button: TextureButton = $ScrollContainer/VBoxContainer/ProfileHeaderBox/LeftIdentificationColumn/ProfileCut/ProfilePicButton
@onready var name_button: Button = $ScrollContainer/VBoxContainer/ProfileHeaderBox/LeftIdentificationColumn/NameButton
@onready var name_label: Label = $ScrollContainer/VBoxContainer/ProfileHeaderBox/LeftIdentificationColumn/NameButton/NameLabel


# Statistics
@onready var battles_label: Label = $ScrollContainer/VBoxContainer/ProfileHeaderBox/StatsColumn/BattlesLabel
@onready var cards_label: Label = $ScrollContainer/VBoxContainer/ProfileHeaderBox/StatsColumn/CardsLabel
@onready var achievements_label: Label = $ScrollContainer/VBoxContainer/ProfileHeaderBox/StatsColumn/AchievementsLabel
@onready var titles_label: Label = $ScrollContainer/VBoxContainer/ProfileHeaderBox/StatsColumn/TitlesLabel
@onready var story_label: Label = $ScrollContainer/VBoxContainer/ProfileHeaderBox/StatsColumn/StoryLabel

# favorite Card/Cards
@onready var favorite_card_texture: TextureButton = $ScrollContainer/VBoxContainer/ProfileHeaderBox/FavoriteCardBox/FavoriteCardTexture
@onready var change_hint_label: Label = $ScrollContainer/VBoxContainer/ProfileHeaderBox/FavoriteCardBox/ChangeHintLabel

# Achieviments
@onready var pending_header: Label = $ScrollContainer/VBoxContainer/Help/AchievementsSection/PendingHeader
@onready var pending_grid: GridContainer = $ScrollContainer/VBoxContainer/Help/AchievementsSection/PendingGrid

func _ready() -> void:
	setup_profile_view()
	load_current_avatar() 

func load_current_avatar() -> void:
	var avatar_path = PlayerData.equipped_avatar
	if ResourceLoader.exists(avatar_path):
		# Updates the Profile
		profile_pic_button.texture_normal = load(avatar_path)
		print("Avatar carregado com sucesso no perfil: ", avatar_path)
	else:
		print("Aviso: Caminho do avatar inválido ou não encontrado -> ", avatar_path)

func _on_profile_pic_button_pressed() -> void:
	if is_owner:
		var popup = preload("res://game/screen/avatar_popup/AvatarPopup.tscn").instantiate()
		get_tree().current_scene.add_child(popup)
		
		
		popup.avatar_changed.connect(func(new_path):
			if ResourceLoader.exists(new_path):
				profile_pic_button.texture_normal = load(new_path)
		)


func setup_profile_view() -> void:
	if is_owner:
		# --- PROFILE'S OWNER VIEW ---
		name_label.text = PlayerData.player_name
		name_label.modulate = Color(PlayerData.equipped_title_color) # Aplica a cor do título/nome
		
		battles_label.text = "Battles Won: " + str(PlayerData.battles_won)
		cards_label.text = "Cards Owned: " + str(PlayerData.total_cards_owned)
		achievements_label.text = "Achievements: " + str(PlayerData.achievements.size())
		titles_label.text = "Titles: " + str(PlayerData.titles.size())
		story_label.text = "Story: Chapter " + str(PlayerData.story_chapter) + ", Level " + str(PlayerData.story_level)
		
		# Edit profile options enabled
		profile_pic_button.disabled = false
		name_button.disabled = false
		if favorite_card_texture:
			favorite_card_texture.disabled = false
			
		# Achievements and Favorite card selec hint visibilty
		pending_header.visible = true
		pending_grid.visible = true
		change_hint_label.visible = true
	else:
		# --- OTHER PLAYER VIEW (Visitor) ---
		name_label.text = PlayerData.player_name
		name_label.modulate = Color(PlayerData.equipped_title_color)
		
		battles_label.text = "Battles Won: " + str(PlayerData.battles_won)
		cards_label.text = "Cards Owned: " + str(PlayerData.total_cards_owned)
		achievements_label.text = "Achievements: " + str(PlayerData.achievements.size())
		titles_label.text = "Titles: " + str(PlayerData.titles.size())
		story_label.text = "Story: Chapter " + str(PlayerData.story_chapter) + ", Level " + str(PlayerData.story_level)
		
		# Edit profile options disabled
		profile_pic_button.disabled = true
		name_button.disabled = true
		if favorite_card_texture:
			favorite_card_texture.disabled = true
			
		# hides pending achievements and hint text
		pending_header.visible = false
		pending_grid.visible = false
		change_hint_label.visible = false

# --- BUTTONS CONNECTIONS ---
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://game/screen/main_scene/main_scene.tscn") 


func _on_avatar_updated_externally(new_path: String) -> void:
	# Updates the Profile Avatar in real time
	if ResourceLoader.exists(new_path):
		profile_pic_button.texture_normal = load(new_path)


func _on_name_button_pressed() -> void:
	if is_owner:
		print("Abrindo menu de títulos (cores do nome)...")

func _on_favorite_card_texture_pressed() -> void:
	if is_owner:
		print("Abrindo seleção de carta favorita...")
