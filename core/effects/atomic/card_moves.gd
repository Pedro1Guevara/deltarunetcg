class_name CardMoves
extends RefCounted
## Atomic effects that move cards and Darkners: deck searches, taking from the discard pile,
## discarding from the hand, attaching to the Field, switching a Darkner in. They choose through
## EffectChoices and change the round only through MatchOperations.


## chooser picks which Darkner on player's Field goes to the Battle Zone. A Field of one is
## switched in without asking. Returns 1 when a Darkner was switched in, 0 otherwise.
static func switch_in(context: EffectContext, player: PlayerState, chooser: PlayerState) -> Variant:
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
	context.operations.switch_in(player, slot)
	return 1


## player looks through their deck for up to count cards that match filters, puts them into
## their hand (their discard pile when to_discard) and shuffles the deck. The whole deck is
## shown while they choose, in its real order with the top card first, since the search ends
## in a shuffle anyway. They are asked even when nothing matches, so a search is also a look at
## the deck (Design Document 3.3). The deck is hidden, so a search may find nothing: the player
## may confirm with fewer cards than count, or none. Returns how many cards were found.
static func search_deck(context: EffectContext, player: PlayerState, filters: Array, count: int, to_discard: bool) -> Variant:
	var verb := "Discard" if to_discard else "Take"
	var prompt := "Search your deck for %s" % CardFilter.describe(filters)
	if to_discard:
		prompt += " to discard"
	var top_first := player.deck.duplicate()
	top_first.reverse()
	var matching := CardFilter.select(player.deck, filters, [])
	var picked: Variant = EffectChoices.choose_several(context, player, prompt, EffectChoices.each_card_options(matching, verb, ""), 0, count,
			"%s nothing" % verb, top_first)
	if picked is String:
		return picked
	var cards: Array[CardData] = []
	cards.assign(picked as Array)
	if to_discard:
		context.operations.discard_from_deck(player, cards)
	else:
		context.operations.take_from_deck(player, cards)
	context.operations.shuffle_deck(player)
	return cards.size()


## player puts up to count cards that match filters from their discard pile into their hand,
## chosen with EffectChoices.pick_cards(). Returns how many cards were taken.
static func take_from_discard(context: EffectContext, player: PlayerState, filters: Array, count: int) -> Variant:
	var prompt := "Choose %s to put into your hand from your discard pile" % ["a card" if count == 1 else "%d cards" % count]
	var picked: Variant = EffectChoices.pick_cards(context, player, CardFilter.select(player.discard, filters, []), count, prompt, "Take", "")
	if picked is String:
		return picked
	return context.operations.take_from_discard(player, picked as Array[CardData])


## player discards count cards from their hand, other than the ACT card being played, chosen
## with EffectChoices.pick_cards(). Returns how many cards were discarded.
static func discard_from_hand(context: EffectContext, player: PlayerState, count: int) -> Variant:
	var prompt := "Choose %s to discard from your hand" % ["a card" if count == 1 else "%d cards" % count]
	var picked: Variant = EffectChoices.pick_cards(context, player, hand_without_card_played(context, player), count, prompt, "Discard", "")
	if picked is String:
		return picked
	return context.operations.discard_from_hand(player, picked as Array[CardData])


## A player's hand without the ACT card being played: requirements are checked while it is
## still in the hand, and "other cards" never counts it.
static func hand_without_card_played(context: EffectContext, player: PlayerState) -> Array[CardData]:
	var cards: Array[CardData] = []
	for card in player.hand:
		if card != context.card:
			cards.append(card)
	return cards


## player attaches 1 card that matches filters from pile (their discard pile, or their hand
## when from_hand) to 1 Darkner on their Field. They choose the card with
## EffectChoices.pick_cards(), then the Darkner, each only when the choice matters. Returns 1
## when a card was attached, 0 when there was nothing to attach or nowhere to attach it.
static func attach_to_benched(context: EffectContext, player: PlayerState, pile: Array[CardData], filters: Array, from_hand: bool) -> Variant:
	var candidates := CardFilter.select(pile, filters, [])
	if candidates.is_empty() or player.bench.is_empty():
		return 0
	var prompt := "Choose a card from your %s to attach" % ["hand" if from_hand else "discard pile"]
	var picked: Variant = EffectChoices.pick_cards(context, player, candidates, 1, prompt, "Attach", "")
	if picked is String:
		return picked
	var energy := (picked as Array[CardData])[0]
	var answers := EffectChoices.answers_after_choice(context)
	var slot := 0
	if not answers.is_empty():
		slot = int(answers[0])
	elif player.bench.size() > 1:
		var targets: Array = []
		for index in player.bench.size():
			targets.append({
				"label": "Attach %s to %s (%s)" % [energy.name, player.bench[index].card.name, MatchEngine.slot_name(index)],
				"value": index,
				"shows": player.bench[index],
			})
		return context.ask(player, "Choose a Darkner on your Field to attach %s to" % energy.name, targets)
	if from_hand:
		context.operations.attach_from_hand(player, energy, player.bench[slot])
	else:
		context.operations.attach_from_discard(player, energy, player.bench[slot])
	return 1