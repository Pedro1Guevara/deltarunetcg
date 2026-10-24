## Headless checks for the Deltarune translator. Run from the project root:
##   godot --headless --path . --script res://tests/deltarune_cards_test.gd
## Exits with code 0 when every check passes.
extends TestCase


func _run() -> void:
	db = DataLoader.load_card_database()

	print("== load")
	expect(db.errors.is_empty(), "no translation errors: %s" % [db.errors])
	expect(db.warnings.is_empty(), "no translation warnings: %s" % [db.warnings])
	expect(db.card_count() == 30, "30 cards loaded (%d)" % db.card_count())

	var library := DataLoader.load_effect_library(db, DataLoader.CARD_EFFECTS_PATH)
	expect(library.errors.is_empty(), "no card effect errors: %s" % [library.errors])
	expect(library.valid_binding_count() == 3, "3 card effect entries in use (%d)" % library.valid_binding_count())
	
	print("== darkner")
	var jevil := db.make("jevil")
	expect(jevil.category == CardData.CATEGORY_POKEMON, "darkner -> Pokemon")
	expect(jevil.is_basic_pokemon(), "basic -> Basic")
	expect(jevil.retreat_cost == 1, "flee_cost -> retreat_cost")
	expect(jevil.weakness_types == ["Fun"] and jevil.weakness_modifier == "+20", "weakness Fun +20")
	expect(jevil.resistance_types == ["Creative"] and jevil.resistance_modifier == "-20", "resistance Creative -20")
	expect(jevil.attacks.size() == 2 and jevil.attacks[1].cost == ["Chaos", "Colorless"], "Chaos Bomb cost")
	expect(jevil.attacks[1].damage == 0 and jevil.attacks[1].has_effect(), "Chaos Bomb prints no damage and has an effect")

	var guei := db.make("guei")
	expect(guei.attacks[0].damage == 40 and guei.attacks[0].damage_suffix == "+", "Flash Melt 40+")

	var tenna := db.make("tenna")
	expect(tenna.powers.size() == 1 and tenna.powers[0].kind == "Ability", "abilities -> powers, kind Ability")

	print("== evolution")
	var mizzle := db.make("miss_mizzle")
	expect(mizzle.stage == CardData.STAGE_BREAK, "evolution -> BREAK")
	expect(mizzle.evolve_from == "Water Cooler", "evolves_from -> evolve_from")
	expect(mizzle.weakness_types.is_empty() and mizzle.weakness_modifier.is_empty(), "no printed weakness, no modifier")
	expect(mizzle.orientation == CardData.ORIENTATION_LANDSCAPE, "landscape orientation")

	print("== act")
	expect(db.make("kris").trainer_type == CardData.TRAINER_SUPPORTER, "lightner -> Supporter")
	expect(db.make("cyber_city").trainer_type == CardData.TRAINER_STADIUM, "area -> Stadium")
	expect(db.make("glowshard").trainer_type == CardData.TRAINER_ITEM, "item -> Item")
	var buster := db.make("rude_buster")
	expect(buster.trainer_type == CardData.TRAINER_SPELL and buster.tp_cost == 1, "spell -> Spell, tp_cost 1")

	print("== energy")
	var chaos := db.make("chaos_energy")
	expect(chaos.is_energy() and chaos.energy_kind == CardData.ENERGY_NORMAL and chaos.provides == ["Chaos"], "basic Chaos Energy")

	print("== colorless")
	var t := DeltaruneCardTranslator.new()
	var colorless_darkner := t.parse({
		"id": "c1", "name": "C1", "category": "darkner", "orientation": "portrait", "stage": "basic", "hp": 60,
		"types": ["Colorless"], "weakness_types": [], "resistance_types": [], "flee_cost": 1,
		"attacks": [{"name": "Tackle", "cost": ["Colorless"], "damage": 10, "damage_suffix": "", "text": ""}], "abilities": [],
	})
	expect(colorless_darkner != null and colorless_darkner.types == ["Colorless"], "a Darkner can be Colorless: %s" % [t.errors])
	t.clear_messages()
	var double_colorless := t.parse({
		"id": "dce", "name": "Double Colorless Energy", "category": "energy", "orientation": "portrait",
		"energy_kind": "special", "provides": ["Colorless", "Colorless"], "text": "",
	})
	expect(double_colorless != null and double_colorless.provides == ["Colorless", "Colorless"], "a Special Energy can provide Colorless: %s" % [t.errors])
	var paid := CardInPlay.new(colorless_darkner, 0)
	paid.attached_energy.append(double_colorless)
	expect(paid.can_pay(["Colorless", "Colorless"]) and not paid.can_pay(["Chaos"]), "Colorless Energy pays Colorless costs only")

	print("== rejected input")
	t.clear_messages()
	expect(t.parse({"id": "x", "name": "X", "category": "pokemon", "orientation": "portrait"}) == null, "unknown category is rejected")
	t.clear_messages()
	expect(t.parse({"id": "y", "name": "Y", "category": "act", "subtype": "tool", "orientation": "portrait"}) == null, "unknown subtype is rejected")
	t.clear_messages()
	expect(t.parse({"id": "z", "name": "Z", "category": "energy", "energy_kind": "basic", "provides": ["Fire"], "orientation": "portrait"}) == null, "unknown type is rejected")

	finish()