class_name MatchLog
extends RefCounted
## The round's events (MatchEvent), in order. The engine and the parts it owns write here;
## nothing else does. It holds no words: game/presentation writes the log from the events.

var entries: Array[MatchEvent] = []
var _players: Array[PlayerState]


func _init(players: Array[PlayerState]) -> void:
	_players = players


## An event every player sees whole.
func add(type: String, player: int, data: Dictionary) -> MatchEvent:
	return _add(type, player, MatchEvent.PUBLIC, data, {})


## An event the other player sees only as hidden_data.
func add_private(type: String, player: int, data: Dictionary, hidden_data: Dictionary) -> MatchEvent:
	return _add(type, player, MatchEvent.PRIVATE, data, hidden_data)


## An event only player sees.
func add_secret(type: String, player: int, data: Dictionary) -> MatchEvent:
	return _add(type, player, MatchEvent.SECRET, data, {})


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


## value with every CardData as its id and every Darkner as its ref plus "hp_left", through
## Arrays and Dictionaries, so it can be kept in an event.
func as_data(value: Variant) -> Variant:
	if value is CardData:
		return (value as CardData).id
	if value is CardInPlay:
		var ref := darkner(value as CardInPlay)
		ref["hp_left"] = (value as CardInPlay).remaining_hp()
		return ref
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(as_data(item))
		return items
	if value is Dictionary:
		var entries_by_key := {}
		for key: Variant in value:
			entries_by_key[key] = as_data((value as Dictionary)[key])
		return entries_by_key
	return value


func player_index(player: PlayerState) -> int:
	return _players.find(player)


static func ids(cards: Array) -> Array:
	var found: Array = []
	for card: Variant in cards:
		found.append((card as CardData).id)
	return found


func _add(type: String, player: int, visibility: String, data: Dictionary, hidden_data: Dictionary) -> MatchEvent:
	var event := MatchEvent.new()
	event.index = entries.size()
	event.type = type
	event.player = player
	event.visibility = visibility
	event.data = data
	event.hidden_data = hidden_data
	entries.append(event)
	return event
