extends Node

# Path where the player data will be saved on the computer
const SAVE_PATH = "user://player_data.save"

# --- PLAYER DATA ---
var player_name: String = ""
var is_first_time: bool = true
var battles_won: int = 0
var total_cards_owned: int = 0
var achievements: Array = []
var titles: Array = []
var darkdollars: int = 999999 # DarkDollars/Prototype value
var story_chapter: int = 1
var story_level: int = 1 

# --- PROFILE CATEGORIES ---
var equipped_avatar: String = "res://assets/ui/Avatars/RedSoul.png"
var equipped_title_color: String = "#FFFFFF" 
var favorite_card_id: String = "" #Favorite cards ID        <- I want to improve it latar, so it will be "favorite cards" it wil store at least three
var unlocked_avatars: Array = ["res://assets/ui/Avatars/RedSoul.png", 
"res://assets/ui/Avatars/OrangeSoul.png", 
"res://assets/ui/Avatars/YellowSoul.png",
"res://assets/ui/Avatars/GreenSoul.png",
"res://assets/ui/Avatars/CyanSoul.png",
"res://assets/ui/Avatars/BlueSoul.png",
"res://assets/ui/Avatars/PurpleSoul.png",
"res://assets/ui/Avatars/MonsterSoul.png"
]

func _ready() -> void:
	load_game()

# Saves all variables
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
			"darkdollars": darkdollars,
			"equipped_avatar": equipped_avatar,
			"equipped_title_color": equipped_title_color,
			"favorite_card_id": favorite_card_id,
			"unlocked_avatars": unlocked_avatars,
			"story_chapter": story_chapter,
			"story_level": story_level
		}
		file.store_string(JSON.stringify(data))
		print("Save Sucessful!")

# Load the data
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
				darkdollars = data.get("darkdollars", 999999)
				equipped_avatar = data.get("equipped_avatar", "res://assets/ui/Avatars/RedSoul.png")
				equipped_title_color = data.get("equipped_title_color", "#FFFFFF")
				favorite_card_id = data.get("favorite_card_id", "")
				unlocked_avatars = data.get("unlocked_avatars", [])
				story_chapter = data.get("story_chapter", 1)
				story_level = data.get("story_level", 1)
				print("Save Loaded")
