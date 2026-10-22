class_name CardText
extends RefCounted
## BBCode description of a card. Shared by every way of inspecting a card: the hotseat
## tooltip now, the hover zoom and the right-click view later (Design Document 8.6).
##
## Every word shown comes from a vocabulary dictionary, never from internal names, so the
## same card can be described in Deltarune terms (the game) or Pokemon terms (legacy data).
## A new vocabulary is a new dictionary with the same keys.

const DELTARUNE := {
	"pokemon": "Darkner",
	"trainer": "ACT",
	"energy": "Energy",
	"stages": {CardData.STAGE_BASIC: "Basic", CardData.STAGE_BREAK: "Evolution"},
	"trainer_types": {
		CardData.TRAINER_ITEM: "Item",
		CardData.TRAINER_SUPPORTER: "Lightner",
		CardData.TRAINER_STADIUM: "Area",
		CardData.TRAINER_SPELL: "Spell",
	},
	"energy_kinds": {CardData.ENERGY_NORMAL: "Basic Energy", CardData.ENERGY_SPECIAL: "Special Energy"},
	"evolves_from": "Evolves from",
	"hp": "HP",
	"type": "Type",
	"weakness": "Weakness",
	"resistance": "Resistance",
	"retreat": "Flee",
	"cost": "Cost",
	"free": "free",
	"none": "none",
	"tp": "TP",
	"provides": "Provides",
	"in_play": "In play",
	"damage": "damage",
	"attached_energy": "Energy",
	"evolved_from": "Evolved from",
	"art": "Art",
}

const POKEMON := {
	"pokemon": "Pokémon",
	"trainer": "Trainer",
	"energy": "Energy",
	"stages": {CardData.STAGE_BASIC: "Basic", "Stage1": "Stage 1", "Stage2": "Stage 2", CardData.STAGE_BREAK: "BREAK"},
	"trainer_types": {
		CardData.TRAINER_ITEM: "Item",
		CardData.TRAINER_SUPPORTER: "Supporter",
		CardData.TRAINER_STADIUM: "Stadium",
		CardData.TRAINER_SPELL: "Spell",
	},
	"energy_kinds": {CardData.ENERGY_NORMAL: "Basic Energy", CardData.ENERGY_SPECIAL: "Special Energy"},
	"evolves_from": "Evolves from",
	"hp": "HP",
	"type": "Type",
	"weakness": "Weakness",
	"resistance": "Resistance",
	"retreat": "Retreat",
	"cost": "Cost",
	"free": "free",
	"none": "none",
	"tp": "TP",
	"provides": "Provides",
	"in_play": "In play",
	"damage": "damage",
	"attached_energy": "Energy",
	"evolved_from": "Evolved from",
	"art": "Illustrator",
}

const TP_PER_QUARTER := 25


static func describe(card: CardData, terms: Dictionary = DELTARUNE) -> String:
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % _escape(card.name))
	if card.is_pokemon():
		_describe_pokemon(card, terms, lines)
	elif card.is_trainer():
		_describe_trainer(card, terms, lines)
	elif card.is_energy():
		_describe_energy(card, terms, lines)
	if not card.artist.is_empty():
		lines.append("")
		lines.append("[color=gray]%s: %s[/color]" % [_term(terms, "art"), _escape(card.artist)])
	return "\n".join(lines)


## The printed card followed by its state on the board.
static func describe_in_play(in_play: CardInPlay, terms: Dictionary = DELTARUNE) -> String:
	var lines := PackedStringArray()
	lines.append(describe(in_play.card, terms))
	lines.append("")
	lines.append("[b]%s[/b]: %d/%d %s (%d %s)" % [
		_term(terms, "in_play"), in_play.remaining_hp(), in_play.card.hp, _term(terms, "hp"),
		in_play.damage, _term(terms, "damage"),
	])
	var energy := PackedStringArray()
	for card in in_play.attached_energy:
		energy.append(card.name)
	lines.append("%s: %s" % [_term(terms, "attached_energy"), ", ".join(energy) if not energy.is_empty() else _term(terms, "none")])
	if not in_play.evolved_from.is_empty():
		var below := PackedStringArray()
		for card in in_play.evolved_from:
			below.append(card.name)
		lines.append("%s: %s" % [_term(terms, "evolved_from"), ", ".join(below)])
	return "\n".join(lines)


static func _describe_pokemon(card: CardData, terms: Dictionary, lines: PackedStringArray) -> void:
	lines.append("%s · %s" % [_term(terms, "pokemon"), _lookup(terms, "stages", card.stage)])
	if not card.evolve_from.is_empty():
		lines.append("%s %s" % [_term(terms, "evolves_from"), _escape(card.evolve_from)])
	lines.append("%s %d · %s: %s" % [_term(terms, "hp"), card.hp, _term(terms, "type"), ", ".join(PackedStringArray(card.types))])
	lines.append("%s: %s · %s: %s · %s: %d" % [
		_term(terms, "weakness"), _modifier(card.weakness_types, card.weakness_modifier, terms),
		_term(terms, "resistance"), _modifier(card.resistance_types, card.resistance_modifier, terms),
		_term(terms, "retreat"), card.retreat_cost,
	])

	for power in card.powers:
		lines.append("")
		lines.append("[color=orange]%s[/color]  [b]%s[/b]" % [_escape(power.kind), _escape(power.name)])
		if not power.effect_text.is_empty():
			lines.append(_escape(power.effect_text))

	for attack in card.attacks:
		lines.append("")
		var damage := ""
		if attack.damage > 0 or not attack.damage_suffix.is_empty():
			damage = "  —  %d%s" % [attack.damage, attack.damage_suffix]
		lines.append("[b]%s[/b]%s" % [_escape(attack.name), damage])
		var cost := ", ".join(PackedStringArray(attack.cost)) if not attack.cost.is_empty() else _term(terms, "free")
		lines.append("%s: %s" % [_term(terms, "cost"), cost])
		if not attack.effect_text.is_empty():
			lines.append(_escape(attack.effect_text))


static func _describe_trainer(card: CardData, terms: Dictionary, lines: PackedStringArray) -> void:
	var header := _term(terms, "trainer")
	if not card.trainer_type.is_empty():
		header += " · %s" % _lookup(terms, "trainer_types", card.trainer_type)
	if card.trainer_type == CardData.TRAINER_SPELL:
		header += " · %d%% %s" % [card.tp_cost * TP_PER_QUARTER, _term(terms, "tp")]
	lines.append(header)
	if not card.effect_text.is_empty():
		lines.append("")
		lines.append(_escape(card.effect_text))


static func _describe_energy(card: CardData, terms: Dictionary, lines: PackedStringArray) -> void:
	lines.append(_lookup(terms, "energy_kinds", card.energy_kind) if not card.energy_kind.is_empty() else _term(terms, "energy"))
	lines.append("%s: %s" % [_term(terms, "provides"), ", ".join(PackedStringArray(card.provides))])
	if not card.effect_text.is_empty():
		lines.append("")
		lines.append(_escape(card.effect_text))


static func _modifier(types: Array[String], modifier: String, terms: Dictionary) -> String:
	if types.is_empty():
		return _term(terms, "none")
	return "%s %s" % [", ".join(PackedStringArray(types)), modifier]


## A word from the vocabulary. A missing key shows itself in brackets so the gap is visible.
static func _term(terms: Dictionary, key: String) -> String:
	if not terms.has(key):
		return "<%s>" % key
	return str(terms[key])


## A label from one of the vocabulary's tables. A value the table does not know is shown
## as stored, so new internal values never disappear from the text.
static func _lookup(terms: Dictionary, table: String, value: String) -> String:
	var entries: Variant = terms.get(table)
	if entries is Dictionary and (entries as Dictionary).has(value):
		return str((entries as Dictionary)[value])
	return value


## Card text is plain text: an opening bracket must not start a BBCode tag.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")