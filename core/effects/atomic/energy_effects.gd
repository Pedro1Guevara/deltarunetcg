class_name EnergyEffects
extends RefCounted
## Atomic effects on Energy: discarding attached Energy cards and counting Energy. Cards counts
## Energy cards, so a Double Colorless Energy is 1; units counts the Energy they provide, so it
## is 2.


## Discards count matching Energy cards (-1 for all), chosen with EffectChoices.pick_cards().
static func discard_energy_cards(context: EffectContext, target: CardInPlay, energy_type: String, count: int) -> Variant:
	var prompt := "Choose %s to discard from %s" % ["an Energy card" if count == 1 else "%d Energy cards" % count, target.card.name]
	var picked: Variant = EffectChoices.pick_cards(context, context.player, matching_cards(target, energy_type), count, prompt,
			"Discard", " from %s" % target.card.name)
	if picked is String:
		return picked
	return context.operations.discard_energy_cards(target, picked as Array[CardData])


## chooser discards up to count Energy cards that match filters from among every Darkner player
## has in play, chosen with EffectChoices.choose_several(). Nothing is asked when the choice
## does not matter. Returns how many cards were discarded.
static func discard_energy_in_play(context: EffectContext, player: PlayerState, chooser: PlayerState, filters: Array, count: int) -> Variant:
	var holders := {}
	var items: Array = []
	var labels: Array[String] = []
	for slot in range(-1, player.bench.size()):
		var target: CardInPlay = player.active if slot == -1 else player.bench[slot]
		if target == null:
			continue
		for energy in CardFilter.select(target.attached_energy, filters, []):
			holders[energy] = target
			var label := "Discard %s from %s (%s)" % [energy.name, target.card.name, MatchEngine.slot_name(slot)]
			items.append({"label": label, "value": energy, "shows": energy})
			if not labels.has(label):
				labels.append(label)
	var picked: Array = []
	if items.size() <= count or labels.size() == 1:
		for index in mini(count, items.size()):
			picked.append(items[index]["value"])
	else:
		var noun := "%s attached to a Darkner" % CardFilter.describe(filters) if count == 1 \
				else "%d %s attached to Darkners" % [count, CardFilter.describe(filters)]
		var several: Variant = EffectChoices.choose_several(context, chooser, "Choose %s to discard" % noun, items, count, count, "", [])
		if several is String:
			return several
		picked = several as Array

	var discarded := 0
	for energy: Variant in picked:
		var cards: Array[CardData] = [energy as CardData]
		discarded += context.operations.discard_energy_cards(holders[energy] as CardInPlay, cards)
	return discarded


static func matching_cards(target: CardInPlay, energy_type: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for energy in target.attached_energy:
		if energy_type == EffectTypes.ANY_ENERGY or energy.provides.has(energy_type):
			result.append(energy)
	return result


static func count_units(pool: Array[String], energy_type: String) -> int:
	if energy_type == EffectTypes.ANY_ENERGY:
		return pool.size()
	return pool.count(energy_type)


## Energy units of the given type left over after paying the resolving attack's cost, paying
## Colorless with other types first so as much of the given type as possible is left.
static func count_unpaid_units(context: EffectContext, energy_type: String) -> int:
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