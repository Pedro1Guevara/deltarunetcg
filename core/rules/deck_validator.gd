class_name DeckValidator
extends RefCounted
## Checks a deck against the round rules (Design Document 4.1). Pure logic: it reports
## problems and the caller decides whether they block the match.


## Returns every problem found. Empty means the deck is legal under these rules.
static func validate(deck: Array[CardData], rules: MatchRules) -> Array[String]:
	var problems: Array[String] = []

	if rules.deck_size > 0 and deck.size() != rules.deck_size:
		problems.append("has %d cards; the rules require %d" % [deck.size(), rules.deck_size])

	# Copies are counted by name, as in the Pokemon TCG. Only Basic Energy is exempt.
	if rules.max_copies > 0:
		var copies := {}
		for card in deck:
			if card.is_energy() and card.energy_kind == CardData.ENERGY_NORMAL:
				continue
			copies[card.name] = int(copies.get(card.name, 0)) + 1
		var names: Array = copies.keys()
		names.sort()
		for card_name: String in names:
			if int(copies[card_name]) > rules.max_copies:
				problems.append("has %d copies of %s; at most %d are allowed" % [copies[card_name], card_name, rules.max_copies])

	var has_basic := false
	for card in deck:
		if card.is_basic_pokemon():
			has_basic = true
			break
	if not has_basic:
		problems.append("has no Basic Darkner")

	return problems