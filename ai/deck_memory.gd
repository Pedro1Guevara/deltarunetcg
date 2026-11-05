class_name DeckMemory
extends RefCounted
## What a CPU knows of its own deck (Design Document 8.7). It knows its decklist, and it sees
## its hand, its discard pile and its Darkners in play, so it always knows which cards are
## unseen: those in its deck or among its Mercy Cards. Searching its deck shows it which of
## them are in the deck, so the rest are its Mercy Cards. From then on it keeps track, as a
## player would: cards that leave its sight went back into the deck (Kris, Berdly) and cards
## that come into sight left it, until it forgets, memory_turns of its own turns after the
## search. Cards are counted by id: copies are alike.

## For how many of its own turns, counting the one it searched in, it remembers which unseen
## cards are its Mercy Cards. 0 forgets at once. A difficulty setting.
var memory_turns: int = 2

var _decklist: Dictionary = {}
var _cards: Dictionary = {}
## Its Mercy Cards by id, while it remembers them.
var _prizes: Dictionary = {}
var _checked_turn: int = -1
var _last_visible: Dictionary = {}
var _last_prize_count: int = -1


func _init(deck: Array[CardData]) -> void:
	for card in deck:
		_decklist[card.id] = int(_decklist.get(card.id, 0)) + 1
		_cards[card.id] = card


## Called with every view the CPU gets.
func observe(view: PlayerView) -> void:
	var me := view.me()
	var visible := visible_cards(view)
	if _checked_turn != -1 and view.turn - _checked_turn >= 2 * memory_turns:
		forget()
	if view.chooser == view.viewer and view.choice_kind == PendingChoice.KIND_PICK_CARDS \
			and view.choice_details.get("zone") == PendingChoice.ZONE_DECK and not view.revealed.is_empty():
		var prizes := _minus(unseen(view), _count_cards(view.revealed))
		if _size(prizes) == me.prize_count:
			_prizes = prizes
			_checked_turn = view.turn
		else:
			forget()
	elif _checked_turn != -1 and _last_prize_count != -1 and me.prize_count < _last_prize_count:
		# Mercy Cards it took: among the cards that just came into sight.
		var taken := _last_prize_count - me.prize_count
		var appeared := _minus(visible, _last_visible)
		for id: String in appeared:
			while taken > 0 and int(_prizes.get(id, 0)) > 0 and int(appeared[id]) > 0:
				_prizes[id] = int(_prizes[id]) - 1
				appeared[id] = int(appeared[id]) - 1
				taken -= 1
		if taken > 0 or _size(_prizes) != me.prize_count:
			forget()
	_last_visible = visible
	_last_prize_count = me.prize_count


func forget() -> void:
	_prizes.clear()
	_checked_turn = -1


## Whether it knows which unseen cards are in its deck.
func remembers() -> bool:
	return _checked_turn != -1


## The cards it cannot see: its deck and its Mercy Cards, by id.
func unseen(view: PlayerView) -> Dictionary:
	return _minus(_decklist, visible_cards(view))


## Its deck as far as it knows: exactly while it remembers, otherwise every unseen card.
func deck(view: PlayerView) -> Dictionary:
	var cards := unseen(view)
	return _minus(cards, _prizes) if remembers() else cards


## How many cards of its deck match filter, as far as it knows (deck()).
func count_matching(view: PlayerView, filter: Array) -> int:
	var found := 0
	var cards := deck(view)
	for id: String in cards:
		if CardFilter.matches(_cards[id] as CardData, filter):
			found += int(cards[id])
	return found


## The cards of its deck as CardData, one per copy, as far as it knows (deck()).
func deck_cards(view: PlayerView) -> Array[CardData]:
	var cards: Array[CardData] = []
	var counts := deck(view)
	for id: String in counts:
		for _copy in int(counts[id]):
			cards.append(_cards[id] as CardData)
	return cards


## Its cards it can see: hand, discard pile, Darkners in play with their Energy and the cards
## under them, its Area, and the ACT card it is playing.
func visible_cards(view: PlayerView) -> Dictionary:
	var me := view.me()
	var cards: Array[CardData] = []
	cards.append_array(me.hand)
	cards.append_array(me.discard)
	for darkner in ([me.active] if me.active != null else []) + me.bench:
		cards.append((darkner as CardInPlay).card)
		cards.append_array((darkner as CardInPlay).evolved_from)
		cards.append_array((darkner as CardInPlay).attached_energy)
	if view.stadium != null and view.stadium_owner == view.viewer:
		cards.append(view.stadium)
	if view.resolving_trainer != null and view.current == view.viewer:
		cards.append(view.resolving_trainer)
	return _count_cards(cards)


static func _count_cards(cards: Array[CardData]) -> Dictionary:
	var counts := {}
	for card in cards:
		counts[card.id] = int(counts.get(card.id, 0)) + 1
	return counts


static func _minus(from: Dictionary, take: Dictionary) -> Dictionary:
	var result := {}
	for id: String in from:
		var left := int(from[id]) - int(take.get(id, 0))
		if left > 0:
			result[id] = left
	return result


static func _size(counts: Dictionary) -> int:
	var total := 0
	for id: String in counts:
		total += int(counts[id])
	return total
