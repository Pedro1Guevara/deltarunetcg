class_name EnergyPayment
extends RefCounted
## How attached Energy pays a cost. Pure functions: they read what they are given and change
## nothing except the pool passed to pay_typed().
##
## A cost is a list of type names, one per unit. A typed requirement is paid only by a unit of
## that type; Colorless is paid by any unit, including the Colorless units of a Special Energy.


## Removes from pool the units that pay the typed requirements of cost. Returns how many
## Colorless units are still owed, or -1 when a typed requirement cannot be paid.
static func pay_typed(pool: Array[String], cost: Array[String]) -> int:
	var colorless_needed := 0
	for requirement in cost:
		if requirement == CardTypes.COLORLESS:
			colorless_needed += 1
			continue
		var index := pool.find(requirement)
		if index == -1:
			return -1
		pool.remove_at(index)
	return colorless_needed


## True when the units in pool can pay cost. pool is not changed.
static func can_pay(pool: Array[String], cost: Array[String]) -> bool:
	var remaining := pool.duplicate()
	var colorless_needed := pay_typed(remaining, cost)
	return colorless_needed != -1 and remaining.size() >= colorless_needed


## Energy units a card provides: a Double Colorless Energy is 2. Never less than 1.
static func units(card: CardData) -> int:
	return maxi(card.provides.size(), 1)


## Every distinct set of cards worth at least units_needed units with no card to spare, as
## {"label": "Discard ...", "value": Array of CardData}, sorted by label. Copies of the same
## card are interchangeable, so each combination appears once. Empty when nothing is owed.
static func discard_options(cards: Array[CardData], units_needed: int) -> Array:
	if units_needed <= 0:
		return []
	var options: Array = []
	var seen: Array[String] = []
	for mask in range((1 << cards.size()) - 1, 0, -1):
		var chosen: Array = []
		var total := 0
		for index in cards.size():
			if mask & (1 << index):
				chosen.append(cards[index])
				total += units(cards[index])
		if total < units_needed:
			continue
		var minimal := true
		for card: Variant in chosen:
			if total - units(card as CardData) >= units_needed:
				minimal = false
				break
		if not minimal:
			continue
		var names: Array[String] = []
		for card: Variant in chosen:
			names.append((card as CardData).name)
		names.sort()
		var key := " + ".join(PackedStringArray(names))
		if seen.has(key):
			continue
		seen.append(key)
		options.append({"label": "Discard %s" % key, "value": chosen})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["label"]) < str(b["label"]))
	return options