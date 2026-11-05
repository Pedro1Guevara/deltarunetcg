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
var _events: Array[String]
## The Darkners the resolving attack has damaged, in order. Cleared when an attack starts.
var _attack_damaged: Array[CardInPlay] = []


func _init(players: Array[PlayerState], rng: Rng, events: Array[String]) -> void:
	_players = players
	_rng = rng
	_events = events


## Called by the engine when an attack starts.
func begin_attack() -> void:
	_attack_damaged.clear()


## Attack damage to a Darkner on the Field. Weakness and Resistance never apply on the Field.
func deal_benched_attack_damage(_context: EffectContext, target: CardInPlay, amount: int) -> int:
	if amount <= 0:
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
	_log("  Player %d attaches %s from their discard pile to %s" % [_players.find(player) + 1, energy.name, target.card.name])


## Attaches an Energy card from a player's hand through an effect. It is not the player's
## once-per-turn attachment.
func attach_from_hand(player: PlayerState, energy: CardData, target: CardInPlay) -> void:
	player.hand.erase(energy)
	target.attached_energy.append(energy)
	_log("  Player %d attaches %s from their hand to %s" % [_players.find(player) + 1, energy.name, target.card.name])


## The player taking the turn takes another turn after this one.
func grant_extra_turn() -> void:
	extra_turn = true


## Removes up to amount damage from a Darkner. Returns the damage removed.
func heal(target: CardInPlay, amount: int) -> int:
	var healed := mini(target.damage, maxi(amount, 0))
	if healed > 0:
		target.damage -= healed
		_log("  %s heals %d damage (%d/%d HP)" % [target.card.name, healed, target.remaining_hp(), target.card.hp])
	return healed


## Whether a player has this much TP, in quarters. Every TP payment asks this first.
func can_spend_tp(player: PlayerState, quarters: int) -> bool:
	return player.tp >= quarters


## Spends TP, in quarters. Every TP payment ends here, Spells and effects alike; the caller
## has asked can_spend_tp() first.
func spend_tp(player: PlayerState, quarters: int) -> void:
	player.tp -= quarters
	_log("  Player %d uses %d%% TP (%d%% left)" % [_players.find(player) + 1, quarters * 25, player.tp * 25])


## Shuffles every Energy card attached to a Darkner into its owner's deck. Returns how many.
func shuffle_energy_into_deck(target: CardInPlay) -> int:
	var owner := owner_of(target)
	var count := target.attached_energy.size()
	if owner == null or count == 0:
		return 0
	owner.deck.append_array(target.attached_energy)
	target.attached_energy.clear()
	_rng.shuffle(owner.deck)
	_log("  %s shuffles %d Energy card%s into the deck" % [target.card.name, count, "" if count == 1 else "s"])
	return count


## An attack with no printed damage deals none, so nothing is logged for it.
func deal_attack_damage(context: EffectContext, base_damage: int) -> int:
	var defender := context.defender
	if defender == null or base_damage <= 0:
		return 0
	return _apply_damage(defender, Damage.apply_modifiers(context.source.card, defender.base_card(), base_damage), DAMAGE_ATTACK)


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
	var hp := "(%d/%d HP)" % [target.remaining_hp(), target.card.hp]
	match kind:
		DAMAGE_ATTACK:
			_log("  %d damage to %s %s" % [amount, target.card.name, hp])
		DAMAGE_COUNTERS:
			var counters := amount / 10
			_log("  %d damage counter%s on %s %s" % [counters, "" if counters == 1 else "s", target.card.name, hp])
		_:
			_log("  %s takes %d damage %s" % [target.card.name, amount, hp])
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
		_log("  %s discards %s" % [target.card.name, energy.name])
	return discarded


## Swaps a player's Active Pokémon with the Pokémon at a Bench slot. It is not a Retreat: no
## cost is paid and the once-per-turn Retreat is still available.
func switch_in(player: PlayerState, slot: int) -> void:
	var leaving := player.active
	player.active = player.bench[slot]
	player.bench[slot] = leaving
	_log("  Player %d switches %s into the Battle Zone; %s goes to the Field" % [
		_players.find(player) + 1, player.active.card.name, leaving.card.name,
	])


## Shuffles a player's hand into their deck. Returns how many cards the hand held.
func shuffle_hand_into_deck(player: PlayerState) -> int:
	var count := player.hand.size()
	player.deck.append_array(player.hand)
	player.hand.clear()
	_rng.shuffle(player.deck)
	_log("  Player %d shuffles %d card%s from their hand into their deck" % [_players.find(player) + 1, count, "" if count == 1 else "s"])
	return count


## Moves the given cards from a player's deck into their hand. Returns how many moved.
func take_from_deck(player: PlayerState, cards: Array[CardData]) -> int:
	var index := _players.find(player) + 1
	if cards.is_empty():
		_log("  Player %d finds nothing" % index)
	for card in cards:
		player.deck.erase(card)
		player.hand.append(card)
		_log("  Player %d puts %s from their deck into their hand" % [index, card.name])
	return cards.size()


## Puts the given Darkner cards from a player's deck onto their Field, as played on turn. They
## were not played from the hand, so Abilities that apply on play do not.
func put_on_bench_from_deck(player: PlayerState, cards: Array[CardData], turn: int) -> int:
	var index := _players.find(player) + 1
	if cards.is_empty():
		_log("  Player %d finds nothing" % index)
	for card in cards:
		player.deck.erase(card)
		player.bench.append(CardInPlay.new(card, turn))
		_log("  Player %d puts %s from their deck onto the Field" % [index, card.name])
	return cards.size()


## Moves the given cards from a player's deck to their discard pile. Returns how many moved.
func discard_from_deck(player: PlayerState, cards: Array[CardData]) -> int:
	var index := _players.find(player) + 1
	if cards.is_empty():
		_log("  Player %d discards nothing" % index)
	for card in cards:
		player.deck.erase(card)
		player.discard.append(card)
		_log("  Player %d discards %s from their deck" % [index, card.name])
	return cards.size()


## Moves the given cards from a player's hand to their discard pile. Returns how many moved.
func discard_from_hand(player: PlayerState, cards: Array[CardData]) -> int:
	var index := _players.find(player) + 1
	for card in cards:
		player.hand.erase(card)
		player.discard.append(card)
		_log("  Player %d discards %s from their hand" % [index, card.name])
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
	_log("  Player %d puts %d card%s from their hand on the bottom of their deck" % [_players.find(player) + 1, count, "" if count == 1 else "s"])
	return count


## Moves the given cards from a player's discard pile into their hand. Returns how many moved.
func take_from_discard(player: PlayerState, cards: Array[CardData]) -> int:
	for card in cards:
		player.discard.erase(card)
		player.hand.append(card)
		_log("  Player %d puts %s from their discard pile into their hand" % [_players.find(player) + 1, card.name])
	return cards.size()


func shuffle_deck(player: PlayerState) -> void:
	_rng.shuffle(player.deck)
	_log("  Player %d shuffles their deck" % (_players.find(player) + 1))


func draw_cards(player: PlayerState, count: int) -> int:
	var drawn := 0
	for _i in maxi(count, 0):
		if not player.draw_card():
			break
		drawn += 1
	_log("  Player %d draws %d card%s" % [_players.find(player) + 1, drawn, "" if drawn == 1 else "s"])
	return drawn


func flip_coin() -> bool:
	var heads := _rng.coin_flip()
	_log("  Coin flip: %s" % ("heads" if heads else "tails"))
	return heads


func owner_of(pokemon: CardInPlay) -> PlayerState:
	for player in _players:
		if player.active == pokemon or player.bench.has(pokemon):
			return player
	return null


func log_event(text: String) -> void:
	_log(text)


func _log(text: String) -> void:
	_events.append(text)