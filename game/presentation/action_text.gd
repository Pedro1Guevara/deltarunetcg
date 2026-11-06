class_name ActionText
extends RefCounted
## The words a player reads for what they can do (Design Document 8.6): the label of each legal
## action, the prompt of the open question and the label of each of its options. The engine
## holds no words; this builds them from the data of a PlayerView, so a player only ever reads
## what their view shows. Option labels also word the answers kept in the log (EventText).
##
## Options come as the engine keeps them (CardData, CardInPlay) or as event data keeps them
## (card ids, Darkner refs with "hp_left"); both read the same.

## What the player reads for each card filter name (CardFilter).
const FILTERS := {
	CardFilter.BASIC_ENERGY: "basic Energy",
	CardFilter.POKEMON: "Darkner",
	CardFilter.BASIC_POKEMON: "non-Evolution Darkner",
	CardFilter.STADIUM: "Area",
	CardFilter.TRAINER: "ACT card",
	CardFilter.ANY: "any card",
}

static var _cards_by_database: Dictionary = {}


## The label of a legal action in view, as the player taking it reads it.
static func label(view: PlayerView, action: Dictionary, cards: CardDatabase) -> String:
	var me := view.me()
	match str(action["type"]):
		"bench":
			return "Put %s on the Field" % me.hand[int(action["hand_index"])].name
		"attach":
			var slot := int(action["slot"])
			return "Attach %s to %s (%s)" % [me.hand[int(action["hand_index"])].name, _in_play(me, slot).card.name, slot_name(slot)]
		"play_trainer":
			return trainer_label(me.hand[int(action["hand_index"])])
		"evolve":
			var slot := int(action["slot"])
			return "Evolve %s into %s (%s)" % [_in_play(me, slot).card.name, me.hand[int(action["hand_index"])].name, slot_name(slot)]
		"use_power":
			var slot := int(action["slot"])
			return "Use %s (%s, %s)" % [str(action["power"]), _in_play(me, slot).card.name, slot_name(slot)]
		"use_area":
			return "Use %s (Area)" % view.stadium.name
		"retreat":
			var slot := int(action["slot"])
			return "Flee %s for %s (%s)" % [me.active.card.name, me.bench[slot].card.name, slot_name(slot)]
		"attack":
			var attack := me.active.attacks()[int(action["attack_index"])]
			return "Attack: %s (%d)" % [attack.name, attack.damage]
		"end_turn":
			return "End turn"
		"choose":
			return option_label(view.choice_kind, view.choice_details, view.choice_options[int(action["option"])], view, cards)
	return str(action["type"])


## Playing an ACT card: "Play X (Item)", "Play X (Lightner)", "Play X (Area)", "Cast X (25% TP)".
## A Spell shows its printed TP cost, which is its cost while no card changes it.
static func trainer_label(card: CardData) -> String:
	match card.trainer_type:
		CardData.TRAINER_SUPPORTER:
			return "Play %s (Lightner)" % card.name
		CardData.TRAINER_STADIUM:
			return "Play %s (Area)" % card.name
		CardData.TRAINER_SPELL:
			return "Cast %s (%d%% TP)" % [card.name, card.tp_cost * 25]
	return "Play %s (Item)" % card.name


## The open question in view, worded for its chooser. Empty when no question is open to them.
static func prompt(view: PlayerView, cards: CardDatabase) -> String:
	if view.chooser != view.viewer:
		return ""
	var details := view.choice_details
	match view.choice_kind:
		PendingChoice.KIND_COIN_CALL:
			return "Call the coin flip: whoever wins goes first"
		PendingChoice.KIND_BATTLING_DARKNER:
			return "Choose your Battling Darkner"
		PendingChoice.KIND_SETUP_BENCH:
			return "Put Basic Darkners on the Field before the game starts"
		PendingChoice.KIND_MULLIGAN_DRAWS:
			var count := int(details["maximum"])
			return "Your opponent took %d more mulligan%s" % [count, _plural(count)]
		PendingChoice.KIND_PROMOTE:
			return "Choose a new Battling Darkner"
		PendingChoice.KIND_FLEE_PAYMENT:
			return "Choose the Energy to discard to flee %s" % view.me().active.card.name
		PendingChoice.KIND_USE_ABILITY:
			return "Use %s?" % str(details["power"])
		PendingChoice.KIND_PAY_TP:
			return "Use %d%% TP?" % (int(details["amount"]) * 25)
		PendingChoice.KIND_PICK_CARDS:
			var asked := _pick_prompt(details, cards)
			if int(details["maximum"]) >= 2:
				asked = "%s (%d/%d chosen)" % [asked, (details["picked"] as Array).size(), int(details["maximum"])]
			return asked
		PendingChoice.KIND_CHOOSE_DARKNER:
			match str(details["purpose"]):
				PendingChoice.PURPOSE_SWITCH_IN:
					return "Choose the Darkner to switch into the Battle Zone"
				PendingChoice.PURPOSE_ATTACH:
					return "Choose a Darkner on your Field to attach %s to" % _name(details["card"], cards)
			return "Choose one of %s Darkners" % ("your" if details["side"] == PendingChoice.SIDE_OWN else "your opponent's")
	return ""


static func _pick_prompt(details: Dictionary, cards: CardDatabase) -> String:
	match str(details.get("about", "")):
		PendingChoice.ABOUT_SEARCH_DECK:
			var asked := "Search your deck for %s" % filter_description(details["filter"] as Array)
			match str(details["destination"]):
				CardMoves.TO_DISCARD:
					asked += " to discard"
				CardMoves.TO_BENCH:
					asked += " to put onto your Field"
			var excluded := details["excluded"] as Array
			if not excluded.is_empty():
				asked += " (not %s)" % ", ".join(PackedStringArray(excluded))
			return asked
		PendingChoice.ABOUT_TAKE_FROM_DISCARD:
			var count := int(details["count"])
			return "Choose %s to put into your hand from your discard pile" % ("a card" if count == 1 else "%d cards" % count)
		PendingChoice.ABOUT_DISCARD_FROM_HAND:
			var count := int(details["count"])
			var filter := details["filter"] as Array
			var noun := "card" if filter.has(CardFilter.ANY) else filter_description(filter)
			return "Choose %s to discard from your hand" % (("a %s" % noun) if count == 1 else "%d %ss" % [count, noun])
		PendingChoice.ABOUT_ATTACH_FROM:
			return "Choose a card from your %s to attach" % ("hand" if details["zone"] == PendingChoice.ZONE_HAND else "discard pile")
		PendingChoice.ABOUT_DISCARD_ATTACHED:
			var count := int(details["count"])
			return "Choose %s to discard from %s" % ["an Energy card" if count == 1 else "%d Energy cards" % count, _name(details["darkner"], cards)]
		PendingChoice.ABOUT_DISCARD_IN_PLAY:
			var count := int(details["count"])
			var kind := filter_description(details["filter"] as Array)
			var noun := "%s attached to a Darkner" % kind if count == 1 else "%d %s attached to Darkners" % [count, kind]
			return "Choose %s to discard" % noun
	return "Choose"


## The label of an option of a question of this kind. view, when given, is the chooser's view
## (the Battling Darkner of a flee); the log words an answer without it.
static func option_label(kind: String, details: Dictionary, option: Dictionary, view: PlayerView, cards: CardDatabase) -> String:
	var value: Variant = option.get("value")
	match kind:
		PendingChoice.KIND_COIN_CALL:
			return "Heads" if bool(value) else "Tails"
		PendingChoice.KIND_BATTLING_DARKNER:
			return "Make %s the Battling Darkner" % _name(value, cards)
		PendingChoice.KIND_SETUP_BENCH:
			return "Finish placing Darkners" if value == null else "Put %s on the Field" % _name(value, cards)
		PendingChoice.KIND_MULLIGAN_DRAWS:
			var amount := int(value)
			return "Draw %d card%s for the opponent's mulligans" % [amount, _plural(amount)]
		PendingChoice.KIND_PROMOTE:
			var shown: Variant = option["shows"]
			return "Promote %s (%s, %d/%d HP)" % [_name(shown, cards), slot_name(int(value)), _hp_left(shown), _card(shown, cards).hp]
		PendingChoice.KIND_FLEE_PAYMENT:
			var names: Array[String] = []
			for energy: Variant in value as Array:
				names.append(_name(energy, cards))
			names.sort()
			return "Discard %s" % " + ".join(PackedStringArray(names))
		PendingChoice.KIND_USE_ABILITY:
			var power := str(details["power"])
			return "Use %s (%s)" % [power, _name(option["shows"], cards)] if bool(value) else "Don't use %s" % power
		PendingChoice.KIND_PAY_TP:
			return "Use %d%% TP" % (int(details["amount"]) * 25) if int(value) == 1 else "Don't use TP"
		PendingChoice.KIND_PICK_CARDS:
			return _pick_label(details, option, cards)
		PendingChoice.KIND_CHOOSE_DARKNER:
			var shown: Variant = option["shows"]
			var slot := int(value)
			match str(details["purpose"]):
				PendingChoice.PURPOSE_SWITCH_IN:
					return "Switch in %s (%s)" % [_name(shown, cards), slot_name(slot)]
				PendingChoice.PURPOSE_ATTACH:
					return "Attach %s to %s (%s)" % [_name(details["card"], cards), _name(shown, cards), slot_name(slot)]
			return "Choose %s (%s, %d/%d HP)" % [_name(shown, cards), slot_name(slot), _hp_left(shown), _card(shown, cards).hp]
	return str(value)


static func _pick_label(details: Dictionary, option: Dictionary, cards: CardDatabase) -> String:
	var verb := str(details["action"]).capitalize()
	if option.get("pick") == PendingChoice.PICK_CONFIRM:
		return "%s nothing" % verb if (details["picked"] as Array).is_empty() else "Confirm"
	var text := "%s %s" % [verb, _name(option["shows"], cards)]
	match str(details.get("about", "")):
		PendingChoice.ABOUT_DISCARD_ATTACHED:
			text += " from %s" % _name(details["darkner"], cards)
		PendingChoice.ABOUT_DISCARD_IN_PLAY:
			text += " from %s (%s)" % [_name(option["holder"], cards), slot_name(int(option["slot"]))]
	if int(option.get("copy", 0)) > 0:
		text += " #%d" % int(option["copy"])
	return ("Undo: %s" % text) if option.get("pick") == PendingChoice.PICK_UNDO else text


## "Battle Zone" for slot -1, "Field 1" and on for the Field.
static func slot_name(slot: int) -> String:
	return "Battle Zone" if slot == -1 else "Field %d" % (slot + 1)


## "basic Energy or Darkner".
static func filter_description(filters: Array) -> String:
	var words: Array[String] = []
	for name: Variant in filters:
		words.append(str(FILTERS.get(name, name)))
	return " or ".join(PackedStringArray(words))


## The card a value is about: a CardData, a CardInPlay, a card id or a Darkner ref.
static func card_of(value: Variant, cards: CardDatabase) -> CardData:
	return _card(value, cards)


static func _card(value: Variant, cards: CardDatabase) -> CardData:
	if value is CardData:
		return value as CardData
	if value is CardInPlay:
		return (value as CardInPlay).card
	if value is Dictionary:
		return _card(str((value as Dictionary).get("card", "")), cards)
	var id := str(value)
	var key := cards.get_instance_id()
	if not _cards_by_database.has(key):
		_cards_by_database[key] = {}
	var known := _cards_by_database[key] as Dictionary
	if not known.has(id):
		known[id] = cards.make(id) if cards.has_card(id) else null
	return known[id] as CardData


static func _name(value: Variant, cards: CardDatabase) -> String:
	var card := _card(value, cards)
	return "?" if card == null else card.name


static func _hp_left(value: Variant) -> int:
	if value is CardInPlay:
		return (value as CardInPlay).remaining_hp()
	if value is Dictionary:
		return int((value as Dictionary).get("hp_left", 0))
	return 0


static func _in_play(side: PlayerView.SideView, slot: int) -> CardInPlay:
	return side.active if slot == -1 else side.bench[slot]


static func _plural(count: int) -> String:
	return "" if count == 1 else "s"
