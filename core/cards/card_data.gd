class_name CardData
extends RefCounted
## One physical card. Field values use TCGdex vocabulary ("Pokemon", "Basic", "Fighting").
## Built by TcgdexParser or the Deltarune translator; never edited after construction.

const CATEGORY_POKEMON := "Pokemon"
const CATEGORY_TRAINER := "Trainer"
const CATEGORY_ENERGY := "Energy"
const STAGE_BASIC := "Basic"
## Deltarune evolutions. Kept apart from Stage1 / Stage2: they keep the previous card's
## attacks, Abilities, Weakness, Resistance and Retreat cost (Design Document 3.2).
const STAGE_BREAK := "BREAK"
const ENERGY_NORMAL := "Normal"
const ENERGY_SPECIAL := "Special"

const TRAINER_ITEM := "Item"
const TRAINER_SUPPORTER := "Supporter"
const TRAINER_STADIUM := "Stadium"
## Deltarune Spell. Plays like an Item, with its own category and a TP cost.
const TRAINER_SPELL := "Spell"

const ORIENTATION_PORTRAIT := "portrait"
const ORIENTATION_LANDSCAPE := "landscape"

var id: String = ""
var local_id: String = ""
var set_id: String = ""
var name: String = ""
var category: String = ""
var rarity: String = ""
## Base URL without quality or extension, e.g. https://assets.tcgdex.net/en/base/base1/52
var image_url: String = ""
## Printed artist credit. Empty when the card prints none.
var artist: String = ""
## How the card is printed. Empty for WOTC cards.
var orientation: String = ""

# Pokemon
var stage: String = ""
var evolve_from: String = ""
var hp: int = 0
var types: Array[String] = []
var weakness_types: Array[String] = []
var weakness_modifier: String = ""
var resistance_types: Array[String] = []
var resistance_modifier: String = ""
var retreat_cost: int = 0
var attacks: Array[AttackData] = []
var powers: Array[PowerData] = []

# Trainer cards and Special Energy
var effect_text: String = ""
## Item, Supporter, Stadium or Spell. Empty for WOTC Trainers, which have no subtype.
var trainer_type: String = ""
## Spell cost in quarters of the TP bar (1 = 25%). 0 for every other card.
var tp_cost: int = 0

# Energy
var energy_kind: String = ""
var provides: Array[String] = []


func is_pokemon() -> bool:
	return category == CATEGORY_POKEMON


func is_basic_pokemon() -> bool:
	return is_pokemon() and stage == STAGE_BASIC


func is_trainer() -> bool:
	return category == CATEGORY_TRAINER


func is_energy() -> bool:
	return category == CATEGORY_ENERGY