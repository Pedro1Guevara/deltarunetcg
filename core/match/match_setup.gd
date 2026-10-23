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
var _events: Array[String]
## Remaining steps, in order: {"player": int, "step": "coin_call" | "active" | "bench" | "compensation", ...}
var _steps: Array[Dictionary] = []


func _init(players: Array[PlayerState], rules: MatchRules, rng: Rng, events: Array[String]) -> void:
	_players = players
	_rules = rules
	_rng = rng
	_events = events


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
## Copies of the same card are one option. Placing the Active Pokemon asks only when there is
## more than one option; benching and mulligan draws are optional, so they always ask while
## there is something to decide.
func advance() -> PendingChoice:
	while not _steps.is_empty():
		var step := _steps[0]
		var index := int(step["player"])
		var player := _players[index]
		match str(step["step"]):
			"coin_call":
				return _ask(index, "Call the coin flip: whoever wins goes first", [
					{"label": "Heads", "value": true},
					{"label": "Tails", "value": false},
				])
			"active":
				var options := _basic_options(player.hand, "Make %s the Battling Darkner")
				if options.size() <= 1:
					if options.size() == 1:
						_place_active(index, (options[0] as Dictionary)["value"] as CardData)
					_steps.pop_front()
					continue
				return _ask(index, "Choose your Battling Darkner", options)
			"bench":
				var allowed: Array[CardData] = player.hand
				if step.has("cards"):
					allowed = []
					for card: Variant in step["cards"] as Array:
						if player.hand.has(card):
							allowed.append(card as CardData)
				var options := _basic_options(allowed, "Put %s on the Field")
				if options.is_empty() or player.bench.size() >= _rules.bench_limit:
					_steps.pop_front()
					continue
				options.append({"label": "Finish placing Darkners", "value": null})
				return _ask(index, "Put Basic Darkners on the Field before the game starts", options)
			"compensation":
				var count := int(step["count"])
				var options: Array = []
				for amount in range(count, -1, -1):
					options.append({"label": "Draw %d card%s for the opponent's mulligans" % [amount, "" if amount == 1 else "s"], "value": amount})
				return _ask(index, "Your opponent took %d more mulligan%s" % [count, "" if count == 1 else "s"], options)
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
			_log("Player %d calls %s. Coin flip: %s. Player %d goes first" % [
				index + 1, "heads" if called_heads else "tails", "heads" if heads else "tails", first_player + 1,
			])
		"active":
			_place_active(index, value as CardData)
			_steps.pop_front()
		"bench":
			if value == null:
				_steps.pop_front()
			else:
				var card := value as CardData
				player.hand.erase(card)
				player.bench.append(CardInPlay.new(card, 0))
				_log("Player %d puts %s on the Field during setup" % [index + 1, card.name])
		"compensation":
			_steps.pop_front()
			var drawn: Array[CardData] = []
			for _i in int(value):
				if not player.draw_card():
					break
				drawn.append(player.hand.back())
			_log("Player %d draws %d card%s for mulligans" % [index + 1, drawn.size(), "" if drawn.size() == 1 else "s"])
			if not drawn.is_empty():
				_steps.push_front({"player": index, "step": "bench", "cards": drawn})
	return advance()


func _deal_player(index: int, deck: Array[CardData]) -> PlayerState:
	var player := PlayerState.new()
	player.deck = deck

	for attempt in MAX_ATTEMPTS:
		_rng.shuffle(player.deck)
		for _i in _rules.hand_size:
			player.draw_card()
		if player.first_basic_pokemon_in_hand() != -1:
			break
		player.mulligans += 1
		_log("Player %d mulligan (attempt %d)" % [index + 1, attempt + 1])
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


func _basic_options(cards: Array[CardData], label_format: String) -> Array:
	var options: Array = []
	var offered: Array[String] = []
	for card in cards:
		if card.is_basic_pokemon() and not offered.has(card.id):
			offered.append(card.id)
			options.append({"label": label_format % card.name, "value": card})
	return options


func _ask(index: int, prompt: String, options: Array) -> PendingChoice:
	return PendingChoice.new(index, prompt, options, PendingChoice.RESUME_SETUP, {})


func _place_active(index: int, card: CardData) -> void:
	var player := _players[index]
	player.hand.erase(card)
	player.active = CardInPlay.new(card, 0)
	_log("Player %d starts with %s" % [index + 1, card.name])


func _log(text: String) -> void:
	_events.append(text)