class_name CpuPlayer
extends RefCounted
## A CPU opponent that plays toward its deck's plan by fixed priorities (Design Document 8.7).
## It decides from a PlayerView only, never from the engine, so it knows what a player at the
## table knows, and it always answers with one of the view's legal actions.
##
## Before its first decision it builds its DeckPlan: the attacker, the attack and the Field
## its deck aims for. On its turn it does, in this order, whatever is legal and worth it: put
## Basic Darkners on the Field (the plan's first, others while there is room to spare),
## evolve, attach Energy where it lets an attack be paid soonest or where the plan needs it,
## play ACT cards and use Abilities and the Area when what they bring is worth more than what
## they cost, Flee when its Battling Darkner is far from attacking, attack with the attack
## worth most after its effects, and end the turn. Questions are answered by their kind
## (PendingChoice): it takes the cards worth most to it and discards those worth least, and
## never undoes a pick.
##
## Card effects are read from their data (EffectReader), never from card text: what each step
## of an effect brings or costs, the damage of attacks on the board, the damage to its own
## Darkners, and what a search looks for. It keeps track of its deck (DeckMemory) and keeps a
## ledger of what it discarded and took back this turn, so it does not take back what it just
## discarded or discard what it just took back.

## Turn actions, most wanted first.
const TURN_ORDER: Array[String] = ["bench", "evolve", "attach", "play_trainer", "use_power", "use_area", "retreat", "attack"]
## The atomic effect that attaches an Energy from the discard pile to a Darkner on the Field.
const ATTACH_FROM_DISCARD := "attach_from_discard_to_benched"
## What a card the plan still needs is worth on top of its own worth.
const PLAN_BONUS := 3.0
## What a card it discarded or took back this turn is worth, against moving it again.
const LEDGER_BONUS := 5.0
## TP spent on a Spell, in card worth per quarter.
const TP_WORTH := 0.25
## What an Energy is worth when it already holds all the Energy its Darkners still need.
const SPARE_ENERGY_WORTH := 0.5
## What an ACT card, Ability or Area action must bring, over what it costs, to be used: more
## than shuffling spare cards around.
const WORTH_IT := 0.5

## Its memory of its deck. memory.memory_turns is a difficulty setting.
var memory: DeckMemory

var _reader: EffectReader
var _deck: Array[CardData] = []
var _plan_data: Dictionary = {}
var _plan: DeckPlan = null
## A knockout it is setting up this turn by giving up a Darkner (_sacrifice_plan()):
## {"turn", "slot": the Field slot that gets the Energy and is promoted, "energy": card id}.
var _sacrifice: Dictionary = {}
## What moved through its discard pile this turn, seen by comparing the pile between its
## decisions: {"turn", "discarded": {id: copies}, "retrieved": {id: copies}}.
var _ledger: Dictionary = {"turn": -1, "discarded": {}, "retrieved": {}}
var _last_discard: Dictionary = {}


## effects: the card effect data (may be null: it then reads nothing). deck: its decklist.
## plan_data: the deck's "plan" entry in decks.json, or empty for an automatic plan.
func _init(effects: EffectLibrary, deck: Array[CardData], plan_data: Dictionary) -> void:
	_reader = EffectReader.new(effects)
	_deck = deck.duplicate()
	_plan_data = plan_data.duplicate(true)
	memory = DeckMemory.new(_deck)


## The plan it plays toward, built for a Field of bench_limit Darkners the first time.
func plan_for(bench_limit: int) -> DeckPlan:
	if _plan == null:
		_plan = DeckPlan.build(_deck, _reader, bench_limit, _plan_data)
		for warning in _plan.warnings:
			push_warning("CpuPlayer: %s; playing an automatic plan" % warning)
	return _plan


## One of view.legal_actions. Empty only when the view has none: the round is over or another
## player is to act.
func choose(view: PlayerView) -> Dictionary:
	if view.legal_actions.is_empty():
		return {}
	plan_for(view.rules.bench_limit)
	memory.observe(view)
	_observe_discard(view)
	if not _sacrifice.is_empty() and int(_sacrifice["turn"]) != view.turn:
		_sacrifice = {}
	if view.chooser == view.viewer:
		return _answer(view)
	for type in TURN_ORDER:
		var candidates := view.legal_actions.filter(func(action: Dictionary) -> bool: return action["type"] == type)
		var picked := _pick_turn_action(view, type, candidates)
		if not picked.is_empty():
			return picked
	return _first_of_type(view.legal_actions, "end_turn")


# --- Turn actions -----------------------------------------------------------------------

func _pick_turn_action(view: PlayerView, type: String, candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return {}
	var me := view.me()
	match type:
		"bench":
			return _pick_bench(view, candidates)
		"evolve":
			return _best(candidates, func(action: Dictionary) -> float:
				return PLAN_BONUS if _plan.attacker_line.has(me.hand[int(action["hand_index"])].id) else 0.0)
		"attach":
			return _best(candidates, func(action: Dictionary) -> float: return _attach_score(view, action))
		"play_trainer":
			return _best_worth_it(candidates, func(action: Dictionary) -> float:
				return _trainer_value(view, me.hand[int(action["hand_index"])]))
		"use_power":
			return _pick_power(view, candidates)
		"use_area":
			if view.stadium == null or me.powers_used_this_turn.has(view.stadium.name):
				return {}
			var value := _effect_value(view, view.stadium.id, EffectLibrary.SECTION_TRAINER, view.stadium.name, null)
			return candidates[0] if value > WORTH_IT else {}
		"retreat":
			return _pick_retreat(view, candidates)
		"attack":
			return _best(candidates, func(action: Dictionary) -> float: return _attack_score(view, action))
	return candidates[0]


## The plan's Basic Darkners first, its attacker's line before the rest. Any other Basic only
## while the Field is empty or has room to spare after the plan's missing Darkners.
func _pick_bench(view: PlayerView, candidates: Array) -> Dictionary:
	var me := view.me()
	var missing := _plan.missing(me)
	var wanted := candidates.filter(func(action: Dictionary) -> bool: return missing.has(me.hand[int(action["hand_index"])].id))
	if not wanted.is_empty():
		return _best(wanted, func(action: Dictionary) -> float:
			return 1.0 if _plan.attacker_line.has(me.hand[int(action["hand_index"])].id) else 0.0)
	var missing_basics := 0
	for line: Array in [_plan.attacker_line] + _plan.field_lines:
		if missing.has(line[0]):
			missing_basics += 1
	var room := view.rules.bench_limit - me.bench.size()
	if me.bench.is_empty() or room > missing_basics:
		return candidates[0]
	return {}


## Abilities worth using, each once a turn, never one that would knock out its own Darkner,
## except as the last option for a knockout this turn that nothing else gives
## (_sacrifice_plan()).
func _pick_power(view: PlayerView, candidates: Array) -> Dictionary:
	var me := view.me()
	var unused := candidates.filter(func(action: Dictionary) -> bool:
		return not me.powers_used_this_turn.has(action["power"]) and _power_named(_user_of(me, action), str(action["power"])) != null)
	var safe := unused.filter(func(action: Dictionary) -> bool: return not _power_knocks_out_user(me, action))
	var chosen := _best_worth_it(safe, func(action: Dictionary) -> float:
		var user := _user_of(me, action)
		var power := _power_named(user, str(action["power"]))
		return _effect_value(view, user.card_with_power(power).id, EffectLibrary.SECTION_POWERS, power.name, null))
	if not chosen.is_empty() or _knockout_attack_available(view):
		return chosen
	for action: Dictionary in unused:
		var sacrifice := _sacrifice_plan(view, action)
		if not sacrifice.is_empty():
			_sacrifice = sacrifice
			return action
	return {}


## Flees only when its Battling Darkner cannot attack and is more than one Energy away from
## every attack, so the Energy it would discard is not almost an attack; then to the Darkner
## on the Field it would promote, among those that can attack.
func _pick_retreat(view: PlayerView, candidates: Array) -> Dictionary:
	var me := view.me()
	if not _first_of_type(view.legal_actions, "attack").is_empty() or _energy_distance(me.active) <= 1:
		return {}
	var able := candidates.filter(func(action: Dictionary) -> bool: return _can_pay_an_attack(me.bench[int(action["slot"])]))
	if able.is_empty():
		return {}
	return _best(able, func(action: Dictionary) -> float: return _promote_score(me.bench[int(action["slot"])]))


## Energy goes first where it lets the Battling Darkner attack, then to the plan's attacker
## while it has fewer Energy than the plan wants on it (DeckPlan.energy_goal), then where it
## makes or brings closer another attack, the Battle Zone before the Field; failing that, to
## the Battle Zone.
func _attach_score(view: PlayerView, action: Dictionary) -> float:
	var me := view.me()
	var slot := int(action["slot"])
	var target := me.active if slot == -1 else me.bench[slot]
	var energy := me.hand[int(action["hand_index"])]
	var trial := target.snapshot()
	trial.attached_energy.append(energy)
	var in_battle_zone := slot == -1
	var score := 1.0 if in_battle_zone else 0.0
	# An attack this turn comes before the plan; the plan before any other progress.
	if _payable_attacks(trial) > _payable_attacks(target):
		score += 30.0 if in_battle_zone else 6.0
	elif _energy_helps(target, energy):
		score += 12.0 if in_battle_zone else 3.0
	if _plan.wants_energy(target):
		score += 15.0
	return score


## Whether energy pays part of an attack darkner cannot pay yet: one of the types it asks for,
## or Colorless while it still lacks Energy.
func _energy_helps(darkner: CardInPlay, energy: CardData) -> bool:
	for attack in darkner.attacks():
		if _helps_cost(darkner, energy, attack.cost):
			return true
	return false


static func _helps_cost(darkner: CardInPlay, energy: CardData, cost: Array[String]) -> bool:
	if cost.is_empty() or darkner.can_pay(cost):
		return false
	for provided in energy.provides:
		if cost.has(provided):
			return true
	return cost.has(CardTypes.COLORLESS) and darkner.energy_pool().size() < cost.size()


## The attack's expected damage after its effects (EffectReader.estimate_attack()), plus what
## its other steps bring; a knockout of the Battling Darkner counts above any damage, each
## knockout on the Field a little less, and knocking out its own Darkner below everything.
func _attack_score(view: PlayerView, action: Dictionary) -> float:
	var me := view.me()
	var opponent := view.opponent()
	var attacker := me.active
	var attack := attacker.attacks()[int(action["attack_index"])]
	var estimate := _reader.estimate_attack(attacker, attack, me, opponent)
	var score := float(estimate["total"])
	if opponent.active != null and float(estimate["active"]) >= opponent.active.remaining_hp():
		score += 1000.0
	for darkner in opponent.bench:
		if float(estimate["bench_each"]) >= darkner.remaining_hp():
			score += 300.0
	var id := attacker.card_with_attack(attack).id
	score += _effect_value(view, id, EffectLibrary.SECTION_ATTACKS, attack.name, null)
	var harm := _reader.self_harm(id, EffectLibrary.SECTION_ATTACKS, attack.name)
	if harm > 0 and harm >= attacker.remaining_hp():
		score -= 2000.0
	return score


func _knockout_attack_available(view: PlayerView) -> bool:
	return view.legal_actions.any(func(action: Dictionary) -> bool: return action["type"] == "attack" and _attack_score(view, action) >= 1000.0)


# --- What an effect is worth --------------------------------------------------------------

## An ACT card is worth what its effect brings, less the TP a Spell costs. An Area does
## nothing when played: it is worth playing when its action would be worth using, or when it
## replaces the opponent's Area.
func _trainer_value(view: PlayerView, card: CardData) -> float:
	var value := _effect_value(view, card.id, EffectLibrary.SECTION_TRAINER, card.name, card)
	if card.trainer_type == CardData.TRAINER_STADIUM:
		var replaces_theirs := view.stadium != null and view.stadium_owner != view.viewer
		return maxf(value, 0.0) + (1.0 if replaces_theirs or view.stadium == null else -1.0)
	return value - card.tp_cost * TP_WORTH


## What a card's effect is worth to it now, in card worth (_worth()): each step adds what it
## brings and takes what it costs, read from the effect data. A step under a condition counts
## half. played is the card being played, which is no longer in the hand.
func _effect_value(view: PlayerView, card_id: String, section: String, name: String, played: CardData) -> float:
	var me := view.me()
	var opponent := view.opponent()
	var hand := me.hand.duplicate()
	if played != null:
		hand.erase(played)
	var value := 0.0
	for step in _reader.steps(card_id, section, name):
		var args := step["args"] as Dictionary
		var weight := 0.5 if not (step["conditions"] as Array).is_empty() else 1.0
		var own: bool = args.get("player", EffectTypes.PLAYER_REF) == EffectTypes.PLAYER_REF
		var delta := 0.0
		match str(step["call"]):
			"draw_cards":
				delta = _amount(args, "count") * (_average_unseen_worth(view) if own else -0.5)
			"shuffle_hand_into_deck", "put_hand_on_bottom_of_deck":
				delta = -_hand_worth(view, hand) if own else 0.3 * opponent.hand_size
			"discard_hand":
				delta = -_hand_worth(view, hand)
			"discard_from_hand":
				delta = -_cheapest_worth(view, hand, args.get("filter", ["any"]) as Array, int(_amount(args, "count")))
			"search_deck":
				delta = _best_worth(view, memory.deck_cards(view), args.get("filter", []) as Array, int(_amount(args, "count")), false)
			"search_deck_to_bench":
				var room := view.rules.bench_limit - me.bench.size()
				if room > 0:
					var count := mini(room, int(_amount(args, "count")))
					delta = _best_worth(view, memory.deck_cards(view), args.get("filter", []) as Array, count, false) + 0.5
			"take_from_discard":
				delta = _best_worth(view, me.discard, args.get("filter", []) as Array, int(_amount(args, "count")), true)
			ATTACH_FROM_DISCARD, "attach_from_hand_to_benched":
				var pile := me.discard if step["call"] == ATTACH_FROM_DISCARD else hand
				delta = _attach_from_value(me, pile, args.get("filter", []) as Array)
			"switch_in":
				delta = _switch_value(me) if own else _opponent_switch_value(opponent)
			"heal_benched":
				delta = 0.5 * me.bench.filter(func(darkner: CardInPlay) -> bool: return darkner.damage > 0).size()
			"discard_energy_in_play":
				delta = 1.5 if not own else -1.5
			"place_damage_counters":
				if args.get("target") == EffectTypes.SELF:
					delta = -0.3 * _amount(args, "count")
		value += weight * delta
	return value


## The worth of a card to it now: what its kind is worth (_keep_value()), more when the plan
## still needs it or it is Energy the plan's attacker lacks. Energy beyond what its Darkners
## still need, counting what it already holds, is worth little: it attaches one a turn.
func _worth(view: PlayerView, card: CardData) -> float:
	var me := view.me()
	if card.is_energy():
		var held := me.hand.filter(func(held_card: CardData) -> bool: return held_card.is_energy()).size()
		if me.hand.has(card):
			held -= 1
		if held >= _energy_needed(me):
			return SPARE_ENERGY_WORTH
	var worth := _keep_value(me, card)
	if _plan.missing(me).has(card.id):
		worth += PLAN_BONUS
	elif card.is_energy():
		for darkner in _in_play(me):
			if _plan.wants_energy(darkner):
				worth += PLAN_BONUS - 1.0
				break
	return worth


## How many Energy its Darkners still lack: the plan's attacker for the plan's attack, and the
## Battling Darkner for its nearest attack. At least 1, so one is always kept for next turn.
func _energy_needed(me: PlayerView.SideView) -> int:
	var needed := 0
	for darkner in _in_play(me):
		if _plan.is_attacker(darkner):
			needed += _plan.energy_short(darkner)
		elif darkner == me.active:
			needed += mini(_energy_distance(darkner), 5)
	return maxi(needed, 1)


## Taking back a card it discarded this turn is worth nothing more than moving it in a circle.
func _take_worth(view: PlayerView, card: CardData, from_discard: bool) -> float:
	var worth := _worth(view, card)
	if from_discard and int((_ledger["discarded"] as Dictionary).get(card.id, 0)) > 0:
		worth -= LEDGER_BONUS
	return worth


## A card it took back this turn is kept.
func _discard_worth(view: PlayerView, card: CardData) -> float:
	var worth := _worth(view, card)
	if int((_ledger["retrieved"] as Dictionary).get(card.id, 0)) > 0:
		worth += LEDGER_BONUS
	return worth


func _hand_worth(view: PlayerView, hand: Array[CardData]) -> float:
	var total := 0.0
	for card in hand:
		total += _discard_worth(view, card)
	return total


## The worth of the count cheapest cards of hand that match filter: what discarding them costs.
func _cheapest_worth(view: PlayerView, hand: Array[CardData], filter: Array, count: int) -> float:
	var worths: Array[float] = []
	for card in hand:
		if CardFilter.matches(card, filter):
			worths.append(_discard_worth(view, card))
	worths.sort()
	var total := 0.0
	for index in mini(count, worths.size()):
		total += worths[index]
	return total


## The worth of the count best cards of cards that match filter: what taking them brings.
## Never below 0.
func _best_worth(view: PlayerView, cards: Array[CardData], filter: Array, count: int, from_discard: bool) -> float:
	var worths: Array[float] = []
	for card in cards:
		if CardFilter.matches(card, filter):
			worths.append(_take_worth(view, card, from_discard))
	worths.sort()
	worths.reverse()
	var total := 0.0
	for index in mini(count, worths.size()):
		total += maxf(worths[index], 0.0)
	return total


## What drawing one card is worth: the average worth of the cards of its deck, as far as it
## knows them.
func _average_unseen_worth(view: PlayerView) -> float:
	var cards := memory.deck_cards(view)
	if cards.is_empty():
		return 0.0
	var total := 0.0
	for card in cards:
		total += _worth(view, card)
	return total / cards.size()


func _attach_from_value(me: PlayerView.SideView, pile: Array[CardData], filter: Array) -> float:
	var energies := pile.filter(func(card: CardData) -> bool: return CardFilter.matches(card, filter))
	if energies.is_empty() or me.bench.is_empty():
		return 0.0
	for darkner in me.bench:
		for energy: CardData in energies:
			if _energy_helps(darkner, energy) or _plan.wants_energy(darkner):
				return 2.0
	return 0.3


## Switching its own Battling Darkner: worth it when one on the Field would be promoted ahead
## of it.
func _switch_value(me: PlayerView.SideView) -> float:
	if me.active == null or me.bench.is_empty():
		return 0.0
	var best := -INF
	for darkner in me.bench:
		best = maxf(best, _promote_score(darkner))
	return 2.0 if best > _promote_score(me.active) else -1.0


## Switching the opponent's Battling Darkner: worth it when it can attack and one on their
## Field cannot, which is the one it would bring in.
func _opponent_switch_value(opponent: PlayerView.SideView) -> float:
	if opponent.active == null or not _can_pay_an_attack(opponent.active):
		return 0.0
	if opponent.bench.any(func(darkner: CardInPlay) -> bool: return not _can_pay_an_attack(darkner)):
		return 1.5
	return 0.0


static func _amount(args: Dictionary, key: String) -> float:
	var value: Variant = args.get(key, 0)
	return float(value) if value is int or value is float else 0.0


# --- Giving up a Darkner for a knockout ---------------------------------------------------

## A plan when using this Ability knocks out its own Battling Darkner but attaches an Energy
## from the discard pile to a Darkner on the Field that, promoted in its place, can then knock
## out the opponent's Battling Darkner, and only thanks to that Energy. Never when the Mercy
## Card the opponent takes for it would win them the round, or when attacking is not allowed
## this turn. An empty Dictionary when there is no such knockout.
func _sacrifice_plan(view: PlayerView, action: Dictionary) -> Dictionary:
	var me := view.me()
	var opponent := view.opponent()
	if int(action["slot"]) != -1 or opponent.active == null or me.bench.is_empty():
		return {}
	if opponent.prize_count <= view.rules.prizes_per_knockout:
		return {}
	if view.turn <= 1 and not view.rules.first_player_can_attack:
		return {}
	var user := me.active
	var power := _power_named(user, str(action["power"]))
	var filters := _reader.filters_of(user.card_with_power(power).id, EffectLibrary.SECTION_POWERS, power.name, [ATTACH_FROM_DISCARD])
	if filters.is_empty():
		return {}
	var energies := {}
	for card in me.discard:
		if CardFilter.matches(card, filters[0]):
			energies[card.id] = card
	for slot in me.bench.size():
		var darkner := me.bench[slot]
		for id: String in energies:
			var trial := darkner.snapshot()
			trial.attached_energy.append(energies[id] as CardData)
			var promoted := PlayerView.SideView.new()
			promoted.active = trial
			for index in me.bench.size():
				if index != slot:
					promoted.bench.append(me.bench[index])
			for attack in trial.attacks():
				if not trial.can_pay(attack.cost) or darkner.can_pay(attack.cost):
					continue
				var estimate := _reader.estimate_attack(trial, attack, promoted, opponent)
				if float(estimate["active"]) >= opponent.active.remaining_hp():
					return {"turn": view.turn, "slot": slot, "energy": id}
	return {}


func _sacrifice_slot() -> int:
	return -1 if _sacrifice.is_empty() else int(_sacrifice["slot"])


# --- Questions --------------------------------------------------------------------------

func _answer(view: PlayerView) -> Dictionary:
	var options := view.choice_options
	var index := 0
	match view.choice_kind:
		PendingChoice.KIND_COIN_CALL:
			index = _option_with_value(options, true)
		PendingChoice.KIND_USE_ABILITY:
			index = _option_with_value(options, _wants_on_play_ability(view))
		PendingChoice.KIND_PAY_TP:
			index = _option_with_value(options, 1)
		PendingChoice.KIND_BATTLING_DARKNER:
			index = _best_option(options, func(option: Dictionary) -> float: return (option["value"] as CardData).hp)
		PendingChoice.KIND_SETUP_BENCH:
			index = _best_option(options, func(option: Dictionary) -> float: return 0.0 if option["value"] == null else 1.0)
		PendingChoice.KIND_MULLIGAN_DRAWS:
			index = _best_option(options, func(option: Dictionary) -> float: return float(option["value"]))
		PendingChoice.KIND_PROMOTE:
			index = _best_option(options, func(option: Dictionary) -> float:
				var slot := int(option["value"])
				return 10000.0 if _sacrifice_slot() == slot else _promote_score(view.me().bench[slot]))
		PendingChoice.KIND_PICK_CARDS:
			index = _pick_card(view)
		PendingChoice.KIND_CHOOSE_DARKNER:
			index = _best_option(options, func(option: Dictionary) -> float: return _darkner_score(view, option))
	return _choose_action(view, index)


## Uses an Ability offered when its Darkner is played when it is worth it, never when it would
## knock that Darkner out.
func _wants_on_play_ability(view: PlayerView) -> bool:
	for option in view.choice_options:
		var user := option.get("shows") as CardInPlay
		if user == null:
			continue
		var power := _power_named(user, str(view.choice_details.get("power", "")))
		if power == null:
			return true
		var id := user.card_with_power(power).id
		var harm := _reader.self_harm(id, EffectLibrary.SECTION_POWERS, power.name)
		if harm > 0 and harm >= user.remaining_hp():
			return false
		return _effect_value(view, id, EffectLibrary.SECTION_POWERS, power.name, null) > WORTH_IT
	return true


## Takes up to the most it may, the cards worth most first; discards no more than it must,
## the cards worth least first (among equals, the one it holds most copies of). Never undoes.
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
	var from_discard: bool = details.get("zone") == PendingChoice.ZONE_DISCARD
	var me := view.me()
	var best := adds[0]
	var best_score := -INF
	for index in adds:
		var card := _card_of(view.choice_options[index])
		if card == null:
			continue
		var score := 0.0
		if discarding:
			var copies := me.hand.filter(func(held: CardData) -> bool: return held.id == card.id).size()
			score = -_discard_worth(view, card) + 0.01 * copies
		else:
			score = _take_worth(view, card, from_discard)
		if not _sacrifice.is_empty() and card.id == str(_sacrifice["energy"]) and from_discard:
			score += 1000.0
		if score > best_score:
			best = index
			best_score = score
	return best


## Keeps this turn's ledger: cards that came into its discard pile since its last decision
## were discarded, cards that left it were taken back. A new turn starts a new ledger from the
## pile as it stands, so Darkners knocked out before it are not counted.
func _observe_discard(view: PlayerView) -> void:
	var pile := {}
	for card in view.me().discard:
		pile[card.id] = int(pile.get(card.id, 0)) + 1
	if int(_ledger["turn"]) != view.turn:
		_ledger = {"turn": view.turn, "discarded": {}, "retrieved": {}}
		_last_discard = pile
		return
	for id: String in pile:
		var added := int(pile[id]) - int(_last_discard.get(id, 0))
		if added > 0:
			_ledger["discarded"][id] = int((_ledger["discarded"] as Dictionary).get(id, 0)) + added
	for id: String in _last_discard:
		var removed := int(_last_discard[id]) - int(pile.get(id, 0))
		if removed > 0:
			_ledger["retrieved"][id] = int((_ledger["retrieved"] as Dictionary).get(id, 0)) + removed
	_last_discard = pile


## What a card's kind is worth to keep: an evolution for a Darkner in play most, then Basic
## Darkners, Energy one of its Darkners asks for, ACT cards, and last an evolution with nothing
## to evolve or Energy none of its Darkners asks for.
func _keep_value(me: PlayerView.SideView, card: CardData) -> float:
	var in_play := _in_play(me)
	if card.is_basic_pokemon():
		return 3.0
	if card.is_pokemon():
		return 4.0 if in_play.any(func(darkner: CardInPlay) -> bool: return darkner.card.name == card.evolve_from) else 0.0
	if card.is_energy():
		var asked := in_play.any(func(darkner: CardInPlay) -> bool:
			return darkner.attacks().any(func(attack: AttackData) -> bool:
				return attack.cost.has(CardTypes.COLORLESS) or card.provides.any(func(type: String) -> bool: return attack.cost.has(type))))
		return 2.0 if asked else 0.0
	return 1.0


## The healthiest Darkner that can attack, one that can pay the plan's attack first; failing
## that, the healthiest.
func _promote_score(darkner: CardInPlay) -> float:
	var score := float(darkner.remaining_hp())
	if _can_pay_an_attack(darkner):
		score += 1000.0
		if _plan != null and _plan.is_attacker(darkner) and _can_pay_plan_attack(darkner):
			score += 500.0
	return score


func _can_pay_plan_attack(darkner: CardInPlay) -> bool:
	return darkner.attacks().any(func(attack: AttackData) -> bool: return attack.name == _plan.attack_name and darkner.can_pay(attack.cost))


## Own Darkners: switch in the one it would promote, attach to the plan's attacker while it
## wants Energy, else where it lets an attack be paid (or where its sacrifice plan says), aim
## at the most damaged. The opponent's: switch in one
## that cannot attack, the weakest first; aim at the one closest to being knocked out.
func _darkner_score(view: PlayerView, option: Dictionary) -> float:
	var details := view.choice_details
	var darkner := option.get("shows") as CardInPlay
	if darkner == null:
		return 0.0
	var own := str(details.get("side", "")) == PendingChoice.SIDE_OWN
	match str(details.get("purpose", "")):
		PendingChoice.PURPOSE_SWITCH_IN:
			if own:
				return _promote_score(darkner)
			return (0.0 if _can_pay_an_attack(darkner) else 1000.0) - darkner.remaining_hp()
		PendingChoice.PURPOSE_ATTACH:
			if _sacrifice_slot() != -1 and int(option["value"]) == _sacrifice_slot():
				return 10000.0
			var score := float(_payable_attacks(darkner) < darkner.attacks().size()) * 10.0 - darkner.attached_energy.size()
			if _plan.wants_energy(darkner):
				score += 15.0
			return score
	return darkner.damage if own else -darkner.remaining_hp()


func _power_knocks_out_user(me: PlayerView.SideView, action: Dictionary) -> bool:
	var user := _user_of(me, action)
	var power := _power_named(user, str(action["power"]))
	if power == null:
		return false
	var harm := _reader.self_harm(user.card_with_power(power).id, EffectLibrary.SECTION_POWERS, power.name)
	return harm > 0 and harm >= user.remaining_hp()


# --- Helpers ----------------------------------------------------------------------------

## How many Energy the Darkner lacks for its nearest attack: at least 1 when it has enough
## Energy of the wrong types, 0 when it can attack, 99 without attacks.
func _energy_distance(darkner: CardInPlay) -> int:
	var nearest := 99
	var units := darkner.energy_pool().size()
	for attack in darkner.attacks():
		var missing := attack.cost.size() - units
		if missing <= 0:
			missing = 0 if darkner.can_pay(attack.cost) else 1
		nearest = mini(nearest, missing)
	return nearest


func _payable_attacks(darkner: CardInPlay) -> int:
	return darkner.attacks().filter(func(attack: AttackData) -> bool: return darkner.can_pay(attack.cost)).size()


func _can_pay_an_attack(darkner: CardInPlay) -> bool:
	return _payable_attacks(darkner) > 0


static func _user_of(me: PlayerView.SideView, action: Dictionary) -> CardInPlay:
	var slot := int(action["slot"])
	return me.active if slot == -1 else me.bench[slot]


static func _power_named(darkner: CardInPlay, power_name: String) -> PowerData:
	for power in darkner.powers():
		if power.name == power_name:
			return power
	return null


static func _in_play(side: PlayerView.SideView) -> Array[CardInPlay]:
	var darkners: Array[CardInPlay] = []
	if side.active != null:
		darkners.append(side.active)
	darkners.append_array(side.bench)
	return darkners


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


## The action with the highest value above WORTH_IT, or an empty Dictionary.
static func _best_worth_it(actions: Array, value: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_value := WORTH_IT
	for action: Dictionary in actions:
		var worth := float(value.call(action))
		if worth > best_value:
			best = action
			best_value = worth
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