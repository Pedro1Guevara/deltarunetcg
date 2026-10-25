class_name AtomicEffects
extends RefCounted
## The atomic effect vocabulary (Design Document 7, first block). Effects change state only
## through MatchEngine; counts and checks only read it.
##
## Energy is counted two ways, and the name always says which: cards counts Energy cards,
## so a Double Colorless Energy is 1; units counts the Energy they provide, so it is 2.

const ROLE_EFFECT := "effect"
const ROLE_CHECK := "check"

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
		"switch_in":
			return _switch_in(context, args["player"] as PlayerState, args["chooser"] as PlayerState)
		"shuffle_hand_into_deck":
			return engine.shuffle_hand_into_deck(args["player"] as PlayerState)
		"search_deck":
			return _search_deck(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]))
		"take_from_discard":
			return _take_from_discard(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]))
		"discard_energy_in_play":
			return _discard_energy_in_play(context, args["player"] as PlayerState, args["chooser"] as PlayerState,
					args["filter"] as Array, int(args["count"]))
	push_error("AtomicEffects: '%s' is not an effect" % name)
	return null


static func check(name: String, _context: EffectContext, args: Dictionary) -> bool:
	match name:
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


## Discards count matching Energy cards (-1 for all). The player chooses whenever the choice
## matters: when more cards match than must be discarded and they are not all the same card.
## Earlier answers live in context.selection, so the effect resumes where it stopped.
static func _discard_energy_cards(context: EffectContext, target: CardInPlay, energy_type: String, count: int) -> Variant:
	var selected := context.selection
	var candidates: Array[CardData] = []
	for energy in _matching_cards(target, energy_type):
		if not selected.has(energy):
			candidates.append(energy)
	var needed := selected.size() + candidates.size() if count < 0 else count

	while selected.size() < needed and not candidates.is_empty():
		if candidates.size() <= needed - selected.size() or _all_same_card(candidates):
			selected.append(candidates.pop_back())
			continue
		var options: Array = []
		var offered_ids: Array[String] = []
		for index in range(candidates.size() - 1, -1, -1):
			var energy := candidates[index]
			if offered_ids.has(energy.id):
				continue
			offered_ids.append(energy.id)
			options.append({"label": "Discard %s from %s" % [energy.name, target.card.name], "value": energy})
		return context.ask(context.player, "Choose an Energy card to discard from %s" % target.card.name, options)

	var cards: Array[CardData] = []
	for energy: Variant in selected:
		cards.append(energy as CardData)
	return context.engine.discard_energy_cards(target, cards)

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
			})
		return context.ask(chooser, "Choose the Darkner to switch into the Battle Zone", options)
	context.engine.switch_in(player, slot)
	return 1

## player looks through their deck for up to count cards that match filters, puts them into
## their hand and shuffles the deck. The deck is hidden, so a search may find nothing: when
## nothing matches, or because the player chooses to stop (a null answer). Returns how many
## cards were found.
static func _search_deck(context: EffectContext, player: PlayerState, filters: Array, count: int) -> Variant:
	var found := context.selection
	if found.size() < count and not found.has(null):
		var options := _take_options(CardFilter.select(player.deck, filters, found))
		if not options.is_empty():
			options.append({"label": "Take nothing" if found.is_empty() else "Stop searching", "value": null})
			return context.ask(player, "Search your deck for %s" % CardFilter.describe(filters), options)
	var cards: Array[CardData] = []
	for card: Variant in found:
		if card != null:
			cards.append(card as CardData)
	context.engine.take_from_deck(player, cards)
	context.engine.shuffle_deck(player)
	return cards.size()


## player puts up to count cards that match filters from their discard pile into their hand.
## The player chooses only when the choice matters, as with discarding Energy. Returns how
## many cards were taken.
static func _take_from_discard(context: EffectContext, player: PlayerState, filters: Array, count: int) -> Variant:
	var taken := context.selection
	var candidates := CardFilter.select(player.discard, filters, taken)
	while taken.size() < count and not candidates.is_empty():
		if candidates.size() <= count - taken.size() or _all_same_card(candidates):
			taken.append(candidates.pop_back())
			continue
		return context.ask(player, "Choose a card to put into your hand from your discard pile", _take_options(candidates))
	var cards: Array[CardData] = []
	for card: Variant in taken:
		cards.append(card as CardData)
	return context.engine.take_from_discard(player, cards)


## chooser discards up to count Energy cards that match filters from among every Darkner player
## has in play. Copies of the same card on the same Darkner are one option. Returns how many
## cards were discarded.
static func _discard_energy_in_play(context: EffectContext, player: PlayerState, chooser: PlayerState, filters: Array, count: int) -> Variant:
	var picked := context.selection
	var picked_cards: Array = []
	for pick: Variant in picked:
		picked_cards.append((pick as Dictionary)["card"])
	while picked.size() < count:
		var options: Array = []
		var offered: Array[String] = []
		for slot in range(-1, player.bench.size()):
			var target: CardInPlay = player.active if slot == -1 else player.bench[slot]
			if target == null:
				continue
			for energy in CardFilter.select(target.attached_energy, filters, picked_cards):
				var key := "%d/%s" % [slot, energy.id]
				if offered.has(key):
					continue
				offered.append(key)
				options.append({
					"label": "Discard %s from %s (%s)" % [energy.name, target.card.name, MatchEngine.slot_name(slot)],
					"value": {"target": target, "card": energy},
				})
		if options.is_empty():
			break
		if options.size() > 1:
			return context.ask(chooser, "Choose %s attached to a Darkner to discard" % CardFilter.describe(filters), options)
		picked.append(options[0]["value"])
		picked_cards.append((options[0]["value"] as Dictionary)["card"])

	var discarded := 0
	for pick: Variant in picked:
		var cards: Array[CardData] = [(pick as Dictionary)["card"] as CardData]
		discarded += context.engine.discard_energy_cards((pick as Dictionary)["target"] as CardInPlay, cards)
	return discarded


## One option per distinct card, labelled "Take <name>", valued with the card itself.
static func _take_options(cards: Array[CardData]) -> Array:
	var options: Array = []
	var offered: Array[String] = []
	for card in cards:
		if offered.has(card.id):
			continue
		offered.append(card.id)
		options.append({"label": "Take %s" % card.name, "value": card})
	return options

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
