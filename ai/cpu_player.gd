class_name CpuPlayer
extends RefCounted
## A simple CPU opponent that plays by fixed priorities (Design Document 8.7). It decides from
## a PlayerView only, never from the engine, so it knows what a player at the table knows,
## and it always answers with one of the view's legal actions.
##
## On its turn it does, in this order, whatever is legal: put Basic Darkners on the Field,
## evolve, attach Energy where it lets an attack be paid soonest, play ACT cards, use each
## Ability and the Area at most once, Flee when its Battling Darkner cannot attack and one on
## the Field can, attack with the attack that does the most damage, and end the turn.
## Questions are answered by their kind (PendingChoice): it takes as many cards as it may,
## discards as few as it must, and never undoes a pick.

## Turn actions, most wanted first.
const TURN_ORDER: Array[String] = ["bench", "evolve", "attach", "play_trainer", "use_power", "use_area", "retreat", "attack"]


## One of view.legal_actions. Empty only when the view has none: the round is over or another
## player is to act.
func choose(view: PlayerView) -> Dictionary:
	if view.legal_actions.is_empty():
		return {}
	if view.chooser == view.viewer:
		return _answer(view)
	for type in TURN_ORDER:
		var candidates := view.legal_actions.filter(func(action: Dictionary) -> bool: return action["type"] == type)
		var picked := _pick_turn_action(view, type, candidates)
		if not picked.is_empty():
			return picked
	return _first_of_type(view.legal_actions, "end_turn")


func _pick_turn_action(view: PlayerView, type: String, candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return {}
	var me := view.me()
	match type:
		"attach":
			return _best(candidates, func(action: Dictionary) -> float: return _attach_score(me, action))
		"use_power":
			var unused := candidates.filter(func(action: Dictionary) -> bool: return not me.powers_used_this_turn.has(action["power"]))
			return {} if unused.is_empty() else unused[0]
		"use_area":
			return {} if view.stadium == null or me.powers_used_this_turn.has(view.stadium.name) else candidates[0]
		"retreat":
			if _first_of_type(view.legal_actions, "attack").is_empty():
				var able := candidates.filter(func(action: Dictionary) -> bool: return _can_pay_an_attack(me.bench[int(action["slot"])]))
				if not able.is_empty():
					return _best(able, func(action: Dictionary) -> float: return me.bench[int(action["slot"])].remaining_hp())
			return {}
		"attack":
			return _best(candidates, func(action: Dictionary) -> float: return _attack_score(view, action))
	return candidates[0]


## Energy goes first where it makes an attack payable, then where it pays part of an attack
## not yet payable, the Battle Zone before the Field in both; failing that, to the Battle Zone.
func _attach_score(me: PlayerView.SideView, action: Dictionary) -> float:
	var slot := int(action["slot"])
	var target := me.active if slot == -1 else me.bench[slot]
	var energy := me.hand[int(action["hand_index"])]
	var trial := target.snapshot()
	trial.attached_energy.append(energy)
	var in_battle_zone := slot == -1
	var score := 1.0 if in_battle_zone else 0.0
	if _payable_attacks(trial) > _payable_attacks(target):
		score += 20.0 if in_battle_zone else 6.0
	elif _energy_helps(target, energy):
		score += 12.0 if in_battle_zone else 3.0
	return score


## Whether energy pays part of an attack darkner cannot pay yet: one of the types it asks for,
## or Colorless while it still lacks Energy.
func _energy_helps(darkner: CardInPlay, energy: CardData) -> bool:
	var units := darkner.energy_pool().size()
	for attack in darkner.attacks():
		if darkner.can_pay(attack.cost):
			continue
		for provided in energy.provides:
			if attack.cost.has(provided):
				return true
		if attack.cost.has("Colorless") and units < attack.cost.size():
			return true
	return false


## The attack's damage against the Battling Darkner after Weakness and Resistance; a knockout
## counts above any damage.
func _attack_score(view: PlayerView, action: Dictionary) -> float:
	var attacker := view.me().active
	var defender := view.opponent().active
	var attack := attacker.attacks()[int(action["attack_index"])]
	var damage := Damage.apply_modifiers(attacker.card, defender.card, attack.damage)
	return damage + (1000.0 if damage >= defender.remaining_hp() else 0.0)


func _answer(view: PlayerView) -> Dictionary:
	var options := view.choice_options
	var index := 0
	match view.choice_kind:
		PendingChoice.KIND_COIN_CALL, PendingChoice.KIND_USE_ABILITY:
			index = _option_with_value(options, true)
		PendingChoice.KIND_PAY_TP:
			index = _option_with_value(options, 1)
		PendingChoice.KIND_BATTLING_DARKNER:
			index = _best_option(options, func(option: Dictionary) -> float: return (option["value"] as CardData).hp)
		PendingChoice.KIND_SETUP_BENCH:
			index = _best_option(options, func(option: Dictionary) -> float: return 0.0 if option["value"] == null else 1.0)
		PendingChoice.KIND_MULLIGAN_DRAWS:
			index = _best_option(options, func(option: Dictionary) -> float: return float(option["value"]))
		PendingChoice.KIND_PROMOTE:
			index = _best_option(options, func(option: Dictionary) -> float: return _promote_score(view.me().bench[int(option["value"])]))
		PendingChoice.KIND_PICK_CARDS:
			index = _pick_card(view)
		PendingChoice.KIND_CHOOSE_DARKNER:
			index = _best_option(options, func(option: Dictionary) -> float: return _darkner_score(view.choice_details, option))
	return _choose_action(view, index)


## Takes up to the most it may; discards no more than it must. Never undoes.
func _pick_card(view: PlayerView) -> int:
	var details := view.choice_details
	var picked := (details["picked"] as Array).size()
	var discarding := str(details["action"]) == "discard"
	var confirm := -1
	var adds: Array[int] = []
	for index in view.choice_options.size():
		var pick := str(view.choice_options[index].get("pick", ""))
		if pick == PendingChoice.PICK_CONFIRM:
			confirm = index
		elif pick == PendingChoice.PICK_ADD:
			adds.append(index)
	if confirm != -1 and (adds.is_empty() or (discarding and picked >= int(details["minimum"]))):
		return confirm
	if adds.is_empty():
		return confirm if confirm != -1 else 0
	var best := adds[0]
	var best_score := -INF
	for index in adds:
		var card := _card_of(view.choice_options[index])
		var score := _discard_score(view.me(), card) if discarding else _take_score(card)
		if score > best_score:
			best = index
			best_score = score
	return best


## Basic Darkners first, then evolutions, then Energy, then ACT cards.
func _take_score(card: CardData) -> float:
	if card == null:
		return 0.0
	if card.is_basic_pokemon():
		return 4.0
	if card.is_pokemon():
		return 3.0
	if card.is_energy():
		return 2.0
	return 1.0


## The card with the most copies in hand goes first.
func _discard_score(me: PlayerView.SideView, card: CardData) -> float:
	if card == null:
		return 0.0
	return float(me.hand.filter(func(held: CardData) -> bool: return held.id == card.id).size())


func _promote_score(darkner: CardInPlay) -> float:
	return darkner.remaining_hp() + (1000.0 if _can_pay_an_attack(darkner) else 0.0)


## Own Darkners: switch in the healthiest, attach to the Battle Zone, aim at the most damaged.
## The opponent's: aim at the one closest to being knocked out.
func _darkner_score(details: Dictionary, option: Dictionary) -> float:
	var darkner := option.get("shows") as CardInPlay
	if darkner == null:
		return 0.0
	var own := str(details.get("side", "")) == PendingChoice.SIDE_OWN
	match str(details.get("purpose", "")):
		PendingChoice.PURPOSE_SWITCH_IN:
			return darkner.remaining_hp() if own else -darkner.remaining_hp()
		PendingChoice.PURPOSE_ATTACH:
			return float(_payable_attacks(darkner) < darkner.attacks().size()) * 10.0 - darkner.attached_energy.size()
	return darkner.damage if own else -darkner.remaining_hp()


func _payable_attacks(darkner: CardInPlay) -> int:
	return darkner.attacks().filter(func(attack: AttackData) -> bool: return darkner.can_pay(attack.cost)).size()


func _can_pay_an_attack(darkner: CardInPlay) -> bool:
	return _payable_attacks(darkner) > 0


static func _card_of(option: Dictionary) -> CardData:
	var shown: Variant = option.get("shows")
	if shown is CardInPlay:
		return (shown as CardInPlay).card
	if shown is CardData:
		return shown as CardData
	return option.get("value") as CardData if option.get("value") is CardData else null


static func _option_with_value(options: Array[Dictionary], value: Variant) -> int:
	for index in options.size():
		if typeof(options[index]["value"]) == typeof(value) and options[index]["value"] == value:
			return index
	return 0


## The index of the best option; the first one on a tie.
static func _best_option(options: Array[Dictionary], score: Callable) -> int:
	var best := 0
	var best_score := -INF
	for index in options.size():
		var value := float(score.call(options[index]))
		if value > best_score:
			best = index
			best_score = value
	return best


static func _best(actions: Array, score: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for action: Dictionary in actions:
		var value := float(score.call(action))
		if value > best_score:
			best = action
			best_score = value
	return best


static func _first_of_type(actions: Array[Dictionary], type: String) -> Dictionary:
	for action in actions:
		if action["type"] == type:
			return action
	return {}


static func _choose_action(view: PlayerView, option: int) -> Dictionary:
	for action in view.legal_actions:
		if action["type"] == "choose" and int(action["option"]) == option:
			return action
	return view.legal_actions[0]