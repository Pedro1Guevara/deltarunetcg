class_name AtomicEffects
extends RefCounted
## The atomic effect vocabulary (Design Document 7, first block). Effects change state only
## through MatchEngine; counts and checks only read it.
##
## Energy is counted two ways, and the name always says which: cards counts Energy cards,
## so a Double Colorless Energy is 1; units counts the Energy they provide, so it is 2.

const ROLE_EFFECT := "effect"
const ROLE_CHECK := "check"
## The answer that ends a choice of several cards (_choose_several).
const CONFIRM := "__confirm__"

## name -> {role, params: {name: type}, returns: type or "", attack_only: bool}
const DECLARATIONS := {
	"flip_coins": {
		"role": ROLE_EFFECT, "params": {"count": "int"}, "returns": "int", "attack_only": false,
	},
	"attack_damage": {
		"role": ROLE_EFFECT, "params": {"times": "int", "plus": "int"}, "returns": "int", "attack_only": true,
	},
	"direct_damage": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "amount": "int"}, "returns": "int", "attack_only": false,
	},
	"discard_attached_energy_cards": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "energy_type": "energy_type_or_any", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"discard_all_attached_energy_cards": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"draw_cards": {
		"role": ROLE_EFFECT, "params": {"player": "player", "count": "int"}, "returns": "int", "attack_only": false,
	},
	"count_damage_counters": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"count_attached_energy_cards": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "energy_type": "energy_type_or_any"},
		"returns": "int", "attack_only": false,
	},
	"count_attached_energy_units": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "energy_type": "energy_type_or_any"},
		"returns": "int", "attack_only": false,
	},
	"count_unpaid_energy_units": {
		"role": ROLE_EFFECT, "params": {"energy_type": "energy_type_or_any"}, "returns": "int", "attack_only": true,
	},
	"count_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"multiply": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
	"add": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
	"min": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
		"switch_in": {
		"role": ROLE_EFFECT, "params": {"player": "player", "chooser": "player"}, "returns": "int", "attack_only": false,
	},
	"shuffle_hand_into_deck": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"search_deck": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"search_deck_to_discard": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"discard_from_hand": {
		"role": ROLE_EFFECT, "params": {"player": "player", "count": "int"}, "returns": "int", "attack_only": false,
	},
	"discard_hand": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"put_hand_on_bottom_of_deck": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"has_cards_in_hand": {
		"role": ROLE_CHECK, "params": {"player": "player", "count": "int"}, "returns": "", "attack_only": false,
	},
	"take_from_discard": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"discard_energy_in_play": {
		"role": ROLE_EFFECT, "params": {"player": "player", "chooser": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"has_cards_in_deck": {
		"role": ROLE_CHECK, "params": {"player": "player", "count": "int"}, "returns": "", "attack_only": false,
	},
	"has_cards_in_discard": {
		"role": ROLE_CHECK, "params": {"player": "player", "filter": "card_filter", "count": "int"}, "returns": "", "attack_only": false,
	},
	"has_energy_in_play": {
		"role": ROLE_CHECK, "params": {"player": "player", "filter": "card_filter", "count": "int"}, "returns": "", "attack_only": false,
	},
	"has_benched": {
		"role": ROLE_CHECK, "params": {"player": "player", "count": "int"}, "returns": "", "attack_only": false,
	},
	"attack_damage_to_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player", "amount": "int"}, "returns": "int", "attack_only": true,
	},
	"heal_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player", "amount": "int"}, "returns": "int", "attack_only": false,
	},
	"pay_tp": {
		"role": ROLE_EFFECT, "params": {"player": "player", "amount": "int"}, "returns": "int", "attack_only": false,
	},
	"shuffle_attached_energy_into_deck": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"count_same_name_in_play": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"at_least": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
	"place_damage_counters": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "count": "int"}, "returns": "int", "attack_only": false,
	},
		"place_damage_counters_on_attack_damaged": {
		"role": ROLE_EFFECT, "params": {"count": "int"}, "returns": "int", "attack_only": false,
	},
	"attach_from_discard_to_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter"}, "returns": "int", "attack_only": false,
	},
	"has_attached_energy_cards": {
		"role": ROLE_CHECK, "params": {"target": "pokemon", "energy_type": "energy_type_or_any", "count": "int"},
		"returns": "", "attack_only": false,
	},
}


static func has(name: String) -> bool:
	return DECLARATIONS.has(name)


static func declaration(name: String) -> Dictionary:
	return DECLARATIONS.get(name, {}) as Dictionary


static func params_of(name: String) -> Dictionary:
	return declaration(name).get("params", {}) as Dictionary


static func role_of(name: String) -> String:
	return str(declaration(name).get("role", ""))


static func returns_of(name: String) -> String:
	return str(declaration(name).get("returns", ""))


static func is_attack_only(name: String) -> bool:
	return bool(declaration(name).get("attack_only", false))


## Runs an effect or a count. Arguments are already resolved and type-checked.
## Returns EffectContext.PENDING when the effect is waiting for a player's choice.
static func execute(name: String, context: EffectContext, args: Dictionary) -> Variant:
	var engine := context.engine
	match name:
		"flip_coins":
			var heads := 0
			for _i in maxi(int(args["count"]), 0):
				if engine.flip_coin():
					heads += 1
			return heads
		"attack_damage":
			return engine.deal_attack_damage(context, context.attack.damage * int(args["times"]) + int(args["plus"]))
		"direct_damage":
			return engine.deal_direct_damage(args["target"] as CardInPlay, int(args["amount"]))
		"discard_attached_energy_cards":
			return _discard_energy_cards(context, args["target"] as CardInPlay, str(args["energy_type"]), int(args["count"]))
		"discard_all_attached_energy_cards":
			return _discard_energy_cards(context, args["target"] as CardInPlay, EffectTypes.ANY_ENERGY, -1)
		"draw_cards":
			return engine.draw_cards(args["player"] as PlayerState, int(args["count"]))
		"count_damage_counters":
			return floori((args["target"] as CardInPlay).damage / 10.0)
		"count_attached_energy_cards":
			return _matching_cards(args["target"] as CardInPlay, str(args["energy_type"])).size()
		"count_attached_energy_units":
			return _count_units((args["target"] as CardInPlay).energy_pool(), str(args["energy_type"]))
		"count_unpaid_energy_units":
			return _count_unpaid_units(context, str(args["energy_type"]))
		"count_benched":
			return (args["player"] as PlayerState).bench.size()
		"multiply":
			return int(args["a"]) * int(args["b"])
		"add":
			return int(args["a"]) + int(args["b"])
		"min":
			return mini(int(args["a"]), int(args["b"]))
		"at_least":
			return 1 if int(args["a"]) >= int(args["b"]) else 0
		"place_damage_counters":
			return engine.place_damage_counters(args["target"] as CardInPlay, int(args["count"]))
		"place_damage_counters_on_attack_damaged":
			var placed := 0
			for target in engine.damaged_by_attack():
				placed += engine.place_damage_counters(target, int(args["count"]))
			return placed
		"attach_from_discard_to_benched":
			return _attach_from_discard_to_benched(context, args["player"] as PlayerState, args["filter"] as Array)
		"attack_damage_to_benched":
			var dealt := 0
			for target in (args["player"] as PlayerState).bench.duplicate():
				dealt += engine.deal_benched_attack_damage(context, target, int(args["amount"]))
			return dealt
		"heal_benched":
			var healed := 0
			for target in (args["player"] as PlayerState).bench:
				healed += engine.heal(target, int(args["amount"]))
			return healed
		"pay_tp":
			return _pay_tp(context, args["player"] as PlayerState, int(args["amount"]))
		"shuffle_attached_energy_into_deck":
			return engine.shuffle_energy_into_deck(args["target"] as CardInPlay)
		"count_same_name_in_play":
			var target := args["target"] as CardInPlay
			var owner := engine.owner_of(target)
			var copies := 0
			if owner != null:
				for darkner: CardInPlay in [owner.active] + owner.bench:
					if darkner != null and darkner.card.name == target.card.name:
						copies += 1
			return copies
		"switch_in":
			return _switch_in(context, args["player"] as PlayerState, args["chooser"] as PlayerState)
		"shuffle_hand_into_deck":
			return engine.shuffle_hand_into_deck(args["player"] as PlayerState)
		"search_deck":
			return _search_deck(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]), false)
		"search_deck_to_discard":
			return _search_deck(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]), true)
		"discard_from_hand":
			return _discard_from_hand(context, args["player"] as PlayerState, int(args["count"]))
		"discard_hand":
			return engine.discard_from_hand(args["player"] as PlayerState, (args["player"] as PlayerState).hand.duplicate())
		"put_hand_on_bottom_of_deck":
			return engine.put_hand_on_bottom_of_deck(args["player"] as PlayerState)
		"take_from_discard":
			return _take_from_discard(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]))
		"discard_energy_in_play":
			return _discard_energy_in_play(context, args["player"] as PlayerState, args["chooser"] as PlayerState,
					args["filter"] as Array, int(args["count"]))
	push_error("AtomicEffects: '%s' is not an effect" % name)
	return null


static func check(name: String, context: EffectContext, args: Dictionary) -> bool:
	match name:
		"has_cards_in_hand":
			return _hand_without_card_played(context, args["player"] as PlayerState).size() >= int(args["count"])
		"has_benched":
			return (args["player"] as PlayerState).bench.size() >= int(args["count"])
		"has_cards_in_deck":
			return (args["player"] as PlayerState).deck.size() >= int(args["count"])
		"has_cards_in_discard":
			var owner := args["player"] as PlayerState
			return CardFilter.select(owner.discard, args["filter"] as Array, []).size() >= int(args["count"])
		"has_energy_in_play":
			var side := args["player"] as PlayerState
			var found := 0
			for darkner: CardInPlay in [side.active] + side.bench:
				if darkner != null:
					found += CardFilter.select(darkner.attached_energy, args["filter"] as Array, []).size()
			return found >= int(args["count"])
		"has_attached_energy_cards":
			var target := args["target"] as CardInPlay
			return _matching_cards(target, str(args["energy_type"])).size() >= int(args["count"])
	push_error("AtomicEffects: '%s' is not a check" % name)
	return false


## Discards count matching Energy cards (-1 for all), chosen with _pick_cards().
static func _discard_energy_cards(context: EffectContext, target: CardInPlay, energy_type: String, count: int) -> Variant:
	var prompt := "Choose %s to discard from %s" % ["an Energy card" if count == 1 else "%d Energy cards" % count, target.card.name]
	var picked: Variant = _pick_cards(context, context.player, _matching_cards(target, energy_type), count, prompt,
			"Discard", " from %s" % target.card.name)
	if picked is String:
		return picked
	return context.engine.discard_energy_cards(target, picked as Array[CardData])

## chooser picks which Darkner on player's Field goes to the Battle Zone. A Field of one is
## switched in without asking. Returns 1 when a Darkner was switched in, 0 otherwise.
static func _switch_in(context: EffectContext, player: PlayerState, chooser: PlayerState) -> Variant:
	if player.bench.is_empty() or player.active == null:
		return 0
	var slot := 0
	if not context.selection.is_empty():
		slot = int(context.selection[0])
	elif player.bench.size() > 1:
		var options: Array = []
		for index in player.bench.size():
			options.append({
				"label": "Switch in %s (%s)" % [player.bench[index].card.name, MatchEngine.slot_name(index)],
				"value": index,
				"shows": player.bench[index],
			})
		return context.ask(chooser, "Choose the Darkner to switch into the Battle Zone", options)
	context.engine.switch_in(player, slot)
	return 1

## player looks through their deck for up to count cards that match filters, puts them into
## their hand (their discard pile when to_discard) and shuffles the deck. The whole deck is
## shown while they choose, in its real order with the top card first, since the search ends
## in a shuffle anyway. They are asked even when nothing matches, so a search is also a look at
## the deck (Design Document 3.3). The deck is hidden, so a search may find nothing: a null
## answer stops a search for one card, and a search for several may be confirmed with fewer.
## Returns how many cards were found.
static func _search_deck(context: EffectContext, player: PlayerState, filters: Array, count: int, to_discard: bool) -> Variant:
	var verb := "Discard" if to_discard else "Take"
	var prompt := "Search your deck for %s" % CardFilter.describe(filters)
	if to_discard:
		prompt += " to discard"
	var top_first := player.deck.duplicate()
	top_first.reverse()
	var cards: Array[CardData] = []
	if count >= 2:
		var matching := CardFilter.select(player.deck, filters, [])
		var picked: Variant = _choose_several(context, player, prompt, _each_card_options(matching, verb, ""), 0, count,
				"%s nothing" % verb, top_first)
		if picked is String:
			return picked
		cards.assign(picked as Array)
	else:
		var found := context.selection
		if found.is_empty():
			var options := _card_options(CardFilter.select(player.deck, filters, []), verb)
			options.append({"label": "%s nothing" % verb, "value": null})
			return context.ask_showing(player, prompt, options, top_first)
		if found[0] != null:
			cards.append(found[0] as CardData)
	if to_discard:
		context.engine.discard_from_deck(player, cards)
	else:
		context.engine.take_from_deck(player, cards)
	context.engine.shuffle_deck(player)
	return cards.size()


## player puts up to count cards that match filters from their discard pile into their hand,
## chosen with _pick_cards(). Returns how many cards were taken.
static func _take_from_discard(context: EffectContext, player: PlayerState, filters: Array, count: int) -> Variant:
	var prompt := "Choose %s to put into your hand from your discard pile" % ["a card" if count == 1 else "%d cards" % count]
	var picked: Variant = _pick_cards(context, player, CardFilter.select(player.discard, filters, []), count, prompt, "Take", "")
	if picked is String:
		return picked
	return context.engine.take_from_discard(player, picked as Array[CardData])


## chooser discards up to count Energy cards that match filters from among every Darkner player
## has in play. For one card, copies of the same card on the same Darkner are one option; for
## several, every card is its own option, picked one at a time and confirmed (_choose_several).
## Returns how many cards were discarded.
static func _discard_energy_in_play(context: EffectContext, player: PlayerState, chooser: PlayerState, filters: Array, count: int) -> Variant:
	var holders := {}
	var items: Array = []
	var options: Array = []
	var offered: Array[String] = []
	for slot in range(-1, player.bench.size()):
		var target: CardInPlay = player.active if slot == -1 else player.bench[slot]
		if target == null:
			continue
		for energy in CardFilter.select(target.attached_energy, filters, []):
			holders[energy] = target
			var label := "Discard %s from %s (%s)" % [energy.name, target.card.name, MatchEngine.slot_name(slot)]
			items.append({"label": label, "value": energy, "shows": energy})
			var key := "%d/%s" % [slot, energy.id]
			if not offered.has(key):
				offered.append(key)
				options.append({"label": label, "value": energy, "shows": energy})
	var picked: Array = []
	if items.size() <= count or offered.size() == 1:
		for index in mini(count, items.size()):
			picked.append(items[index]["value"])
	elif count >= 2:
		var prompt := "Choose %d %s attached to Darkners to discard" % [count, CardFilter.describe(filters)]
		var several: Variant = _choose_several(context, chooser, prompt, items, count, count, "", [])
		if several is String:
			return several
		picked = several as Array
	elif context.selection.is_empty():
		return context.ask(chooser, "Choose %s attached to a Darkner to discard" % CardFilter.describe(filters), options)
	else:
		picked = [context.selection[0]]

	var discarded := 0
	for energy: Variant in picked:
		var cards: Array[CardData] = [energy as CardData]
		discarded += context.engine.discard_energy_cards(holders[energy] as CardInPlay, cards)
	return discarded


## One option per distinct card, labelled "Take <name>", valued with the card itself.
static func _take_options(cards: Array[CardData]) -> Array:
	return _card_options(cards, "Take")


## One option per distinct card, labelled "<verb> <name>", valued with the card itself.
static func _card_options(cards: Array[CardData], verb: String) -> Array:
	var options: Array = []
	var offered: Array[String] = []
	for card in cards:
		if offered.has(card.id):
			continue
		offered.append(card.id)
		options.append({"label": "%s %s" % [verb, card.name], "value": card, "shows": card})
	return options


## player discards count cards from their hand, other than the ACT card being played, chosen
## with _pick_cards(). Returns how many cards were discarded.
static func _discard_from_hand(context: EffectContext, player: PlayerState, count: int) -> Variant:
	var prompt := "Choose %s to discard from your hand" % ["a card" if count == 1 else "%d cards" % count]
	var picked: Variant = _pick_cards(context, player, _hand_without_card_played(context, player), count, prompt, "Discard", "")
	if picked is String:
		return picked
	return context.engine.discard_from_hand(player, picked as Array[CardData])


## chooser picks count of candidates (all of them when count is -1 or there are no more). When
## the choice does not matter, because there are no more candidates than needed or they are all
## the same card, they are picked without asking. One card is one question, with one option per
## distinct card. Several cards are picked with _choose_several(). Returns Array[CardData], or
## PENDING while waiting for an answer.
static func _pick_cards(context: EffectContext, chooser: PlayerState, candidates: Array[CardData], count: int,
		prompt: String, verb: String, suffix: String) -> Variant:
	if count < 0 or candidates.size() <= count or _all_same_card(candidates):
		var taken := candidates.size() if count < 0 else mini(count, candidates.size())
		return candidates.slice(candidates.size() - taken)
	var picked: Array[CardData] = []
	if count == 1:
		if context.selection.is_empty():
			var options: Array = []
			for option in _card_options(candidates, verb):
				option["label"] = str(option["label"]) + suffix
				options.append(option)
			return context.ask(chooser, prompt, options)
		picked.append(context.selection[0] as CardData)
		return picked
	var several: Variant = _choose_several(context, chooser, prompt, _each_card_options(candidates, verb, suffix), count, count, "", [])
	if several is String:
		return several
	picked.assign(several as Array)
	return picked


## Asks chooser to pick between minimum and maximum of items ({label, value, shows}, each value
## a distinct object) one at a time. Every item is its own option, copies numbered. A picked
## item is offered again as "Undo: ..." until the chooser confirms, which they can do once at
## least minimum are picked. Answers accumulate in context.selection. Returns the picked
## values in the order they were picked, or PENDING while waiting for an answer.
static func _choose_several(context: EffectContext, chooser: PlayerState, prompt: String, items: Array,
		minimum: int, maximum: int, nothing_label: String, shown: Array[CardData]) -> Variant:
	var picked: Array = []
	for answer: Variant in context.selection:
		if answer is String and answer == CONFIRM:
			return picked
		if picked.has(answer):
			picked.erase(answer)
		else:
			picked.append(answer)
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
	return context.ask_showing(chooser, "%s (%d/%d chosen)" % [prompt, picked.size(), maximum], options, shown)


## One option per card, copies included, labelled "<verb> <name><suffix>".
static func _each_card_options(cards: Array[CardData], verb: String, suffix: String) -> Array:
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


## A player's hand without the ACT card being played: requirements are checked while it is
## still in the hand, and "other cards" never counts it.
static func _hand_without_card_played(context: EffectContext, player: PlayerState) -> Array[CardData]:
	var cards: Array[CardData] = []
	for card in player.hand:
		if card != context.card:
			cards.append(card)
	return cards

## player attaches 1 card that matches filters from their discard pile to 1 Darkner on their
## Field. They choose the card, then the Darkner, each only when the choice matters. Returns 1
## when a card was attached, 0 when there was nothing to attach or nowhere to attach it.
static func _attach_from_discard_to_benched(context: EffectContext, player: PlayerState, filters: Array) -> Variant:
	var picked := context.selection
	var candidates := CardFilter.select(player.discard, filters, [])
	if candidates.is_empty() or player.bench.is_empty():
		return 0
	if picked.is_empty():
		if not _all_same_card(candidates):
			var options: Array = []
			for option in _take_options(candidates):
				options.append({"label": "Attach %s" % (option["value"] as CardData).name, "value": option["value"]})
			return context.ask(player, "Choose a card from your discard pile to attach", options)
		picked.append(candidates.back())
	var energy := picked[0] as CardData
	var slot := 0
	if picked.size() > 1:
		slot = int(picked[1])
	elif player.bench.size() > 1:
		var targets: Array = []
		for index in player.bench.size():
			targets.append({
				"label": "Attach %s to %s (%s)" % [energy.name, player.bench[index].card.name, MatchEngine.slot_name(index)],
				"value": index,
				"shows": player.bench[index],
			})
		return context.ask(player, "Choose a Darkner on your Field to attach %s to" % energy.name, targets)
	context.engine.attach_from_discard(player, energy, player.bench[slot])
	return 1

## player chooses whether to spend amount TP, in quarters. Without enough TP nothing is asked
## and nothing is spent. Returns 1 when the TP was spent, 0 otherwise.
static func _pay_tp(context: EffectContext, player: PlayerState, amount: int) -> Variant:
	if not context.engine.can_spend_tp(player, amount):
		return 0
	if context.selection.is_empty():
		return context.ask(player, "Use %d%% TP?" % (amount * 25), [
			{"label": "Use %d%% TP" % (amount * 25), "value": 1},
			{"label": "Don't use TP", "value": 0},
		])
	if int(context.selection[0]) == 0:
		return 0
	context.engine.spend_tp(player, amount)
	return 1

static func _matching_cards(target: CardInPlay, energy_type: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for energy in target.attached_energy:
		if energy_type == EffectTypes.ANY_ENERGY or energy.provides.has(energy_type):
			result.append(energy)
	return result


static func _all_same_card(cards: Array[CardData]) -> bool:
	for card in cards:
		if card.id != cards[0].id:
			return false
	return true


static func _count_units(pool: Array[String], energy_type: String) -> int:
	if energy_type == EffectTypes.ANY_ENERGY:
		return pool.size()
	return pool.count(energy_type)


## Energy units of the given type left over after paying the resolving attack's cost, paying
## Colorless with other types first so as much of the given type as possible is left.
static func _count_unpaid_units(context: EffectContext, energy_type: String) -> int:
	var pool := context.source.energy_pool()
	var colorless_needed := EnergyPayment.pay_typed(pool, context.engine.attack_cost(context.source, context.attack))
	if colorless_needed == -1:
		return 0

	if energy_type != EffectTypes.ANY_ENERGY:
		var others := 0
		var matching := 0
		for energy in pool:
			if energy == energy_type:
				matching += 1
			else:
				others += 1
		colorless_needed -= mini(colorless_needed, others)
		return maxi(matching - colorless_needed, 0)

	return maxi(pool.size() - colorless_needed, 0)