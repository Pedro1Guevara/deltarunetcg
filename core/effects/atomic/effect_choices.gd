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
## Returns Array[CardData], or PENDING while waiting for an answer.
static func pick_cards(context: EffectContext, chooser: PlayerState, candidates: Array[CardData], count: int,
		prompt: String, verb: String, suffix: String) -> Variant:
	if count < 0 or candidates.size() <= count or all_same_card(candidates):
		var taken := candidates.size() if count < 0 else mini(count, candidates.size())
		return candidates.slice(candidates.size() - taken)
	var several: Variant = choose_several(context, chooser, prompt, each_card_options(candidates, verb, suffix), count, count, "", [])
	if several is String:
		return several
	var picked: Array[CardData] = []
	picked.assign(several as Array)
	return picked


## Asks chooser to pick between minimum and maximum of items ({label, value, shows}, each value
## a distinct object), one at a time. A picked item is offered again as "Undo: ..." until the
## chooser confirms, which they can do once at least minimum are picked (Design Document 4.1).
## When several can be picked, every item is its own option, copies numbered; when one can,
## items with the same label are the same choice and offered once. Answers accumulate in
## context.selection up to the confirmation (see answers_after_choice()). Returns the picked
## values in the order they were picked, or PENDING while waiting for an answer.
static func choose_several(context: EffectContext, chooser: PlayerState, prompt: String, items: Array,
		minimum: int, maximum: int, nothing_label: String, shown: Array[CardData]) -> Variant:
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
			var label := str((item as Dictionary)["label"])
			if picked.has((item as Dictionary)["value"]) or not seen.has(label):
				seen.append(label)
				distinct.append(item)
		items = distinct
	var labels := _numbered_labels(items)
	var options: Array = []
	for index in items.size():
		var item := items[index] as Dictionary
		var chosen := picked.has(item["value"])
		if not chosen and picked.size() >= maximum:
			continue
		options.append({"label": ("Undo: %s" % labels[index]) if chosen else labels[index], "value": item["value"], "shows": item["shows"]})
	if picked.size() >= minimum:
		options.append({"label": nothing_label if picked.is_empty() else "Confirm", "value": CONFIRM})
	if maximum >= 2:
		prompt = "%s (%d/%d chosen)" % [prompt, picked.size(), maximum]
	return context.ask_showing(chooser, prompt, options, shown)


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


## One option per card, copies included, labelled "<verb> <name><suffix>".
static func each_card_options(cards: Array[CardData], verb: String, suffix: String) -> Array:
	var items: Array = []
	for card in cards:
		items.append({"label": "%s %s%s" % [verb, card.name, suffix], "value": card, "shows": card})
	return items


## The items' labels, with " #1", " #2"... added to labels that repeat.
static func _numbered_labels(items: Array) -> Array[String]:
	var totals := {}
	for item: Variant in items:
		var label := str((item as Dictionary)["label"])
		totals[label] = int(totals.get(label, 0)) + 1
	var seen := {}
	var labels: Array[String] = []
	for item: Variant in items:
		var label := str((item as Dictionary)["label"])
		if int(totals[label]) == 1:
			labels.append(label)
			continue
		seen[label] = int(seen.get(label, 0)) + 1
		labels.append("%s #%d" % [label, int(seen[label])])
	return labels


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
			var darkner: CardInPlay = player.active if index == -1 else player.bench[index]
			options.append({
				"label": "Choose %s (%s, %d/%d HP)" % [darkner.card.name, MatchEngine.slot_name(index), darkner.remaining_hp(), darkner.card.hp],
				"value": index,
				"shows": darkner,
			})
		var whose := "your" if player == chooser else "your opponent's"
		return context.ask(chooser, "Choose one of %s Darkners" % whose, options)
	return player.active if slot == -1 else player.bench[slot]