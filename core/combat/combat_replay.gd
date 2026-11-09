class_name CombatReplay
extends RefCounted
## Everything needed to play a combat again exactly (Design Document 8.4): the combat's seed,
## rules and decks, and every game played (MatchReplay), Sudden Death games included. Combat
## records one (Combat.replay()). Written as legible JSON (to_text()) or as a short code
## (to_code()); from_text() reads both.

## Bumped when the text or the code changes shape.
const FORMAT := 1
## Starts every code, so from_text() tells it from JSON and from a round's code (MatchReplay).
const CODE_PREFIX := "DRC1:"

## The seed the combat's games took their seeds from.
var combat_seed: int = 0
## MatchRules.to_dict() of the rules every round starts with.
var rules: Dictionary = {}
## Each player's deck as card ids, as the combat hands it to every game.
var decks: Array[PackedStringArray] = []
## Every game in order, the last one possibly unfinished.
var games: Array[MatchReplay] = []


## One line of JSON. Seeds are written as text, so no JSON reader rounds them.
func to_text() -> String:
	var deck_lists: Array = []
	for deck in decks:
		deck_lists.append(Array(deck))
	var game_data: Array = []
	for game in games:
		game_data.append(game.to_data(false))
	return JSON.stringify({
		"format": FORMAT,
		"seed": str(combat_seed),
		"rules": rules,
		"decks": deck_lists,
		"games": game_data,
	})


## A short code for the same combat: one line starting with CODE_PREFIX. Empty when an action
## has no token (MatchReplay.TOKENS).
func to_code() -> String:
	var deck_runs: Array = []
	for deck in decks:
		deck_runs.append(MatchReplay.deck_as_runs(deck))
	var game_data: Array = []
	for game in games:
		var compact := game.to_compact_data(false)
		if compact.is_empty():
			return ""
		game_data.append(compact)
	return CODE_PREFIX + MatchReplay.pack({
		"format": FORMAT,
		"seed": str(combat_seed),
		"rules": rules,
		"decks": deck_runs,
		"games": game_data,
	})


## The combat written by to_text() or to_code(), or null when text is neither.
static func from_text(text: String) -> CombatReplay:
	var trimmed := text.strip_edges()
	if trimmed.begins_with(CODE_PREFIX):
		var packed: Variant = MatchReplay.unpack(trimmed.substr(CODE_PREFIX.length()))
		return null if packed == null else _from_data(packed as Dictionary, true)
	var json := JSON.new()
	if json.parse(trimmed) != OK or not json.data is Dictionary:
		return null
	return _from_data(json.data as Dictionary, false)


static func _from_data(data: Dictionary, compact: bool) -> CombatReplay:
	for key: String in ["format", "seed", "rules", "decks", "games"]:
		if not data.has(key):
			return null
	if int(data["format"]) != FORMAT or not data["rules"] is Dictionary or not data["decks"] is Array or not data["games"] is Array:
		return null
	var record := CombatReplay.new()
	record.combat_seed = str(data["seed"]).to_int()
	var read_rules := MatchRules.from_dict(data["rules"] as Dictionary)
	if read_rules == null:
		return null
	record.rules = read_rules.to_dict()
	var decks_by_id: Array = []
	for deck: Variant in data["decks"]:
		var ids: Variant = MatchReplay.deck_from_runs(deck) if compact else deck
		if not ids is Array:
			return null
		decks_by_id.append(ids)
		record.decks.append(PackedStringArray(ids as Array))
	if record.decks.size() != 2:
		return null
	for game: Variant in data["games"]:
		if not game is Dictionary:
			return null
		var read: MatchReplay = null
		if compact:
			read = MatchReplay.from_compact_data(game as Dictionary, decks_by_id)
		else:
			var with_decks := (game as Dictionary).duplicate()
			with_decks["decks"] = decks_by_id
			read = MatchReplay.from_data(with_decks)
		if read == null:
			return null
		record.games.append(read)
	return record


## Plays the combat again with this card data and these effects and returns it where it ends.
## Stops at the first action that is not legal, or at a game the combat would not start, which
## happens when the card data or the rules changed since the combat was recorded.
func play(cards: CardDatabase, effects: EffectLibrary) -> Combat:
	var combat := Combat.new(cards, effects, decks[0], decks[1], MatchRules.from_dict(rules), combat_seed)
	var seeds: Array[int] = []
	for game in games:
		seeds.append(game.rng_seed)
	combat.use_seeds(seeds)
	combat.start()
	for index in games.size():
		if index > 0 and not combat.next_game():
			push_warning("CombatReplay: game %d of %d does not start here" % [index + 1, games.size()])
			return combat
		var actions := games[index].actions
		for step in actions.size():
			if not combat.engine.is_legal(actions[step]):
				push_warning("CombatReplay: game %d, action %d of %d is not legal here: %s" % [index + 1, step + 1, actions.size(), actions[step]])
				return combat
			combat.engine.apply(actions[step])
	return combat
