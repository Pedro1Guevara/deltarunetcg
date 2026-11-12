class_name MatchEvent
extends RefCounted
## One thing that happened in a round, as data (Design Document 8.4): what a board, a log or an
## animation shows, and what a player is allowed to know of it. The engine writes events as
## the round goes (MatchLog); each player reads them through MatchEngine.events_for(),
## where a private event shows its hidden version to the other player, or nothing.
##
## data holds card ids (never CardData), Darkners as darkner refs ({"side", "slot", "card"}, as
## they stood when it happened; slot -1 is the Battle Zone) and numbers. What each type holds
## is listed with its constant.

## Every player sees the whole event.
const PUBLIC := "public"
## The player it is about sees data; the other sees hidden_data.
const PRIVATE := "private"
## Only the player it is about sees it at all.
const SECRET := "secret"

## Zones, for card_moved.
const ZONE_DECK := "deck"
const ZONE_HAND := "hand"
const ZONE_DISCARD := "discard"
const ZONE_FIELD := "field"
const ZONE_PRIZES := "prizes"

## Setup. first_player: {"caller", "called_heads", "heads", "first"}. mulligan: {"attempt"}.
## battling_darkner_placed / setup_bench_placed: {"darkner"}. mulligan_draws: {"count"}, private
## {"cards"}.
const FIRST_PLAYER := "first_player"
const MULLIGAN := "mulligan"
const BATTLING_DARKNER_PLACED := "battling_darkner_placed"
const SETUP_BENCH_PLACED := "setup_bench_placed"
const MULLIGAN_DRAWS := "mulligan_draws"
## Turns. turn_started: {"turn"}. turn_ended: {}. extra_turn: {}. tp_recovered: {"tp"}.
## deck_out: {"loses": bool}.
const TURN_STARTED := "turn_started"
const TURN_ENDED := "turn_ended"
const EXTRA_TURN := "extra_turn"
const TP_RECOVERED := "tp_recovered"
const DECK_OUT := "deck_out"
## Actions. evolved: {"darkner", "from", "into"}. energy_attached: {"card", "darkner", "from":
## a zone, "by_effect": false for the turn's attachment}. trainer_played: {"card", "trainer_type"}. area_replaced: {"card", "owner"}.
## area_used: {"card"}. retreated: {"from", "to", "discarded": card ids}. power_used:
## {"darkner", "power", "timing"}. attack_used: {"darkner", "attack"}. area_triggered: {"card",
## "darkner"}. effect_missing: {}. choice_answered (secret): {"kind", "index", "details",
## "option"}, the question's details and the option picked as data (MatchLog.as_data()).
const EVOLVED := "evolved"
const ENERGY_ATTACHED := "energy_attached"
const TRAINER_PLAYED := "trainer_played"
const AREA_REPLACED := "area_replaced"
const AREA_USED := "area_used"
const RETREATED := "retreated"
const POWER_USED := "power_used"
const ATTACK_USED := "attack_used"
const AREA_TRIGGERED := "area_triggered"
const EFFECT_MISSING := "effect_missing"
const CHOICE_ANSWERED := "choice_answered"
## Effects. damage: {"darkner", "amount", "kind": MatchOperations.DAMAGE_*, "hp_left"}.
## damage_prevented: {"darkner", "by": the Ability's name}. healed: {"darkner", "amount", "hp_left"}.
## tp_spent: {"amount", "tp"}. energy_discarded: {"darkner", "card"}. energy_shuffled_into_deck:
## {"darkner", "count"}. switched: {"in", "out"}. coin_flip: {"heads": bool}.
## darkner_shuffled_into_deck: {"darkner", "count": cards that went into the deck, the Darkner's
## own included}. darkner_returned_to_hand: {"darkner", "count": cards that went to the hand,
## "discarded": attached cards that went to the discard pile}.
const DAMAGE := "damage"
const DAMAGE_PREVENTED := "damage_prevented"
const HEALED := "healed"
const TP_SPENT := "tp_spent"
const ENERGY_DISCARDED := "energy_discarded"
const ENERGY_SHUFFLED_INTO_DECK := "energy_shuffled_into_deck"
const DARKNER_SHUFFLED_INTO_DECK := "darkner_shuffled_into_deck"
const DARKNER_RETURNED_TO_HAND := "darkner_returned_to_hand"
const SWITCHED := "switched"
const COIN_FLIP := "coin_flip"
## Cards. card_moved: {"card", "from", "to"} with zones; a card taken from the deck into the hand
## is private when the search could find any card (hidden {"from", "to"}). put_on_field:
## {"darkner", "from"}. nothing_found: {}. nothing_discarded: {}. hand_shuffled_into_deck /
## hand_to_bottom_of_deck: {"count"}. deck_shuffled: {}. drew: {"count", "at_turn_start",
## "extra": true for the extra cards of the first turn after a Spare or a Fight}, private {"cards"}.
const CARD_MOVED := "card_moved"
const PUT_ON_FIELD := "put_on_field"
const NOTHING_FOUND := "nothing_found"
const NOTHING_DISCARDED := "nothing_discarded"
const HAND_SHUFFLED_INTO_DECK := "hand_shuffled_into_deck"
const HAND_TO_BOTTOM_OF_DECK := "hand_to_bottom_of_deck"
const DECK_SHUFFLED := "deck_shuffled"
const DREW := "drew"
## Knockouts. knocked_out: {"darkner"}. prize_taken: {"left", "slot": the position in the pile
## it was taken from, 0 first}, private {"card"}. promoted:
## {"darkner"}. won: {"winner", "after_deck_out": true when the legacy deck-out rule gave the
## last Mercy Card}. sudden_death: {}.
## Spare and Fight (Design Document 4.5), about the player who took their last Mercy Card.
## spared: {"extra_draws": the opponent's extra cards next round}. fight_chosen: {}.
## fight_ended: {"won": bool, "extra_draws": the opponent's extra cards next round, 0 when won}.
const KNOCKED_OUT := "knocked_out"
const PRIZE_TAKEN := "prize_taken"
const PROMOTED := "promoted"
const WON := "won"
const SUDDEN_DEATH := "sudden_death"
const SPARED := "spared"
const FIGHT_CHOSEN := "fight_chosen"
const FIGHT_ENDED := "fight_ended"
## An effect's data could not be used as written (EffectResolver). {"message"}.
const EFFECT_WARNING := "effect_warning"

## Its place in the round, from 0.
var index: int = 0
var type: String = ""
## The player the event is about, or -1 when it is about nobody in particular.
var player: int = -1
var visibility: String = PUBLIC
var data: Dictionary = {}
## What the other player sees of a private event.
var hidden_data: Dictionary = {}


## The event as viewer sees it: itself, its hidden version, or null when it is not theirs to see.
func for_viewer(viewer: int) -> MatchEvent:
	if visibility == PUBLIC or viewer == player:
		return copy()
	if visibility == SECRET:
		return null
	var hidden := copy()
	hidden.data = hidden_data.duplicate(true)
	hidden.visibility = PUBLIC
	hidden.hidden_data = {}
	return hidden


func copy() -> MatchEvent:
	var event := MatchEvent.new()
	event.index = index
	event.type = type
	event.player = player
	event.visibility = visibility
	event.data = data.duplicate(true)
	event.hidden_data = hidden_data.duplicate(true)
	return event
