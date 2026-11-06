class_name MatchSetup
extends RefCounted
## The setup of one round (Design Document 4.1): dealing with mulligans, the Mercy Cards, the
## coin call, the Battling Darkner, the Field, and draws for the opponent's extra mulligans.
##
## Owned by MatchEngine and called only by it, so it counts as part of the engine: it changes
## only the players and the log the engine hands it. It keeps no reference to the engine.

const MAX_ATTEMPTS := 50

## The player who takes the first turn. Final once advance() returns null.
var first_player: int = 0

var _players: Array[PlayerState]
var _rules: MatchRules
var _rng: Rng
var _log: MatchLog
## Remaining steps, in order: {"player": int, "step": "coin_call" | "active" | "bench" | "compensation", ...}
var _steps: Array[Dictionary] = []


func _init(players: Array[PlayerState], rules: MatchRules, rng: Rng, match_log: MatchLog) -> void:
	_players = players
	_rules = rules
	_rng = rng
	_log = match_log


## Deals both players from their decks and lays out the steps that will need answers.
func deal(deck_a: Array[CardData], deck_b: Array[CardData]) -> void:
	_players.append(_deal_player(0, deck_a))
	_players.append(_deal_player(1, deck_b))

	# Setup follows the rulebook: each player places an Active Pokemon and may bench Basic
	# Pokemon; then the player who took fewer mulligans may draw one card for each extra
	# mulligan the opponent took, and may bench any Basic Pokemon drawn that way.
	if _rules.random_first_player:
		var caller := 0 if _rng.coin_flip() else 1
		_steps.append({"player": caller, "step": "coin_call"})
	for index in 2:
		_steps.append({"player": index, "step": "active"})
		_steps.append({"player": index, "step": "bench"})
	var extra := _players[0].mulligans - _players[1].mulligans
	if extra != 0:
		_steps.append({"player": 1 if extra > 0 else 0, "step": "compensation", "count": absi(extra)})


## Runs the steps until one needs a choice, and returns it; null when the setup is done.
## Copies of the same card are one option. Placing the Active Pokemon always asks, even with a
## single option, so the player sees it happen (Design Document 4.1); benching and mulligan
## draws ask while there is something to decide.
func advance() -> PendingChoice:
	while not _steps.is_empty():
		var step := _steps[0]
		var index := int(step["player"])
		var player := _players[index]
		match str(step["step"]):
			"coin_call":
				return _ask(index, PendingChoice.KIND_COIN_CALL, {}, [{"value": true}, {"value": false}])
			"active":
				var options := _basic_options(player.hand)
				if options.is_empty():
					_steps.pop_front()
					continue
				return _ask(index, PendingChoice.KIND_BATTLING_DARKNER, {}, options)
			"bench":
				var allowed: Array[CardData] = player.hand
				if step.has("cards"):
					allowed = []
					for card: Variant in step["cards"] as Array:
						if player.hand.has(card):
							allowed.append(card as CardData)
				var options := _basic_options(allowed)
				if options.is_empty() or player.bench.size() >= _rules.bench_limit:
					_steps.pop_front()
					continue
				options.append({"value": null})
				return _ask(index, PendingChoice.KIND_SETUP_BENCH, {}, options)
			"compensation":
				var count := int(step["count"])
				var options: Array = []
				for amount in range(count, -1, -1):
					options.append({"value": amount})
				return _ask(index, PendingChoice.KIND_MULLIGAN_DRAWS, {"maximum": count}, options)
	return null


## Applies the answer to the open step, then runs on like advance().
func answer(value: Variant) -> PendingChoice:
	var step := _steps[0]
	var index := int(step["player"])
	var player := _players[index]
	match str(step["step"]):
		"coin_call":
			_steps.pop_front()
			var heads := _rng.coin_flip()
			var called_heads := bool(value)
			first_player = index if called_heads == heads else 1 - index
			_log.add(MatchEvent.FIRST_PLAYER, index, {"caller": index, "called_heads": called_heads, "heads": heads, "first": first_player})
		"active":
			_place_active(index, value as CardData)
			_steps.pop_front()
		"bench":
			if value == null:
				_steps.pop_front()
			else:
				var card := value as CardData
				player.hand.erase(card)
				var placed := CardInPlay.new(card, 0)
				player.bench.append(placed)
				_log.add(MatchEvent.SETUP_BENCH_PLACED, index, {"darkner": _log.darkner(placed)})
		"compensation":
			_steps.pop_front()
			var drawn: Array[CardData] = []
			for _i in int(value):
				if not player.draw_card():
					break
				drawn.append(player.hand.back())
			_log.add_private(MatchEvent.MULLIGAN_DRAWS, index, {"count": drawn.size(), "cards": MatchLog.ids(drawn)}, {"count": drawn.size()})
			if not drawn.is_empty():
				_steps.push_front({"player": index, "step": "bench", "cards": drawn})
	return advance()


func _deal_player(index: int, deck: Array[CardData]) -> PlayerState:
	var player := PlayerState.new()
	player.deck = deck
	player.tp = _rules.tp_start

	for attempt in MAX_ATTEMPTS:
		_rng.shuffle(player.deck)
		for _i in _rules.hand_size:
			player.draw_card()
		if player.first_basic_pokemon_in_hand() != -1:
			break
		player.mulligans += 1
		_log.add(MatchEvent.MULLIGAN, index, {"attempt": attempt + 1})
		player.deck.append_array(player.hand)
		player.hand.clear()

	if player.first_basic_pokemon_in_hand() == -1:
		push_error("MatchSetup: player %d has no Basic Pokemon after %d attempts" % [index + 1, MAX_ATTEMPTS])

	# Prizes come off the deck, so dealing them before the Active Pokemon is chosen from the
	# hand changes nothing.
	for _i in _rules.prize_count:
		if player.deck.is_empty():
			break
		player.prizes.append(player.deck.pop_back() as CardData)

	return player


func _basic_options(cards: Array[CardData]) -> Array:
	var options: Array = []
	var offered: Array[String] = []
	for card in cards:
		if card.is_basic_pokemon() and not offered.has(card.id):
			offered.append(card.id)
			options.append({"value": card})
	return options


func _ask(index: int, kind: String, details: Dictionary, options: Array) -> PendingChoice:
	return PendingChoice.new(index, kind, details, options, PendingChoice.RESUME_SETUP, {})


func _place_active(index: int, card: CardData) -> void:
	var player := _players[index]
	player.hand.erase(card)
	player.active = CardInPlay.new(card, 0)
	_log.add(MatchEvent.BATTLING_DARKNER_PLACED, index, {"darkner": _log.darkner(player.active)})