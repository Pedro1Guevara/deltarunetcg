class_name MatchEngine
extends RefCounted

const NO_WINNER := -1
## Both players won at the same time and in the same number of ways: play Sudden Death.
const SUDDEN_DEATH := -2

var players: Array[PlayerState] = []
var current_index: int = 0
var turn: int = 0
var winner: int = NO_WINNER
## The round's events as data (MatchEvent); each player reads theirs through events_for().
## The engine holds no words: game/presentation writes the log, the prompts and the labels.
var match_log: MatchLog = null
## The rules of the round being played. Set by start().
var rules: MatchRules
## Null means every attack resolves as its printed damage.
var effects: EffectLibrary = null
## The changes card effects make to the round. Set by start().
var operations: MatchOperations

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
## Knockouts, Mercy Cards and promotions. Set by start().
var _knockouts: KnockoutResolver
## Triggered Abilities waiting to resolve after the attack: {"user": CardInPlay, "power": PowerData}.
var _triggers: Array[Dictionary] = []
## The Darkner just played from the hand and its Abilities still to be offered (on play).
var _on_play_user: CardInPlay = null
var _on_play_queue: Array[PowerData] = []
var _turn_ends_after_promotions: bool = false
## This round so far, to play it again (MatchReplay).
var _replay: MatchReplay = null

## The player who chose to Fight after taking their last Mercy Card, or -1 (Design Document 4.5).
var fighting: int = -1
## Extra cards each player draws at the start of their first turn of the next round, by player
## index: what a Spare or a lost Fight gave them. Combat hands it to the next round's rules.
var extra_draws_next_round: Array[int] = [0, 0]

## What a round goes on with after a Spare or Fight question, once Fight is chosen.
const _AFTER_BENCH := "bench"
const _AFTER_POWER := "power"
const _AFTER_ATTACK := "attack"

## Every round rule comes from match_rules (MatchRules), never from constants. rng must be
## fresh: the replay records only its seed.
func start(deck_a: Array[CardData], deck_b: Array[CardData], match_rules: MatchRules, rng: Rng) -> void:
	_replay = MatchReplay.new()
	_replay.rng_seed = rng.seed_value
	_replay.rules = match_rules.to_dict()
	for deck in [deck_a, deck_b]:
		var ids := PackedStringArray()
		for card: CardData in deck:
			ids.append(card.id)
		_replay.decks.append(ids)
	rules = match_rules
	_rng = rng
	players.clear()
	winner = NO_WINNER
	turn = 0
	stadium = null
	stadium_owner = -1
	resolving_trainer = null
	_pending = null
	_triggers.clear()
	_on_play_user = null
	_on_play_queue.clear()
	_turn_ends_after_promotions = false
	fighting = -1
	extra_draws_next_round = [0, 0]
	match_log = MatchLog.new(players)
	operations = MatchOperations.new(players, _rng, match_log)
	_knockouts = KnockoutResolver.new(players, match_log)
	_setup = MatchSetup.new(players, rules, _rng, match_log)
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


## The player who must answer the open choice, or -1.
func choice_chooser() -> int:
	return -1 if _pending == null else _pending.chooser


## The round's events from the from-th on, as player_index sees them (MatchEvent.for_viewer()):
## another player's private events in their hidden version, their secret ones not at all.
func events_for(player_index: int, from: int) -> Array[MatchEvent]:
	return match_log.entries_for(player_index, from)


## What player_index can see of the round (PlayerView): never the other hand, the order of a
## deck, the Mercy Cards, nor a question or legal actions that are not theirs.
func view_for(player_index: int) -> PlayerView:
	var view := PlayerView.new()
	view.viewer = player_index
	view.turn = turn
	view.current = current_index
	view.is_over = is_over()
	view.winner = winner
	view.fighting = fighting
	view.rules = MatchRules.from_dict(rules.to_dict())
	view.stadium = stadium
	view.stadium_owner = stadium_owner
	view.resolving_trainer = resolving_trainer
	view.event_count = match_log.entries.size()
	for index in players.size():
		var player := players[index]
		var side := PlayerView.SideView.new()
		side.index = index
		if index == player_index:
			side.hand = player.hand.duplicate()
			for card in player.hand:
				if card.trainer_type == CardData.TRAINER_SPELL:
					view.spell_costs[card.id] = spell_cost(card)
		side.hand_size = player.hand.size()
		side.deck_size = player.deck.size()
		side.prize_count = player.prizes.size()
		side.discard = player.discard.duplicate()
		side.active = null if player.active == null else player.active.snapshot()
		for darkner in player.bench:
			side.bench.append(darkner.snapshot())
		side.tp = player.tp
		side.mulligans = player.mulligans
		side.energy_attached_this_turn = player.energy_attached_this_turn
		side.retreated_this_turn = player.retreated_this_turn
		side.supporter_played_this_turn = player.supporter_played_this_turn
		side.stadium_played_this_turn = player.stadium_played_this_turn
		side.attack_used_last_turn = player.attack_used_last_turn
		side.powers_used_this_turn = player.powers_used_this_turn.duplicate()
		view.sides.append(side)
	if _pending != null:
		view.chooser = _pending.chooser
		view.choice_kind = _pending.kind
		if _pending.chooser == player_index:
			view.choice_details = _pending.details.duplicate(true)
			for index in _pending.options.size():
				var option := _pending.option(index).duplicate(true)
				for key: Variant in option:
					if option[key] is CardInPlay:
						option[key] = (option[key] as CardInPlay).snapshot()
				view.choice_options.append(option)
			view.revealed.assign(_pending.revealed)
	var actor := _pending.chooser if _pending != null else current_index
	if actor == player_index:
		view.legal_actions = legal_actions()
	return view


## What the open question is about (a PendingChoice.KIND_ constant), or an empty string.
func choice_kind() -> String:
	return "" if _pending == null else _pending.kind


## What the open question's kind needs to know (see PendingChoice), or an empty Dictionary.
func choice_details() -> Dictionary:
	return {} if _pending == null else _pending.details.duplicate()


## An option of the open question: {"value"} and, for some kinds, "pick", "copy" or "shows"
## (PendingChoice).
func choice_option(index: int) -> Dictionary:
	if _pending == null or index < 0 or index >= _pending.options.size():
		return {}
	return _pending.option(index).duplicate()


## Cards shown to the chooser while they answer, such as their deck during a search.
func choice_revealed() -> Array[CardData]:
	var shown: Array[CardData] = []
	if _pending != null:
		shown.assign(_pending.revealed)
	return shown


## What an option of the open choice is about: a CardData, a CardInPlay, or null when it is
## about no card (Heads, Take nothing). For showing it, never for rules.
func choice_option_shows(index: int) -> Object:
	if _pending == null or index < 0 or index >= _pending.options.size():
		return null
	var option := _pending.option(index)
	if option.has("shows"):
		return option["shows"] as Object
	var value: Variant = option["value"]
	return value as CardData if value is CardData else null


func legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_over():
		return actions

	# While a choice is open, answering it is the only legal action.
	if _pending != null:
		for index in _pending.options.size():
			actions.append({"type": "choose", "option": index})
		return actions

	return LegalActions.for_turn(self)


## Applies a legal action. An action is identified by its fields: {"type": "end_turn"}. A
## "label" a caller adds for its own use is ignored.
func apply(requested: Dictionary) -> void:
	var action := _legal_action_like(requested)
	if action.is_empty():
		push_error("MatchEngine: illegal action %s" % requested)
		return
	var recorded := action.duplicate()
	recorded.erase("label")
	_replay.actions.append(recorded)

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
		"use_power":
			_do_use_power(int(action["slot"]), str(action["power"]))
		"use_area":
			_do_use_area()
		"end_turn":
			_end_turn(false)
		"choose":
			_do_choose(int(action["option"]))


## Whether requested is one of the legal actions, compared as apply() compares them.
func is_legal(requested: Dictionary) -> bool:
	return not _legal_action_like(requested).is_empty()


## The round so far: its seed, rules, decks and every action applied (MatchReplay). A copy.
func replay() -> MatchReplay:
	return _replay.duplicate_replay()


## The legal action with the same fields as requested, label aside, or an empty Dictionary.
## Numbers match by value, so an index that came back from JSON as a float still matches.
func _legal_action_like(requested: Dictionary) -> Dictionary:
	for action in legal_actions():
		if _same_action(action, requested):
			return action
	return {}


static func _same_action(listed: Dictionary, requested: Dictionary) -> bool:
	for key: Variant in listed:
		if key == "label":
			continue
		if not requested.has(key):
			return false
		var a: Variant = listed[key]
		var b: Variant = requested[key]
		var numbers := (a is int or a is float) and (b is int or b is float)
		if (numbers and not is_equal_approx(float(a), float(b))) or (not numbers and a != b):
			return false
	for key: Variant in requested:
		if key != "label" and not listed.has(key):
			return false
	return true


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
## here, such as refilling TP after a pass (Design Document 5). Then the opponent's turn begins.
func _end_turn(attacked: bool) -> void:
	var player := current_player()
	if not attacked:
		match_log.add(MatchEvent.TURN_ENDED, current_index, {})
	if rules.tp_max > 0 and not attacked:
		_set_tp(player, rules.tp_max)
	if operations.extra_turn:
		operations.extra_turn = false
		match_log.add(MatchEvent.EXTRA_TURN, current_index, {})
		_begin_turn(current_index)
		return
	_begin_turn(_opponent_index())


## Starts player_index's turn. Called by _end_turn() with the opponent, and once with the
## first player when the setup is done.
func _begin_turn(player_index: int) -> void:
	current_index = player_index
	turn += 1
	var player := current_player()
	player.reset_turn_flags()
	player.turns_started += 1
	match_log.add(MatchEvent.TURN_STARTED, current_index, {"turn": turn})

	if player.deck.is_empty():
		if rules.deck_out_loses:
			# Deltarune (Design Document 4.5): a player who cannot draw loses the round.
			winner = _opponent_index()
			match_log.add(MatchEvent.DECK_OUT, current_index, {"loses": true})
			return
		# Legacy roguelite rule: deck-out costs a prize instead of losing.
		match_log.add(MatchEvent.DECK_OUT, current_index, {"loses": false})
		_knockouts.take_prize(_opponent_index(), 1)
		if players[_opponent_index()].prizes.is_empty():
			winner = _opponent_index()
			match_log.add(MatchEvent.WON, winner, {"winner": winner, "after_deck_out": true})
		return
	if rules.tp_max > 0:
		_set_tp(player, mini(player.tp + rules.tp_recovery, rules.tp_max))
	player.draw_card()
	# The board shows the turn's draw; the log does not. The player sees the card.
	match_log.add_private(MatchEvent.DREW, current_index, {"count": 1, "cards": [player.hand.back().id], "at_turn_start": true, "extra": false}, {"count": 1, "at_turn_start": true, "extra": false})
	# What a Spare or a lost Fight gave this player in the round before (Design Document 4.5):
	# as many as the deck still holds; running out here loses nothing.
	var extra := rules.first_turn_extra_draws[current_index] if player.turns_started == 1 else 0
	if extra > 0:
		var drawn: Array[CardData] = []
		for _i in extra:
			if not player.draw_card():
				break
			drawn.append(player.hand.back())
		match_log.add_private(MatchEvent.DREW, current_index, {"count": drawn.size(), "cards": MatchLog.ids(drawn), "at_turn_start": true, "extra": true},
				{"count": drawn.size(), "at_turn_start": true, "extra": true})


## TP recovery (Design Document 5): 25% at the start of each turn, 100% when a player passes.
func _set_tp(player: PlayerState, quarters: int) -> void:
	if player.tp == quarters:
		return
	player.tp = quarters
	match_log.add(MatchEvent.TP_RECOVERED, players.find(player), {"tp": quarters})


func _do_bench(hand_index: int) -> void:
	var player := current_player()
	var darkner := operations.put_on_bench_from_hand(player, player.hand[hand_index], turn)
	if _resolve_knockouts({"then": _AFTER_BENCH, "darkner": darkner}):
		_after_bench(darkner)


## Offers the on-play Abilities of the Darkner just put on the Field, if it is still there.
func _after_bench(darkner: CardInPlay) -> void:
	if not current_player().bench.has(darkner):
		return
	_on_play_user = darkner
	_on_play_queue = EffectBindings.on_play_powers(self, darkner)
	_offer_on_play()


## Asks whether to use the next Ability of the Darkner just played ("you may use this ability").
## Each is checked again first: using one may have used up another's limit or requirements.
func _offer_on_play() -> void:
	while not _on_play_queue.is_empty():
		var power := _on_play_queue[0]
		if not EffectBindings.on_play_powers(self, _on_play_user).has(power):
			_on_play_queue.pop_front()
			continue
		_pending = PendingChoice.new(current_index, PendingChoice.KIND_USE_ABILITY, {"power": power.name}, [
			{"value": true, "shows": _on_play_user},
			{"value": false},
		], PendingChoice.RESUME_ON_PLAY, {})
		return
	_on_play_user = null


## Counts a use of an Ability toward its per-turn limit.
func _note_power_used(power: PowerData) -> void:
	var used := current_player().powers_used_this_turn
	used[power.name] = int(used.get(power.name, 0)) + 1


func _do_evolve(hand_index: int, slot: int) -> void:
	var player := current_player()
	var evolution := player.hand.pop_at(hand_index) as CardData
	var target := in_play_at(player, slot)
	var previous := target.card.name
	var previous_id := target.card.id
	target.evolve(evolution, turn)
	match_log.add(MatchEvent.EVOLVED, current_index, {"darkner": match_log.darkner(target), "from": previous_id, "into": evolution.id})


func _do_attach(hand_index: int, slot: int) -> void:
	var player := current_player()
	var energy := player.hand.pop_at(hand_index) as CardData
	var target := in_play_at(player, slot)
	target.attached_energy.append(energy)
	player.energy_attached_this_turn = true
	match_log.add(MatchEvent.ENERGY_ATTACHED, current_index, {"card": energy.id, "darkner": match_log.darkner(target), "from": MatchEvent.ZONE_HAND, "by_effect": false})


## Plays a Trainer card from hand. An Stadium stays in the shared slot and sends the one it replaces
## to its owner's discard pile; every other Trainer card is discarded after it resolves. Effects
## are not resolved yet.
func _do_play_trainer(hand_index: int) -> void:
	var player := current_player()
	var card := player.hand.pop_at(hand_index) as CardData
	match card.trainer_type:
		CardData.TRAINER_SPELL:
			_log_trainer(card, "Player %d casts %s" % [current_index + 1, card.name])
			operations.spend_tp(player, spell_cost(card))
		CardData.TRAINER_SUPPORTER:
			player.supporter_played_this_turn = true
			_log_trainer(card, "Player %d plays %s" % [current_index + 1, card.name])
		CardData.TRAINER_STADIUM:
			player.stadium_played_this_turn = true
			if stadium != null:
				players[stadium_owner].discard.append(stadium)
				match_log.add(MatchEvent.AREA_REPLACED, stadium_owner, {"card": stadium.id, "owner": stadium_owner})
			stadium = card
			stadium_owner = current_index
			_log_trainer(card, "Player %d puts %s into play" % [current_index + 1, card.name])
		_:
			_log_trainer(card, "Player %d plays %s" % [current_index + 1, card.name])
	_resolve_trainer(card)


func _log_trainer(card: CardData, text: String) -> void:
	match_log.add(MatchEvent.TRAINER_PLAYED, current_index, {"card": card.id, "trainer_type": card.trainer_type})


## Resolves the effect bound to a Trainer card, then finishes the card. Resolution may stop for a
## choice; _finish_effect() finishes the card once it is answered.
func _resolve_trainer(card: CardData) -> void:
	resolving_trainer = card
	var binding := EffectBindings.trainer_binding(self, card)
	if binding.has(EffectLibrary.TIMING_KEY):
		# An Area with an action or a trigger: it does nothing when played.
		_finish_trainer(card)
		return
	if binding.is_empty():
		match_log.add(MatchEvent.EFFECT_MISSING, current_index, {})
		_finish_trainer(card)
		return
	_pending = EffectBindings.run(self, binding, EffectBindings.trainer_context(self, card))
	if _pending == null:
		_finish_trainer(card)


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
	_pending = PendingChoice.new(current_index, PendingChoice.KIND_FLEE_PAYMENT, {}, options, PendingChoice.RESUME_RETREAT, {"slot": slot})


func _complete_retreat(slot: int, payment: Array) -> void:
	var player := current_player()
	var retreating := player.active
	var from := match_log.darkner(retreating)
	var to := match_log.darkner(player.bench[slot])
	for energy: Variant in payment:
		retreating.attached_energy.erase(energy)
		player.discard.append(energy as CardData)
	player.active = player.bench[slot]
	player.bench[slot] = retreating
	player.retreated_this_turn = true
	match_log.add(MatchEvent.RETREATED, current_index, {"from": from, "to": to, "discarded": MatchLog.ids(payment)})


## Uses an activated Ability of the Darkner at a slot (Battle Zone or Field).
func _do_use_power(slot: int, power_name: String) -> void:
	var user := in_play_at(current_player(), slot)
	var binding := {}
	for power in user.powers():
		if power.name == power_name:
			binding = EffectBindings.power_binding(self, user, power)
			_note_power_used(power)
	match_log.add(MatchEvent.POWER_USED, current_index, {"darkner": match_log.darkner(user), "power": power_name, "timing": EffectLibrary.TIMING_ACTIVATED})
	_pending = EffectBindings.run(self, binding, EffectBindings.power_context(self, user, EffectContext.KIND_POWER))
	if _pending == null:
		_finish_power()


## An Ability can knock out a Darkner during its owner's turn, even the one using it: the
## opponent takes the Mercy Card, a knocked out Battling Darkner is replaced, and the turn goes
## on.
func _finish_power() -> void:
	if _resolve_knockouts({"then": _AFTER_POWER}):
		_after_power()


func _after_power() -> void:
	if _advance_promotions():
		_offer_on_play()


func _do_attack(attack_index: int) -> void:
	var attacker := current_player()
	var attack := attacker.active.attacks()[attack_index]
	match_log.add(MatchEvent.ATTACK_USED, current_index, {"darkner": match_log.darkner(attacker.active), "attack": attack.name})
	attacker.attack_used_this_turn = attack.name
	operations.begin_attack()

	var context := EffectBindings.attack_context(self, attack)
	var binding := EffectBindings.attack_binding(self, attack)
	if binding.is_empty():
		if attack.has_effect():
			# Known divergence (4.8): without a card effect entry only the printed number is dealt.
			match_log.add(MatchEvent.EFFECT_MISSING, current_index, {})
		operations.deal_attack_damage(context, attack.damage)
		_finish_attack()
		return

	_pending = EffectBindings.run(self, binding, context)
	if _pending == null:
		_finish_attack()


## Continues the turn once a suspended effect has finished resolving.
func _finish_effect(context: EffectContext) -> void:
	match context.kind:
		EffectContext.KIND_TRAINER:
			_finish_trainer(context.card)
		EffectContext.KIND_POWER, EffectContext.KIND_AREA:
			_finish_power()
		EffectContext.KIND_TRIGGER:
			_continue_attack()
		_:
			_finish_attack()


func _do_choose(option: int) -> void:
	var choice := _pending
	_pending = null
	var picked := choice.option(option)
	# Only the chooser sees the answer; what it leads to has events of its own.
	match_log.add_secret(MatchEvent.CHOICE_ANSWERED, choice.chooser, {"kind": choice.kind, "index": option,
			"details": match_log.as_data(choice.details), "option": match_log.as_data(picked)})

	match choice.resume:
		PendingChoice.RESUME_EFFECT:
			choice.context.selection.append(picked["value"])
			if choice.resolver.resume():
				_finish_effect(choice.context)
			else:
				_pending = EffectBindings.choice_for(choice.resolver, choice.context)
		PendingChoice.RESUME_SETUP:
			_continue_setup(_setup.answer(picked["value"]))
		PendingChoice.RESUME_PROMOTE:
			_knockouts.promote(choice.chooser, int(picked["value"]))
			if _advance_promotions() and _turn_ends_after_promotions:
				_turn_ends_after_promotions = false
				_end_turn(true)
		PendingChoice.RESUME_TAKE_PRIZE:
			_answer_prize(int(picked["value"]), choice.data)
		PendingChoice.RESUME_SPARE_FIGHT:
			_answer_spare_fight(choice.chooser, picked["value"] == PendingChoice.SPARE, choice.data)
		PendingChoice.RESUME_RETREAT:
			_complete_retreat(int(choice.data["slot"]), picked["value"] as Array)
		PendingChoice.RESUME_ON_PLAY:
			var power: PowerData = _on_play_queue.pop_front()
			if not bool(picked["value"]):
				_offer_on_play()
				return
			_note_power_used(power)
			match_log.add(MatchEvent.POWER_USED, current_index, {"darkner": match_log.darkner(_on_play_user), "power": power.name, "timing": EffectLibrary.TIMING_ON_PLAY})
			var binding := EffectBindings.power_binding(self, _on_play_user, power)
			_pending = EffectBindings.run(self, binding, EffectBindings.power_context(self, _on_play_user, EffectContext.KIND_POWER))
			if _pending == null:
				_finish_power()


## After the attack's own effect: Abilities set off by its damage, then knockouts, then the end
## of the turn.
func _finish_attack() -> void:
	_triggers = _attack_damage_triggers()
	_continue_attack()


## Every on_attack_damage Ability of the attacking player's Darkners, Battle Zone first, when the
## attack damaged at least one of the opponent's Darkners. Each copy in play triggers on its own.
func _attack_damage_triggers() -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	var opponent := opponent_player()
	var damaged_opponent := false
	for darkner in operations.damaged_by_attack():
		if darkner == opponent.active or opponent.bench.has(darkner):
			damaged_opponent = true
	if not damaged_opponent:
		return queue
	var player := current_player()
	for darkner: CardInPlay in [player.active] + player.bench:
		if darkner == null:
			continue
		for power in darkner.powers():
			if EffectBindings.power_binding(self, darkner, power).get(EffectLibrary.TIMING_KEY) == EffectLibrary.TIMING_ON_ATTACK_DAMAGE:
				queue.append({"user": darkner, "power": power})
	return queue


## Resolves the queued triggered Abilities, then knockouts and the end of the turn. A trigger
## that asks a question stops here; _finish_effect() continues once it is answered.
func _continue_attack() -> void:
	while not _triggers.is_empty():
		var trigger: Dictionary = _triggers.pop_front()
		var user := trigger["user"] as CardInPlay
		var power := trigger["power"] as PowerData
		var binding := EffectBindings.power_binding(self, user, power)
		_note_power_used(power)
		match_log.add(MatchEvent.POWER_USED, current_index, {"darkner": match_log.darkner(user), "power": power.name, "timing": EffectLibrary.TIMING_ON_ATTACK_DAMAGE})
		_pending = EffectBindings.run(self, binding, EffectBindings.power_context(self, user, EffectContext.KIND_TRIGGER))
		if _pending != null:
			return
	if _resolve_knockouts({"then": _AFTER_ATTACK}):
		_after_attack()


func _after_attack() -> void:
	# Attacking passes priority, once every knocked out Pokemon has been replaced.
	if _advance_promotions():
		_end_turn(true)
	else:
		_turn_ends_after_promotions = true


## Each player whose Battling Darkner was knocked out chooses a replacement, the defending
## player first. Returns true once every promotion is done; otherwise their question is open.
func _advance_promotions() -> bool:
	_pending = _knockouts.next_promotion()
	return _pending == null


## Resolves knockouts after an attack, ACT card or Ability (KnockoutResolver.resolve()).
## Uses the action of the Area in play ("Once during each player's turn, that player may...").
func _do_use_area() -> void:
	var player := current_player()
	var used := player.powers_used_this_turn
	used[stadium.name] = int(used.get(stadium.name, 0)) + 1
	match_log.add(MatchEvent.AREA_USED, current_index, {"card": stadium.id})
	var binding := EffectBindings.area_binding(self, EffectLibrary.TIMING_AREA_ACTION)
	_pending = EffectBindings.run(self, binding, EffectBindings.area_context(self, null))
	if _pending == null:
		_finish_power()


## Resolves the Area's on_put_onto_field effect for every Darkner put onto a Field since the
## last time (Cold Place). These effects resolve at once and never ask a question.
func _resolve_field_entries() -> void:
	for darkner in operations.take_entered_field():
		var binding := EffectBindings.area_binding(self, EffectLibrary.TIMING_ON_PUT_ONTO_FIELD)
		if binding.is_empty():
			continue
		var entered := match_log.darkner(darkner)
		match_log.add(MatchEvent.AREA_TRIGGERED, int(entered["side"]), {"card": stadium.id, "darkner": entered})
		if EffectBindings.run(self, binding, EffectBindings.area_context(self, darkner)) != null:
			push_error("MatchEngine: %s asked a question while resolving on_put_onto_field" % stadium.name)


## Resolves what Darkners put onto a Field set off, then knockouts, after an attack, an Ability,
## an Area action or a Darkner put onto the Field (KnockoutResolver.resolve()). True when the
## turn goes on at once; false when the round is over, a Mercy Card waits to be picked
## (MatchRules.choose_prizes), or the player who took their last Mercy Card must choose to
## Spare or to Fight. then says how the turn goes on once those questions are answered.
func _resolve_knockouts(then: Dictionary) -> bool:
	_resolve_field_entries()
	var result := _knockouts.resolve(_opponent_index(), rules, fighting)
	if result == KnockoutResolver.CHOOSING_PRIZES:
		_pending = _knockouts.next_prize_choice(then)
		return false
	return _settle_knockouts(result, then)


## What the knockouts lead to once every Mercy Card is taken: the end of the round, the Spare
## or Fight question, or (true) the turn goes on.
func _settle_knockouts(result: int, then: Dictionary) -> bool:
	var fighter := fighting
	if result != NO_WINNER:
		winner = result
		if fighter != -1 and result == 1 - fighter:
			# A lost Fight: the winner still draws the extra cards (Design Document 4.5).
			extra_draws_next_round[result] = rules.spare_extra_draws
		return false
	var taker := _knockouts.take_spare_fight_offer()
	if taker != -1:
		_pending = PendingChoice.new(taker, PendingChoice.KIND_SPARE_FIGHT, {"extra_draws": rules.spare_extra_draws},
				[{"value": PendingChoice.SPARE}, {"value": PendingChoice.FIGHT}], PendingChoice.RESUME_SPARE_FIGHT, then)
		return false
	return true


## The next Mercy Card is picked; after the last one the knockouts settle and the turn goes on.
func _answer_prize(slot: int, then: Dictionary) -> void:
	_knockouts.take_prize_at(slot)
	if _knockouts.has_prize_choice():
		_pending = _knockouts.next_prize_choice(then)
		return
	if _settle_knockouts(_knockouts.settle(rules, fighting), then):
		_go_on_after_knockouts(then)


## Spare wins the round, and the opponent draws the extra cards next round. Fight goes on with
## the turn: the next knockout decides the round (KnockoutResolver.resolve()).
func _answer_spare_fight(chooser: int, spared: bool, then: Dictionary) -> void:
	if spared:
		extra_draws_next_round[1 - chooser] = rules.spare_extra_draws
		match_log.add(MatchEvent.SPARED, chooser, {"extra_draws": rules.spare_extra_draws})
		winner = chooser
		match_log.add(MatchEvent.WON, winner, {"winner": winner, "after_deck_out": false})
		return
	fighting = chooser
	match_log.add(MatchEvent.FIGHT_CHOSEN, chooser, {})
	_go_on_after_knockouts(then)


## How the turn goes on after knockouts that did not end the round (_resolve_knockouts()).
func _go_on_after_knockouts(then: Dictionary) -> void:
	match str(then["then"]):
		_AFTER_BENCH:
			_after_bench(then["darkner"] as CardInPlay)
		_AFTER_POWER:
			_after_power()
		_AFTER_ATTACK:
			_after_attack()


# --- Effective costs --------------------------------------------------------------------
# Legality reads these, never a printed cost (Design Document 5): the continuous-effects layer
# changes them (Showtime!, Cyber City, Mewers Live).

## The Energy an attack costs this Darkner now.
func attack_cost(attacker: CardInPlay, attack: AttackData) -> Array[String]:
	return ContinuousEffects.attack_cost(self, attacker, attack)


## The Energy fleeing costs this Darkner now, one Colorless per unit.
func retreat_cost(pokemon: CardInPlay) -> Array[String]:
	var cost: Array[String] = []
	for _i in pokemon.base_card().retreat_cost + ContinuousEffects.retreat_cost_more(self, pokemon):
		cost.append(CardTypes.COLORLESS)
	return cost


## The TP, in quarters, casting this Spell costs now.
func spell_cost(spell: CardData) -> int:
	return ContinuousEffects.spell_cost(self, spell)


## The Darkner at a slot: -1 is the Battle Zone, 0 and up are Field positions.
static func in_play_at(player: PlayerState, slot: int) -> CardInPlay:
	return player.active if slot == -1 else player.bench[slot]


func _opponent_index() -> int:
	return 1 - current_index
