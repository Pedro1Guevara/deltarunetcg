class_name CardDatabase
extends RefCounted

var _raw_by_id: Dictionary = {}


func load_cards(raw_cards: Array) -> void:
	_raw_by_id.clear()
	for entry: Variant in raw_cards:
		var raw := entry as Dictionary
		var id := str(raw.get("id", ""))
		if id.is_empty():
			push_error("CardDatabase: card without id skipped")
			continue
		if _raw_by_id.has(id):
			push_error("CardDatabase: duplicate card id '%s'" % id)
			continue
		_raw_by_id[id] = raw


func has_card(id: String) -> bool:
	return _raw_by_id.has(id)


## Builds a new CardData on every call. Each physical copy is a distinct object.
func make(id: String) -> CardData:
	if not _raw_by_id.has(id):
		push_error("CardDatabase: unknown card id '%s'" % id)
		return null
	return CardData.from_dict(_raw_by_id[id] as Dictionary)


func build_deck(deck_def: Dictionary) -> Array[CardData]:
	var deck: Array[CardData] = []
	var counts := deck_def.get("cards", {}) as Dictionary
	for id: Variant in counts:
		for _copy in int(counts[id]):
			var card := make(str(id))
			if card != null:
				deck.append(card)
	return deck
