class_name DataLoader
extends RefCounted

const TCGDEX_DIR := "res://data/tcgdex"
const DECKS_PATH := "res://data/decks.json"


## Reads every set file in data/tcgdex/ into a CardDatabase and reports its problems
## to the Output panel. Returns an empty database if no set could be read.
static func load_card_database() -> CardDatabase:
	var database := CardDatabase.new()
	var files := DirAccess.get_files_at(TCGDEX_DIR)
	if files.is_empty():
		push_error("DataLoader: no set files in %s. Run tools/import_tcgdex.gd" % TCGDEX_DIR)
		return database

	var names: Array[String] = []
	for file_name in files:
		if file_name.get_extension() == "json":
			names.append(file_name)
	names.sort()

	for file_name in names:
		var document: Variant = read_json("%s/%s" % [TCGDEX_DIR, file_name])
		if document is Dictionary:
			database.load_set(document as Dictionary)

	for message in database.errors:
		push_error(message)
	for message in database.warnings:
		push_warning(message)
	print("DataLoader: %d cards loaded, %d errors, %d warnings" % [
		database.card_count(), database.errors.size(), database.warnings.size(),
	])
	return database


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
