class_name PendingChoice
extends RefCounted
## The one question a round can be waiting on (Design Document 8.4). While it is open,
## answering it is the only legal action. The chooser is explicit because it is not always the
## player taking the turn: a knocked out player promotes, and some effects ask the opponent.

## What the engine does with the answer.
const RESUME_SETUP := "setup"
const RESUME_PROMOTE := "promote"
const RESUME_RETREAT := "retreat"
const RESUME_EFFECT := "effect"
const RESUME_ON_PLAY := "on_play"
const RESUME_SPARE_FIGHT := "spare_fight"
const RESUME_TAKE_PRIZE := "take_prize"

## What the question is about, as data: the engine holds no words (Design Document 8.4). The
## kind, its details and its options are all a player needs to answer it, and all the game
## needs to word it (game/presentation). details carries what each kind needs; option values
## are listed per kind. An option is {"value"} and, for some kinds, "shows" (the card or
## Darkner it is about), "pick" and "copy" (pick_cards) or "holder" and "slot" (an Energy in
## play).
## coin_call: values true (heads) and false. details {}.
const KIND_COIN_CALL := "coin_call"
## battling_darkner: values the Basic Darkner cards in hand. details {}.
const KIND_BATTLING_DARKNER := "battling_darkner"
## setup_bench: values Basic Darkner cards in hand, and null to finish. details {}.
const KIND_SETUP_BENCH := "setup_bench"
## mulligan_draws: values how many cards to draw, an int. details {"maximum": int}.
const KIND_MULLIGAN_DRAWS := "mulligan_draws"
## promote: values Field slots. details {}.
const KIND_PROMOTE := "promote"
## flee_payment: values the Energy cards to discard, an Array. details {}: the Battling
## Darkner flees.
const KIND_FLEE_PAYMENT := "flee_payment"
## use_ability: values true and false. details {"power": the Ability's name}.
const KIND_USE_ABILITY := "use_ability"
## pay_tp: values 1 (pay) and 0. details {"amount": quarters}.
const KIND_PAY_TP := "pay_tp"
## pick_cards: one card at a time, undone and confirmed (EffectChoices.choose_several()).
## Each option has "pick": PICK_ADD, PICK_UNDO or PICK_CONFIRM, and "copy": which copy of a
## card it is (1, 2...) when the same card is offered more than once, 0 otherwise; values are
## the cards, and EffectChoices.CONFIRM. details {"minimum", "maximum": int, "picked": Array of
## cards, "zone": a ZONE_ constant, "action": what happens to them ("take", "discard", "put",
## "attach"), "about": an ABOUT_ constant} and what that ABOUT_ lists.
const KIND_PICK_CARDS := "pick_cards"
## choose_darkner: values slots, -1 for the Battle Zone; each option shows its Darkner.
## details {"side": SIDE_OWN or SIDE_OPPONENT, "purpose": PURPOSE_SWITCH_IN, PURPOSE_ATTACH
## (with "card": the Energy's card id) or PURPOSE_TARGET}.
const KIND_CHOOSE_DARKNER := "choose_darkner"
## spare_fight: the player who took their last Mercy Card Spares (wins the round) or Fights
## (Design Document 4.5). Values SPARE and FIGHT. details {"extra_draws": the cards the opponent
## draws next round if spared}.
const KIND_SPARE_FIGHT := "spare_fight"
## take_prize: the player who knocked out a Darkner picks one of their face-down Mercy Cards.
## Values are positions in the pile, 0 first; options show no card. details {"left": cards in
## the pile, "to_take": how many they still take now, this one included}.
const KIND_TAKE_PRIZE := "take_prize"
const SPARE := "spare"
const FIGHT := "fight"

const PICK_ADD := "add"
const PICK_UNDO := "undo"
const PICK_CONFIRM := "confirm"
const ZONE_DECK := "deck"
const ZONE_HAND := "hand"
const ZONE_DISCARD := "discard"
const ZONE_IN_PLAY := "in_play"
const SIDE_OWN := "own"
const SIDE_OPPONENT := "opponent"
const PURPOSE_SWITCH_IN := "switch_in"
const PURPOSE_ATTACH := "attach"
const PURPOSE_TARGET := "target"
## Which pick_cards question it is. search_deck: {"filter", "destination": CardMoves.TO_,
## "excluded": names}. take_from_discard: {"count"}. discard_from_hand: {"count", "filter"}.
## attach_from: {} (zone says from where). discard_attached: {"count", "darkner": card id of the
## Darkner they are attached to}. discard_in_play: {"count", "filter"}; each option has
## "holder" (its Darkner) and "slot".
const ABOUT_SEARCH_DECK := "search_deck"
const ABOUT_TAKE_FROM_DISCARD := "take_from_discard"
const ABOUT_DISCARD_FROM_HAND := "discard_from_hand"
const ABOUT_ATTACH_FROM := "attach_from"
const ABOUT_DISCARD_ATTACHED := "discard_attached"
const ABOUT_DISCARD_IN_PLAY := "discard_in_play"

## Index of the player who answers.
var chooser: int
## One of the KIND_ constants, and what that kind needs to know.
var kind: String
var details: Dictionary
## [{"value": Variant, ...}], one per legal answer (see the kinds above).
var options: Array
## One of the RESUME_ constants.
var resume: String
## Values the resume step needs, such as {"slot": int} for a flee.
var data: Dictionary
## Cards shown to the chooser while they answer, such as their deck during a search, in the
## order the effect gives them. Empty for most choices.
var revealed: Array[CardData] = []
## The suspended effect. Set only when resume is RESUME_EFFECT.
var resolver: EffectResolver = null
var context: EffectContext = null


func _init(answered_by: int, question_kind: String, question_details: Dictionary, answers: Array,
		resume_with: String, resume_data: Dictionary) -> void:
	chooser = answered_by
	kind = question_kind
	details = question_details
	options = answers
	resume = resume_with
	data = resume_data


## The option the player picked, by index in options.
func option(index: int) -> Dictionary:
	return options[index] as Dictionary