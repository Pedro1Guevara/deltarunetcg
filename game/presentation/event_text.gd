class_name EventText
extends RefCounted
## The log a player reads (Design Document 8.4): one line per MatchEvent, built from its data.
## Lines that belong to an action already logged (its damage, its draws, its coin flips) are
## indented. Some events have no line, such as a turn's draw, which the board shows.

const INDENT := "  "


## The lines of these events, in order, leaving out events that have none.
static func lines(events: Array[MatchEvent], cards: CardDatabase) -> PackedStringArray:
	var text := PackedStringArray()
	for event in events:
		var line_text := line(event, cards)
		if not line_text.is_empty():
			text.append(line_text)
	return text


## The line of one event, or "" when it has none.
static func line(event: MatchEvent, cards: CardDatabase) -> String:
	var data := event.data
	var who := "Player %d" % (event.player + 1)
	match event.type:
		MatchEvent.FIRST_PLAYER:
			return "Player %d calls %s. Coin flip: %s. Player %d goes first" % [int(data["caller"]) + 1, _coin(bool(data["called_heads"])),
					_coin(bool(data["heads"])), int(data["first"]) + 1]
		MatchEvent.MULLIGAN:
			return "%s mulligan (attempt %d)" % [who, int(data["attempt"])]
		MatchEvent.BATTLING_DARKNER_PLACED:
			return "%s starts with %s" % [who, _name(data["darkner"], cards)]
		MatchEvent.SETUP_BENCH_PLACED:
			return "%s puts %s on the Field during setup" % [who, _name(data["darkner"], cards)]
		MatchEvent.MULLIGAN_DRAWS:
			var count := int(data["count"])
			return "%s draws %d card%s for mulligans" % [who, count, _plural(count)]
		MatchEvent.TURN_STARTED:
			return "--- Turn %d: %s ---" % [int(data["turn"]), who]
		MatchEvent.TURN_ENDED:
			return "%s ends the turn" % who
		MatchEvent.EXTRA_TURN:
			return "%s takes another turn" % who
		MatchEvent.TP_RECOVERED:
			return "%s recovers TP: %d%%" % [who, int(data["tp"]) * 25]
		MatchEvent.DECK_OUT:
			if bool(data["loses"]):
				return "%s cannot draw and loses the round" % who
			return "%s cannot draw: the opponent takes a Mercy Card" % who
		MatchEvent.WON:
			if bool(data["after_deck_out"]):
				return "Player %d took the last Mercy Card and wins" % (int(data["winner"]) + 1)
			return "Player %d wins" % (int(data["winner"]) + 1)
		MatchEvent.SUDDEN_DEATH:
			return "Both players win at the same time: Sudden Death"
		MatchEvent.SPARED:
			var extra := int(data["extra_draws"])
			return "%s spares the opponent, who draws %d extra card%s next round" % [who, extra, _plural(extra)]
		MatchEvent.FIGHT_CHOSEN:
			return "%s chooses to Fight: the next knockout decides the round" % who
		MatchEvent.FIGHT_ENDED:
			if bool(data["won"]):
				return "%s wins the Fight" % who
			var extra := int(data["extra_draws"])
			return "%s loses the Fight; the opponent draws %d extra card%s next round" % [who, extra, _plural(extra)]
		MatchEvent.EVOLVED:
			return "%s evolves %s into %s" % [who, _name(data["from"], cards), _name(data["into"], cards)]
		MatchEvent.ENERGY_ATTACHED:
			if not bool(data["by_effect"]):
				return "%s attaches %s to %s" % [who, _name(data["card"], cards), _name(data["darkner"], cards)]
			var pile := "discard pile" if data["from"] == MatchEvent.ZONE_DISCARD else "hand"
			return INDENT + "%s attaches %s from their %s to %s" % [who, _name(data["card"], cards), pile, _name(data["darkner"], cards)]
		MatchEvent.TRAINER_PLAYED:
			match str(data["trainer_type"]):
				CardData.TRAINER_SPELL:
					return "%s casts %s" % [who, _name(data["card"], cards)]
				CardData.TRAINER_STADIUM:
					return "%s puts %s into play" % [who, _name(data["card"], cards)]
			return "%s plays %s" % [who, _name(data["card"], cards)]
		MatchEvent.AREA_REPLACED:
			return "%s is discarded" % _name(data["card"], cards)
		MatchEvent.AREA_USED:
			return "%s uses %s" % [who, _name(data["card"], cards)]
		MatchEvent.RETREATED:
			return "%s retreats %s for %s" % [who, _name(data["from"], cards), _name(data["to"], cards)]
		MatchEvent.POWER_USED:
			if data["timing"] == EffectLibrary.TIMING_ON_ATTACK_DAMAGE:
				return "%s: %s" % [_name(data["darkner"], cards), str(data["power"])]
			return "%s uses %s" % [_name(data["darkner"], cards), str(data["power"])]
		MatchEvent.ATTACK_USED:
			return "%s uses %s" % [_name(data["darkner"], cards), str(data["attack"])]
		MatchEvent.AREA_TRIGGERED:
			return "%s: %s" % [_name(data["card"], cards), _name(data["darkner"], cards)]
		MatchEvent.EFFECT_MISSING:
			return INDENT + "[effect not implemented]"
		MatchEvent.CHOICE_ANSWERED:
			var answer := ActionText.option_label(str(data["kind"]), data["details"] as Dictionary, data["option"] as Dictionary, null, cards)
			return INDENT + "%s chooses: %s" % [who, answer]
		MatchEvent.DAMAGE:
			var amount := int(data["amount"])
			var target := _name(data["darkner"], cards)
			var hp := "(%d/%d HP)" % [int(data["hp_left"]), _card(data["darkner"], cards).hp]
			match str(data["kind"]):
				MatchOperations.DAMAGE_ATTACK:
					return INDENT + "%d damage to %s %s" % [amount, target, hp]
				MatchOperations.DAMAGE_COUNTERS:
					var counters := amount / 10
					return INDENT + "%d damage counter%s on %s %s" % [counters, _plural(counters), target, hp]
			return INDENT + "%s takes %d damage %s" % [target, amount, hp]
		MatchEvent.DAMAGE_PREVENTED:
			return INDENT + "%s prevents the damage to %s" % [str(data["by"]), _name(data["darkner"], cards)]
		MatchEvent.HEALED:
			return INDENT + "%s heals %d damage (%d/%d HP)" % [_name(data["darkner"], cards), int(data["amount"]), int(data["hp_left"]),
					_card(data["darkner"], cards).hp]
		MatchEvent.TP_SPENT:
			return INDENT + "%s uses %d%% TP (%d%% left)" % [who, int(data["amount"]) * 25, int(data["tp"]) * 25]
		MatchEvent.ENERGY_SHUFFLED_INTO_DECK:
			var count := int(data["count"])
			return INDENT + "%s shuffles %d Energy card%s into the deck" % [_name(data["darkner"], cards), count, _plural(count)]
		MatchEvent.ENERGY_DISCARDED:
			return INDENT + "%s discards %s" % [_name(data["darkner"], cards), _name(data["card"], cards)]
		MatchEvent.SWITCHED:
			return INDENT + "%s switches %s into the Battle Zone; %s goes to the Field" % [who, _name(data["in"], cards), _name(data["out"], cards)]
		MatchEvent.COIN_FLIP:
			return INDENT + "Coin flip: %s" % _coin(bool(data["heads"]))
		MatchEvent.CARD_MOVED:
			return INDENT + _moved(who, data, cards)
		MatchEvent.PUT_ON_FIELD:
			if data["from"] == MatchEvent.ZONE_DECK:
				return INDENT + "%s puts %s from their deck onto the Field" % [who, _name(data["darkner"], cards)]
			return "%s puts %s on the Field" % [who, _name(data["darkner"], cards)]
		MatchEvent.NOTHING_FOUND:
			return INDENT + "%s finds nothing" % who
		MatchEvent.NOTHING_DISCARDED:
			return INDENT + "%s discards nothing" % who
		MatchEvent.HAND_SHUFFLED_INTO_DECK:
			var count := int(data["count"])
			return INDENT + "%s shuffles %d card%s from their hand into their deck" % [who, count, _plural(count)]
		MatchEvent.HAND_TO_BOTTOM_OF_DECK:
			var count := int(data["count"])
			return INDENT + "%s puts %d card%s from their hand on the bottom of their deck" % [who, count, _plural(count)]
		MatchEvent.DECK_SHUFFLED:
			return INDENT + "%s shuffles their deck" % who
		MatchEvent.DREW:
			if bool(data["extra"]):
				var extra := int(data["count"])
				return "%s draws %d extra card%s" % [who, extra, _plural(extra)]
			if bool(data["at_turn_start"]):
				return ""
			var count := int(data["count"])
			return INDENT + "%s draws %d card%s" % [who, count, _plural(count)]
		MatchEvent.KNOCKED_OUT:
			return "%s is knocked out" % _name(data["darkner"], cards)
		MatchEvent.PRIZE_TAKEN:
			return "%s takes a Mercy Card (%d left)" % [who, int(data["left"])]
		MatchEvent.PROMOTED:
			return "%s promotes %s" % [who, _name(data["darkner"], cards)]
		MatchEvent.EFFECT_WARNING:
			return str(data["message"])
	return ""


static func _moved(who: String, data: Dictionary, cards: CardDatabase) -> String:
	var from := str(data["from"])
	var to := str(data["to"])
	if not data.has("card"):
		return "%s puts a card from their %s into their %s" % [who, from, to]
	var card := _name(data["card"], cards)
	if to == MatchEvent.ZONE_DISCARD:
		return "%s discards %s from their %s" % [who, card, from]
	var pile := "discard pile" if from == MatchEvent.ZONE_DISCARD else from
	return "%s puts %s from their %s into their %s" % [who, card, pile, to]


static func _name(value: Variant, cards: CardDatabase) -> String:
	var card := _card(value, cards)
	return "?" if card == null else card.name


static func _card(value: Variant, cards: CardDatabase) -> CardData:
	return ActionText.card_of(value, cards)


static func _coin(heads: bool) -> String:
	return "heads" if heads else "tails"


static func _plural(count: int) -> String:
	return "" if count == 1 else "s"
