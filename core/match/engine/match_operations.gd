class_name MatchOperations
extends RefCounted
## The changes to a round that card effects make: moving cards between zones, damage, healing,
## TP, coin flips. Part of the engine (Design Document 8.3): MatchEngine owns it, and effects
## reach it through their EffectContext. It holds only what it changes, never the engine.

## How damage reached a Darkner (_apply_damage). Attack: from an attack, after Weakness and
## Resistance. Direct: damage that is not an attack's, such as an attacker hurting itself.
## Counters: damage counters placed by an effect.
const DAMAGE_ATTACK := "attack"
const DAMAGE_DIRECT := "direct"
const DAMAGE_COUNTERS := "counters"

## True when the player taking the turn takes another one after it (Quick Selfie). The engine
## reads and clears it when the turn ends.
var extra_turn: bool = false

var _players: Array[PlayerState]
var _rng: Rng
var _log: MatchLog
## The Darkners the resolving attack has damaged, in order. Cleared when an attack starts.
var _attack_damaged: Array[CardInPlay] = []
## Darkners put onto a Field during a turn whose triggers have not resolved yet, in order.
var _entered_field: Array[CardInPlay] = []


func _init(players: Array[PlayerState], rng: Rng, match_log: MatchLog) -> void:
	_players = players
	_rng = rng
	_log = match_log


## Called by the engine when an attack starts.
func begin_attack() -> void:
	_attack_damaged.clear()


## Attack damage to a Darkner on the Field. Weakness and Resistance never apply on the Field.
func deal_benched_attack_damage(context: EffectContext, target: CardInPlay, amount: int) -> int:
	if amount <= 0 or _attack_damage_prevented(context, target):
		return 0
	return _apply_damage(target, amount, DAMAGE_ATTACK)


## Places damage counters on a Darkner: 10 damage each, never changed by Weakness or Resistance.
func place_damage_counters(target: CardInPlay, count: int) -> int:
	if count <= 0:
		return 0
	_apply_damage(target, count * 10, DAMAGE_COUNTERS)
	return count


## Attaches an Energy card from a player's discard pile to one of their Darkners. An effect,
## so it does not use the once-per-turn attachment.
func attach_from_discard(player: PlayerState, energy: CardData, target: CardInPlay) -> void:
	player.discard.erase(energy)
	target.attached_energy.append(energy)
	_log.add(MatchEvent.ENERGY_ATTACHED, _players.find(player), {"card": energy.id, "darkner": _log.darkner(target), "from": MatchEvent.ZONE_DISCARD, "by_effect": true})


## Attaches an Energy card from a player's hand through an effect. It is not the player's
## once-per-turn attachment.
func attach_from_hand(player: PlayerState, energy: CardData, target: CardInPlay) -> void:
	player.hand.erase(energy)
	target.attached_energy.append(energy)
	_log.add(MatchEvent.ENERGY_ATTACHED, _players.find(player), {"card": energy.id, "darkner": _log.darkner(target), "from": MatchEvent.ZONE_HAND, "by_effect": true})


## The player taking the turn takes another turn after this one.
func grant_extra_turn() -> void:
	extra_turn = true


## Removes up to amount damage from a Darkner. Returns the damage removed.
func heal(target: CardInPlay, amount: int) -> int:
	var healed := mini(target.damage, maxi(amount, 0))
	if healed > 0:
		target.damage -= healed
		var healed_ref := _log.darkner(target)
		_log.add(MatchEvent.HEALED, int(healed_ref["side"]), {"darkner": healed_ref, "amount": healed, "hp_left": target.remaining_hp()})
	return healed


## Whether a player has this much TP, in quarters. Every TP payment asks this first.
func can_spend_tp(player: PlayerState, quarters: int) -> bool:
	return player.tp >= quarters


## Spends TP, in quarters. Every TP payment ends here, Spells and effects alike; the caller
## has asked can_spend_tp() first.
func spend_tp(player: PlayerState, quarters: int) -> void:
	player.tp -= quarters
	_log.add(MatchEvent.TP_SPENT, _players.find(player), {"amount": quarters, "tp": player.tp})


## Shuffles every Energy card attached to a Darkner into its owner's deck. Returns how many.
func shuffle_energy_into_deck(target: CardInPlay) -> int:
	var owner := owner_of(target)
	var count := target.attached_energy.size()
	if owner == null or count == 0:
		return 0
	owner.deck.append_array(target.attached_energy)
	target.attached_energy.clear()
	_rng.shuffle(owner.deck)
	var shuffled_ref := _log.darkner(target)
	_log.add(MatchEvent.ENERGY_SHUFFLED_INTO_DECK, int(shuffled_ref["side"]), {"darkner": shuffled_ref, "count": count})
	return count


## Shuffles a Darkner in play into its owner's deck with every card under it and attached to it
## (Close Tab). Its Battle Zone or Field slot is left empty; an empty Battle Zone is filled after
## the effect, as after a knockout (KnockoutResolver). Returns how many cards went into the deck.
func shuffle_into_deck(target: CardInPlay) -> int:
	var owner := owner_of(target)
	if owner == null:
		return 0
	var shuffled_ref := _log.darkner(target)
	var cards: Array[CardData] = []
	cards.append_array(target.evolved_from)
	cards.append(target.card)
	cards.append_array(target.attached_energy)
	target.evolved_from.clear()
	target.attached_energy.clear()
	if owner.active == target:
		owner.active = null
	else:
		owner.bench.erase(target)
	owner.deck.append_array(cards)
	_rng.shuffle(owner.deck)
	_log.add(MatchEvent.DARKNER_SHUFFLED_INTO_DECK, int(shuffled_ref["side"]), {"darkner": shuffled_ref, "count": cards.size()})
	return cards.size()


## An attack with no printed damage deals none, so nothing is logged for it.
func deal_attack_damage(context: EffectContext, base_damage: int) -> int:
	var defender := context.defender
	if defender == null or base_damage <= 0 or _attack_damage_prevented(context, defender):
		return 0
	return _apply_damage(defender, Damage.apply_modifiers(context.source.card, defender.base_card(), base_damage), DAMAGE_ATTACK)


## Whether a continuous effect prevents attack damage to target, logging which one.
func _attack_damage_prevented(context: EffectContext, target: CardInPlay) -> bool:
	var preventer := ContinuousEffects.attack_damage_preventer(context.engine, target)
	if preventer == null:
		return false
	var prevented_ref := _log.darkner(target)
	_log.add(MatchEvent.DAMAGE_PREVENTED, int(prevented_ref["side"]), {"darkner": prevented_ref, "by": preventer.name})
	return true


## Damage without Weakness or Resistance, such as an attacker damaging itself.
func deal_direct_damage(target: CardInPlay, amount: int) -> int:
	if amount <= 0:
		return 0
	return _apply_damage(target, amount, DAMAGE_DIRECT)


## The Darkners the resolving attack has damaged, in order.
func damaged_by_attack() -> Array[CardInPlay]:
	return _attack_damaged.duplicate()


## The one place damage lands on a Darkner. Every way of dealing damage ends here, so what must
## happen to all damage (preventing it, effects that watch for it) is written once.
func _apply_damage(target: CardInPlay, amount: int, kind: String) -> int:
	target.damage += amount
	if kind == DAMAGE_ATTACK and amount > 0 and not _attack_damaged.has(target):
		_attack_damaged.append(target)
	var ref := _log.darkner(target)
	_log.add(MatchEvent.DAMAGE, int(ref["side"]), {"darkner": ref, "amount": amount, "kind": kind, "hp_left": target.remaining_hp()})
	return amount


## Discards the given Energy cards from a Pokemon into its owner's discard pile.
func discard_energy_cards(target: CardInPlay, cards: Array[CardData]) -> int:
	var owner := owner_of(target)
	var discarded := 0
	for energy in cards:
		var index := target.attached_energy.find(energy)
		if index == -1:
			continue
		target.attached_energy.remove_at(index)
		if owner != null:
			owner.discard.append(energy)
		discarded += 1
		var discarded_ref := _log.darkner(target)
		_log.add(MatchEvent.ENERGY_DISCARDED, int(discarded_ref["side"]), {"darkner": discarded_ref, "card": energy.id})
	return discarded


## Swaps a player's Active Pokémon with the Pokémon at a Bench slot. It is not a Retreat: no
## cost is paid and the once-per-turn Retreat is still available.
func switch_in(player: PlayerState, slot: int) -> void:
	var leaving := player.active
	player.active = player.bench[slot]
	player.bench[slot] = leaving
	_log.add(MatchEvent.SWITCHED, _players.find(player), {"in": _log.darkner(player.active), "out": _log.darkner(leaving)})


## Shuffles a player's hand into their deck. Returns how many cards the hand held.
func shuffle_hand_into_deck(player: PlayerState) -> int:
	var count := player.hand.size()
	player.deck.append_array(player.hand)
	player.hand.clear()
	_rng.shuffle(player.deck)
	_log.add(MatchEvent.HAND_SHUFFLED_INTO_DECK, _players.find(player), {"count": count})
	return count


## Moves the given cards from a player's deck into their hand. Returns how many moved. revealed:
## the opponent sees which cards, as when a search asks for a kind of card; otherwise they see
## only that a card was taken.
func take_from_deck(player: PlayerState, cards: Array[CardData], revealed: bool) -> int:
	var index := _players.find(player) + 1
	if cards.is_empty():
		_log.add(MatchEvent.NOTHING_FOUND, index - 1, {})
	for card in cards:
		player.deck.erase(card)
		player.hand.append(card)
		var data := {"card": card.id, "from": MatchEvent.ZONE_DECK, "to": MatchEvent.ZONE_HAND}
		if revealed:
			_log.add(MatchEvent.CARD_MOVED, index - 1, data)
		else:
			_log.add_private(MatchEvent.CARD_MOVED, index - 1, data, {"from": MatchEvent.ZONE_DECK, "to": MatchEvent.ZONE_HAND})
	return cards.size()


## Puts the given Darkner cards from a player's deck onto their Field, as played on turn. They
## were not played from the hand, so Abilities that apply on play do not.
func put_on_bench_from_deck(player: PlayerState, cards: Array[CardData], turn: int) -> int:
	var index := _players.find(player) + 1
	if cards.is_empty():
		_log.add(MatchEvent.NOTHING_FOUND, index - 1, {})
	for card in cards:
		player.deck.erase(card)
		var placed := _put_on_bench(player, card, turn)
		_log.add(MatchEvent.PUT_ON_FIELD, index - 1, {"darkner": _log.darkner(placed), "from": MatchEvent.ZONE_DECK})
	return cards.size()


## Puts a Basic Darkner from a player's hand onto their Field, as played on turn. Returns it.
func put_on_bench_from_hand(player: PlayerState, card: CardData, turn: int) -> CardInPlay:
	player.hand.erase(card)
	var darkner := _put_on_bench(player, card, turn)
	_log.add(MatchEvent.PUT_ON_FIELD, _players.find(player), {"darkner": _log.darkner(darkner), "from": MatchEvent.ZONE_HAND})
	return darkner


## The Darkners put onto a Field since the last call, oldest first, for the engine to resolve
## what that sets off (Cold Place).
func take_entered_field() -> Array[CardInPlay]:
	var entered := _entered_field.duplicate()
	_entered_field.clear()
	return entered


func _put_on_bench(player: PlayerState, card: CardData, turn: int) -> CardInPlay:
	var darkner := CardInPlay.new(card, turn)
	player.bench.append(darkner)
	_entered_field.append(darkner)
	return darkner


## Moves the given cards from a player's deck to their discard pile. Returns how many moved.
func discard_from_deck(player: PlayerState, cards: Array[CardData]) -> int:
	var index := _players.find(player) + 1
	if cards.is_empty():
		_log.add(MatchEvent.NOTHING_DISCARDED, index - 1, {})
	for card in cards:
		player.deck.erase(card)
		player.discard.append(card)
		_log.add(MatchEvent.CARD_MOVED, index - 1, {"card": card.id, "from": MatchEvent.ZONE_DECK, "to": MatchEvent.ZONE_DISCARD})
	return cards.size()


## Moves the given cards from a player's hand to their discard pile. Returns how many moved.
func discard_from_hand(player: PlayerState, cards: Array[CardData]) -> int:
	var index := _players.find(player) + 1
	for card in cards:
		player.hand.erase(card)
		player.discard.append(card)
		_log.add(MatchEvent.CARD_MOVED, index - 1, {"card": card.id, "from": MatchEvent.ZONE_HAND, "to": MatchEvent.ZONE_DISCARD})
	return cards.size()


## Shuffles a player's hand and puts it on the bottom of their deck. Returns how many cards the
## hand held.
func put_hand_on_bottom_of_deck(player: PlayerState) -> int:
	var cards := player.hand.duplicate()
	player.hand.clear()
	_rng.shuffle(cards)
	for card: CardData in cards:
		player.deck.insert(0, card)
	var count := cards.size()
	_log.add(MatchEvent.HAND_TO_BOTTOM_OF_DECK, _players.find(player), {"count": count})
	return count


## Moves the given cards from a player's discard pile into their hand. Returns how many moved.
func take_from_discard(player: PlayerState, cards: Array[CardData]) -> int:
	for card in cards:
		player.discard.erase(card)
		player.hand.append(card)
		_log.add(MatchEvent.CARD_MOVED, _players.find(player), {"card": card.id, "from": MatchEvent.ZONE_DISCARD, "to": MatchEvent.ZONE_HAND})
	return cards.size()


func shuffle_deck(player: PlayerState) -> void:
	_rng.shuffle(player.deck)
	_log.add(MatchEvent.DECK_SHUFFLED, _players.find(player), {})


func draw_cards(player: PlayerState, count: int) -> int:
	var drawn: Array[CardData] = []
	for _i in maxi(count, 0):
		if not player.draw_card():
			break
		drawn.append(player.hand.back())
	_log.add_private(MatchEvent.DREW, _players.find(player), {"count": drawn.size(), "cards": MatchLog.ids(drawn), "at_turn_start": false, "extra": false}, {"count": drawn.size(), "at_turn_start": false, "extra": false})
	return drawn.size()


func flip_coin() -> bool:
	var heads := _rng.coin_flip()
	_log.add(MatchEvent.COIN_FLIP, -1, {"heads": heads})
	return heads


func owner_of(pokemon: CardInPlay) -> PlayerState:
	for player in _players:
		if player.active == pokemon or player.bench.has(pokemon):
			return player
	return null


## A problem with effect data met while resolving (EffectResolver), in the log.
func log_effect_warning(message: String) -> void:
	_log.add(MatchEvent.EFFECT_WARNING, -1, {"message": message})