class_name CardData
extends RefCounted

const KIND_POKEMON := "pokemon"
const KIND_ENERGY := "energy"

var id: String = ""
var name: String = ""
var kind: String = ""
var hp: int = 0
var types: Array[String] = []
var weakness_types: Array[String] = []
var weakness_modifier: String = ""
var resistance_types: Array[String] = []
var resistance_modifier: String = ""
var retreat_cost: int = 0
var attacks: Array[AttackData] = []
var provides: Array[String] = []


static func from_dict(raw: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = str(raw.get("id", ""))
	card.name = str(raw.get("name", card.id))
	card.kind = str(raw.get("kind", ""))
	card.hp = int(raw.get("hp", 0))
	card.types.assign(raw.get("types", []) as Array)

	var weakness := raw.get("weakness", {}) as Dictionary
	card.weakness_types.assign(weakness.get("types", []) as Array)
	card.weakness_modifier = str(weakness.get("modifier", ""))

	var resistance := raw.get("resistance", {}) as Dictionary
	card.resistance_types.assign(resistance.get("types", []) as Array)
	card.resistance_modifier = str(resistance.get("modifier", ""))

	card.retreat_cost = int(raw.get("retreat_cost", 0))
	for attack_raw: Variant in raw.get("attacks", []) as Array:
		card.attacks.append(AttackData.from_dict(attack_raw as Dictionary))

	card.provides.assign(raw.get("provides", []) as Array)
	return card


func is_pokemon() -> bool:
	return kind == KIND_POKEMON


func is_energy() -> bool:
	return kind == KIND_ENERGY
