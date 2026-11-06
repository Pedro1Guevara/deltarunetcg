class_name EffectContext
extends RefCounted
## What a resolving effect can see: the engine, the context values of Design Document 7.3,
## and the player's choice in progress (7.6).

## The changes the effect may make to the round. Held strongly: it holds no reference back.
var operations: MatchOperations

const KIND_ATTACK := "attack"
const KIND_POWER := "power"
const KIND_TRAINER := "trainer"
## An Ability that resolved by itself, set off by something that happened (its timing).
const KIND_TRIGGER := "trigger"
## An Ability that applies while its condition holds, read through ContinuousEffects.
const KIND_CONTINUOUS := "continuous"
## An effect of the Area in play: an action it gives the player taking the turn, or a trigger.
const KIND_AREA := "area"

## Returned by an atomic effect that needs a player's choice before it can finish.
const PENDING := "__pending_choice__"

## The engine resolving the effect. Held weakly: the engine keeps this context alive through
## its pending choice, and a strong reference back would keep both alive after the round.
var engine: MatchEngine:
	get:
		return _engine.get_ref() as MatchEngine
	set(value):
		_engine = weakref(value)
var kind: String = KIND_ATTACK
## The Pokemon whose attack or Power is resolving. Null for Trainers.
var source: CardInPlay
var defender: CardInPlay
var player: PlayerState
var opponent: PlayerState
## The Darkner a triggered effect is about ($subject), or null.
var subject: CardInPlay
## The attack being resolved. Null unless kind is attack.
var attack: AttackData

## The Trainercard being played. Null unless kind is trainer.
var card: CardData

var _engine: WeakRef = null

## The open question, or empty: {"chooser": PlayerState, "kind", "details", "options",
## "revealed"} (PendingChoice).
var choice: Dictionary = {}
## Answers given so far to the step currently resolving. Cleared when the step finishes.
var selection: Array = []


func value_of(ref_name: String) -> Variant:
	match ref_name:
		EffectTypes.SELF:
			return source
		EffectTypes.SUBJECT:
			return subject
		EffectTypes.DEFENDER:
			return defender
		EffectTypes.PLAYER_REF:
			return player
		EffectTypes.OPPONENT:
			return opponent
	return null


func is_waiting() -> bool:
	return not choice.is_empty()


## Suspends the effect until chooser answers. The effect decides who that is: usually its
## own player, but some effects make the opponent choose.
## kind and details say what the question is about (PendingChoice.KIND_).
func ask(chooser: PlayerState, kind: String, details: Dictionary, options: Array) -> String:
	choice = {"chooser": chooser, "kind": kind, "details": details, "options": options, "revealed": []}
	return PENDING


## Like ask(), and shows cards to the chooser while they answer, such as their deck during a
## search.
func ask_showing(chooser: PlayerState, kind: String, details: Dictionary, options: Array,
		shown: Array[CardData]) -> String:
	choice = {"chooser": chooser, "kind": kind, "details": details, "options": options, "revealed": shown.duplicate()}
	return PENDING