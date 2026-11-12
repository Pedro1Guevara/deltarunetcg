extends Node

const SAVE_PATH = "user://player_data.save"

func _ready() -> void:
	load_player_game()

var show_first_time_popup: bool = false
var session_welcome_shown: bool = false


# --- PLAYER DATA ---
var player_name: String = ""
var is_first_time: bool = true
var battles_won: int = 0
var total_cards_owned: int = 0
var achievements: Array = []
var titles: Array = []
var darkdollars: int = 999999 # DarkDollars/Placeholder, Test value
var story_chapter: int = 1
var story_level: int = 1 


# --- PROFILE CATEGORIES ---
var equipped_avatar: String = "res://assets/ui/Avatars/RedSoul.png"
var equipped_title: String = "" 
var equipped_title_color: String = "#ffffff"
var is_title_animated: bool = false
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
var unlocked_titles: Array = []

# Returns all data in form of a dictionary for the SaveService to save
func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"is_first_time": is_first_time,
		"battles_won": battles_won,
		"total_cards_owned": total_cards_owned,
		"achievements": achievements,
		"titles": titles,
		"darkdollars": darkdollars,
		"equipped_avatar": equipped_avatar,
		"equipped_title": equipped_title,
		"equipped_title_color": equipped_title_color,
		"is_title_animated": is_title_animated,
		"favorite_card_id": favorite_card_id,
		"unlocked_avatars": unlocked_avatars,
		"unlocked_titles": unlocked_titles,
		"story_chapter": story_chapter,
		"story_level": story_level
		}


# Load the data from the dictionary
func from_dict(data: Dictionary) -> void:
	player_name = data.get("player_name", "")
	is_first_time = data.get("is_first_time", true)
	battles_won = data.get("battles_won", 0)
	total_cards_owned = data.get("total_cards_owned", 0)
	achievements = data.get("achievements", [])
	titles = data.get("titles", [])
	darkdollars = data.get("darkdollars", 999999)
	equipped_avatar = data.get("equipped_avatar", "res://assets/ui/Avatars/RedSoul.png")
	equipped_title = data.get("equipped_title", "")
	equipped_title_color = data.get("equipped_title_color", "#ffffff")
	is_title_animated = data.get("is_title_animated", false)
	favorite_card_id = data.get("favorite_card_id", "")
	story_chapter = data.get("story_chapter", 1)
	story_level = data.get("story_level", 1)
	unlocked_avatars = data.get("unlocked_avatars", ["res://assets/ui/Avatars/RedSoul.png", 
"res://assets/ui/Avatars/OrangeSoul.png", 
"res://assets/ui/Avatars/YellowSoul.png",
"res://assets/ui/Avatars/GreenSoul.png",
"res://assets/ui/Avatars/CyanSoul.png",
"res://assets/ui/Avatars/BlueSoul.png",
"res://assets/ui/Avatars/PurpleSoul.png",
"res://assets/ui/Avatars/MonsterSoul.png"])
	unlocked_titles = data.get("unlocked_titles", [])
	print("Save Loaded")


# Connects PlayerData to the SaveSevice
func save_player_game() -> void:
	SaveService.save_json("player_data.save", PlayerData.to_dict())

func load_player_game() -> void:
	var loaded_data = SaveService.load_json("player_data.save")
	if loaded_data != null and loaded_data is Dictionary:
		from_dict(loaded_data)
	else:
		print("Nenhum save encontrado, ou dados invalidos. usando padrões.")






# Resets all of PlayerData's data to default
func reset_game_data() -> void:
	player_name = ""
	is_first_time = true
	battles_won = 0
	total_cards_owned = 0
	achievements.clear()
	titles.clear()
	darkdollars = 999999
	equipped_avatar = "res://assets/ui/Avatars/RedSoul.png"
	equipped_title = ""
	equipped_title_color = "#ffffff"
	is_title_animated = false
	favorite_card_id = ""
	story_chapter = 1
	story_level = 1
	unlocked_avatars = ["res://assets/ui/Avatars/RedSoul.png", 
"res://assets/ui/Avatars/OrangeSoul.png", 
"res://assets/ui/Avatars/YellowSoul.png",
"res://assets/ui/Avatars/GreenSoul.png",
"res://assets/ui/Avatars/CyanSoul.png",
"res://assets/ui/Avatars/BlueSoul.png",
"res://assets/ui/Avatars/PurpleSoul.png",
"res://assets/ui/Avatars/MonsterSoul.png"]
	unlocked_titles.clear()
	
	var save_path = "user://player_data.save"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
		print("Self Destruction Sucessful!! :D")
