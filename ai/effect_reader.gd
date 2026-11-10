class_name EffectReader
extends RefCounted
## Reads card effect data (EffectLibrary) for the CPU (Design Document 8.7): what an attack,
## Ability or ACT card does, step by step, and how much damage an attack is worth on a given
## board. It reads the same data the engine runs, never card text, and changes nothing.
## Every player may know what cards do, so reading it is not cheating.

const MAX_DEPTH := 16
## Damage to its own Darkner that atomic effects do, by atomic name: the argument holding the
## target, the one holding the amount, and how much damage one unit of that amount is.
const SELF_HARM := {
	"place_damage_counters": ["target", "count", 10],
	"direct_damage": ["target", "amount", 1],
}
## Atomic effects that search the player's own deck, each with a "filter" argument.
const DECK_SEARCHES: Array[String] = ["search_deck", "search_deck_to_discard", "search_deck_to_bench"]
## The atomic effect a continuous Ability names to prevent attack damage to its owner's Field.
const PREVENT_BENCH_DAMAGE := "prevent_attack_damage_to_bench"
## Atomic effects that attach Energy to Darkners on the Field.
const FIELD_FEEDING: Array[String] = ["attach_from_discard_to_benched", "attach_from_hand_to_benched"]

var _effects: EffectLibrary
var _scopes: int = 0
## steps() by card, section and name: effect data does not change during a round.
var _steps_cache: Dictionary = {}


## effects may be null: every reading is then empty and every estimate uses printed damage.
func _init(effects: EffectLibrary) -> void:
	_effects = effects


## The binding of a card's attack, Ability or ACT card, or an empty Dictionary.
func binding(card_id: String, section: String, name: String) -> Dictionary:
	if _effects == null:
		return {}
	return _effects.binding_for(card_id, section, name)


## The atomic effects a binding runs, in order, each as {"call", "args", "as", "conditions"}.
## Arguments have the binding's values filled in; a reference to a value an earlier step
## produced is "$" plus a name unique to this reading, and "as" is that name. conditions holds
## the "when" of the step and of every function call around it. Empty without a binding.
func steps(card_id: String, section: String, name: String) -> Array[Dictionary]:
	var key := "%s/%s/%s" % [card_id, section, name]
	if not _steps_cache.has(key):
		var found := binding(card_id, section, name)
		var into: Array[Dictionary] = []
		if not found.is_empty():
			_collect(str(found["function"]), found["args"] as Dictionary, [], 0, into)
		_steps_cache[key] = into
	return _steps_cache[key] as Array[Dictionary]


func _collect(function_name: String, args: Dictionary, conditions: Array, depth: int, into: Array[Dictionary]) -> void:
	var definition := _effects.functions.get(function_name, {}) as Dictionary
	if depth > MAX_DEPTH or not definition.get("steps") is Array:
		return
	_scopes += 1
	var scope := "s%d." % _scopes
	var outputs := {}
	for step: Variant in definition["steps"]:
		if step is Dictionary and (step as Dictionary).has("as"):
			outputs[str((step as Dictionary)["as"])] = true
	for step: Variant in definition["steps"]:
		if not step is Dictionary:
			continue
		var call := str((step as Dictionary).get("call", ""))
		var step_args := {}
		var raw := (step as Dictionary).get("args", {}) as Dictionary
		for key: Variant in raw:
			step_args[key] = _resolve(raw[key], args, outputs, scope)
		var step_conditions := conditions.duplicate()
		if (step as Dictionary).get("when") is Dictionary:
			var when := ((step as Dictionary)["when"] as Dictionary).duplicate()
			when["value"] = _resolve(when.get("value"), args, outputs, scope)
			step_conditions.append(when)
		if _effects.functions.has(call):
			_collect(call, step_args, step_conditions, depth + 1, into)
		else:
			var output := scope + str((step as Dictionary)["as"]) if (step as Dictionary).has("as") else ""
			into.append({"call": call, "args": step_args, "as": output, "conditions": step_conditions})


## A parameter takes the argument's value; an earlier step's output gets this reading's name;
## context references ($self, $player...) and literals stay as they are.
static func _resolve(value: Variant, args: Dictionary, outputs: Dictionary, scope: String) -> Variant:
	if not value is String or not (value as String).begins_with("$"):
		return value
	var name := (value as String).substr(1)
	if EffectTypes.CONTEXT.has(value):
		return value
	if args.has(name):
		return args[name]
	if outputs.has(name):
		return "$" + scope + name
	return value


## The filters of every step that calls one of these atomic effects.
func filters_of(card_id: String, section: String, name: String, calls: Array) -> Array[Array]:
	var filters: Array[Array] = []
	for step in steps(card_id, section, name):
		if calls.has(step["call"]) and step["args"].get("filter") is Array:
			filters.append(step["args"]["filter"] as Array)
	return filters


## The most damage an attack or Ability can do to its own Darkner: every step counted,
## whatever its condition, so a coin flip counts as the worst case.
func self_harm(card_id: String, section: String, name: String) -> int:
	var harm := 0
	for step in steps(card_id, section, name):
		if not SELF_HARM.has(step["call"]):
			continue
		var spec := SELF_HARM[step["call"]] as Array
		var amount: Variant = step["args"].get(spec[1])
		if step["args"].get(spec[0]) == EffectTypes.SELF and (amount is int or amount is float):
			harm += int(amount) * int(spec[2])
	return harm


## What attack is expected to do when attacker uses it, with own as its owner's side and
## opponent as the other side, both as they would stand: {"active": damage to the opponent's
## Battling Darkner, "bench_each": damage to each Darkner on their Field, "bench_targets": how
## many, "total"}. Coin flips count at their expected value; counts (copies, types, Energy)
## are read from the boards; Weakness and Resistance apply to the Battling Darkner; Abilities
## of the attacker's side that follow attack damage (on_attack_damage) are added; a continuous
## Ability that prevents damage to the opponent's Field is respected.
func estimate_attack(attacker: CardInPlay, attack: AttackData, own: PlayerView.SideView, opponent: PlayerView.SideView) -> Dictionary:
	var result := {"active": 0.0, "bench_each": 0.0, "bench_targets": opponent.bench.size(), "total": 0.0}
	var defender := opponent.active
	var attack_steps := steps(attacker.card_with_attack(attack).id, EffectLibrary.SECTION_ATTACKS, attack.name)
	if attack_steps.is_empty():
		# No effect data: the printed damage, as the engine deals it.
		var printed: Array[Dictionary] = [{"call": "attack_damage", "args": {"times": 1, "plus": 0}, "as": "", "conditions": []}]
		attack_steps = printed
	var bench_protected := _prevents_bench_damage(opponent)
	var vars := {}
	var coins := {}
	for step in attack_steps:
		var weight := _weight(step["conditions"] as Array, vars, coins)
		if weight <= 0.0:
			continue
		var args := step["args"] as Dictionary
		match str(step["call"]):
			"attack_damage":
				var times := _number(args.get("times"), vars)
				var plus := _number(args.get("plus"), vars)
				var raw := attack.damage * times + plus
				var dealt := float(raw)
				if defender != null:
					# Times counted from coins is an expected value: Weakness and Resistance apply to
					# the damage of the flips that hit, not to the average.
					var whole := ceilf(times)
					if whole > times:
						dealt = Damage.apply_modifiers(attacker.card, defender.base_card(), int(round(attack.damage * whole + plus))) * times / whole
					else:
						dealt = Damage.apply_modifiers(attacker.card, defender.base_card(), int(round(raw)))
				result["active"] = float(result["active"]) + weight * dealt
			"attack_damage_to_benched":
				if args.get("player") == EffectTypes.OPPONENT and not bench_protected:
					result["bench_each"] = float(result["bench_each"]) + weight * _number(args.get("amount"), vars)
			"place_damage_counters":
				# Counters on a chosen Darkner of the opponent's: counted on the Battling Darkner.
				if args.get("target") != EffectTypes.SELF:
					result["active"] = float(result["active"]) + weight * _number(args.get("count"), vars) * 10.0
		_store(step, attacker, own, opponent, vars, coins)
	_add_triggers(own, opponent, result)
	result["total"] = float(result["active"]) + float(result["bench_each"]) * int(result["bench_targets"])
	return result


## on_attack_damage Abilities of the attacking side: each puts its counters on every Darkner
## the attack damaged.
func _add_triggers(own: PlayerView.SideView, opponent: PlayerView.SideView, result: Dictionary) -> void:
	var damaged_active := float(result["active"]) > 0.0
	var damaged_bench := float(result["bench_each"]) > 0.0 and int(result["bench_targets"]) > 0
	if not damaged_active and not damaged_bench:
		return
	for darkner in _in_play(own):
		for power in darkner.powers():
			var id := darkner.card_with_power(power).id
			if binding(id, EffectLibrary.SECTION_POWERS, power.name).get(EffectLibrary.TIMING_KEY) != EffectLibrary.TIMING_ON_ATTACK_DAMAGE:
				continue
			var vars := {}
			var coins := {}
			for step in steps(id, EffectLibrary.SECTION_POWERS, power.name):
				var weight := _weight(step["conditions"] as Array, vars, coins)
				if weight > 0.0 and step["call"] == "place_damage_counters_on_attack_damaged":
					var damage := weight * _number(step["args"].get("count"), vars) * 10.0
					if damaged_active:
						result["active"] = float(result["active"]) + damage
					if damaged_bench:
						result["bench_each"] = float(result["bench_each"]) + damage
				_store(step, darkner, own, opponent, vars, coins)


## Keeps what a counting step produces, as an expected value.
func _store(step: Dictionary, user: CardInPlay, own: PlayerView.SideView, opponent: PlayerView.SideView, vars: Dictionary, coins: Dictionary) -> void:
	var output := str(step["as"])
	if output.is_empty():
		return
	var args := step["args"] as Dictionary
	var value := 0.0
	match str(step["call"]):
		"flip_coins":
			var count := _number(args.get("count"), vars)
			value = count * 0.5
			coins[output] = count
		"multiply":
			value = _number(args.get("a"), vars) * _number(args.get("b"), vars)
		"add":
			value = _number(args.get("a"), vars) + _number(args.get("b"), vars)
		"min":
			value = minf(_number(args.get("a"), vars), _number(args.get("b"), vars))
		"at_least":
			value = 1.0 if _number(args.get("a"), vars) >= _number(args.get("b"), vars) else 0.0
		"count_attached_energy_units":
			var target := _darkner(args.get("target"), user, opponent)
			if target != null:
				var energy_type := str(args.get("energy_type", EffectTypes.ANY_ENERGY))
				value = target.energy_pool().filter(func(unit: String) -> bool: return energy_type == EffectTypes.ANY_ENERGY or unit == energy_type).size()
		"count_attached_energy_cards":
			var target := _darkner(args.get("target"), user, opponent)
			value = 0.0 if target == null else target.attached_energy.size()
		"count_damage_counters":
			var target := _darkner(args.get("target"), user, opponent)
			value = 0.0 if target == null else target.damage / 10.0
		"count_benched":
			value = (own if args.get("player") == EffectTypes.PLAYER_REF else opponent).bench.size()
		"count_same_name_in_play":
			value = _in_play(own).filter(func(darkner: CardInPlay) -> bool: return darkner.card.name == user.card.name).size()
		"count_types_on_bench":
			var side := own if args.get("player") == EffectTypes.PLAYER_REF else opponent
			var types := {}
			for darkner in side.bench:
				for type in darkner.card.types:
					types[type] = true
			value = types.size()
	vars[output] = value


## How likely a step is to happen, from its conditions: a condition on one coin is a half;
## any other is decided on expected values.
static func _weight(conditions: Array, vars: Dictionary, coins: Dictionary) -> float:
	var weight := 1.0
	for condition: Dictionary in conditions:
		var reference: Variant = condition.get("value")
		var name := str(reference).substr(1) if reference is String else ""
		if coins.has(name) and float(coins[name]) == 1.0:
			for comparison: String in ["eq", "ne"]:
				if condition.has(comparison):
					var wanted := float(condition[comparison])
					if wanted == 0.0 or wanted == 1.0:
						weight *= 0.5
					else:
						weight *= 1.0 if comparison == "ne" else 0.0
			continue
		var value := _number(reference, vars)
		for comparison: String in EffectLibrary.COMPARISONS:
			if not condition.has(comparison):
				continue
			var other := _number(condition[comparison], vars)
			var holds := false
			match comparison:
				"eq": holds = is_equal_approx(value, other)
				"ne": holds = not is_equal_approx(value, other)
				"gt": holds = value > other
				"gte": holds = value >= other
				"lt": holds = value < other
				"lte": holds = value <= other
			if not holds:
				weight = 0.0
	return weight


static func _number(value: Variant, vars: Dictionary) -> float:
	if value is int or value is float:
		return float(value)
	if value is String and (value as String).begins_with("$"):
		return float(vars.get((value as String).substr(1), 0.0))
	return 0.0


static func _darkner(reference: Variant, user: CardInPlay, opponent: PlayerView.SideView) -> CardInPlay:
	if reference == EffectTypes.SELF:
		return user
	if reference == EffectTypes.DEFENDER:
		return opponent.active
	return null


## What a Darkner does for its own Field, read from its Abilities and attacks: "protects" (a
## continuous Ability that prevents attack damage to the Field while it battles, Vow of
## Majesty), "heals" (an attack that heals the Field, Refreshing Splash) and "feeds" (an
## Ability or attack that attaches Energy to the Field, Selfless Devotion, Helpful Training).
func field_support(darkner: CardInPlay) -> Dictionary:
	var traits := {"protects": false, "heals": false, "feeds": false}
	for power in darkner.powers():
		var id := darkner.card_with_power(power).id
		var timing: Variant = binding(id, EffectLibrary.SECTION_POWERS, power.name).get(EffectLibrary.TIMING_KEY)
		for step in steps(id, EffectLibrary.SECTION_POWERS, power.name):
			if timing == EffectLibrary.TIMING_CONTINUOUS and step["call"] == PREVENT_BENCH_DAMAGE:
				traits["protects"] = true
			if FIELD_FEEDING.has(step["call"]):
				traits["feeds"] = true
	for attack in darkner.attacks():
		for step in steps(darkner.card_with_attack(attack).id, EffectLibrary.SECTION_ATTACKS, attack.name):
			if step["call"] == "heal_benched":
				traits["heals"] = true
			if FIELD_FEEDING.has(step["call"]):
				traits["feeds"] = true
	return traits


func _prevents_bench_damage(side: PlayerView.SideView) -> bool:
	if side.active == null:
		return false
	for power in side.active.powers():
		var id := side.active.card_with_power(power).id
		if binding(id, EffectLibrary.SECTION_POWERS, power.name).get(EffectLibrary.TIMING_KEY) != EffectLibrary.TIMING_CONTINUOUS:
			continue
		for step in steps(id, EffectLibrary.SECTION_POWERS, power.name):
			if step["call"] == PREVENT_BENCH_DAMAGE:
				return true
	return false


static func _in_play(side: PlayerView.SideView) -> Array[CardInPlay]:
	var darkners: Array[CardInPlay] = []
	if side.active != null:
		darkners.append(side.active)
	darkners.append_array(side.bench)
	return darkners
