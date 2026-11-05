class_name KnockoutResolver
extends RefCounted
## Knockouts, Mercy Cards and the promotions that follow (Design Document 4.4 and 4.5). Part of
## the engine: MatchEngine owns it and is its only caller, and hands it the players and the log
## it may change. It never holds the engine.

var _players: Array[PlayerState]
var _events: Array[String]
## The players whose Battling Darkner was knocked out and still has to be replaced, in order.
var _promotion_queue: Array[int] = []


func _init(players: Array[PlayerState], events: Array[String]) -> void:
	_players = players
	_events = events


## Resolves every knocked out Darkner at once, as the rulebook does, in the Battle Zone or on
## the Field, the defending player's first: all are discarded, every Mercy Card is taken, and
## only then are wins checked. A player wins by taking their last Mercy Card, or when the
## opponent's Battling Darkner was knocked out and nothing on their Field can replace it. If
## both win, the one who won in more ways is the winner; otherwise it is Sudden Death. Returns
## the winner (MatchEngine.NO_WINNER, a player index or MatchEngine.SUDDEN_DEATH). With no
## winner, the players who lost their Battling Darkner are queued to promote. rules are the
## round's rules as they are now.
func resolve(defender_index: int, rules: MatchRules) -> int:
	var knocked_out: Array[CardInPlay] = []
	var owners: Array[int] = []
	var lost_battling: Array[int] = []
	for index: int in [defender_index, 1 - defender_index]:
		var side := _players[index]
		for darkner: CardInPlay in [side.active] + side.bench:
			if darkner != null and darkner.is_knocked_out():
				knocked_out.append(darkner)
				owners.append(index)
				if darkner == side.active:
					lost_battling.append(index)
	if knocked_out.is_empty():
		return MatchEngine.NO_WINNER

	for position in knocked_out.size():
		var side := _players[owners[position]]
		var darkner := knocked_out[position]
		_log("%s is knocked out" % darkner.card.name)
		side.discard_from_play(darkner)
		if side.active == darkner:
			side.active = null
		else:
			side.bench.erase(darkner)

	var ways := [0, 0]
	for position in knocked_out.size():
		take_prize(1 - owners[position], _prizes_for_knockout(rules, knocked_out[position]))
	for taker in 2:
		if owners.has(1 - taker) and _players[taker].prizes.is_empty():
			ways[taker] = 1
	for index in lost_battling:
		if _players[index].bench.is_empty():
			ways[1 - index] = int(ways[1 - index]) + 1

	if int(ways[0]) > 0 or int(ways[1]) > 0:
		if int(ways[0]) == int(ways[1]):
			_log("Both players win at the same time: Sudden Death")
			return MatchEngine.SUDDEN_DEATH
		var winner := 0 if int(ways[0]) > int(ways[1]) else 1
		_log("Player %d wins" % (winner + 1))
		return winner

	_promotion_queue.assign(lost_battling)
	return MatchEngine.NO_WINNER


## Moves count Mercy Cards from the taker's pile to their hand, stopping when the pile is empty.
func take_prize(taker_index: int, count: int) -> void:
	var taker := _players[taker_index]
	for _i in count:
		if taker.prizes.is_empty():
			return
		taker.hand.append(taker.prizes.pop_back() as CardData)
		_log("Player %d takes a Mercy Card (%d left)" % [taker_index + 1, taker.prizes.size()])


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
			options.append({
				"label": "Promote %s (%s, %d/%d HP)" % [darkner.card.name, MatchEngine.slot_name(slot), darkner.remaining_hp(), darkner.card.hp],
				"value": slot,
				"shows": darkner,
			})
		return PendingChoice.new(index, "Choose a new Battling Darkner", options, PendingChoice.RESUME_PROMOTE, {})
	return null


## Moves the Darkner at a Field slot into the Battle Zone of the player whose promotion is next.
func promote(index: int, slot: int) -> void:
	var side := _players[index]
	side.active = side.bench.pop_at(slot) as CardInPlay
	_promotion_queue.erase(index)
	_log("Player %d promotes %s" % [index + 1, side.active.card.name])


## Mercy Cards taken for knocking out this Darkner. Effects that change it will be read here
## once the continuous-effects layer exists.
func _prizes_for_knockout(rules: MatchRules, _knocked_out: CardInPlay) -> int:
	return rules.prizes_per_knockout


func _log(text: String) -> void:
	_events.append(text)