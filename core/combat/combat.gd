class_name Combat
extends RefCounted
## A combat (Design Document 2.1): the best of three rounds between the same two decks. Each
## round is a complete game from setup, played on its own MatchEngine with a fresh Rng, so the
## coin flip, the shuffles and TP start over every round. A round that ends in Sudden Death is
## decided by a Sudden Death game, a new game with SUDDEN_DEATH_PRIZE_COUNT Mercy Cards each,
## played again until one player wins it; the round goes to that player.
##
## The combat holds the score and the games already played; the engine of the game being
## played is engine, and every action of that game goes to it as usual (legal_actions(),
## apply()). When the game is over, next_game() starts the next one.

## Rounds a player must win to win the combat: the best of three.
const ROUNDS_TO_WIN := 2
## Mercy Cards each player sets aside in a Sudden Death game, as in the Pokémon TCG.
const SUDDEN_DEATH_PRIZE_COUNT := 1

## The rules every round starts with.
var rules: MatchRules
## Each player's deck as card ids, in the order it is handed to every game. The same in every
## round (Design Document 2.1).
var decks: Array[PackedStringArray] = []
## The seed every game's seed comes from.
var combat_seed: int = 0
## The engine of the game being played, or null before start().
var engine: MatchEngine = null
## The round being played, from 1.
var round_number: int = 0
## Whether the game being played is a Sudden Death game.
var sudden_death := false
## The games already played, in order: {"round": int, "sudden_death": bool, "winner": int (a
## player index or MatchEngine.SUDDEN_DEATH), "replay": MatchReplay}.
var games: Array[Dictionary] = []

var _cards: CardDatabase
var _effects: EffectLibrary
var _seeds: Rng
## Seeds to use before drawing new ones, when a combat is played again (CombatReplay).
var _seed_queue: Array[int] = []
## The decks handed to the game being played, before it shuffled them.
var _game_decks: Array = []


func _init(cards: CardDatabase, effects: EffectLibrary, deck_a: PackedStringArray, deck_b: PackedStringArray,
		round_rules: MatchRules, seed: int) -> void:
	_cards = cards
	_effects = effects
	decks.append(deck_a.duplicate())
	decks.append(deck_b.duplicate())
	rules = round_rules
	combat_seed = seed
	_seeds = Rng.new(seed)


## Starts the first round.
func start() -> void:
	games.clear()
	round_number = 1
	_start_game(false, [0, 0])


## Whether the game being played has ended.
func is_game_over() -> bool:
	return engine != null and engine.is_over()


## Rounds won by each player, counting the game being played once it is over.
func score() -> Array[int]:
	var won: Array[int] = [0, 0]
	for game in games:
		if int(game["winner"]) >= 0:
			won[int(game["winner"])] += 1
	if is_game_over() and engine.winner >= 0:
		won[engine.winner] += 1
	return won


func is_over() -> bool:
	return score().max() >= ROUNDS_TO_WIN


## The player who won the combat, or -1 while it goes on.
func winner() -> int:
	var won := score()
	for player in won.size():
		if won[player] >= ROUNDS_TO_WIN:
			return player
	return -1


## Whether next_game() would start a Sudden Death game.
func next_is_sudden_death() -> bool:
	return is_game_over() and engine.winner == MatchEngine.SUDDEN_DEATH


## Ends the game that is over and starts the next one: a Sudden Death game in the same round
## after Sudden Death, otherwise the next round. False, changing nothing, while the game goes
## on or once the combat is over.
func next_game() -> bool:
	if not is_game_over() or is_over():
		return false
	var again := next_is_sudden_death()
	games.append({"round": round_number, "sudden_death": sudden_death, "winner": engine.winner, "replay": engine.replay()})
	# A Spare or a lost Fight gives extra cards in the next round, never in a Sudden Death game.
	var extra_draws: Array[int] = [0, 0]
	if not again:
		extra_draws.assign(engine.extra_draws_next_round)
	if not again:
		round_number += 1
	_start_game(again, extra_draws)
	return true


## A fresh copy of a player's deck as the game being played was handed it, before it was
## shuffled: what the CPU playing that seat knows as its decklist.
func decklist(player: int) -> Array[CardData]:
	var cards: Array[CardData] = []
	cards.assign((_game_decks[player] as Array[CardData]).duplicate())
	return cards


## The combat so far, every game in order including the one being played (CombatReplay).
func replay() -> CombatReplay:
	var record := CombatReplay.new()
	record.combat_seed = combat_seed
	record.rules = rules.to_dict()
	for deck in decks:
		record.decks.append(deck.duplicate())
	for game in games:
		record.games.append((game["replay"] as MatchReplay).duplicate_replay())
	if engine != null:
		record.games.append(engine.replay())
	return record


## Seeds the next games use before new ones are drawn, in order (CombatReplay.play()).
func use_seeds(seeds: Array[int]) -> void:
	_seed_queue = seeds.duplicate()


## extra_draws: each player's extra cards on their first turn (Design Document 4.5).
func _start_game(is_sudden_death: bool, extra_draws: Array[int]) -> void:
	sudden_death = is_sudden_death
	var seed := _seeds.next_seed()
	if not _seed_queue.is_empty():
		seed = _seed_queue.pop_front()
	_game_decks.clear()
	var handed: Array = []
	for deck in decks:
		var cards: Array[CardData] = []
		for id in deck:
			cards.append(_cards.make(id))
		var kept: Array[CardData] = []
		kept.assign(cards.duplicate())
		_game_decks.append(kept)
		handed.append(cards)
	engine = MatchEngine.new()
	engine.effects = _effects
	# A copy, so nothing a game changes in its rules reaches the next one.
	var game_rules := rules.with_prize_count(SUDDEN_DEATH_PRIZE_COUNT) if is_sudden_death else MatchRules.from_dict(rules.to_dict())
	game_rules.first_turn_extra_draws = extra_draws.duplicate()
	var won := score()
	for player in won.size():
		engine.match_point[player] = won[player] == ROUNDS_TO_WIN - 1
	engine.start(handed[0] as Array[CardData], handed[1] as Array[CardData], game_rules, Rng.new(seed))
