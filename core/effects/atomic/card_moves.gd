class_name CardMoves
extends RefCounted
## Atomic effects that move cards and Darkners: deck searches, taking from the discard pile,
## discarding from the hand, attaching to the Field, switching a Darkner in. They choose through
## EffectChoices and change the round only through MatchOperations.

## Where the cards found by search_deck() go.
const TO_HAND := "hand"
const TO_DISCARD := "discard"
const TO_BENCH := "bench"


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
			options.append({"value": index, "shows": player.bench[index]})
		var details := {"side": PendingChoice.SIDE_OWN if player == chooser else PendingChoice.SIDE_OPPONENT, "purpose": PendingChoice.PURPOSE_SWITCH_IN}
		return context.ask(chooser, PendingChoice.KIND_CHOOSE_DARKNER, details, options)
	context.operations.switch_in(player, slot)
	return 1


## player looks through their deck for up to count cards that match filters, other than cards
## named in excluded, puts them where destination says (their hand, their discard pile or their
## Field) and shuffles the deck. The whole deck is
## shown while they choose, in its real order with the top card first, since the search ends
## in a shuffle anyway. They are asked even when nothing matches, so a search is also a look at
## the deck (Design Document 3.3). The deck is hidden, so a search may find nothing: the player
## may confirm with fewer cards than count, or none. Returns how many cards were found.
static func search_deck(context: EffectContext, player: PlayerState, filters: Array, count: int, destination: String,
		excluded: Array[String]) -> Variant:
	var action := "take"
	match destination:
		TO_DISCARD:
			action = "discard"
		TO_BENCH:
			action = "put"
	var details := {"about": PendingChoice.ABOUT_SEARCH_DECK, "filter": filters.duplicate(), "destination": destination, "excluded": excluded.duplicate()}
	var top_first := player.deck.duplicate()
	top_first.reverse()
	var matching: Array[CardData] = []
	for card in CardFilter.select(player.deck, filters, []):
		if not excluded.has(card.name):
			matching.append(card)
	var picked: Variant = EffectChoices.choose_several(context, player, details, EffectChoices.each_card_options(matching), 0, count,
			top_first, PendingChoice.ZONE_DECK, action)
	if picked is String:
		return picked
	var cards: Array[CardData] = []
	cards.assign(picked as Array)
	match destination:
		TO_DISCARD:
			context.operations.discard_from_deck(player, cards)
		TO_BENCH:
			context.operations.put_on_bench_from_deck(player, cards, context.engine.turn)
		_:
			# A search for a kind of card shows the opponent what it took; one for any card does not.
			context.operations.take_from_deck(player, cards, not filters.has(CardFilter.ANY))
	context.operations.shuffle_deck(player)
	return cards.size()


## player puts up to count cards that match filters from their discard pile into their hand,
## chosen with EffectChoices.pick_cards(). Returns how many cards were taken.
static func take_from_discard(context: EffectContext, player: PlayerState, filters: Array, count: int) -> Variant:
	var details := {"about": PendingChoice.ABOUT_TAKE_FROM_DISCARD, "count": count}
	var picked: Variant = EffectChoices.pick_cards(context, player, CardFilter.select(player.discard, filters, []), count, details,
			PendingChoice.ZONE_DISCARD, "take")
	if picked is String:
		return picked
	return context.operations.take_from_discard(player, picked as Array[CardData])


## player discards count cards that match filters from their hand, other than the ACT card
## being played, chosen with EffectChoices.pick_cards(). Returns how many cards were discarded.
static func discard_from_hand(context: EffectContext, player: PlayerState, filters: Array, count: int) -> Variant:
	var details := {"about": PendingChoice.ABOUT_DISCARD_FROM_HAND, "count": count, "filter": filters.duplicate()}
	var candidates := CardFilter.select(hand_without_card_played(context, player), filters, [])
	var picked: Variant = EffectChoices.pick_cards(context, player, candidates, count, details, PendingChoice.ZONE_HAND, "discard")
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
	var picked: Variant = EffectChoices.pick_cards(context, player, candidates, 1, {"about": PendingChoice.ABOUT_ATTACH_FROM},
			PendingChoice.ZONE_HAND if from_hand else PendingChoice.ZONE_DISCARD, "attach")
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
			targets.append({"value": index, "shows": player.bench[index]})
		var details := {"side": PendingChoice.SIDE_OWN, "purpose": PendingChoice.PURPOSE_ATTACH, "card": energy.id}
		return context.ask(player, PendingChoice.KIND_CHOOSE_DARKNER, details, targets)
	if from_hand:
		context.operations.attach_from_hand(player, energy, player.bench[slot])
	else:
		context.operations.attach_from_discard(player, energy, player.bench[slot])
	return 1