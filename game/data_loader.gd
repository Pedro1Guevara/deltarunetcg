class_name DataLoader
extends RefCounted

const CARDS_PATH := "res://data/cards.json"
const DECKS_PATH := "res://data/decks.json"


## Returns the parsed JSON, or null if the file is missing or invalid.
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("DataLoader: file not found: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("DataLoader: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
