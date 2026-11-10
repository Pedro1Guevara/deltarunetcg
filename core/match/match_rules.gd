class_name MatchRules
extends RefCounted
## The rules of one round. Every value is set explicitly by a factory below; the engine
## reads them instead of constants, so the same engine plays both rule sets.

## Cards drawn at setup.
var hand_size: int = 0
## Darkners allowed on the Field, not counting the Battle Zone.
var bench_limit: int = 0
## Mercy Cards set aside per player.
var prize_count: int = 0
## Mercy Cards taken per knockout. Effects may change it (Design Document 4.4).
var prizes_per_knockout: int = 0
## True: a player who cannot draw at the start of their turn loses. False: the opponent takes a prize (legacy roguelite rule).
var deck_out_loses: bool = false
## Whether the player going first may attack on their first turn.
var first_player_can_attack: bool = false
## Whether the player going first may play a Lightner (Supporter) on their first turn.
var first_player_can_play_supporter: bool = false
## True: a coin flip decides who goes first. False: player 1 always goes first.
var random_first_player: bool = false
## Required deck size. 0 means any size.
var deck_size: int = 0
## Copies of one card allowed per deck, Energy excepted. 0 means no limit.
var max_copies: int = 0
## Most TP a player can hold, in quarters (Design Document 5). 0 means the rules have no TP.
var tp_max: int = 0
## TP recovered at the start of each of the player's turns, in quarters. A player who passes
## recovers up to tp_max at the end of that turn instead.
var tp_recovery: int = 0
## TP each player holds when the round starts, in quarters.
var tp_start: int = 0
## True: the player who takes their last Mercy Card chooses to Spare or to Fight (Design Document
## 4.5). False: taking the last Mercy Card wins the round at once (legacy rule).
var spare_fight: bool = false
## Extra cards the opponent draws at the start of their first turn of the next round when a
## player Spares them, or when they win against a player who chose to Fight. Effects may change it.
var spare_extra_draws: int = 0
## Extra cards each player draws at the start of their first turn of this game, by player index:
## what Spare and Fight gave them in the round before. Combat sets it for each game.
var first_turn_extra_draws: Array[int] = [0, 0]
## True: a player who knocks out a Darkner picks which of their face-down Mercy Cards to take,
## one question per card (Design Document 4.4). False: the top card of the pile is taken at once
## (legacy rule, and replays recorded before the choice existed).
var choose_prizes: bool = false
## Whether winning this game wins the combat, by player index. Combat sets it for each game. A
## player at match point who takes their last Mercy Card wins at once, with no Spare or Fight:
## Spare would win the combat, and nothing would come of the extra cards.
var match_point: Array[bool] = [false, false]

## Rules a replay recorded before they existed, with the value that plays it as it was played.
const _ADDED_LATER := {"spare_fight": false, "spare_extra_draws": 0, "first_turn_extra_draws": [0, 0], "match_point": [false, false], "choose_prizes": false}


## The rules the WOTC build used. Only for the legacy test data.
static func legacy() -> MatchRules:
	var rules := MatchRules.new()
	rules.hand_size = 7
	rules.bench_limit = 5
	rules.prize_count = 3
	rules.prizes_per_knockout = 1
	rules.deck_out_loses = false
	rules.first_player_can_attack = true
	rules.first_player_can_play_supporter = true
	rules.random_first_player = false
	rules.deck_size = 0
	rules.max_copies = 0
	rules.tp_max = 0
	rules.tp_recovery = 0
	rules.tp_start = 0
	rules.spare_fight = false
	rules.choose_prizes = false
	rules.spare_extra_draws = 0
	rules.first_turn_extra_draws = [0, 0]
	rules.match_point = [false, false]
	return rules


## Deltarune TCG (Design Document 4).
static func deltarune() -> MatchRules:
	var rules := MatchRules.new()
	rules.hand_size = 10
	rules.bench_limit = 4
	rules.prize_count = 4
	rules.prizes_per_knockout = 1
	rules.deck_out_loses = true
	rules.first_player_can_attack = false
	rules.first_player_can_play_supporter = false
	rules.random_first_player = true
	rules.deck_size = 50
	rules.max_copies = 4
	rules.tp_max = 4
	rules.tp_recovery = 1
	rules.tp_start = 4
	rules.spare_fight = true
	rules.choose_prizes = true
	rules.spare_extra_draws = 3
	rules.first_turn_extra_draws = [0, 0]
	rules.match_point = [false, false]
	return rules


## Every rule by name, for a replay.
func to_dict() -> Dictionary:
	var values := {}
	for property in _rule_names():
		var value: Variant = get(property)
		values[property] = (value as Array).duplicate() if value is Array else value
	return values


## The rules to_dict() wrote, or null when a rule is missing. A rule added after a replay was
## recorded takes the value that plays it as it was played (_ADDED_LATER). Numbers read back
## from JSON are turned back into whole numbers.
static func from_dict(values: Dictionary) -> MatchRules:
	var rules := MatchRules.new()
	for property in rules._rule_names():
		var value: Variant
		if values.has(property):
			value = values[property]
		elif _ADDED_LATER.has(property):
			value = _ADDED_LATER[property]
		else:
			return null
		var current: Variant = rules.get(property)
		if current is int:
			value = int(value)
		elif current is bool:
			value = bool(value)
		elif current is Array and (current as Array).get_typed_builtin() == TYPE_BOOL:
			var flags: Array[bool] = []
			for flag: Variant in value as Array:
				flags.append(bool(flag))
			value = flags
		elif current is Array:
			var numbers: Array[int] = []
			for number: Variant in value as Array:
				numbers.append(int(number))
			value = numbers
		rules.set(property, value)
	return rules


func _rule_names() -> Array[String]:
	var names: Array[String] = []
	for property in get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(str(property["name"]))
	return names


## The same rules with a different prize count, for Sudden Death.
func with_prize_count(count: int) -> MatchRules:
	var copy := MatchRules.from_dict(to_dict())
	copy.prize_count = count
	return copy
