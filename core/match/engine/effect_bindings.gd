class_name EffectBindings
extends RefCounted
## How the engine finds and runs card effects: the binding of an attack, Ability or ACT card,
## the EffectContext it resolves in, whether its requirements hold, and the question it asks
## while suspended. Static functions of the engine's public state; they keep nothing, so they
## never hold the engine.


static func attack_binding(engine: MatchEngine, attack: AttackData) -> Dictionary:
	if engine.effects == null:
		return {}
	return engine.effects.binding_for(engine.current_player().active.card_with_attack(attack).id, EffectLibrary.SECTION_ATTACKS, attack.name)


static func power_binding(engine: MatchEngine, user: CardInPlay, power: PowerData) -> Dictionary:
	if engine.effects == null:
		return {}
	return engine.effects.binding_for(user.card_with_power(power).id, EffectLibrary.SECTION_POWERS, power.name)


static func trainer_binding(engine: MatchEngine, card: CardData) -> Dictionary:
	if engine.effects == null:
		return {}
	return engine.effects.binding_for(card.id, EffectLibrary.SECTION_TRAINER, card.name)


static func attack_context(engine: MatchEngine, attack: AttackData) -> EffectContext:
	var context := _context(engine, EffectContext.KIND_ATTACK)
	context.source = engine.current_player().active
	context.attack = attack
	return context


## The context of an Ability of user. kind is KIND_POWER when the player uses it and
## KIND_TRIGGER when something set it off.
static func power_context(engine: MatchEngine, user: CardInPlay, kind: String) -> EffectContext:
	var context := _context(engine, kind)
	context.source = user
	return context


## The context of a continuous Ability: its player is the Darkner's owner, whoever is taking
## the turn.
static func continuous_context(engine: MatchEngine, user: CardInPlay, owner_index: int) -> EffectContext:
	var context := _context(engine, EffectContext.KIND_CONTINUOUS)
	context.source = user
	context.player = engine.players[owner_index]
	context.opponent = engine.players[1 - owner_index]
	context.defender = context.opponent.active
	return context


static func trainer_context(engine: MatchEngine, card: CardData) -> EffectContext:
	var context := _context(engine, EffectContext.KIND_TRAINER)
	context.card = card
	return context


static func attack_requirements_met(engine: MatchEngine, attack: AttackData) -> bool:
	return _requirements_met(engine, attack_binding(engine, attack), attack_context(engine, attack))


## An activated Ability can be used when it has a binding and its requirements hold, which
## includes "it would do something" (Design Document 3.3 applies to Abilities too).
static func power_usable(engine: MatchEngine, user: CardInPlay, power: PowerData) -> bool:
	return _power_ready(engine, user, power, EffectLibrary.TIMING_ACTIVATED)


## The Abilities of a Darkner just played from the hand that its owner may use now, in printed
## order (EffectLibrary.TIMING_ON_PLAY).
static func on_play_powers(engine: MatchEngine, user: CardInPlay) -> Array[PowerData]:
	var ready: Array[PowerData] = []
	for power in user.powers():
		if _power_ready(engine, user, power, EffectLibrary.TIMING_ON_PLAY):
			ready.append(power)
	return ready


## Whether an Ability with this timing can be used now: it has a binding with that timing, its
## per-turn limit is not reached, and its requirements hold.
static func _power_ready(engine: MatchEngine, user: CardInPlay, power: PowerData, timing: String) -> bool:
	var binding := power_binding(engine, user, power)
	if binding.is_empty() or binding.get(EffectLibrary.TIMING_KEY) != timing:
		return false
	var limit := int(binding.get(EffectLibrary.PER_TURN_KEY, 0))
	if limit > 0 and int(engine.current_player().powers_used_this_turn.get(power.name, 0)) >= limit:
		return false
	return _requirements_met(engine, binding, power_context(engine, user, EffectContext.KIND_POWER))


## An Area's binding is its effect while in play, not when played, so it never stops the Area
## from being played.
static func trainer_requirements_met(engine: MatchEngine, card: CardData) -> bool:
	var binding := trainer_binding(engine, card)
	if binding.has(EffectLibrary.TIMING_KEY):
		return true
	return _requirements_met(engine, binding, trainer_context(engine, card))


## The context of an effect of the Area in play. subject is the Darkner a trigger is about, or
## null for an action.
static func area_context(engine: MatchEngine, subject: CardInPlay) -> EffectContext:
	var context := _context(engine, EffectContext.KIND_AREA)
	context.card = engine.stadium
	context.subject = subject
	return context


## The binding of the Area in play when it has this timing, or an empty Dictionary.
static func area_binding(engine: MatchEngine, timing: String) -> Dictionary:
	if engine.stadium == null:
		return {}
	var binding := trainer_binding(engine, engine.stadium)
	return binding if binding.get(EffectLibrary.TIMING_KEY) == timing else {}


## Whether the player taking the turn can use the action of the Area in play: it has one, its
## per-turn limit is not reached, and its requirements hold.
static func area_action_usable(engine: MatchEngine) -> bool:
	var binding := area_binding(engine, EffectLibrary.TIMING_AREA_ACTION)
	if binding.is_empty():
		return false
	var limit := int(binding.get(EffectLibrary.PER_TURN_KEY, 0))
	if limit > 0 and int(engine.current_player().powers_used_this_turn.get(engine.stadium.name, 0)) >= limit:
		return false
	return _requirements_met(engine, binding, area_context(engine, null))


## Runs a binding in its context. Returns null when the effect finished, or the question it is
## waiting on.
static func run(engine: MatchEngine, binding: Dictionary, context: EffectContext) -> PendingChoice:
	var resolver := EffectResolver.new(engine.effects, context)
	if resolver.run(str(binding["function"]), binding["args"] as Dictionary):
		return null
	return choice_for(resolver, context)


## Wraps the question a suspended effect is asking. The effect names who answers.
static func choice_for(resolver: EffectResolver, context: EffectContext) -> PendingChoice:
	var asked := context.choice
	var choice := PendingChoice.new(context.engine.players.find(asked["chooser"]), str(asked["kind"]),
			asked["details"] as Dictionary, asked["options"] as Array, PendingChoice.RESUME_EFFECT, {})
	choice.revealed.assign(asked["revealed"] as Array)
	choice.resolver = resolver
	choice.context = context
	return choice


## An effect with no binding has no requirements.
static func _requirements_met(engine: MatchEngine, binding: Dictionary, context: EffectContext) -> bool:
	if binding.is_empty():
		return true
	var resolver := EffectResolver.new(engine.effects, context)
	return resolver.requirements_met(str(binding["function"]), binding["args"] as Dictionary)


static func _context(engine: MatchEngine, kind: String) -> EffectContext:
	var context := EffectContext.new()
	context.engine = engine
	context.operations = engine.operations
	context.kind = kind
	context.defender = engine.opponent_player().active
	context.player = engine.current_player()
	context.opponent = engine.opponent_player()
	return context