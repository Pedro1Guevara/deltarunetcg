class_name MatchReplay
extends RefCounted
## Everything needed to play a round again exactly (Design Document 8.4): the seed, the rules
## and the decks it started with, and every action applied, by its fields. With the same card
## data and effects, playing it again gives the same round, so a round can be attached to a bug
## report as text. MatchEngine records one while it plays (MatchEngine.replay()).
##
## Two ways to write it, both read by from_text(): legible JSON (to_text()), and a short code
## (to_code()) for long rounds: decks as runs of copies, actions as tokens, compressed and in
## base64.

## Bumped when the text or the code changes shape.
const FORMAT := 1
## Starts every code, so from_text() tells it from JSON.
const CODE_PREFIX := "DRT1:"
## Each action type as a token: its letter, then its fields in this order. Only "power" is
## text; every other field is a whole number.
const TOKENS := {
	"choose": ["c", ["option"]],
	"bench": ["b", ["hand_index"]],
	"attach": ["a", ["hand_index", "slot"]],
	"evolve": ["v", ["hand_index", "slot"]],
	"play_trainer": ["t", ["hand_index"]],
	"retreat": ["r", ["slot"]],
	"attack": ["k", ["attack_index"]],
	"use_power": ["p", ["slot", "power"]],
	"use_area": ["u", []],
	"end_turn": ["e", []],
}
const TEXT_FIELDS := ["power"]
## The largest code read back, uncompressed, in bytes.
const MAX_CODE_BYTES := 1 << 24

## The seed of the Rng the round started with.
var rng_seed: int = 0
## MatchRules.to_dict() as the round started.
var rules: Dictionary = {}
## Each player's deck as card ids, in the order it was handed to the engine, before shuffling.
var decks: Array[PackedStringArray] = []
## Every action applied, in order, without its label.
var actions: Array[Dictionary] = []


## A copy that shares nothing with this one.
func duplicate_replay() -> MatchReplay:
	var copy := MatchReplay.new()
	copy.rng_seed = rng_seed
	copy.rules = rules.duplicate(true)
	for deck in decks:
		copy.decks.append(deck.duplicate())
	for action in actions:
		copy.actions.append(action.duplicate(true))
	return copy


## One line of JSON. The seed is written as text, so no JSON reader rounds it.
func to_text() -> String:
	var deck_lists: Array = []
	for deck in decks:
		deck_lists.append(Array(deck))
	return JSON.stringify({
		"format": FORMAT,
		"seed": str(rng_seed),
		"rules": rules,
		"decks": deck_lists,
		"actions": actions,
	})


## A short code for the same replay: one line starting with CODE_PREFIX. Empty when an
## action has no token (TOKENS), which a test guards against.
func to_code() -> String:
	var deck_runs: Array = []
	for deck in decks:
		var runs: Array = []
		for id in deck:
			if not runs.is_empty() and (runs.back() as Array)[0] == id:
				(runs.back() as Array)[1] = int((runs.back() as Array)[1]) + 1
			else:
				runs.append([id, 1])
		deck_runs.append(runs)
	var tokens := PackedStringArray()
	for action in actions:
		var token := _action_token(action)
		if token.is_empty():
			push_error("MatchReplay: no token for %s" % action)
			return ""
		tokens.append(token)
	var compact := JSON.stringify({
		"format": FORMAT,
		"seed": str(rng_seed),
		"rules": rules,
		"decks": deck_runs,
		"actions": "|".join(tokens),
	})
	var packed := compact.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	return CODE_PREFIX + Marshalls.raw_to_base64(packed)


## The replay written by to_text() or to_code(), or null when text is neither.
static func from_text(text: String) -> MatchReplay:
	var trimmed := text.strip_edges()
	if trimmed.begins_with(CODE_PREFIX):
		return _from_code(trimmed.substr(CODE_PREFIX.length()))
	var json := JSON.new()
	if json.parse(trimmed) != OK or not json.data is Dictionary:
		return null
	return _from_data(json.data as Dictionary)


static func _from_code(code: String) -> MatchReplay:
	# Checked first: Godot reports an error for text that is not base64.
	var base64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")
	if code.length() % 4 != 0 or base64.search(code) == null:
		return null
	var packed := Marshalls.base64_to_raw(code)
	if packed.is_empty():
		return null
	var json := JSON.new()
	if json.parse(packed.decompress_dynamic(MAX_CODE_BYTES, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()) != OK or not json.data is Dictionary:
		return null
	var data := json.data as Dictionary
	if not data.get("decks") is Array or not data.get("actions") is String:
		return null
	var decks_by_id: Array = []
	for runs: Variant in data["decks"]:
		if not runs is Array:
			return null
		var ids: Array = []
		for run: Variant in runs:
			if not run is Array or (run as Array).size() != 2:
				return null
			for _copy in int((run as Array)[1]):
				ids.append(str((run as Array)[0]))
		decks_by_id.append(ids)
	data["decks"] = decks_by_id
	var listed: Array = []
	var text := str(data["actions"])
	for token in ([] if text.is_empty() else Array(text.split("|"))):
		var action := _token_action(str(token))
		if action.is_empty():
			return null
		listed.append(action)
	data["actions"] = listed
	return _from_data(data)


static func _action_token(action: Dictionary) -> String:
	var type := str(action.get("type", ""))
	if not TOKENS.has(type):
		return ""
	var entry := TOKENS[type] as Array
	var fields := entry[1] as Array
	if action.size() != fields.size() + 1:
		return ""
	var values := PackedStringArray()
	for field: String in fields:
		if not action.has(field):
			return ""
		values.append(str(action[field]).uri_encode() if TEXT_FIELDS.has(field) else str(int(action[field])))
	return str(entry[0]) + ",".join(values)


static func _token_action(token: String) -> Dictionary:
	for type: String in TOKENS:
		var entry := TOKENS[type] as Array
		if not token.begins_with(str(entry[0])):
			continue
		var fields := entry[1] as Array
		var rest := token.substr(str(entry[0]).length())
		var values := PackedStringArray() if rest.is_empty() else rest.split(",")
		if values.size() != fields.size():
			return {}
		var action := {"type": type}
		for index in fields.size():
			var field := str(fields[index])
			action[field] = values[index].uri_decode() if TEXT_FIELDS.has(field) else values[index].to_int()
		return action
	return {}


static func _from_data(data: Dictionary) -> MatchReplay:
	for key: String in ["format", "seed", "rules", "decks", "actions"]:
		if not data.has(key):
			return null
	if int(data["format"]) != FORMAT or not data["rules"] is Dictionary or not data["decks"] is Array or not data["actions"] is Array:
		return null
	var replay := MatchReplay.new()
	replay.rng_seed = str(data["seed"]).to_int()
	var read_rules := MatchRules.from_dict(data["rules"] as Dictionary)
	if read_rules == null:
		return null
	# Through MatchRules, so numbers read from JSON become whole numbers again.
	replay.rules = read_rules.to_dict()
	for deck: Variant in data["decks"]:
		if not deck is Array:
			return null
		replay.decks.append(PackedStringArray(deck as Array))
	for action: Variant in data["actions"]:
		if not action is Dictionary:
			return null
		# JSON reads every number as a float; action fields are whole numbers or text.
		var fields := action as Dictionary
		for key: Variant in fields:
			if fields[key] is float:
				fields[key] = int(fields[key])
		replay.actions.append(fields)
	if replay.decks.size() != 2:
		return null
	return replay


## Plays the round again with this card data and these effects and returns the engine where it
## ends. Stops at the first action that is not legal, which happens when the card data or the
## rules changed since the round was recorded; the engine's own replay() then holds fewer
## actions than this one.
func play(cards: CardDatabase, effects: EffectLibrary) -> MatchEngine:
	var engine := MatchEngine.new()
	engine.effects = effects
	var built: Array = []
	for deck in decks:
		var cards_in_deck: Array[CardData] = []
		for id in deck:
			cards_in_deck.append(cards.make(id))
		built.append(cards_in_deck)
	engine.start(built[0] as Array[CardData], built[1] as Array[CardData], MatchRules.from_dict(rules), Rng.new(rng_seed))
	for step in actions.size():
		if not engine.is_legal(actions[step]):
			push_warning("MatchReplay: action %d of %d is not legal here: %s" % [step + 1, actions.size(), actions[step]])
			break
		engine.apply(actions[step])
	return engine