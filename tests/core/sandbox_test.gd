## Headless checks for sandboxes, the rounds a planning CPU tries actions on (Design Document
## 8.7): MatchEngine.copy() and MatchEngine.from_view(). Run from the project root:
##   godot --headless --path . --script res://tests/core/sandbox_test.gd
## Exits with code 0 when every check passes.
extends TestCase

const DECK_PAIRS := [["holy", "chaos"], ["creative", "darkness"], ["darkness", "holy"], ["deltarune_chaos", "deltarune_holy"]]
const SEEDS := 3
## Every this many decisions of a round, a sandbox is built and checked.
const CHECK_EVERY := 3

var library: EffectLibrary
var decks: Dictionary


## Everything about a round that playing it can change, as text: two rounds with the same
## digest play the same from here on.
func digest(engine: MatchEngine) -> String:
	var parts: Array[String] = ["t%d c%d w%d f%d x%s a%s/%d" % [engine.turn, engine.current_index, engine.winner, engine.fighting, engine.operations.extra_turn,
			"" if engine.stadium == null else engine.stadium.id, engine.stadium_owner]]
	parts.append("q%s/%d/%d" % [engine.choice_kind(), engine.choice_chooser(), engine.legal_actions().size()])
	for player in engine.players:
		parts.append("h%s d%s r%s p%s" % [MatchLog.ids(player.hand), MatchLog.ids(player.deck), MatchLog.ids(player.discard), MatchLog.ids(player.prizes)])
		parts.append("tp%d e%s r%s s%s a%s m%d n%d u%s/%s w%s" % [player.tp, player.energy_attached_this_turn, player.retreated_this_turn, player.supporter_played_this_turn,
				player.stadium_played_this_turn, player.mulligans, player.turns_started, player.attack_used_this_turn, player.attack_used_last_turn, player.powers_used_this_turn])
		for darkner in [player.active] + player.bench:
			if darkner == null:
				parts.append("-")
				continue
			var in_play := darkner as CardInPlay
			parts.append("%s<%s dmg%d e%s t%d" % [in_play.card.id, MatchLog.ids(in_play.evolved_from), in_play.damage, MatchLog.ids(in_play.attached_energy), in_play.turn_played])
	return " | ".join(parts)


## What a player cannot see of the round, as it really is: the guesses that make a sandbox built
## from their view the same round.
func true_hidden(engine: MatchEngine) -> Dictionary:
	var hidden := {"hands": [], "decks": [], "prizes": []}
	for player in engine.players:
		(hidden["hands"] as Array).append(player.hand.duplicate())
		(hidden["decks"] as Array).append(player.deck.duplicate())
		(hidden["prizes"] as Array).append(player.prizes.duplicate())
	return hidden


func new_cpus(pair: Array) -> Array[CpuPlayer]:
	var cpus: Array[CpuPlayer] = []
	for id: String in pair:
		cpus.append(CpuPlayer.new(library, db.build_deck(decks[id] as Dictionary), (decks[id] as Dictionary).get("plan", {}) as Dictionary))
	return cpus


func _run() -> void:
	db = DataLoader.load_card_database()
	library = DataLoader.load_effect_library(db, DataLoader.CARD_EFFECTS_PATH)
	decks = DataLoader.read_json(DataLoader.DECKS_PATH) as Dictionary

	print("== a copy plays as the round does")
	var shadow_mismatch := ""
	var view_mismatch := ""
	var actions_mismatch := ""
	var refused := ""
	var checked := 0
	var tried := 0
	var copy_us := 0
	var view_us := 0
	var apply_us := 0
	for pair: Array in DECK_PAIRS:
		for seed in SEEDS:
			var engine := MatchEngine.new()
			engine.effects = library
			engine.start(db.build_deck(decks[pair[0]] as Dictionary), db.build_deck(decks[pair[1]] as Dictionary), MatchRules.deltarune(), Rng.new(seed))
			var cpus := new_cpus(pair)
			var shadow: MatchEngine = null
			for step in 3000:
				if engine.is_over():
					break
				var actor := engine.choice_chooser() if engine.is_waiting_for_choice() else engine.current_index
				var at_decision := not engine.is_waiting_for_choice() and engine.turn > 0
				if at_decision and step % CHECK_EVERY == 0:
					checked += 1
					var t0 := Time.get_ticks_usec()
					var copied := engine.copy(engine.rng_state())
					var t1 := Time.get_ticks_usec()
					var built := MatchEngine.from_view(engine.view_for(actor), true_hidden(engine), library, engine.rng_state())
					var t2 := Time.get_ticks_usec()
					copy_us += t1 - t0
					view_us += t2 - t1
					if copied == null or built == null:
						refused = "%s seed %d step %d" % [pair, seed, step]
					else:
						if view_mismatch.is_empty() and (digest(built) != digest(engine) or digest(copied) != digest(engine)):
							view_mismatch = "%s seed %d step %d\n  real  %s\n  view  %s\n  copy  %s" % [pair, seed, step, digest(engine), digest(built), digest(copied)]
						if actions_mismatch.is_empty() and (built.legal_actions() != engine.legal_actions() or copied.legal_actions() != engine.legal_actions()):
							actions_mismatch = "%s seed %d step %d" % [pair, seed, step]
						# Every legal action, tried on a copy and on a sandbox from the view, plays the same.
						for action in engine.legal_actions():
							var on_copy := engine.copy(engine.rng_state())
							var on_view := MatchEngine.from_view(engine.view_for(actor), true_hidden(engine), library, engine.rng_state())
							var t3 := Time.get_ticks_usec()
							on_copy.apply(action)
							apply_us += Time.get_ticks_usec() - t3
							tried += 1
							on_view.apply(action)
							for _answer in 20:
								if not on_copy.is_waiting_for_choice() or on_copy.is_over():
									break
								on_copy.apply({"type": "choose", "option": 0})
								on_view.apply({"type": "choose", "option": 0})
							if view_mismatch.is_empty() and digest(on_copy) != digest(on_view):
								view_mismatch = "%s seed %d step %d after %s\n  copy  %s\n  view  %s" % [pair, seed, step, action, digest(on_copy), digest(on_view)]
					if shadow == null:
						shadow = engine.copy(engine.rng_state())
				var action := cpus[actor].choose(engine.view_for(actor))
				engine.apply(action)
				if shadow != null:
					shadow.apply(action)
					if shadow_mismatch.is_empty() and digest(shadow) != digest(engine):
						shadow_mismatch = "%s seed %d step %d after %s\n  real    %s\n  shadow  %s" % [pair, seed, step, action, digest(engine), digest(shadow)]
			if shadow != null and shadow_mismatch.is_empty() and shadow.winner != engine.winner:
				shadow_mismatch = "%s seed %d: winner %d against %d" % [pair, seed, shadow.winner, engine.winner]
	expect(refused.is_empty(), "between actions a sandbox can always be made: %s" % refused)
	expect(shadow_mismatch.is_empty(), "a copy with the round's Rng, given the same actions, plays the whole round the same: %s" % shadow_mismatch)
	expect(view_mismatch.is_empty(), "a sandbox from a player's view, given the real hidden cards, is the same round, and stays so after each action: %s" % view_mismatch)
	expect(actions_mismatch.is_empty(), "and offers the same legal actions: %s" % actions_mismatch)
	print("  %d states checked, %d actions tried; average: copy %.0f us, from a view %.0f us, apply %.0f us"
			% [checked, tried, copy_us / float(checked), view_us / float(checked), apply_us / float(tried)])
	expect((copy_us / float(checked) + apply_us / float(tried)) < 1000.0, "a tried action (a copy and an apply) costs under 1 ms on average")

	print("== what a sandbox leaves alone")
	var real := MatchEngine.new()
	real.effects = library
	real.start(db.build_deck(decks["holy"] as Dictionary), db.build_deck(decks["chaos"] as Dictionary), MatchRules.deltarune(), Rng.new(4))
	finish_setup(real)
	var before := digest(real)
	var events := real.match_log.entries.size()
	var sandbox := real.copy(Rng.new(99))
	for _step in 30:
		if sandbox.is_over():
			break
		var options := sandbox.legal_actions()
		sandbox.apply(options.back())
	expect(digest(real) == before and real.match_log.entries.size() == events, "playing on a copy changes nothing in the round")
	expect(sandbox.match_log.entries.is_empty() and sandbox.replay().actions.size() > 0, "a sandbox keeps no events, but records the actions it was given")
	var short_guess := true_hidden(real)
	((short_guess["decks"] as Array)[0] as Array).pop_back()
	expect(MatchEngine.from_view(real.view_for(real.current_index), short_guess, library, Rng.new(1)) == null, "a guess whose counts do not match the view is refused")
	real.apply({"type": "end_turn"})
	var waiting := false
	for _step in 40:
		if real.is_waiting_for_choice():
			waiting = true
			break
		var options := real.legal_actions()
		real.apply(options[0])
	expect(not waiting or (real.copy(Rng.new(1)) == null and MatchEngine.from_view(real.view_for(real.choice_chooser()), true_hidden(real), library, Rng.new(1)) == null),
			"while a question is open there is no sandbox")

	finish()
