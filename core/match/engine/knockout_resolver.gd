class_name KnockoutResolver
extends RefCounted
## Knockouts, Mercy Cards and the promotions that follow (Design Document 4.4 and 4.5). Part of
## the engine: MatchEngine owns it and is its only caller, and hands it the players and the log
## it may change. It never holds the engine.

var _players: Array[PlayerState]
var _log: MatchLog
## The players whose Battling Darkner was knocked out and still has to be replaced, in order.
var _promotion_queue: Array[int] = []
## The player who took their last Mercy Card in the last resolve() and chooses to Spare or to
## Fight, or -1 (Design Document 4.5). Read once with take_spare_fight_offer().
var _spare_fight_offer: int = -1
## resolve() returns it while Mercy Cards wait to be picked (MatchRules.choose_prizes): ask
## next_prize_choice() until has_prize_choice() is false, then settle().
const CHOOSING_PRIZES := -3
## Who still picks a Mercy Card, one entry per card, in order.
var _prize_queue: Array[int] = []
## The knockouts being resolved, kept for settle(): each knocked out Darkner's owner, and the
## players who lost their Battling Darkner.
var _owners: Array[int] = []
var _lost_battling: Array[int] = []


func _init(players: Array[PlayerState], match_log: MatchLog) -> void:
	_players = players
	_log = match_log


## Resolves every knocked out Darkner at once, as the rulebook does, in the Battle Zone or on
## the Field, the defending player's first: all are discarded, every Mercy Card is taken, and
## only then are wins checked. When the rules let players pick their Mercy Cards, it returns
## CHOOSING_PRIZES after the discards; the engine asks each pick and then calls settle(), which
## checks wins as described here. A player wins by taking their last Mercy Card, or when the
## opponent's Battling Darkner was knocked out and nothing on their Field can replace it. If
## both win, the one who won in more ways is the winner; otherwise it is Sudden Death. Returns
## the winner (MatchEngine.NO_WINNER, a player index or MatchEngine.SUDDEN_DEATH). With no
## winner, the players who lost their Battling Darkner are queued to promote. rules are the
## round's rules as they are now.
##
## With Spare and Fight (Design Document 4.5): a player whose only win is their last Mercy Card
## does not win yet, unless they are at match point; take_spare_fight_offer() names them, and
## they choose. fighting is the player
## who chose to Fight, or -1: the next knockout decides the round. A Darkner of the opponent
## knocked out wins it for them; one of their own knocked out loses it; both at once is Sudden
## Death.
func resolve(defender_index: int, rules: MatchRules, fighting: int) -> int:
	var knocked_out: Array[CardInPlay] = []
	var owners: Array[int] = []
	var lost_battling: Array[int] = []
	for index: int in [defender_index, 1 - defender_index]:
		var side := _players[index]
		# A Battle Zone an effect emptied (Close Tab) is filled like one emptied by a knockout,
		# with no Mercy Card for it.
		if side.active == null:
			lost_battling.append(index)
		for darkner: CardInPlay in [side.active] + side.bench:
			if darkner != null and darkner.is_knocked_out():
				knocked_out.append(darkner)
				owners.append(index)
				if darkner == side.active:
					lost_battling.append(index)
	if knocked_out.is_empty() and lost_battling.is_empty():
		return MatchEngine.NO_WINNER

	for position in knocked_out.size():
		var side := _players[owners[position]]
		var darkner := knocked_out[position]
		_log.add(MatchEvent.KNOCKED_OUT, owners[position], {"darkner": _log.darkner(darkner)})
		side.discard_from_play(darkner)
		if side.active == darkner:
			side.active = null
		else:
			side.bench.erase(darkner)

	_owners = owners
	_lost_battling = lost_battling
	var owed := [0, 0]
	for position in knocked_out.size():
		var taker := 1 - owners[position]
		owed[taker] = int(owed[taker]) + _prizes_for_knockout(rules, knocked_out[position])
	_prize_queue.clear()
	for taker in 2:
		var count := mini(int(owed[taker]), _players[taker].prizes.size())
		if not rules.choose_prizes:
			take_prize(taker, count)
			continue
		for _i in count:
			_prize_queue.append(taker)
	if not _prize_queue.is_empty():
		return CHOOSING_PRIZES
	return settle(rules, fighting)


## Checks wins once every Mercy Card of the knockouts resolve() found has been taken: the
## winner (MatchEngine.NO_WINNER, a player index or MatchEngine.SUDDEN_DEATH), the Spare or
## Fight offer, or the promotions to make.
func settle(rules: MatchRules, fighting: int) -> int:
	var owners := _owners
	var lost_battling := _lost_battling
	var ways := [0, 0]
	for taker in 2:
		if owners.has(1 - taker) and _players[taker].prizes.is_empty():
			ways[taker] = 1
	for index in lost_battling:
		if _players[index].bench.is_empty():
			ways[1 - index] = int(ways[1 - index]) + 1

	if rules.spare_fight and fighting != -1 and not owners.is_empty():
		return _end_fight(fighting, owners.has(1 - fighting), owners.has(fighting), rules)

	if rules.spare_fight:
		for taker in 2:
			var by_mercy_cards_only := int(ways[taker]) == 1 and owners.has(1 - taker) and _players[taker].prizes.is_empty()
			if by_mercy_cards_only and int(ways[1 - taker]) == 0 and not rules.match_point[taker]:
				_spare_fight_offer = taker
				_promotion_queue.assign(lost_battling)
				return MatchEngine.NO_WINNER

	if int(ways[0]) > 0 or int(ways[1]) > 0:
		if int(ways[0]) == int(ways[1]):
			_log.add(MatchEvent.SUDDEN_DEATH, -1, {})
			return MatchEngine.SUDDEN_DEATH
		var winner := 0 if int(ways[0]) > int(ways[1]) else 1
		_log.add(MatchEvent.WON, winner, {"winner": winner, "after_deck_out": false})
		return winner

	_promotion_queue.assign(lost_battling)
	return MatchEngine.NO_WINNER


## The player who chooses to Spare or to Fight after the last resolve(), or -1. Reading it clears it.
func take_spare_fight_offer() -> int:
	var taker := _spare_fight_offer
	_spare_fight_offer = -1
	return taker


## The winner of a fight the knockouts just ended: the fighter when only the opponent lost a
## Darkner, the opponent when only the fighter did, Sudden Death when both did.
func _end_fight(fighter: int, fighter_won: bool, fighter_lost: bool, rules: MatchRules) -> int:
	if fighter_won and fighter_lost:
		_log.add(MatchEvent.SUDDEN_DEATH, -1, {})
		return MatchEngine.SUDDEN_DEATH
	var winner := fighter if fighter_won else 1 - fighter
	_log.add(MatchEvent.FIGHT_ENDED, fighter, {"won": fighter_won, "extra_draws": 0 if fighter_won else rules.spare_extra_draws})
	_log.add(MatchEvent.WON, winner, {"winner": winner, "after_deck_out": false})
	return winner


## Moves count Mercy Cards from the top of the taker's pile to their hand, stopping when the
## pile is empty.
func take_prize(taker_index: int, count: int) -> void:
	for _i in count:
		if _players[taker_index].prizes.is_empty():
			return
		_move_prize(taker_index, _players[taker_index].prizes.size() - 1)


## Whether a Mercy Card is still to be picked.
func has_prize_choice() -> bool:
	return not _prize_queue.is_empty()


## The next pick: its player chooses a position in their face-down pile. data is what the
## engine goes on with once every pick is made.
func next_prize_choice(data: Dictionary) -> PendingChoice:
	var taker := _prize_queue[0]
	var options: Array = []
	for slot in _players[taker].prizes.size():
		options.append({"value": slot})
	return PendingChoice.new(taker, PendingChoice.KIND_TAKE_PRIZE, {"left": _players[taker].prizes.size(), "to_take": _prize_queue.count(taker)},
			options, PendingChoice.RESUME_TAKE_PRIZE, data)


## The next pick's player takes the Mercy Card at slot.
func take_prize_at(slot: int) -> void:
	_move_prize(_prize_queue.pop_front(), slot)


func _move_prize(taker_index: int, slot: int) -> void:
	var taker := _players[taker_index]
	var prize := taker.prizes.pop_at(slot) as CardData
	taker.hand.append(prize)
	_log.add_private(MatchEvent.PRIZE_TAKEN, taker_index, {"left": taker.prizes.size(), "slot": slot, "card": prize.id},
			{"left": taker.prizes.size(), "slot": slot})


## Each player whose Battling Darkner was knocked out chooses a replacement from the Field,
## the defending player first. A Field of one is promoted without asking. Returns the next
## question, or null when every promotion is done.
func next_promotion() -> PendingChoice:
	while not _promotion_queue.is_empty():
		var index := _promotion_queue[0]
		var side := _players[index]
		if side.bench.size() == 1:
			promote(index, 0)
			continue
		var options: Array = []
		for slot in side.bench.size():
			var darkner := side.bench[slot]
			options.append({"value": slot, "shows": darkner})
		return PendingChoice.new(index, PendingChoice.KIND_PROMOTE, {}, options, PendingChoice.RESUME_PROMOTE, {})
	return null


## Moves the Darkner at a Field slot into the Battle Zone of the player whose promotion is next.
func promote(index: int, slot: int) -> void:
	var side := _players[index]
	side.active = side.bench.pop_at(slot) as CardInPlay
	_promotion_queue.erase(index)
	_log.add(MatchEvent.PROMOTED, index, {"darkner": _log.darkner(side.active)})


## Mercy Cards taken for knocking out this Darkner. Effects that change it will be read here
## once the continuous-effects layer exists.
func _prizes_for_knockout(rules: MatchRules, _knocked_out: CardInPlay) -> int:
	return rules.prizes_per_knockout
