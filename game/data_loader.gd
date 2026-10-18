# game/data_loader.gd
class_name DataLoader
extends RefCounted

const DECKS_PATH := "res://data/decks.json"
const FUNCTIONS_PATH := "res://data/effects/functions.json"
const CARD_EFFECTS_PATH := "res://data/effects/card_effects.json"

## WOTC data kept as test fixtures for the engine's Pokemon TCG mechanics.
const LEGACY_TCGDEX_DIR := "res://data/legacy/tcgdex"
const LEGACY_DECKS_PATH := "res://data/legacy/decks.json"
const LEGACY_CARD_EFFECTS_PATH := "res://data/legacy/card_effects.json"


## Reads every set file in data/legacy/tcgdex/ into a CardDatabase and reports its problems
## to the Output panel. Returns an empty database if no set could be read.
static func load_legacy_card_database() -> CardDatabase:
	var database := CardDatabase.new()
	var files := DirAccess.get_files_at(LEGACY_TCGDEX_DIR)
	if files.is_empty():
		push_error("DataLoader: no set files in %s. Run tools/import_tcgdex.gd" % LEGACY_TCGDEX_DIR)
		return database

	var names: Array[String] = []
	for file_name in files:
		if file_name.get_extension() == "json":
			names.append(file_name)
	names.sort()

	for file_name in names:
		var document: Variant = read_json("%s/%s" % [LEGACY_TCGDEX_DIR, file_name])
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


## Reads the function catalog and the given card effects file, and validates them against the
## database, reporting problems to the Output panel. Missing files leave the library empty:
## every attack then deals its printed damage.
static func load_effect_library(database: CardDatabase, card_effects_path: String) -> EffectLibrary:
	var library := EffectLibrary.new()
	var functions: Variant = read_json(FUNCTIONS_PATH) if FileAccess.file_exists(FUNCTIONS_PATH) else {}
	var card_effects: Variant = read_json(card_effects_path) if FileAccess.file_exists(card_effects_path) else {}
	if not functions is Dictionary or not card_effects is Dictionary:
		push_error("DataLoader: %s or %s could not be read; card effects are disabled" % [FUNCTIONS_PATH, card_effects_path])
		return library

	library.load_data(functions as Dictionary, card_effects as Dictionary, database)
	for message in library.errors:
		push_error(message)
	for message in library.warnings:
		push_warning(message)
	print("DataLoader: %d functions, %d card effect entries in use, %d errors, %d warnings" % [
		library.function_count(), library.valid_binding_count(), library.errors.size(), library.warnings.size(),
	])
	return library


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
