class_name EffectChoices
extends RefCounted
## How atomic effects ask a player to choose (Design Document 4.1): cards picked one at a time,
## undone and confirmed, a Darkner, and whether a choice matters at all. Static functions; the
## answers live in the EffectContext.

## The answer that ends a choice of several cards (choose_several()).
const CONFIRM := "__confirm__"


## chooser picks count of candidates (all of them when count is -1 or there are no more). When
## the choice does not matter, because there are no more candidates than needed or they are all
## the same card, they are picked without asking. Otherwise they pick with choose_several().
## Returns Array[CardData], or PENDING while waiting for an answer. details says which question
## it is (PendingChoice.ABOUT_); zone is where the candidates are (PendingChoice.ZONE_); action
## is what happens to them.
static func pick_cards(context: EffectContext, chooser: PlayerState, candidates: Array[CardData], count: int,
		details: Dictionary, zone: String, action: String) -> Variant:
	if count < 0 or candidates.size() <= count or all_same_card(candidates):
		var taken := candidates.size() if count < 0 else mini(count, candidates.size())
		return candidates.slice(candidates.size() - taken)
	var several: Variant = choose_several(context, chooser, details, each_card_options(candidates), count, count, [], zone, action)
	if several is String:
		return several
	var picked: Array[CardData] = []
	picked.assign(several as Array)
	return picked


## Asks chooser to pick between minimum and maximum of items ({"value", "shows", "key"}, each
## value a distinct object; any other field is kept on its option), one at a time. A picked
## item is offered again as an undo until the chooser confirms, which they can do once at
## least minimum are picked (Design Document 4.1). When several can be picked, every item is
## its own option, copies numbered; when one can, items with the same key are the same choice
## and offered once. Answers accumulate in context.selection up to the confirmation (see
## answers_after_choice()). Returns the picked values in the order they were picked, or PENDING
## while waiting for an answer. details, zone and action describe the question
## (PendingChoice.KIND_PICK_CARDS).
static func choose_several(context: EffectContext, chooser: PlayerState, details: Dictionary, items: Array,
		minimum: int, maximum: int, shown: Array[CardData], zone: String, action: String) -> Variant:
	var picked: Array = []
	for answer: Variant in context.selection:
		if answer is String and answer == CONFIRM:
			return picked
		if picked.has(answer):
			picked.erase(answer)
		else:
			picked.append(answer)
	if maximum == 1:
		var distinct: Array = []
		var seen: Array[String] = []
		for item: Variant in items:
			var key := str((item as Dictionary)["key"])
			if picked.has((item as Dictionary)["value"]) or not seen.has(key):
				seen.append(key)
				distinct.append(item)
		items = distinct
	var copies := _copy_numbers(items)
	var options: Array = []
	for index in items.size():
		var item := items[index] as Dictionary
		var chosen := picked.has(item["value"])
		if not chosen and picked.size() >= maximum:
			continue
		var option := item.duplicate()
		option.erase("key")
		option["copy"] = copies[index]
		option["pick"] = PendingChoice.PICK_UNDO if chosen else PendingChoice.PICK_ADD
		options.append(option)
	if picked.size() >= minimum:
		options.append({"value": CONFIRM, "pick": PendingChoice.PICK_CONFIRM})
	var full := details.duplicate()
	full.merge({"minimum": minimum, "maximum": maximum, "picked": picked.duplicate(), "zone": zone, "action": action}, true)
	return context.ask_showing(chooser, PendingChoice.KIND_PICK_CARDS, full, options, shown)


## The answers given after a choice made with choose_several() was confirmed, for the next
## question of the same effect. All of them when no confirmation was needed.
static func answers_after_choice(context: EffectContext) -> Array:
	var index := -1
	for position in context.selection.size():
		var answer: Variant = context.selection[position]
		if answer is String and answer == CONFIRM:
			index = position
			break
	return context.selection.slice(index + 1)


## One item per card, copies included, keyed by card id.
static func each_card_options(cards: Array[CardData]) -> Array:
	var items: Array = []
	for card in cards:
		items.append({"value": card, "shows": card, "key": card.id})
	return items


## For each item, which copy of its key it is (1, 2...) when the key repeats, 0 otherwise.
static func _copy_numbers(items: Array) -> Array[int]:
	var totals := {}
	for item: Variant in items:
		var key := str((item as Dictionary)["key"])
		totals[key] = int(totals.get(key, 0)) + 1
	var seen := {}
	var copies: Array[int] = []
	for item: Variant in items:
		var key := str((item as Dictionary)["key"])
		if int(totals[key]) == 1:
			copies.append(0)
			continue
		seen[key] = int(seen.get(key, 0)) + 1
		copies.append(int(seen[key]))
	return copies


static func all_same_card(cards: Array[CardData]) -> bool:
	for card in cards:
		if card.id != cards[0].id:
			return false
	return true


## chooser picks one of player's Darkners in play, in the Battle Zone or on the Field. Only one
## Darkner is picked without asking. Returns it, or null when player has none.
static func choose_darkner(context: EffectContext, player: PlayerState, chooser: PlayerState) -> Variant:
	var slots: Array[int] = []
	for slot in range(-1, player.bench.size()):
		if (player.active if slot == -1 else player.bench[slot]) != null:
			slots.append(slot)
	if slots.is_empty():
		return null
	var slot := slots[0]
	if not context.selection.is_empty():
		slot = int(context.selection[0])
	elif slots.size() > 1:
		var options: Array = []
		for index in slots:
			options.append({"value": index, "shows": player.active if index == -1 else player.bench[index]})
		var details := {"side": PendingChoice.SIDE_OWN if player == chooser else PendingChoice.SIDE_OPPONENT, "purpose": PendingChoice.PURPOSE_TARGET}
		return context.ask(chooser, PendingChoice.KIND_CHOOSE_DARKNER, details, options)
	return player.active if slot == -1 else player.bench[slot]