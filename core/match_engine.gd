class_name MatchEngine
extends RefCounted

const HAND_SIZE := 7
const BENCH_LIMIT := 5
const MAX_SETUP_ATTEMPTS := 50
const NO_WINNER := -1

var players: Array[PlayerState] = []
var current_index: int = 0
var turn: int = 0
var winner: int = NO_WINNER
var events: Array[String] = []

var _rng: Rng


## Prize counts are parameters, never constants: the run supplies the NPC value.
func start(deck_a: Array[CardData], deck_b: Array[CardData], prize_count_a: int, prize_count_b: int, rng: Rng) -> void:
	_rng = rng
	players.clear()
	events.clear()
	winner = NO_WINNER
	turn = 0
	players.append(_setup_player(0, deck_a, prize_count_a))
	players.append(_setup_player(1, deck_b, prize_count_b))
	# _begin_turn switches the active player first, so player 1 (index 0) opens.
	current_index = 1
	_begin_turn()


func is_over() -> bool:
	return winner != NO_WINNER


func current_player() -> PlayerState:
	return players[current_index]


func opponent_player() -> PlayerState:
	return players[_opponent_index()]


func legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_over():
		return actions

	var player := current_player()
	var opponent := opponent_player()

	for hand_index in player.hand.size():
		var card := player.hand[hand_index]
		if card.is_pokemon() and player.bench.size() < BENCH_LIMIT:
			actions.append({
				"type": "bench",
				"hand_index": hand_index,
				"label": "Bench %s" % card.name,
			})
		elif card.is_energy() and not player.energy_attached_this_turn:
			if player.active != null:
				actions.append({
					"type": "attach",
					"hand_index": hand_index,
					"slot": -1,
					"label": "Attach %s to %s (active)" % [card.name, player.active.card.name],
				})
			for slot in player.bench.size():
				actions.append({
					"type": "attach",
					"hand_index": hand_index,
					"slot": slot,
					"label": "Attach %s to %s (bench %d)" % [card.name, player.bench[slot].card.name, slot + 1],
				})

	if player.active != null and not player.retreated_this_turn and player.active.can_pay(player.active.retreat_cost()):
		for slot in player.bench.size():
			actions.append({
				"type": "retreat",
				"slot": slot,
				"label": "Retreat %s for %s" % [player.active.card.name, player.bench[slot].card.name],
			})

	if player.active != null and opponent.active != null:
		var attacks := player.active.card.attacks
		for attack_index in attacks.size():
			var attack := attacks[attack_index]
			if player.active.can_pay(attack.cost):
				actions.append({
					"type": "attack",
					"attack_index": attack_index,
					"label": "Attack: %s (%d)" % [attack.name, attack.damage],
				})

	actions.append({"type": "end_turn", "label": "End turn"})
	return actions


func apply(action: Dictionary) -> void:
	if not legal_actions().has(action):
		push_error("MatchEngine: illegal action %s" % action)
		return

	match str(action["type"]):
		"bench":
			_do_bench(int(action["hand_index"]))
		"attach":
			_do_attach(int(action["hand_index"]), int(action["slot"]))
		"retreat":
			_do_retreat(int(action["slot"]))
		"attack":
			_do_attack(int(action["attack_index"]))
		"end_turn":
			_log("Player %d ends the turn" % (current_index + 1))
			_begin_turn()


func _setup_player(index: int, deck: Array[CardData], prize_count: int) -> PlayerState:
	var player := PlayerState.new()
	player.deck = deck

	for attempt in MAX_SETUP_ATTEMPTS:
		_rng.shuffle(player.deck)
		for _i in HAND_SIZE:
			player.draw_card()
		if player.first_pokemon_in_hand() != -1:
			break
		# Known divergence (4.8): the opponent gets nothing for a mulligan.
		_log("Player %d mulligan (attempt %d)" % [index + 1, attempt + 1])
		player.deck.append_array(player.hand)
		player.hand.clear()

	var pokemon_index := player.first_pokemon_in_hand()
	if pokemon_index == -1:
		push_error("MatchEngine: player %d has no Pokemon after %d attempts" % [index + 1, MAX_SETUP_ATTEMPTS])
	else:
		# Known divergence (4.8): the first Pokemon in hand is chosen automatically.
		var starter := player.hand.pop_at(pokemon_index) as CardData
		player.active = CardInPlay.new(starter, 0)

	for _i in prize_count:
		if player.deck.is_empty():
			break
		player.prizes.append(player.deck.pop_back() as CardData)

	return player


func _begin_turn() -> void:
	current_index = _opponent_index()
	turn += 1
	var player := current_player()
	player.reset_turn_flags()
	_log("--- Turn %d: Player %d ---" % [turn, current_index + 1])

	# Project rule (4.7): deck-out costs a prize instead of losing.
	if player.deck.is_empty():
		_log("Player %d cannot draw: the opponent takes a prize" % (current_index + 1))
		_take_prize(_opponent_index())
		return

	player.draw_card()


func _do_bench(hand_index: int) -> void:
	var player := current_player()
	var card := player.hand.pop_at(hand_index) as CardData
	player.bench.append(CardInPlay.new(card, turn))
	_log("Player %d benches %s" % [current_index + 1, card.name])


func _do_attach(hand_index: int, slot: int) -> void:
	var player := current_player()
	var energy := player.hand.pop_at(hand_index) as CardData
	var target: CardInPlay = player.active if slot == -1 else player.bench[slot]
	target.attached_energy.append(energy)
	player.energy_attached_this_turn = true
	_log("Player %d attaches %s to %s" % [current_index + 1, energy.name, target.card.name])


func _do_retreat(slot: int) -> void:
	var player := current_player()
	var retreating := player.active
	var paid := retreating.detach_last_energy(retreating.card.retreat_cost)
	player.discard.append_array(paid)
	player.active = player.bench[slot]
	player.bench[slot] = retreating
	player.retreated_this_turn = true
	_log("Player %d retreats %s for %s" % [current_index + 1, retreating.card.name, player.active.card.name])


func _do_attack(attack_index: int) -> void:
	var attacker := current_player()
	var defender := opponent_player()
	var attack := attacker.active.card.attacks[attack_index]
	var dealt := _apply_modifiers(attacker.active.card, defender.active.card, attack.damage)
	defender.active.damage += dealt
	_log("%s uses %s: %d damage to %s (%d/%d HP)" % [
		attacker.active.card.name, attack.name, dealt, defender.active.card.name,
		defender.active.remaining_hp(), defender.active.card.hp,
	])

	if defender.active.is_knocked_out():
		_knock_out(_opponent_index())

	# Attacking passes priority.
	if not is_over():
		_begin_turn()


func _apply_modifiers(attacker: CardData, defender: CardData, base_damage: int) -> int:
	if base_damage <= 0:
		return 0
	var result := base_damage
	# Weakness before Resistance, each applied once.
	if defender.weakness_modifier == "x2" and _shares_type(attacker.types, defender.weakness_types):
		result *= 2
	if defender.resistance_modifier == "-30" and _shares_type(attacker.types, defender.resistance_types):
		result = maxi(result - 30, 0)
	return result


func _shares_type(attacker_types: Array[String], target_types: Array[String]) -> bool:
	for attacker_type in attacker_types:
		if target_types.has(attacker_type):
			return true
	return false


func _knock_out(defender_index: int) -> void:
	var defender := players[defender_index]
	var attacker_index := 1 - defender_index
	var knocked_out := defender.active
	defender.discard_from_play(knocked_out)
	defender.active = null
	_log("%s is knocked out" % knocked_out.card.name)

	_take_prize(attacker_index)
	if is_over():
		return

	if defender.bench.is_empty():
		winner = attacker_index
		_log("Player %d has no Pokemon in play. Player %d wins" % [defender_index + 1, attacker_index + 1])
		return

	# Known divergence (4.8): bench[0] is promoted automatically.
	defender.active = defender.bench.pop_at(0) as CardInPlay
	_log("Player %d promotes %s" % [defender_index + 1, defender.active.card.name])


func _take_prize(taker_index: int) -> void:
	var taker := players[taker_index]
	if taker.prizes.is_empty():
		return
	taker.hand.append(taker.prizes.pop_back() as CardData)
	_log("Player %d takes a prize (%d left)" % [taker_index + 1, taker.prizes.size()])
	if taker.prizes.is_empty():
		winner = taker_index
		_log("Player %d took the last prize and wins" % (taker_index + 1))


func _opponent_index() -> int:
	return 1 - current_index


func _log(text: String) -> void:
	events.append(text)
