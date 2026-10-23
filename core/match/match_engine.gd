class_name MatchEngine
extends RefCounted

const MAX_SETUP_ATTEMPTS := 50
const NO_WINNER := -1
## Both players won at the same time and in the same number of ways: play Sudden Death.
const SUDDEN_DEATH := -2

var players: Array[PlayerState] = []
var current_index: int = 0
var turn: int = 0
var winner: int = NO_WINNER
var events: Array[String] = []
## The rules of the round being played. Set by start().
var rules: MatchRules
## Card effects (Design Document 7). Null means every attack resolves as its printed damage.
var effects: EffectLibrary = null

var _rng: Rng
## The open question, or null: the coin call, an Active Pokemon or the bench at setup, a
## promotion after a knockout, which Energy pays a retreat, or an effect's choice (7.6).
var _pending: PendingChoice = null
## Remaining setup steps, in order: {"player": int, "step": "coin_call" | "active" | "bench" | "compensation", ...}
var _setup_steps: Array[Dictionary] = []
var _mulligans: Array[int] = [0, 0]
var _first_player: int = 0
var _promotion_queue: Array[int] = []
var _turn_ends_after_promotions: bool = false

## Every round rule comes from match_rules (MatchRules), never from constants.
func start(deck_a: Array[CardData], deck_b: Array[CardData], match_rules: MatchRules, rng: Rng) -> void:
	rules = match_rules
	_rng = rng
	players.clear()
	events.clear()
	winner = NO_WINNER
	turn = 0
	_pending = null
	_promotion_queue.clear()
	_turn_ends_after_promotions = false
	_mulligans = [0, 0]
	_first_player = 0
	players.append(_setup_player(0, deck_a, rules.prize_count))
	players.append(_setup_player(1, deck_b, rules.prize_count))

	# Setup follows the rulebook: each player places an Active Pokemon and may bench Basic
	# Pokemon; then the player who took fewer mulligans may draw one card for each extra
	# mulligan the opponent took, and may bench any Basic Pokemon drawn that way.
	_setup_steps.clear()
	if rules.random_first_player:
		var caller := 0 if _rng.coin_flip() else 1
		_setup_steps.append({"player": caller, "step": "coin_call"})
	for index in 2:
		_setup_steps.append({"player": index, "step": "active"})
		_setup_steps.append({"player": index, "step": "bench"})
	var extra := _mulligans[0] - _mulligans[1]
	if extra != 0:
		_setup_steps.append({"player": 1 if extra > 0 else 0, "step": "compensation", "count": absi(extra)})
	_advance_setup()


func is_over() -> bool:
	return winner != NO_WINNER


func current_player() -> PlayerState:
	return players[current_index]


func opponent_player() -> PlayerState:
	return players[_opponent_index()]


func is_waiting_for_choice() -> bool:
	return _pending != null


## The question being asked, or an empty string.
func choice_prompt() -> String:
	return "" if _pending == null else _pending.prompt


## The player who must answer the open choice, or -1.
func choice_chooser() -> int:
	return -1 if _pending == null else _pending.chooser


func legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_over():
		return actions

	# While a choice is open, answering it is the only legal action.
	if _pending != null:
		for index in _pending.options.size():
			actions.append({
				"type": "choose",
				"option": index,
				"label": str(_pending.option(index)["label"]),
			})
		return actions

	var player := current_player()
	var opponent := opponent_player()

	# Copies of the same card are interchangeable: one set of actions per distinct card.
	var offered := {}
	for hand_index in player.hand.size():
		var card := player.hand[hand_index]
		if offered.has(card.id):
			continue
		offered[card.id] = true
		if card.is_basic_pokemon() and player.bench.size() < rules.bench_limit:
			actions.append({
				"type": "bench",
				"hand_index": hand_index,
				"label": "Put %s on the Field" % card.name,
			})
		elif card.is_energy() and not player.energy_attached_this_turn:
			for slot in range(-1, player.bench.size()):
				var target := _in_play_at(player, slot)
				if target == null:
					continue
				actions.append({
					"type": "attach",
					"hand_index": hand_index,
					"slot": slot,
					"label": "Attach %s to %s (%s)" % [card.name, target.card.name, _slot_name(slot)],
				})

	var offered_evolutions := {}
	for hand_index in player.hand.size():
		var evolution := player.hand[hand_index]
		if not _is_evolution_card(evolution) or offered_evolutions.has(evolution.id):
			continue
		offered_evolutions[evolution.id] = true
		for slot in range(-1, player.bench.size()):
			var target := _in_play_at(player, slot)
			if target != null and can_evolve(player, target, evolution):
				actions.append({
					"type": "evolve",
					"hand_index": hand_index,
					"slot": slot,
					"label": "Evolve %s into %s (%s)" % [target.card.name, evolution.name, _slot_name(slot)],
				})

	if player.active != null and not player.retreated_this_turn and player.active.can_pay(player.active.retreat_cost()):
		for slot in player.bench.size():
			actions.append({
				"type": "retreat",
				"slot": slot,
				"label": "Flee %s for %s (%s)" % [player.active.card.name, player.bench[slot].card.name, _slot_name(slot)],
			})

	if player.active != null and opponent.active != null and _attacks_allowed():
		var attacks := player.active.card.attacks
		for attack_index in attacks.size():
			var attack := attacks[attack_index]
			if player.active.can_pay(attack.cost) and _attack_requirements_met(attack):
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
		"evolve":
			_do_evolve(int(action["hand_index"]), int(action["slot"]))
		"retreat":
			_do_retreat(int(action["slot"]))
		"attack":
			_do_attack(int(action["attack_index"]))
		"end_turn":
			_end_turn(false)
		"choose":
			_do_choose(int(action["option"]))


func _setup_player(index: int, deck: Array[CardData], prize_count: int) -> PlayerState:
	var player := PlayerState.new()
	player.deck = deck

	for attempt in MAX_SETUP_ATTEMPTS:
		_rng.shuffle(player.deck)
		for _i in rules.hand_size:
			player.draw_card()
		if player.first_basic_pokemon_in_hand() != -1:
			break
		_mulligans[index] += 1
		_log("Player %d mulligan (attempt %d)" % [index + 1, attempt + 1])
		player.deck.append_array(player.hand)
		player.hand.clear()

	if player.first_basic_pokemon_in_hand() == -1:
		push_error("MatchEngine: player %d has no Basic Pokemon after %d attempts" % [index + 1, MAX_SETUP_ATTEMPTS])

	# Prizes come off the deck, so dealing them before the Active Pokemon is chosen from the
	# hand changes nothing.
	for _i in prize_count:
		if player.deck.is_empty():
			break
		player.prizes.append(player.deck.pop_back() as CardData)

	return player


## Runs the setup steps until one needs a choice. Copies of the same card are one option.
## Placing the Active Pokemon asks only when there is more than one option; benching and
## mulligan draws are optional, so they always ask while there is something to decide.
func _advance_setup() -> void:
	while not _setup_steps.is_empty():
		var step := _setup_steps[0]
		var index := int(step["player"])
		var player := players[index]
		match str(step["step"]):
			"coin_call":
				_ask_setup(index, "Call the coin flip: whoever wins goes first", [
					{"label": "Heads", "value": true},
					{"label": "Tails", "value": false},
				])
				return
			"active":
				var options := _basic_options(player.hand, "Make %s the Battling Darkner")
				if options.size() <= 1:
					if options.size() == 1:
						_place_active(index, (options[0] as Dictionary)["value"] as CardData)
					_setup_steps.pop_front()
					continue
				_ask_setup(index, "Choose your Battling Darkner", options)
				return
			"bench":
				var allowed: Array[CardData] = player.hand
				if step.has("cards"):
					allowed = []
					for card: Variant in step["cards"] as Array:
						if player.hand.has(card):
							allowed.append(card as CardData)
				var options := _basic_options(allowed, "Put %s on the Field")
				if options.is_empty() or player.bench.size() >= rules.bench_limit:
					_setup_steps.pop_front()
					continue
				options.append({"label": "Finish placing Darkners", "value": null})
				_ask_setup(index, "Put Basic Darkners on the Field before the game starts", options)
				return
			"compensation":
				var count := int(step["count"])
				var options: Array = []
				for amount in range(count, -1, -1):
					options.append({"label": "Draw %d card%s for the opponent's mulligans" % [amount, "" if amount == 1 else "s"], "value": amount})
				_ask_setup(index, "Your opponent took %d more mulligan%s" % [count, "" if count == 1 else "s"], options)
				return

	# _begin_turn switches the current player first, so start from the other one.
	current_index = 1 - _first_player
	_begin_turn()


func _answer_setup(value: Variant) -> void:
	var step := _setup_steps[0]
	var index := int(step["player"])
	var player := players[index]
	match str(step["step"]):
		"coin_call":
			_setup_steps.pop_front()
			var heads := _rng.coin_flip()
			var called_heads := bool(value)
			_first_player = index if called_heads == heads else 1 - index
			_log("Player %d calls %s. Coin flip: %s. Player %d goes first" % [
				index + 1, "heads" if called_heads else "tails", "heads" if heads else "tails", _first_player + 1,
			])
		"active":
			_place_active(index, value as CardData)
			_setup_steps.pop_front()
		"bench":
			if value == null:
				_setup_steps.pop_front()
			else:
				var card := value as CardData
				player.hand.erase(card)
				player.bench.append(CardInPlay.new(card, 0))
				_log("Player %d puts %s on the Field during setup" % [index + 1, card.name])
		"compensation":
			_setup_steps.pop_front()
			var drawn: Array[CardData] = []
			for _i in int(value):
				if not player.draw_card():
					break
				drawn.append(player.hand.back())
			_log("Player %d draws %d card%s for mulligans" % [index + 1, drawn.size(), "" if drawn.size() == 1 else "s"])
			if not drawn.is_empty():
				_setup_steps.push_front({"player": index, "step": "bench", "cards": drawn})
	_advance_setup()


func _basic_options(cards: Array[CardData], label_format: String) -> Array:
	var options: Array = []
	var offered: Array[String] = []
	for card in cards:
		if card.is_basic_pokemon() and not offered.has(card.id):
			offered.append(card.id)
			options.append({"label": label_format % card.name, "value": card})
	return options


func _ask_setup(index: int, prompt: String, options: Array) -> void:
	_pending = PendingChoice.new(index, prompt, options, PendingChoice.RESUME_SETUP, {})


func _place_active(index: int, card: CardData) -> void:
	var player := players[index]
	player.hand.erase(card)
	player.active = CardInPlay.new(card, 0)
	_log("Player %d starts with %s" % [index + 1, card.name])

## The only way a turn ends: the player ends it without attacking (passing), or attacks and
## every knocked out Darkner has been replaced. What happens at the end of every turn goes
## here, such as TP recovery (Design Document 5). Then the opponent's turn begins.
func _end_turn(attacked: bool) -> void:
	if not attacked:
		_log("Player %d ends the turn" % (current_index + 1))
	_begin_turn()


## Starts the next player's turn. Called by _end_turn() and once when setup finishes.
func _begin_turn() -> void:
	current_index = _opponent_index()
	turn += 1
	var player := current_player()
	player.reset_turn_flags()
	player.turns_started += 1
	_log("--- Turn %d: Player %d ---" % [turn, current_index + 1])

	if player.deck.is_empty():
		if rules.deck_out_loses:
			# Deltarune (Design Document 4.5): a player who cannot draw loses the round.
			winner = _opponent_index()
			_log("Player %d cannot draw and loses the round" % (current_index + 1))
			return
		# Legacy roguelite rule: deck-out costs a prize instead of losing.
		_log("Player %d cannot draw: the opponent takes a Mercy Card" % (current_index + 1))
		_take_prize(_opponent_index(), 1)
		if players[_opponent_index()].prizes.is_empty():
			winner = _opponent_index()
			_log("Player %d took the last Mercy Card and wins" % (winner + 1))
		return

	player.draw_card()


func _do_bench(hand_index: int) -> void:
	var player := current_player()
	var card := player.hand.pop_at(hand_index) as CardData
	player.bench.append(CardInPlay.new(card, turn))
	_log("Player %d puts %s on the Field" % [current_index + 1, card.name])


## Evolution rules (5.1): the card evolves from the target's name, one stage at a time;
## the target has been in play since before this turn; and it is not the player's first turn.
func can_evolve(player: PlayerState, target: CardInPlay, evolution: CardData) -> bool:
	if not _is_evolution_card(evolution) or evolution.evolve_from != target.card.name:
		return false
	var expected_stage := "Stage1" if target.card.stage == CardData.STAGE_BASIC else "Stage2" if target.card.stage == "Stage1" else ""
	if evolution.stage != expected_stage:
		return false
	return player.turns_started > 1 and target.turn_played < turn


func _is_evolution_card(card: CardData) -> bool:
	return card.is_pokemon() and not card.is_basic_pokemon() and not card.evolve_from.is_empty()


func _do_evolve(hand_index: int, slot: int) -> void:
	var player := current_player()
	var evolution := player.hand.pop_at(hand_index) as CardData
	var target := _in_play_at(player, slot)
	var previous := target.card.name
	target.evolve(evolution, turn)
	_log("Player %d evolves %s into %s" % [current_index + 1, previous, evolution.name])


func _do_attach(hand_index: int, slot: int) -> void:
	var player := current_player()
	var energy := player.hand.pop_at(hand_index) as CardData
	var target := _in_play_at(player, slot)
	target.attached_energy.append(energy)
	player.energy_attached_this_turn = true
	_log("Player %d attaches %s to %s" % [current_index + 1, energy.name, target.card.name])


func _do_retreat(slot: int) -> void:
	var retreating := current_player().active
	var options := EnergyPayment.discard_options(retreating.attached_energy, retreating.card.retreat_cost)
	if options.size() <= 1:
		var payment: Array = [] if options.is_empty() else (options[0] as Dictionary)["value"] as Array
		_complete_retreat(slot, payment)
		return
	_pending = PendingChoice.new(current_index, "Choose the Energy to discard to flee %s" % retreating.card.name,
			options, PendingChoice.RESUME_RETREAT, {"slot": slot})


func _complete_retreat(slot: int, payment: Array) -> void:
	var player := current_player()
	var retreating := player.active
	for energy: Variant in payment:
		retreating.attached_energy.erase(energy)
		player.discard.append(energy as CardData)
	player.active = player.bench[slot]
	player.bench[slot] = retreating
	player.retreated_this_turn = true
	_log("Player %d retreats %s for %s" % [current_index + 1, retreating.card.name, player.active.card.name])


func _do_attack(attack_index: int) -> void:
	var attacker := current_player()
	var attack := attacker.active.card.attacks[attack_index]
	_log("%s uses %s" % [attacker.active.card.name, attack.name])

	var context := _attack_context(attack)
	var binding := _attack_binding(attack)
	if binding.is_empty():
		if attack.has_effect():
			# Known divergence (4.8): without a card effect entry only the printed number is dealt.
			_log("  [effect not implemented]")
		deal_attack_damage(context, attack.damage)
		_finish_attack()
		return

	var resolver := EffectResolver.new(effects, context)
	if resolver.run(str(binding["function"]), binding["args"] as Dictionary):
		_finish_attack()
	else:
		_pending = _effect_choice(resolver, context)


## Wraps the question a suspended effect is asking. The effect names who answers.
func _effect_choice(resolver: EffectResolver, context: EffectContext) -> PendingChoice:
	var asked := context.choice
	var choice := PendingChoice.new(players.find(asked["chooser"]), str(asked["prompt"]),
			asked["options"] as Array, PendingChoice.RESUME_EFFECT, {})
	choice.resolver = resolver
	choice.context = context
	return choice


func _do_choose(option: int) -> void:
	var choice := _pending
	_pending = null
	var picked := choice.option(option)
	_log("  Player %d chooses: %s" % [choice.chooser + 1, picked["label"]])

	match choice.resume:
		PendingChoice.RESUME_EFFECT:
			choice.context.selection.append(picked["value"])
			if choice.resolver.resume():
				_finish_attack()
			else:
				_pending = _effect_choice(choice.resolver, choice.context)
		PendingChoice.RESUME_SETUP:
			_answer_setup(picked["value"])
		PendingChoice.RESUME_PROMOTE:
			_promote(choice.chooser, int(picked["value"]))
			_promotion_queue.pop_front()
			if _advance_promotions() and _turn_ends_after_promotions:
				_turn_ends_after_promotions = false
				_end_turn(true)
		PendingChoice.RESUME_RETREAT:
			_complete_retreat(int(choice.data["slot"]), picked["value"] as Array)


func _finish_attack() -> void:
	_resolve_knockouts()
	if is_over():
		return
	# Attacking passes priority, once every knocked out Pokemon has been replaced.
	if _advance_promotions():
		_end_turn(true)
	else:
		_turn_ends_after_promotions = true


## Each player whose Active Pokemon was knocked out chooses a replacement from the bench,
## the defending player first. A bench of one is promoted without asking.
func _advance_promotions() -> bool:
	while not _promotion_queue.is_empty():
		var index := _promotion_queue[0]
		var side := players[index]
		if side.bench.size() == 1:
			_promote(index, 0)
			_promotion_queue.pop_front()
			continue
		var options: Array = []
		for slot in side.bench.size():
			var pokemon := side.bench[slot]
			options.append({
				"label": "Promote %s (%s, %d/%d HP)" % [pokemon.card.name, _slot_name(slot), pokemon.remaining_hp(), pokemon.card.hp],
				"value": slot,
			})
		_pending = PendingChoice.new(index, "Choose a new Battling Darkner", options, PendingChoice.RESUME_PROMOTE, {})
		return false
	return true


func _promote(index: int, slot: int) -> void:
	var side := players[index]
	side.active = side.bench.pop_at(slot) as CardInPlay
	_log("Player %d promotes %s" % [index + 1, side.active.card.name])


# --- Mutations available to atomic effects ---------------------------------------------

## Deals attack damage to the defending Pokemon through the damage pipeline (4.5).
func deal_attack_damage(context: EffectContext, base_damage: int) -> int:
	var defender := context.defender
	if defender == null:
		return 0
	var dealt := Damage.apply_modifiers(context.source.card, defender.card, base_damage)
	defender.damage += dealt
	_log("  %d damage to %s (%d/%d HP)" % [dealt, defender.card.name, defender.remaining_hp(), defender.card.hp])
	return dealt


## Damage without Weakness or Resistance, such as an attacker damaging itself.
func deal_direct_damage(target: CardInPlay, amount: int) -> int:
	if amount <= 0:
		return 0
	target.damage += amount
	_log("  %s takes %d damage (%d/%d HP)" % [target.card.name, amount, target.remaining_hp(), target.card.hp])
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


func draw_cards(player: PlayerState, count: int) -> int:
	var drawn := 0
	for _i in maxi(count, 0):
		if not player.draw_card():
			break
		drawn += 1
	_log("  Player %d draws %d card%s" % [players.find(player) + 1, drawn, "" if drawn == 1 else "s"])
	return drawn


func flip_coin() -> bool:
	var heads := _rng.coin_flip()
	_log("  Coin flip: %s" % ("heads" if heads else "tails"))
	return heads


func owner_of(pokemon: CardInPlay) -> PlayerState:
	for player in players:
		if player.active == pokemon or player.bench.has(pokemon):
			return player
	return null


func log_event(text: String) -> void:
	_log(text)


# --- Attack resolution helpers ----------------------------------------------------------

func _attack_context(attack: AttackData) -> EffectContext:
	var context := EffectContext.new()
	context.engine = self
	context.kind = EffectContext.KIND_ATTACK
	context.source = current_player().active
	context.defender = opponent_player().active
	context.player = current_player()
	context.opponent = opponent_player()
	context.attack = attack
	return context


func _attack_binding(attack: AttackData) -> Dictionary:
	if effects == null:
		return {}
	return effects.binding_for(current_player().active.card.id, EffectLibrary.SECTION_ATTACKS, attack.name)

## Current standard rule (Design Document 4.2): the player going first cannot attack on
## their first turn. Turn 1 is always that turn, since start() resets the counter.
func _attacks_allowed() -> bool:
	return rules.first_player_can_attack or turn > 1

func _attack_requirements_met(attack: AttackData) -> bool:
	var binding := _attack_binding(attack)
	if binding.is_empty():
		return true
	var resolver := EffectResolver.new(effects, _attack_context(attack))
	return resolver.requirements_met(str(binding["function"]), binding["args"] as Dictionary)


## Resolves every Active Pokemon knocked out by the attack at once, as the rulebook does:
## all of them are discarded, every prize is taken, and only then are wins checked. A player
## wins by taking their last prize, or when an opponent has no Benched Pokemon to promote.
## If both win, the one who won in more ways is the winner; otherwise it is Sudden Death.
func _resolve_knockouts() -> void:
	var knocked_out: Array[int] = []
	for index: int in [_opponent_index(), current_index]:
		var side := players[index]
		if side.active != null and side.active.is_knocked_out():
			knocked_out.append(index)
	if knocked_out.is_empty():
		return

	var knocked_out_cards := {}
	for index in knocked_out:
		var side := players[index]
		knocked_out_cards[index] = side.active
		_log("%s is knocked out" % side.active.card.name)
		side.discard_from_play(side.active)
		side.active = null

	var ways := [0, 0]
	for index in knocked_out:
		var taker := 1 - index
		_take_prize(taker, _prizes_for_knockout(knocked_out_cards[index] as CardInPlay))
		if players[taker].prizes.is_empty():
			ways[taker] = maxi(int(ways[taker]), 1)
	for index in knocked_out:
		if players[index].bench.is_empty():
			ways[1 - index] = int(ways[1 - index]) + 1

	if int(ways[0]) > 0 or int(ways[1]) > 0:
		if int(ways[0]) == int(ways[1]):
			winner = SUDDEN_DEATH
			_log("Both players win at the same time: Sudden Death")
		else:
			winner = 0 if int(ways[0]) > int(ways[1]) else 1
			_log("Player %d wins" % (winner + 1))
		return

	_promotion_queue.assign(knocked_out)


## Moves count prizes from the taker's pile to their hand, stopping when the pile is empty.
func _take_prize(taker_index: int, count: int) -> void:
	var taker := players[taker_index]
	for _i in count:
		if taker.prizes.is_empty():
			return
		taker.hand.append(taker.prizes.pop_back() as CardData)
		_log("Player %d takes a Mercy Card (%d left)" % [taker_index + 1, taker.prizes.size()])


## Mercy Cards taken for knocking out this Darkner. Effects that
## change it will be read here once the continuous-effects layer exists.
func _prizes_for_knockout(_knocked_out: CardInPlay) -> int:
	return rules.prizes_per_knockout

## The Darkner at a slot: -1 is the Battle Zone, 0 and up are Field positions.
func _in_play_at(player: PlayerState, slot: int) -> CardInPlay:
	return player.active if slot == -1 else player.bench[slot]


func _slot_name(slot: int) -> String:
	return "Battle Zone" if slot == -1 else "Field %d" % (slot + 1)

func _opponent_index() -> int:
	return 1 - current_index


func _log(text: String) -> void:
	events.append(text)
