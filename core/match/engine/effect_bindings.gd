class_name EffectBindings
extends RefCounted
## How the engine finds and runs card effects: the binding of an attack, Ability or ACT card,
## the EffectContext it resolves in, whether its requirements hold, and the question it asks
## while suspended. Static functions of the engine's public state; they keep nothing, so they
## never hold the engine.


static func attack_binding(engine: MatchEngine, attack: AttackData) -> Dictionary:
	if engine.effects == null:
		return {}
	return engine.effects.binding_for(engine.current_player().active.card.id, EffectLibrary.SECTION_ATTACKS, attack.name)


static func power_binding(engine: MatchEngine, user: CardInPlay, power: PowerData) -> Dictionary:
	if engine.effects == null:
		return {}
	return engine.effects.binding_for(user.card.id, EffectLibrary.SECTION_POWERS, power.name)


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


static func trainer_context(engine: MatchEngine, card: CardData) -> EffectContext:
	var context := _context(engine, EffectContext.KIND_TRAINER)
	context.card = card
	return context


static func attack_requirements_met(engine: MatchEngine, attack: AttackData) -> bool:
	return _requirements_met(engine, attack_binding(engine, attack), attack_context(engine, attack))


## An activated Ability can be used when it has a binding and its requirements hold, which
## includes "it would do something" (Design Document 3.3 applies to Abilities too).
static func power_usable(engine: MatchEngine, user: CardInPlay, power: PowerData) -> bool:
	var binding := power_binding(engine, user, power)
	if binding.is_empty() or binding.get(EffectLibrary.TIMING_KEY) != EffectLibrary.TIMING_ACTIVATED:
		return false
	return _requirements_met(engine, binding, power_context(engine, user, EffectContext.KIND_POWER))


static func trainer_requirements_met(engine: MatchEngine, card: CardData) -> bool:
	return _requirements_met(engine, trainer_binding(engine, card), trainer_context(engine, card))


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
	var choice := PendingChoice.new(context.engine.players.find(asked["chooser"]), str(asked["prompt"]),
			asked["options"] as Array, PendingChoice.RESUME_EFFECT, {})
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