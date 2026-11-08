extends Node

# Caminho onde o arquivo de salvamento ficará gravado no computador/dispositivo
const SAVE_PATH = "user://player_data.save"

# --- DADOS DO JOGADOR ---
var player_name: String = ""
var is_first_time: bool = true
var battles_won: int = 0
var total_cards_owned: int = 0
var achievements: Array = []
var titles: Array = []
var coins: int = 999999 # DarkDollars/moedas iniciais do prototipo
var story_chapter: int = 1
var story_level: int = 1 

# --- CAMPOS DO PERFIL ---
var equipped_avatar: String = "res://Avatars/default.png"
var equipped_title_color: String = "#FFFFFF" # Cor hexadecimal do nome (padrão branco)
var favorite_card_id: String = "" # ID da carta favorita
var unlocked_avatars: Array = ["res://Avatars/default.png"]

func _ready() -> void:
	load_game()

# Salva todas as variáveis atuais no arquivo
func save_game() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"player_name": player_name,
			"is_first_time": is_first_time,
			"battles_won": battles_won,
			"total_cards_owned": total_cards_owned,
			"achievements": achievements,
			"titles": titles,
			"coins": coins,
			"equipped_avatar": equipped_avatar,
			"equipped_title_color": equipped_title_color,
			"favorite_card_id": favorite_card_id,
			"unlocked_avatars": unlocked_avatars,
			"story_chapter": story_chapter,
			"story_level": story_level
		}
		file.store_string(JSON.stringify(data))
		print("Save Sucessful!")

# Carrega os dados gravados se o arquivo existir
func load_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			var error = json.parse(file.get_as_text())
			if error == OK:
				var data = json.get_data()
				player_name = data.get("player_name", "")
				is_first_time = data.get("is_first_time", true)
				battles_won = data.get("battles_won", 0)
				total_cards_owned = data.get("total_cards_owned", 0)
				achievements = data.get("achievements", [])
				titles = data.get("titles", [])
				coins = data.get("coins", 999999)
				equipped_avatar = data.get("equipped_avatar", "res://Avatars/default.png")
				equipped_title_color = data.get("equipped_title_color", "#FFFFFF")
				favorite_card_id = data.get("favorite_card_id", "")
				unlocked_avatars = data.get("unlocked_avatars", ["res://Avatars/default.png"])
				story_chapter = data.get("story_chapter", 1)
				story_level = data.get("story_level", 1)
				print("Save Loaded")
