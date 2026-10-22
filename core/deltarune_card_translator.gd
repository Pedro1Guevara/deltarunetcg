class_name DeltaruneCardTranslator
extends CardParser
## Converts cards written in the Deltarune schema (Design Document 6.2) into CardData,
## translating every value into the engine's Pokemon vocabulary (Design Document 6.3).
## Pure logic: no file access.
##
## A value that is not in one of the dictionaries below is an error and the card does not
## load. Nothing is guessed.

const CATEGORY_DARKNER := "darkner"
const CATEGORY_ACT := "act"
const CATEGORY_ENERGY := "energy"

const CATEGORIES := {
	CATEGORY_DARKNER: CardData.CATEGORY_POKEMON,
	CATEGORY_ACT: CardData.CATEGORY_TRAINER,
	CATEGORY_ENERGY: CardData.CATEGORY_ENERGY,
}
const STAGES := {
	"basic": CardData.STAGE_BASIC,
	"evolution": CardData.STAGE_BREAK,
}
const TRAINER_TYPES := {
	"item": CardData.TRAINER_ITEM,
	"lightner": CardData.TRAINER_SUPPORTER,
	"area": CardData.TRAINER_STADIUM,
	"spell": CardData.TRAINER_SPELL,
}
const ENERGY_KINDS := {
	"basic": CardData.ENERGY_NORMAL,
	"special": CardData.ENERGY_SPECIAL,
}
const ORIENTATIONS := [CardData.ORIENTATION_PORTRAIT, CardData.ORIENTATION_LANDSCAPE]

## Every type a card may name. Colorless is valid in every type field: which cards use it is
## a design choice, not a rule the translator enforces.
const TYPES := CardTypes.DELTARUNE + [CardTypes.COLORLESS]
const DAMAGE_SUFFIXES := ["", "+", "x"]

# Filled here so the engine keeps reading it per card.
const WEAKNESS_MODIFIER := "+20"
const RESISTANCE_MODIFIER := "-20"
const ABILITY_KIND := "Ability"
const MAX_TP_COST := 4

const COMMON_FIELDS := ["id", "name", "category", "artist", "image", "orientation"]
const FIELDS := {
	CATEGORY_DARKNER: ["stage", "evolves_from", "hp", "types", "weakness_types", "resistance_types", "flee_cost", "attacks", "abilities"],
	CATEGORY_ACT: ["subtype", "tp_cost", "text"],
	CATEGORY_ENERGY: ["energy_kind", "provides", "text"],
}
const ATTACK_FIELDS := ["name", "cost", "damage", "damage_suffix", "text"]
const ABILITY_FIELDS := ["name", "text"]


func parse(raw: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = str(raw.get("id", ""))
	if card.id.is_empty():
		errors.append("card without id")
		return null

	var error_count := errors.size()
	card.name = _required_string(raw, "name", card.id)
	card.artist = str(raw.get("artist", ""))
	card.image_url = str(raw.get("image", ""))
	card.orientation = _required_string(raw, "orientation", card.id)
	if not card.orientation.is_empty() and not ORIENTATIONS.has(card.orientation):
		errors.append("%s: unknown orientation '%s'" % [card.id, card.orientation])

	var category := _required_string(raw, "category", card.id)
	if not category.is_empty() and not CATEGORIES.has(category):
		errors.append("%s: unknown category '%s'" % [card.id, category])
		return null
	card.category = str(CATEGORIES.get(category, ""))
	_check_fields(raw, COMMON_FIELDS + (FIELDS.get(category, []) as Array), card.id, "card")

	match category:
		CATEGORY_DARKNER:
			_translate_darkner(raw, card)
		CATEGORY_ACT:
			_translate_act(raw, card)
		CATEGORY_ENERGY:
			_translate_energy(raw, card)

	return card if errors.size() == error_count else null


func _translate_darkner(raw: Dictionary, card: CardData) -> void:
	card.stage = _lookup(STAGES, _required_string(raw, "stage", card.id), card.id, "stage")
	card.evolve_from = str(raw.get("evolves_from", ""))
	if card.stage == CardData.STAGE_BREAK and card.evolve_from.is_empty():
		errors.append("%s: evolution without evolves_from" % card.id)
	elif card.stage == CardData.STAGE_BASIC and not card.evolve_from.is_empty():
		errors.append("%s: basic Darkner with evolves_from '%s'" % [card.id, card.evolve_from])

	card.hp = _int(raw, "hp", card.id, 1, -1)

	card.types.assign(_types(raw.get("types"), card.id, "types"))
	if card.types.is_empty():
		errors.append("%s: Darkner without types" % card.id)

	# Evolutions print no Weakness or Resistance: they inherit them (Design Document 3.2).
	card.weakness_types.assign(_types(raw.get("weakness_types"), card.id, "weakness_types"))
	if not card.weakness_types.is_empty():
		card.weakness_modifier = WEAKNESS_MODIFIER
	card.resistance_types.assign(_types(raw.get("resistance_types"), card.id, "resistance_types"))
	if not card.resistance_types.is_empty():
		card.resistance_modifier = RESISTANCE_MODIFIER

	card.retreat_cost = _int(raw, "flee_cost", card.id, 0, -1)

	for attack_value: Variant in _array(raw.get("attacks"), card.id, "attacks"):
		var attack := _translate_attack(attack_value, card.id)
		if attack != null:
			card.attacks.append(attack)

	for ability_value: Variant in _array(raw.get("abilities"), card.id, "abilities"):
		if not ability_value is Dictionary:
			errors.append("%s: ability is not an object" % card.id)
			continue
		var ability_raw := ability_value as Dictionary
		_check_fields(ability_raw, ABILITY_FIELDS, card.id, "ability")
		var power := PowerData.new()
		power.name = _required_string(ability_raw, "name", card.id)
		power.kind = ABILITY_KIND
		power.effect_text = str(ability_raw.get("text", ""))
		card.powers.append(power)

	# Evolutions inherit the previous card's attacks, so only a Basic needs its own.
	if card.stage == CardData.STAGE_BASIC and card.attacks.is_empty() and card.powers.is_empty():
		warnings.append("%s: basic Darkner with neither attacks nor abilities" % card.id)


func _translate_attack(value: Variant, card_id: String) -> AttackData:
	if not value is Dictionary:
		errors.append("%s: attack is not an object" % card_id)
		return null
	var raw := value as Dictionary
	_check_fields(raw, ATTACK_FIELDS, card_id, "attack")
	var attack := AttackData.new()
	attack.name = _required_string(raw, "name", card_id)
	attack.cost.assign(_types(raw.get("cost"), card_id, "attack '%s' cost" % attack.name))
	attack.damage = _int(raw, "damage", card_id, 0, -1)
	attack.damage_suffix = str(raw.get("damage_suffix", ""))
	if not DAMAGE_SUFFIXES.has(attack.damage_suffix):
		errors.append("%s: attack '%s' has unknown damage_suffix '%s'" % [card_id, attack.name, attack.damage_suffix])
	attack.effect_text = str(raw.get("text", ""))
	return attack


func _translate_act(raw: Dictionary, card: CardData) -> void:
	card.trainer_type = _lookup(TRAINER_TYPES, _required_string(raw, "subtype", card.id), card.id, "subtype")
	card.effect_text = str(raw.get("text", ""))
	if card.trainer_type == CardData.TRAINER_SPELL:
		card.tp_cost = _int(raw, "tp_cost", card.id, 1, MAX_TP_COST)
	elif raw.has("tp_cost"):
		errors.append("%s: tp_cost on a card that is not a Spell" % card.id)


func _translate_energy(raw: Dictionary, card: CardData) -> void:
	card.energy_kind = _lookup(ENERGY_KINDS, _required_string(raw, "energy_kind", card.id), card.id, "energy_kind")
	card.effect_text = str(raw.get("text", ""))
	card.provides.assign(_types(raw.get("provides"), card.id, "provides"))
	if card.provides.is_empty():
		errors.append("%s: Energy that provides nothing" % card.id)


# --- Helpers ----------------------------------------------------------------------------

func _lookup(table: Dictionary, key: String, card_id: String, field: String) -> String:
	if key.is_empty():
		return ""
	if not table.has(key):
		errors.append("%s: unknown %s '%s'" % [card_id, field, key])
		return ""
	return str(table[key])

## Reads an array of type names, each of which must be in TYPES.
func _types(value: Variant, card_id: String, field: String) -> Array[String]:
	var result: Array[String] = []
	for item: Variant in _array(value, card_id, field):
		var type := str(item)
		if TYPES.has(type):
			result.append(type)
		else:
			errors.append("%s: %s has unknown type '%s'" % [card_id, field, type])
	return result


## Reads a required whole number. max_value -1 means no upper limit.
func _int(raw: Dictionary, key: String, card_id: String, min_value: int, max_value: int) -> int:
	if not raw.has(key):
		errors.append("%s: missing %s" % [card_id, key])
		return 0
	var value: Variant = raw[key]
	if not (value is int or (value is float and is_equal_approx(value as float, roundf(value as float)))):
		errors.append("%s: %s is not a whole number" % [card_id, key])
		return 0
	var number := int(value)
	if number < min_value or (max_value >= 0 and number > max_value):
		errors.append("%s: %s %d is out of range" % [card_id, key, number])
	return number


## Reports fields the schema does not define, so a typo never passes silently.
func _check_fields(raw: Dictionary, allowed: Array, card_id: String, what: String) -> void:
	for key: Variant in raw:
		if not allowed.has(key):
			warnings.append("%s: unknown %s field '%s'" % [card_id, what, key])


func _required_string(raw: Dictionary, key: String, card_id: String) -> String:
	var value := str(raw.get(key, ""))
	if value.is_empty():
		errors.append("%s: missing %s" % [card_id, key])
	return value


func _array(value: Variant, card_id: String, field: String) -> Array:
	if value == null:
		return []
	if not value is Array:
		errors.append("%s: %s is not an array" % [card_id, field])
		return []
	return value as Array