class_name MatchRules
extends RefCounted
## The rules of one round. Every value is set explicitly by a factory below; the engine
## reads them instead of constants, so the same engine plays both rule sets.

## Cards drawn at setup.
var hand_size: int = 0
## Darkners allowed on the Field, not counting the Battle Zone.
var bench_limit: int = 0
## Mercy Cards set aside per player.
var prize_count: int = 0
## Mercy Cards taken per knockout. Effects may change it (Design Document 4.4).
var prizes_per_knockout: int = 0
## True: a player who cannot draw at the start of their turn loses. False: the opponent takes a prize (legacy roguelite rule).
var deck_out_loses: bool = false
## Whether the player going first may attack on their first turn.
var first_player_can_attack: bool = false
## Whether the player going first may play a Lightner (Supporter) on their first turn.
var first_player_can_play_supporter: bool = false
## True: a coin flip decides who goes first. False: player 1 always goes first.
var random_first_player: bool = false
## Required deck size. 0 means any size.
var deck_size: int = 0
## Copies of one card allowed per deck, Energy excepted. 0 means no limit.
var max_copies: int = 0
## Most TP a player can hold, in quarters (Design Document 5). 0 means the rules have no TP.
var tp_max: int = 0
## TP recovered at the end of a turn in which the player attacked, in quarters. A player who
## passes recovers up to tp_max instead.
var tp_recovery: int = 0



## The rules the WOTC build used. Only for the legacy test data.
static func legacy() -> MatchRules:
	var rules := MatchRules.new()
	rules.hand_size = 7
	rules.bench_limit = 5
	rules.prize_count = 3
	rules.prizes_per_knockout = 1
	rules.deck_out_loses = false
	rules.first_player_can_attack = true
	rules.first_player_can_play_supporter = true
	rules.random_first_player = false
	rules.deck_size = 0
	rules.max_copies = 0
	rules.tp_max = 0
	rules.tp_recovery = 0
	return rules


## Deltarune TCG (Design Document 4).
static func deltarune() -> MatchRules:
	var rules := MatchRules.new()
	rules.hand_size = 10
	rules.bench_limit = 4
	rules.prize_count = 4
	rules.prizes_per_knockout = 1
	rules.deck_out_loses = true
	rules.first_player_can_attack = false
	rules.first_player_can_play_supporter = false
	rules.random_first_player = true
	rules.deck_size = 50
	rules.max_copies = 4
	rules.tp_max = 4
	rules.tp_recovery = 1
	return rules


## The same rules with a different prize count, for Sudden Death.
func with_prize_count(count: int) -> MatchRules:
	var copy := MatchRules.new()
	copy.hand_size = hand_size
	copy.bench_limit = bench_limit
	copy.prize_count = count
	copy.prizes_per_knockout = prizes_per_knockout
	copy.deck_out_loses = deck_out_loses
	copy.first_player_can_attack = first_player_can_attack
	copy.first_player_can_play_supporter = first_player_can_play_supporter
	copy.random_first_player = random_first_player
	copy.deck_size = deck_size
	copy.max_copies = max_copies
	copy.tp_max = tp_max
	copy.tp_recovery = tp_recovery
	return copy