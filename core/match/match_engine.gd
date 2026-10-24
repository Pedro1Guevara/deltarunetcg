class_name MatchEngine
extends RefCounted

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
## Null means every attack resolves as its printed damage.
var effects: EffectLibrary = null

## The Area in play, or null. One slot shared by both players (Design Document 4.0).
var stadium: CardData = null
## The player who put the Area into play, or -1. It goes to their discard pile when replaced.
var stadium_owner: int = -1
## The Trainer card the current player is playing, or null. It sits beside the Battle Zone until
## its effect has resolved: it is in neither the hand nor the discard pile meanwhile.
var resolving_trainer: CardData = null

var _rng: Rng
## The open question, or null: the coin call, an Active Pokemon or the bench at setup, a
## promotion after a knockout, which Energy pays a retreat, or an effect's choice (7.6).
var _pending: PendingChoice = null
## The setup in progress, or null once the first turn has begun.
var _setup: MatchSetup = null
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
	stadium = null
	stadium_owner = -1
	resolving_trainer = null
	_pending = null
	_promotion_queue.clear()
	_turn_ends_after_promotions = false
	_setup = MatchSetup.new(players, rules, _rng, events)
	_setup.deal(deck_a, deck_b)
	_continue_setup(_setup.advance())


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
					"label": "Attach %s to %s (%s)" % [card.name, target.card.name, slot_name(slot)],
				})
		elif card.is_trainer() and _can_play_trainer(player, card):
			actions.append({
				"type": "play_trainer",
				"hand_index": hand_index,
				"label": _trainer_label(card),
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
					"label": "Evolve %s into %s (%s)" % [target.card.name, evolution.name, slot_name(slot)],
				})

	if player.active != null and not player.retreated_this_turn and player.active.can_pay(retreat_cost(player.active)):
		for slot in player.bench.size():
			actions.append({
				"type": "retreat",
				"slot": slot,
				"label": "Flee %s for %s (%s)" % [player.active.card.name, player.bench[slot].card.name, slot_name(slot)],
			})

	if player.active != null and opponent.active != null and _attacks_allowed():
		var attacks := player.active.card.attacks
		for attack_index in attacks.size():
			var attack := attacks[attack_index]
			if player.active.can_pay(attack_cost(player.active, attack)) and _attack_requirements_met(attack):
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
		"play_trainer":
			_do_play_trainer(int(action["hand_index"]))
		"retreat":
			_do_retreat(int(action["slot"]))
		"attack":
			_do_attack(int(action["attack_index"]))
		"end_turn":
			_end_turn(false)
		"choose":
			_do_choose(int(action["option"]))


## Opens the setup's next question, or starts the first turn when there is none left.
func _continue_setup(choice: PendingChoice) -> void:
	if choice != null:
		_pending = choice
		return
	var first := _setup.first_player
	_setup = null
	_begin_turn(first)

## The only way a turn ends: the player ends it without attacking (passing), or attacks and
## every knocked out Darkner has been replaced. What happens at the end of every turn goes
## here, such as TP recovery (Design Document 5). Then the opponent's turn begins.
func _end_turn(attacked: bool) -> void:
	var player := current_player()
	if not attacked:
		_log("Player %d ends the turn" % (current_index + 1))
	if rules.tp_max > 0:
		var before := player.tp
		player.tp = mini(player.tp + rules.tp_recovery, rules.tp_max) if attacked else rules.tp_max
		if player.tp != before:
			_log("Player %d recovers TP: %d%%" % [current_index + 1, player.tp * 25])
	_begin_turn(_opponent_index())


## Starts player_index's turn. Called by _end_turn() with the opponent, and once with the
## first player when the setup is done.
func _begin_turn(player_index: int) -> void:
	current_index = player_index
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


## Trainer cards are played freely; one Supporter per turn, never on the
## first player's first turn; one Stadium per turn, never one with the name of the Stadium in play;
## Spells while the player has the TP. A Trainer with no ACT subtype (legacy data) is not
## playable.
func _can_play_trainer(player: PlayerState, card: CardData) -> bool:
	var allowed := false
	match card.trainer_type:
		CardData.TRAINER_ITEM:
			allowed = true
		CardData.TRAINER_SUPPORTER:
			allowed = not player.supporter_played_this_turn and _supporters_allowed()
		CardData.TRAINER_STADIUM:
			allowed = not player.stadium_played_this_turn and (stadium == null or stadium.name != card.name)
		CardData.TRAINER_SPELL:
			allowed = player.tp >= spell_cost(card)
	# A card that is known to have no effect cannot be played.
	return allowed and _trainer_requirements_met(card)


## The player going first cannot play a Supporter
## on their first turn, which is always turn 1.
func _supporters_allowed() -> bool:
	return rules.first_player_can_play_supporter or turn > 1


func _trainer_label(card: CardData) -> String:
	match card.trainer_type:
		CardData.TRAINER_SUPPORTER:
			return "Play %s (Lightner)" % card.name
		CardData.TRAINER_STADIUM:
			return "Play %s (Area)" % card.name
		CardData.TRAINER_SPELL:
			return "Cast %s (%d%% TP)" % [card.name, spell_cost(card) * 25]
	return "Play %s (Item)" % card.name


## Plays a Trainer card from hand. An Stadium stays in the shared slot and sends the one it replaces
## to its owner's discard pile; every other Trainer card is discarded after it resolves. Effects
## are not resolved yet.
func _do_play_trainer(hand_index: int) -> void:
	var player := current_player()
	var card := player.hand.pop_at(hand_index) as CardData
	match card.trainer_type:
		CardData.TRAINER_SPELL:
			var cost := spell_cost(card)
			player.tp -= cost
			_log("Player %d casts %s for %d%% TP (%d%% left)" % [current_index + 1, card.name, cost * 25, player.tp * 25])
		CardData.TRAINER_SUPPORTER:
			player.supporter_played_this_turn = true
			_log("Player %d plays %s" % [current_index + 1, card.name])
		CardData.TRAINER_STADIUM:
			player.stadium_played_this_turn = true
			if stadium != null:
				players[stadium_owner].discard.append(stadium)
				_log("%s is discarded" % stadium.name)
			stadium = card
			stadium_owner = current_index
			_log("Player %d puts %s into play" % [current_index + 1, card.name])
		_:
			_log("Player %d plays %s" % [current_index + 1, card.name])
	_resolve_trainer(card)

## Resolves the effect bound to a Trainer card, then finishes the card. Resolution may stop for a
## choice; _finish_effect() finishes the card once it is answered.
func _resolve_trainer(card: CardData) -> void:
	resolving_trainer = card
	var binding := _trainer_binding(card)
	if binding.is_empty():
		_log("  [effect not implemented]")
		_finish_trainer(card)
		return
	var context := _trainer_context(card)
	var resolver := EffectResolver.new(effects, context)
	if resolver.run(str(binding["function"]), binding["args"] as Dictionary):
		_finish_trainer(card)
	else:
		_pending = _effect_choice(resolver, context)


## Once its effect has resolved, a Stadiumstays in the shared slot and every other Trainer card
## goes to the discard pile.
func _finish_trainer(card: CardData) -> void:
	resolving_trainer = null
	if card.trainer_type != CardData.TRAINER_STADIUM:
		current_player().discard.append(card)


func _do_retreat(slot: int) -> void:
	var retreating := current_player().active
	var options := EnergyPayment.discard_options(retreating.attached_energy, retreat_cost(retreating).size())
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

## Continues the turn once a suspended effect has finished resolving.
func _finish_effect(context: EffectContext) -> void:
	if context.kind == EffectContext.KIND_TRAINER:
		_finish_trainer(context.card)
	else:
		_finish_attack()

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
				_finish_effect(choice.context)
			else:
				_pending = _effect_choice(choice.resolver, choice.context)
		PendingChoice.RESUME_SETUP:
			_continue_setup(_setup.answer(picked["value"]))
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
				"label": "Promote %s (%s, %d/%d HP)" % [pokemon.card.name, slot_name(slot), pokemon.remaining_hp(), pokemon.card.hp],
				"value": slot,
			})
		_pending = PendingChoice.new(index, "Choose a new Battling Darkner", options, PendingChoice.RESUME_PROMOTE, {})
		return false
	return true


func _promote(index: int, slot: int) -> void:
	var side := players[index]
	side.active = side.bench.pop_at(slot) as CardInPlay
	_log("Player %d promotes %s" % [index + 1, side.active.card.name])

# --- Effective costs --------------------------------------------------------------------
# Legality reads these, never a printed cost (Design Document 5). Today each returns the
# printed cost; the continuous-effects layer will change them (Mewers Live, Cyber City,
# Showtime!).

## The Energy an attack costs this Darkner now.
func attack_cost(_attacker: CardInPlay, attack: AttackData) -> Array[String]:
	return attack.cost.duplicate()


## The Energy fleeing costs this Darkner now, one Colorless per unit.
func retreat_cost(pokemon: CardInPlay) -> Array[String]:
	var cost: Array[String] = []
	for _i in pokemon.card.retreat_cost:
		cost.append(CardTypes.COLORLESS)
	return cost


## The TP, in quarters, casting this Spell costs now.
func spell_cost(spell: CardData) -> int:
	return spell.tp_cost

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

## Swaps a player's Active Pokémon with the Pokémon at a Bench slot. It is not a Retreat: no
## cost is paid and the once-per-turn Retreat is still available.
func switch_in(player: PlayerState, slot: int) -> void:
	var leaving := player.active
	player.active = player.bench[slot]
	player.bench[slot] = leaving
	_log("  Player %d switches %s into the Battle Zone; %s goes to the Field" % [
		players.find(player) + 1, player.active.card.name, leaving.card.name,
	])


## Shuffles a player's hand into their deck. Returns how many cards the hand held.
func shuffle_hand_into_deck(player: PlayerState) -> int:
	var count := player.hand.size()
	player.deck.append_array(player.hand)
	player.hand.clear()
	_rng.shuffle(player.deck)
	_log("  Player %d shuffles %d card%s from their hand into their deck" % [players.find(player) + 1, count, "" if count == 1 else "s"])
	return count

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

func _trainer_context(card: CardData) -> EffectContext:
	var context := EffectContext.new()
	context.engine = self
	context.kind = EffectContext.KIND_TRAINER
	context.card = card
	context.defender = opponent_player().active
	context.player = current_player()
	context.opponent = opponent_player()
	return context


func _trainer_binding(card: CardData) -> Dictionary:
	if effects == null:
		return {}
	return effects.binding_for(card.id, EffectLibrary.SECTION_TRAINER, card.name)


func _trainer_requirements_met(card: CardData) -> bool:
	var binding := _trainer_binding(card)
	if binding.is_empty():
		return true
	var resolver := EffectResolver.new(effects, _trainer_context(card))
	return resolver.requirements_met(str(binding["function"]), binding["args"] as Dictionary)

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


static func slot_name(slot: int) -> String:
	return "Battle Zone" if slot == -1 else "Field %d" % (slot + 1)

func _opponent_index() -> int:
	return 1 - current_index


func _log(text: String) -> void:
	events.append(text)
