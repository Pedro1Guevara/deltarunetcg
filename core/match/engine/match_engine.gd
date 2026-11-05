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
	_triggers.clear()
	_on_play_user = null
	_on_play_queue.clear()
	_turn_ends_after_promotions = false
	operations = MatchOperations.new(players, _rng, events)
	_knockouts = KnockoutResolver.new(players, events)
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
			actions.append({
				"type": "choose",
				"option": index,
				"label": str(_pending.option(index)["label"]),
			})
		return actions

	return LegalActions.for_turn(self)


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
		"use_power":
			_do_use_power(int(action["slot"]), str(action["power"]))
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
## here, such as refilling TP after a pass (Design Document 5). Then the opponent's turn begins.
func _end_turn(attacked: bool) -> void:
	var player := current_player()
	if not attacked:
		_log("Player %d ends the turn" % (current_index + 1))
	if rules.tp_max > 0 and not attacked:
		_set_tp(player, rules.tp_max)
	if operations.extra_turn:
		operations.extra_turn = false
		_log("Player %d takes another turn" % (current_index + 1))
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
	_log("--- Turn %d: Player %d ---" % [turn, current_index + 1])

	if player.deck.is_empty():
		if rules.deck_out_loses:
			# Deltarune (Design Document 4.5): a player who cannot draw loses the round.
			winner = _opponent_index()
			_log("Player %d cannot draw and loses the round" % (current_index + 1))
			return
		# Legacy roguelite rule: deck-out costs a prize instead of losing.
		_log("Player %d cannot draw: the opponent takes a Mercy Card" % (current_index + 1))
		_knockouts.take_prize(_opponent_index(), 1)
		if players[_opponent_index()].prizes.is_empty():
			winner = _opponent_index()
			_log("Player %d took the last Mercy Card and wins" % (winner + 1))
		return
	if rules.tp_max > 0:
		_set_tp(player, mini(player.tp + rules.tp_recovery, rules.tp_max))
	player.draw_card()


## TP recovery (Design Document 5): 25% at the start of each turn, 100% when a player passes.
func _set_tp(player: PlayerState, quarters: int) -> void:
	if player.tp == quarters:
		return
	player.tp = quarters
	_log("Player %d recovers TP: %d%%" % [players.find(player) + 1, quarters * 25])


func _do_bench(hand_index: int) -> void:
	var player := current_player()
	var card := player.hand.pop_at(hand_index) as CardData
	var darkner := CardInPlay.new(card, turn)
	player.bench.append(darkner)
	_log("Player %d puts %s on the Field" % [current_index + 1, card.name])
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
		_pending = PendingChoice.new(current_index, "Use %s?" % power.name, [
			{"label": "Use %s (%s)" % [power.name, _on_play_user.card.name], "value": true, "shows": _on_play_user},
			{"label": "Don't use %s" % power.name, "value": false},
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
	target.evolve(evolution, turn)
	_log("Player %d evolves %s into %s" % [current_index + 1, previous, evolution.name])


func _do_attach(hand_index: int, slot: int) -> void:
	var player := current_player()
	var energy := player.hand.pop_at(hand_index) as CardData
	var target := in_play_at(player, slot)
	target.attached_energy.append(energy)
	player.energy_attached_this_turn = true
	_log("Player %d attaches %s to %s" % [current_index + 1, energy.name, target.card.name])


## Plays a Trainer card from hand. An Stadium stays in the shared slot and sends the one it replaces
## to its owner's discard pile; every other Trainer card is discarded after it resolves. Effects
## are not resolved yet.
func _do_play_trainer(hand_index: int) -> void:
	var player := current_player()
	var card := player.hand.pop_at(hand_index) as CardData
	match card.trainer_type:
		CardData.TRAINER_SPELL:
			_log("Player %d casts %s" % [current_index + 1, card.name])
			operations.spend_tp(player, spell_cost(card))
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
	var binding := EffectBindings.trainer_binding(self, card)
	if binding.is_empty():
		_log("  [effect not implemented]")
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


## Uses an activated Ability of the Darkner at a slot (Battle Zone or Field).
func _do_use_power(slot: int, power_name: String) -> void:
	var user := in_play_at(current_player(), slot)
	var binding := {}
	for power in user.powers():
		if power.name == power_name:
			binding = EffectBindings.power_binding(self, user, power)
			_note_power_used(power)
	_log("%s uses %s" % [user.card.name, power_name])
	_pending = EffectBindings.run(self, binding, EffectBindings.power_context(self, user, EffectContext.KIND_POWER))
	if _pending == null:
		_finish_power()


## An Ability can knock out a Darkner during its owner's turn, even the one using it: the
## opponent takes the Mercy Card, a knocked out Battling Darkner is replaced, and the turn goes
## on.
func _finish_power() -> void:
	_resolve_knockouts()
	if is_over():
		return
	if _advance_promotions():
		_offer_on_play()


func _do_attack(attack_index: int) -> void:
	var attacker := current_player()
	var attack := attacker.active.attacks()[attack_index]
	_log("%s uses %s" % [attacker.active.card.name, attack.name])
	attacker.attack_used_this_turn = attack.name
	operations.begin_attack()

	var context := EffectBindings.attack_context(self, attack)
	var binding := EffectBindings.attack_binding(self, attack)
	if binding.is_empty():
		if attack.has_effect():
			# Known divergence (4.8): without a card effect entry only the printed number is dealt.
			_log("  [effect not implemented]")
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
		EffectContext.KIND_POWER:
			_finish_power()
		EffectContext.KIND_TRIGGER:
			_continue_attack()
		_:
			_finish_attack()


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
				_pending = EffectBindings.choice_for(choice.resolver, choice.context)
		PendingChoice.RESUME_SETUP:
			_continue_setup(_setup.answer(picked["value"]))
		PendingChoice.RESUME_PROMOTE:
			_knockouts.promote(choice.chooser, int(picked["value"]))
			if _advance_promotions() and _turn_ends_after_promotions:
				_turn_ends_after_promotions = false
				_end_turn(true)
		PendingChoice.RESUME_RETREAT:
			_complete_retreat(int(choice.data["slot"]), picked["value"] as Array)
		PendingChoice.RESUME_ON_PLAY:
			var power: PowerData = _on_play_queue.pop_front()
			if not bool(picked["value"]):
				_offer_on_play()
				return
			_note_power_used(power)
			_log("%s uses %s" % [_on_play_user.card.name, power.name])
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
		_log("%s: %s" % [user.card.name, power.name])
		_pending = EffectBindings.run(self, binding, EffectBindings.power_context(self, user, EffectContext.KIND_TRIGGER))
		if _pending != null:
			return
	_resolve_knockouts()
	if is_over():
		return
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
func _resolve_knockouts() -> void:
	var result := _knockouts.resolve(_opponent_index(), rules)
	if result != NO_WINNER:
		winner = result


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
	for _i in pokemon.base_card().retreat_cost:
		cost.append(CardTypes.COLORLESS)
	return cost


## The TP, in quarters, casting this Spell costs now.
func spell_cost(spell: CardData) -> int:
	return spell.tp_cost


## The Darkner at a slot: -1 is the Battle Zone, 0 and up are Field positions.
static func in_play_at(player: PlayerState, slot: int) -> CardInPlay:
	return player.active if slot == -1 else player.bench[slot]


static func slot_name(slot: int) -> String:
	return "Battle Zone" if slot == -1 else "Field %d" % (slot + 1)


func _opponent_index() -> int:
	return 1 - current_index


func _log(text: String) -> void:
	events.append(text)