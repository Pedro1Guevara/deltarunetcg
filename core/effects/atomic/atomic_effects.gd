class_name AtomicEffects
extends RefCounted
## The atomic effect vocabulary (Design Document 7, first block). Effects change state only
## through MatchOperations; counts and checks only read it.
##
## Energy is counted two ways, and the name always says which: cards counts Energy cards,
## so a Double Colorless Energy is 1; units counts the Energy they provide, so it is 2.

const ROLE_EFFECT := "effect"
const ROLE_CHECK := "check"
## A modifier is never run as a step. It is a rule change that applies while the function that
## names it has its requirements met, and the engine reads it when it needs to know
## (ContinuousEffects).
const ROLE_MODIFIER := "modifier"

## name -> {role, params: {name: type}, returns: type or "", attack_only: bool}
const DECLARATIONS := {
	"flip_coins": {
		"role": ROLE_EFFECT, "params": {"count": "int"}, "returns": "int", "attack_only": false,
	},
	"attack_damage": {
		"role": ROLE_EFFECT, "params": {"times": "int", "plus": "int"}, "returns": "int", "attack_only": true,
	},
	"direct_damage": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "amount": "int"}, "returns": "int", "attack_only": false,
	},
	"discard_attached_energy_cards": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "energy_type": "energy_type_or_any", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"discard_all_attached_energy_cards": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"draw_cards": {
		"role": ROLE_EFFECT, "params": {"player": "player", "count": "int"}, "returns": "int", "attack_only": false,
	},
	"count_damage_counters": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"count_attached_energy_cards": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "energy_type": "energy_type_or_any"},
		"returns": "int", "attack_only": false,
	},
	"count_attached_energy_units": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "energy_type": "energy_type_or_any"},
		"returns": "int", "attack_only": false,
	},
	"count_unpaid_energy_units": {
		"role": ROLE_EFFECT, "params": {"energy_type": "energy_type_or_any"}, "returns": "int", "attack_only": true,
	},
	"count_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"multiply": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
	"add": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
	"min": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
		"switch_in": {
		"role": ROLE_EFFECT, "params": {"player": "player", "chooser": "player"}, "returns": "int", "attack_only": false,
	},
	"shuffle_hand_into_deck": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"search_deck": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"search_deck_to_discard": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"discard_from_hand": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int"}, "returns": "int", "attack_only": false,
	},
	"search_deck_to_bench": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int", "exclude_same_name": "int"},
		"returns": "int", "attack_only": false,
	},
	"discard_hand": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"put_hand_on_bottom_of_deck": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"has_cards_in_hand": {
		"role": ROLE_CHECK, "params": {"player": "player", "filter": "card_filter", "count": "int"}, "returns": "", "attack_only": false,
	},
	"has_room_on_field": {
		"role": ROLE_CHECK, "params": {"player": "player", "count": "int"}, "returns": "", "attack_only": false,
	},
	"not_first_turn": {
		"role": ROLE_CHECK, "params": {"player": "player"}, "returns": "", "attack_only": false,
	},
	"take_from_discard": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"discard_energy_in_play": {
		"role": ROLE_EFFECT, "params": {"player": "player", "chooser": "player", "filter": "card_filter", "count": "int"},
		"returns": "int", "attack_only": false,
	},
	"has_cards_in_deck": {
		"role": ROLE_CHECK, "params": {"player": "player", "count": "int"}, "returns": "", "attack_only": false,
	},
	"has_cards_in_discard": {
		"role": ROLE_CHECK, "params": {"player": "player", "filter": "card_filter", "count": "int"}, "returns": "", "attack_only": false,
	},
	"has_energy_in_play": {
		"role": ROLE_CHECK, "params": {"player": "player", "filter": "card_filter", "count": "int"}, "returns": "", "attack_only": false,
	},
	"has_benched": {
		"role": ROLE_CHECK, "params": {"player": "player", "count": "int"}, "returns": "", "attack_only": false,
	},
	"attack_damage_to_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player", "amount": "int"}, "returns": "int", "attack_only": true,
	},
	"heal_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player", "amount": "int"}, "returns": "int", "attack_only": false,
	},
	"pay_tp": {
		"role": ROLE_EFFECT, "params": {"player": "player", "amount": "int"}, "returns": "int", "attack_only": false,
	},
	"shuffle_attached_energy_into_deck": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"count_same_name_in_play": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"at_least": {
		"role": ROLE_EFFECT, "params": {"a": "int", "b": "int"}, "returns": "int", "attack_only": false,
	},
	"place_damage_counters": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon", "count": "int"}, "returns": "int", "attack_only": false,
	},
		"place_damage_counters_on_attack_damaged": {
		"role": ROLE_EFFECT, "params": {"count": "int"}, "returns": "int", "attack_only": false,
	},
	"attach_from_hand_to_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter"}, "returns": "int", "attack_only": false,
	},
	"count_types_on_bench": {
		"role": ROLE_EFFECT, "params": {"player": "player"}, "returns": "int", "attack_only": false,
	},
	"choose_darkner": {
		"role": ROLE_EFFECT, "params": {"player": "player", "chooser": "player"}, "returns": "pokemon", "attack_only": false,
	},
	"is_knocked_out": {
		"role": ROLE_EFFECT, "params": {"target": "pokemon"}, "returns": "int", "attack_only": false,
	},
	"take_extra_turn": {
		"role": ROLE_EFFECT, "params": {}, "returns": "int", "attack_only": false,
	},
	"prevent_attack_damage_to_bench": {
		"role": ROLE_MODIFIER, "params": {"player": "player"}, "returns": "", "attack_only": false,
	},
	"in_battle_zone": {
		"role": ROLE_CHECK, "params": {"target": "pokemon"}, "returns": "", "attack_only": false,
	},
	"attack_not_used_last_turn": {
		"role": ROLE_CHECK, "params": {"player": "player"}, "returns": "", "attack_only": true,
	},
	"attach_from_discard_to_benched": {
		"role": ROLE_EFFECT, "params": {"player": "player", "filter": "card_filter"}, "returns": "int", "attack_only": false,
	},
	"has_attached_energy_cards": {
		"role": ROLE_CHECK, "params": {"target": "pokemon", "energy_type": "energy_type_or_any", "count": "int"},
		"returns": "", "attack_only": false,
	},
}


static func has(name: String) -> bool:
	return DECLARATIONS.has(name)


static func declaration(name: String) -> Dictionary:
	return DECLARATIONS.get(name, {}) as Dictionary


static func params_of(name: String) -> Dictionary:
	return declaration(name).get("params", {}) as Dictionary


static func role_of(name: String) -> String:
	return str(declaration(name).get("role", ""))


static func returns_of(name: String) -> String:
	return str(declaration(name).get("returns", ""))


static func is_attack_only(name: String) -> bool:
	return bool(declaration(name).get("attack_only", false))


## Runs an effect or a count. Arguments are already resolved and type-checked.
## Returns EffectContext.PENDING when the effect is waiting for a player's choice.
static func execute(name: String, context: EffectContext, args: Dictionary) -> Variant:
	var operations := context.operations
	match name:
		"flip_coins":
			var heads := 0
			for _i in maxi(int(args["count"]), 0):
				if operations.flip_coin():
					heads += 1
			return heads
		"attack_damage":
			return operations.deal_attack_damage(context, context.attack.damage * int(args["times"]) + int(args["plus"]))
		"direct_damage":
			return operations.deal_direct_damage(args["target"] as CardInPlay, int(args["amount"]))
		"discard_attached_energy_cards":
			return EnergyEffects.discard_energy_cards(context, args["target"] as CardInPlay, str(args["energy_type"]), int(args["count"]))
		"discard_all_attached_energy_cards":
			return EnergyEffects.discard_energy_cards(context, args["target"] as CardInPlay, EffectTypes.ANY_ENERGY, -1)
		"draw_cards":
			return operations.draw_cards(args["player"] as PlayerState, int(args["count"]))
		"count_damage_counters":
			return floori((args["target"] as CardInPlay).damage / 10.0)
		"count_attached_energy_cards":
			return EnergyEffects.matching_cards(args["target"] as CardInPlay, str(args["energy_type"])).size()
		"count_attached_energy_units":
			return EnergyEffects.count_units((args["target"] as CardInPlay).energy_pool(), str(args["energy_type"]))
		"count_unpaid_energy_units":
			return EnergyEffects.count_unpaid_units(context, str(args["energy_type"]))
		"count_benched":
			return (args["player"] as PlayerState).bench.size()
		"multiply":
			return int(args["a"]) * int(args["b"])
		"add":
			return int(args["a"]) + int(args["b"])
		"min":
			return mini(int(args["a"]), int(args["b"]))
		"at_least":
			return 1 if int(args["a"]) >= int(args["b"]) else 0
		"place_damage_counters":
			return operations.place_damage_counters(args["target"] as CardInPlay, int(args["count"]))
		"place_damage_counters_on_attack_damaged":
			var placed := 0
			for target in operations.damaged_by_attack():
				placed += operations.place_damage_counters(target, int(args["count"]))
			return placed
		"attach_from_discard_to_benched":
			var owner := args["player"] as PlayerState
			return CardMoves.attach_to_benched(context, owner, owner.discard, args["filter"] as Array, false)
		"attach_from_hand_to_benched":
			var holder := args["player"] as PlayerState
			return CardMoves.attach_to_benched(context, holder, holder.hand, args["filter"] as Array, true)
		"count_types_on_bench":
			var types: Array[String] = []
			for darkner in (args["player"] as PlayerState).bench:
				for type in darkner.card.types:
					if not types.has(type):
						types.append(type)
			return types.size()
		"choose_darkner":
			return EffectChoices.choose_darkner(context, args["player"] as PlayerState, args["chooser"] as PlayerState)
		"is_knocked_out":
			return 1 if (args["target"] as CardInPlay).remaining_hp() <= 0 else 0
		"take_extra_turn":
			operations.grant_extra_turn()
			return 1
		"attack_damage_to_benched":
			var dealt := 0
			for target in (args["player"] as PlayerState).bench.duplicate():
				dealt += operations.deal_benched_attack_damage(context, target, int(args["amount"]))
			return dealt
		"heal_benched":
			var healed := 0
			for target in (args["player"] as PlayerState).bench:
				healed += operations.heal(target, int(args["amount"]))
			return healed
		"pay_tp":
			return _pay_tp(context, args["player"] as PlayerState, int(args["amount"]))
		"shuffle_attached_energy_into_deck":
			return operations.shuffle_energy_into_deck(args["target"] as CardInPlay)
		"count_same_name_in_play":
			var target := args["target"] as CardInPlay
			var owner := operations.owner_of(target)
			var copies := 0
			if owner != null:
				for darkner: CardInPlay in [owner.active] + owner.bench:
					if darkner != null and darkner.card.name == target.card.name:
						copies += 1
			return copies
		"switch_in":
			return CardMoves.switch_in(context, args["player"] as PlayerState, args["chooser"] as PlayerState)
		"shuffle_hand_into_deck":
			return operations.shuffle_hand_into_deck(args["player"] as PlayerState)
		"search_deck":
			return CardMoves.search_deck(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]), CardMoves.TO_HAND, [])
		"search_deck_to_discard":
			return CardMoves.search_deck(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]), CardMoves.TO_DISCARD, [])
		"search_deck_to_bench":
			var searcher := args["player"] as PlayerState
			var room := context.engine.rules.bench_limit - searcher.bench.size()
			var excluded: Array[String] = []
			if int(args["exclude_same_name"]) == 1 and context.source != null:
				excluded.append(context.source.card.name)
			return CardMoves.search_deck(context, searcher, args["filter"] as Array, mini(int(args["count"]), room), CardMoves.TO_BENCH, excluded)
		"discard_from_hand":
			return CardMoves.discard_from_hand(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]))
		"discard_hand":
			return operations.discard_from_hand(args["player"] as PlayerState, (args["player"] as PlayerState).hand.duplicate())
		"put_hand_on_bottom_of_deck":
			return operations.put_hand_on_bottom_of_deck(args["player"] as PlayerState)
		"take_from_discard":
			return CardMoves.take_from_discard(context, args["player"] as PlayerState, args["filter"] as Array, int(args["count"]))
		"discard_energy_in_play":
			return EnergyEffects.discard_energy_in_play(context, args["player"] as PlayerState, args["chooser"] as PlayerState,
					args["filter"] as Array, int(args["count"]))
	push_error("AtomicEffects: '%s' is not an effect" % name)
	return null


static func check(name: String, context: EffectContext, args: Dictionary) -> bool:
	match name:
		"in_battle_zone":
			var target := args["target"] as CardInPlay
			var owner := context.operations.owner_of(target)
			return owner != null and owner.active == target
		"attack_not_used_last_turn":
			return context.attack == null or (args["player"] as PlayerState).attack_used_last_turn != context.attack.name
		"has_cards_in_hand":
			var in_hand := CardMoves.hand_without_card_played(context, args["player"] as PlayerState)
			return CardFilter.select(in_hand, args["filter"] as Array, []).size() >= int(args["count"])
		"has_room_on_field":
			return (args["player"] as PlayerState).bench.size() + int(args["count"]) <= context.engine.rules.bench_limit
		"not_first_turn":
			return (args["player"] as PlayerState).turns_started > 1
		"has_benched":
			return (args["player"] as PlayerState).bench.size() >= int(args["count"])
		"has_cards_in_deck":
			return (args["player"] as PlayerState).deck.size() >= int(args["count"])
		"has_cards_in_discard":
			var owner := args["player"] as PlayerState
			return CardFilter.select(owner.discard, args["filter"] as Array, []).size() >= int(args["count"])
		"has_energy_in_play":
			var side := args["player"] as PlayerState
			var found := 0
			for darkner: CardInPlay in [side.active] + side.bench:
				if darkner != null:
					found += CardFilter.select(darkner.attached_energy, args["filter"] as Array, []).size()
			return found >= int(args["count"])
		"has_attached_energy_cards":
			var target := args["target"] as CardInPlay
			return EnergyEffects.matching_cards(target, str(args["energy_type"])).size() >= int(args["count"])
	push_error("AtomicEffects: '%s' is not a check" % name)
	return false


## player chooses whether to spend amount TP, in quarters. Without enough TP nothing is asked
## and nothing is spent. Returns 1 when the TP was spent, 0 otherwise.
static func _pay_tp(context: EffectContext, player: PlayerState, amount: int) -> Variant:
	if not context.operations.can_spend_tp(player, amount):
		return 0
	if context.selection.is_empty():
		return context.ask(player, "Use %d%% TP?" % (amount * 25), [
			{"label": "Use %d%% TP" % (amount * 25), "value": 1},
			{"label": "Don't use TP", "value": 0},
		])
	if int(context.selection[0]) == 0:
		return 0
	context.operations.spend_tp(player, amount)
	return 1