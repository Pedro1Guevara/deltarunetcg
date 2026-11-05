class_name MatchLog
extends RefCounted
## The round's events (MatchEvent) and, for now, their lines of text. The engine and the parts
## it owns write here; nothing else does. lines is the same array as MatchEngine.events.

var lines: Array[String]
var entries: Array[MatchEvent] = []
var _players: Array[PlayerState]


func _init(players: Array[PlayerState], text_lines: Array[String]) -> void:
	_players = players
	lines = text_lines


## An event every player sees whole.
func add(type: String, player: int, data: Dictionary, text: String) -> MatchEvent:
	return _add(type, player, MatchEvent.PUBLIC, data, {}, text, "")


## An event the other player sees only as hidden_data and hidden_text.
func add_private(type: String, player: int, data: Dictionary, hidden_data: Dictionary, text: String, hidden_text: String) -> MatchEvent:
	return _add(type, player, MatchEvent.PRIVATE, data, hidden_data, text, hidden_text)


## An event only player sees.
func add_secret(type: String, player: int, data: Dictionary, text: String) -> MatchEvent:
	return _add(type, player, MatchEvent.SECRET, data, {}, text, "")


## The events as viewer sees them, from the index-th on.
func entries_for(viewer: int, from: int) -> Array[MatchEvent]:
	var seen: Array[MatchEvent] = []
	for position in range(maxi(from, 0), entries.size()):
		var event := entries[position].for_viewer(viewer)
		if event != null:
			seen.append(event)
	return seen


## How a Darkner is named in event data: its side, its slot (-1 the Battle Zone) and its card.
func darkner(target: CardInPlay) -> Dictionary:
	for side in _players.size():
		var owner := _players[side]
		if owner.active == target:
			return {"side": side, "slot": -1, "card": target.card.id}
		var slot := owner.bench.find(target)
		if slot != -1:
			return {"side": side, "slot": slot, "card": target.card.id}
	return {"side": -1, "slot": -1, "card": "" if target == null else target.card.id}


func player_index(player: PlayerState) -> int:
	return _players.find(player)


static func ids(cards: Array) -> Array:
	var found: Array = []
	for card: Variant in cards:
		found.append((card as CardData).id)
	return found


func _add(type: String, player: int, visibility: String, data: Dictionary, hidden_data: Dictionary, text: String, hidden_text: String) -> MatchEvent:
	var event := MatchEvent.new()
	event.index = entries.size()
	event.type = type
	event.player = player
	event.visibility = visibility
	event.data = data
	event.hidden_data = hidden_data
	event.text = text
	event.hidden_text = hidden_text
	entries.append(event)
	if not text.is_empty():
		lines.append(text)
	return event
