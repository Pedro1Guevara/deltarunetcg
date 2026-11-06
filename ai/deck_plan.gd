class_name DeckPlan
extends RefCounted
## The board a CPU deck aims for (Design Document 8.7): one attacker in the Battle Zone using
## one attack, and the Darkners it wants on the Field. Built from the decklist before the
## round, either from a plan written for the deck in decks.json (bosses) or automatically, by
## estimating each attack's damage after its effects on the board that makes it hit hardest.
## The CPU reads what is still missing from it to decide what to play, keep and fetch.

const SOURCE_AUTOMATIC := "automatic"
const SOURCE_PREDEFINED := "predefined"
## The keys a plan written in decks.json must have, all of them: the attacker's card id (the
## last card of its evolution line), the attack's printed name, and the card ids wanted on
## the Field.
const DATA_KEYS: Array[String] = ["battle_zone", "attack", "field"]
## How many Darkners the automatic plan assumes on the opponent's Field, for attacks that
## damage it.
const ASSUMED_OPPONENT_FIELD := 3
## An opponent's Darkner that no estimate knocks out and that has no Weakness or Resistance.
const NEUTRAL_HP := 1000
## How many Energy beyond its cost the plan looks at for an attack that grows with Energy.
const MAX_EXTRA_ENERGY := 6

var source: String = SOURCE_AUTOMATIC
## The attacker's evolution line as card ids, Basic first; its last card is the attacker.
var attacker_line: Array[String] = []
var attack_name: String = ""
## Each Darkner wanted on the Field, as its evolution line, Basic first.
var field_lines: Array = []
## The attack's expected damage on the planned board, against ASSUMED_OPPONENT_FIELD neutral
## Darkners on the opponent's Field.
var expected_damage: float = 0.0
## How many Energy units the attacker wants: its attack's cost, or more when more Energy makes
## the attack hit harder (Flash Melt: 80 more with 5). The fewest that give the most damage.
var energy_goal: int = 0
## Problems with a written plan, which then gave way to the automatic one.
var warnings: Array[String] = []


## The plan for a decklist: data is the deck's "plan" entry in decks.json, or empty.
static func build(deck: Array[CardData], reader: EffectReader, bench_limit: int, data: Dictionary) -> DeckPlan:
	var lines := _lines(deck)
	var counts := _counts(deck)
	var by_id := _by_id(deck)
	if not data.is_empty():
		var written := DeckPlan.new()
		var problems := written._read(data, lines, counts, by_id, bench_limit)
		if problems.is_empty():
			written.source = SOURCE_PREDEFINED
			written.expected_damage = written._estimate(reader, by_id)
			written._set_energy_goal(reader, by_id, deck)
			return written
		var fallback := _automatic(lines, counts, by_id, reader, bench_limit, deck)
		fallback.warnings = problems
		fallback._set_energy_goal(reader, by_id, deck)
		return fallback
	var automatic := _automatic(lines, counts, by_id, reader, bench_limit, deck)
	automatic._set_energy_goal(reader, by_id, deck)
	return automatic


## Whether darkner is the plan's attacker (or will evolve into it) and has fewer Energy units
## than the plan wants on it.
func wants_energy(darkner: CardInPlay) -> bool:
	return energy_short(darkner) > 0


## How many Energy units the plan's attacker still lacks for energy_goal; 0 for any other
## Darkner.
func energy_short(darkner: CardInPlay) -> int:
	if not is_attacker(darkner):
		return 0
	return maxi(0, energy_goal - darkner.energy_pool().size())


func _set_energy_goal(reader: EffectReader, by_id: Dictionary, deck: Array[CardData]) -> void:
	var attacker := _chain(attacker_line, by_id)
	var energies := _energy_by_type(deck)
	for attack in attacker.attacks():
		if attack.name != attack_name:
			continue
		energy_goal = attack.cost.size()
		var paid := _paid(attacker, attack, energies)
		if paid == null:
			return
		var main := paid.attached_energy[0] if not paid.attached_energy.is_empty() else null
		var best := _damage(paid, attack, field_lines, by_id, reader)
		for extra in range(1, MAX_EXTRA_ENERGY + 1):
			if main == null:
				return
			paid.attached_energy.append(main)
			var damage := _damage(paid, attack, field_lines, by_id, reader)
			if damage > best:
				best = damage
				energy_goal = attack.cost.size() + extra
		return


## Card ids and how many of each the plan wants in play, counting every card of each line.
func wanted() -> Dictionary:
	var counts := {}
	for line: Array in [attacker_line] + field_lines:
		for id: String in line:
			counts[id] = int(counts.get(id, 0)) + 1
	return counts


## What the plan still lacks on side: card ids and how many, counting each Darkner in play
## with the cards under it.
func missing(side: PlayerView.SideView) -> Dictionary:
	var lacking := wanted()
	for darkner in _in_play(side):
		for card in [darkner.card] + darkner.evolved_from:
			var id := (card as CardData).id
			if int(lacking.get(id, 0)) > 0:
				lacking[id] = int(lacking[id]) - 1
				if int(lacking[id]) == 0:
					lacking.erase(id)
	return lacking


## Whether darkner is, or will evolve into, the planned attacker.
func is_attacker(darkner: CardInPlay) -> bool:
	for card in [darkner.card] + darkner.evolved_from:
		if attacker_line.has((card as CardData).id):
			return true
	return false


## The planned attack's cost, read from the attacker's line in deck. Empty when unknown.
func attack_cost(deck: Array[CardData]) -> Array[String]:
	var by_id := _by_id(deck)
	var chain := _chain(attacker_line, by_id)
	for attack in chain.attacks():
		if attack.name == attack_name:
			return attack.cost
	return []


func _read(data: Dictionary, lines: Dictionary, counts: Dictionary, by_id: Dictionary, bench_limit: int) -> Array[String]:
	var problems: Array[String] = []
	for key in DATA_KEYS:
		if not data.has(key):
			problems.append("plan has no '%s'" % key)
	if not problems.is_empty():
		return problems
	var attacker := str(data["battle_zone"])
	if not lines.has(attacker):
		return ["plan battle_zone '%s' is not a Darkner of the deck" % attacker]
	attacker_line.assign(lines[attacker] as Array)
	attack_name = str(data["attack"])
	if not _chain(attacker_line, by_id).attacks().any(func(attack: AttackData) -> bool: return attack.name == attack_name):
		problems.append("plan attack '%s' is not an attack of %s" % [attack_name, attacker])
	if not data["field"] is Array:
		return problems + ["plan field is not a list"]
	if (data["field"] as Array).size() > bench_limit:
		problems.append("plan field has more Darkners than the Field holds (%d)" % bench_limit)
	for id: Variant in data["field"]:
		if not lines.has(str(id)):
			problems.append("plan field '%s' is not a Darkner of the deck" % id)
		else:
			field_lines.append((lines[str(id)] as Array).duplicate())
	for id: String in wanted():
		if int(wanted()[id]) > int(counts.get(id, 0)):
			problems.append("plan wants more copies of %s than the deck has" % id)
	return problems


## Tries every attack of every evolution line as the attacker, fills the Field greedily with
## the lines that add most to its damage (then with Darkners that have Abilities, then the
## sturdiest), and keeps the attack that does the most damage. An attack whose typed Energy
## the deck has no Basic Energy for is skipped.
static func _automatic(lines: Dictionary, counts: Dictionary, by_id: Dictionary, reader: EffectReader, bench_limit: int, deck: Array[CardData]) -> DeckPlan:
	var energies := _energy_by_type(deck)
	var best := DeckPlan.new()
	var best_score := -INF
	for final_id: String in lines:
		var line := lines[final_id] as Array
		var attacker := _chain(line, by_id)
		for attack in attacker.attacks():
			var paid := _paid(attacker, attack, energies)
			if paid == null:
				continue
			var remaining := counts.duplicate()
			if not _take_line(remaining, line):
				continue
			var field: Array = []
			while field.size() < bench_limit:
				var choice := _best_addition(paid, attack, field, lines, remaining, by_id, reader)
				if choice.is_empty():
					break
				_take_line(remaining, choice)
				field.append(choice)
			var damage := _damage(paid, attack, field, by_id, reader)
			var score := damage + attacker.card.hp / 10.0 - attack.cost.size()
			if score > best_score:
				best_score = score
				best = DeckPlan.new()
				best.attacker_line.assign(line)
				best.attack_name = attack.name
				best.field_lines = field.duplicate(true)
				best.expected_damage = damage
	return best


static func _best_addition(attacker: CardInPlay, attack: AttackData, field: Array, lines: Dictionary, remaining: Dictionary, by_id: Dictionary, reader: EffectReader) -> Array:
	var base := _damage(attacker, attack, field, by_id, reader)
	var best: Array = []
	var best_score := -INF
	for final_id: String in lines:
		var line := lines[final_id] as Array
		if not _has_line(remaining, line):
			continue
		var gain := _damage(attacker, attack, field + [line], by_id, reader) - base
		var chain := _chain(line, by_id)
		var score := gain * 1000.0 + (50.0 if not chain.powers().is_empty() else 0.0) + chain.card.hp / 10.0
		if score > best_score:
			best_score = score
			best = line
	return best


static func _damage(attacker: CardInPlay, attack: AttackData, field: Array, by_id: Dictionary, reader: EffectReader) -> float:
	var own := PlayerView.SideView.new()
	own.active = attacker
	for line: Array in field:
		own.bench.append(_chain(line, by_id))
	var opponent := PlayerView.SideView.new()
	opponent.active = _neutral()
	for _i in ASSUMED_OPPONENT_FIELD:
		opponent.bench.append(_neutral())
	return float(reader.estimate_attack(attacker, attack, own, opponent)["total"])


func _estimate(reader: EffectReader, by_id: Dictionary) -> float:
	var attacker := _chain(attacker_line, by_id)
	for attack in attacker.attacks():
		if attack.name == attack_name:
			return _damage(attacker, attack, field_lines, by_id, reader)
	return 0.0


## A copy of attacker with Basic Energy attached that pays attack (Colorless with the deck's
## most common type), or null when the deck cannot pay a typed symbol.
static func _paid(attacker: CardInPlay, attack: AttackData, energies: Dictionary) -> CardInPlay:
	if energies.is_empty():
		return null
	var main := ""
	var most := -1
	for type: String in energies:
		if (energies[type] as Array).size() > most:
			main = type
			most = (energies[type] as Array).size()
	var paid := attacker.snapshot()
	for symbol in attack.cost:
		var type := main if symbol == CardTypes.COLORLESS else symbol
		if not energies.has(type):
			return null
		paid.attached_energy.append((energies[type] as Array)[0] as CardData)
	return paid


## Basic Energy cards of the deck by the type they provide.
static func _energy_by_type(deck: Array[CardData]) -> Dictionary:
	var by_type := {}
	for card in deck:
		if card.is_energy() and card.energy_kind == CardData.ENERGY_NORMAL:
			for type in card.provides:
				if not by_type.has(type):
					by_type[type] = []
				(by_type[type] as Array).append(card)
	return by_type


## Each Darkner's evolution line by its card id, Basic first. An evolution whose Basic is not
## in the deck has no line.
static func _lines(deck: Array[CardData]) -> Dictionary:
	var basic_by_name := {}
	for card in deck:
		if card.is_basic_pokemon():
			basic_by_name[card.name] = card.id
	var lines := {}
	for card in deck:
		if not card.is_pokemon() or lines.has(card.id):
			continue
		if card.is_basic_pokemon():
			lines[card.id] = [card.id]
		elif basic_by_name.has(card.evolve_from):
			lines[card.id] = [basic_by_name[card.evolve_from], card.id]
	return lines


## A Darkner in play made of the line's cards, evolved in order.
static func _chain(line: Array, by_id: Dictionary) -> CardInPlay:
	var darkner := CardInPlay.new(by_id[line[0]] as CardData, 0)
	for index in range(1, line.size()):
		darkner.evolve(by_id[line[index]] as CardData, 0)
	return darkner


static func _neutral() -> CardInPlay:
	var card := CardData.new()
	card.category = CardData.CATEGORY_POKEMON
	card.stage = CardData.STAGE_BASIC
	card.name = "Opponent"
	card.hp = NEUTRAL_HP
	return CardInPlay.new(card, 0)


static func _counts(deck: Array[CardData]) -> Dictionary:
	var counts := {}
	for card in deck:
		counts[card.id] = int(counts.get(card.id, 0)) + 1
	return counts


static func _by_id(deck: Array[CardData]) -> Dictionary:
	var by_id := {}
	for card in deck:
		by_id[card.id] = card
	return by_id


static func _has_line(remaining: Dictionary, line: Array) -> bool:
	for id: String in line:
		if int(remaining.get(id, 0)) < 1:
			return false
	return true


static func _take_line(remaining: Dictionary, line: Array) -> bool:
	if not _has_line(remaining, line):
		return false
	for id: String in line:
		remaining[id] = int(remaining[id]) - 1
	return true


static func _in_play(side: PlayerView.SideView) -> Array[CardInPlay]:
	var darkners: Array[CardInPlay] = []
	if side.active != null:
		darkners.append(side.active)
	darkners.append_array(side.bench)
	return darkners