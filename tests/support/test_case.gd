class_name TestCase
extends SceneTree
## Shared base for the headless suites. A suite extends it, sets `db` in `_run()`, calls
## `expect()` for each check and ends with `finish()`.

var db: CardDatabase
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


## Each suite overrides this with its checks.
func _run() -> void:
	pass


func expect(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		failures += 1


## Prints the count and exits with code 0 when every check passed.
func finish() -> void:
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


## Answers setup the quick way: Heads, first Active option, no bench, no mulligan draws.
## Stops at turn 1 even if an effect choice is already open.
func finish_setup(engine: MatchEngine) -> void:
	while engine.is_waiting_for_choice() and engine.turn == 0:
		var actions := engine.legal_actions()
		var pick := actions[0]
		for action in actions:
			var label := str(action["label"])
			if label.begins_with("Finish") or label.begins_with("Draw 0"):
				pick = action
		engine.apply(pick)

## True when no two actions show the same label: every option the player sees is distinct.
func labels_distinct(actions: Array[Dictionary]) -> bool:
	var seen := {}
	for action in actions:
		var label := str(action["label"])
		if seen.has(label):
			return false
		seen[label] = true
	return true

## A fresh copy of each card id, in order.
func energies(ids: Array) -> Array[CardData]:
	var out: Array[CardData] = []
	for id: String in ids:
		out.append(db.make(id))
	return out


## A card in play, entered on turn 0, with the given Energy attached.
func in_play(id: String, attached: Array) -> CardInPlay:
	var card := CardInPlay.new(db.make(id), 0)
	card.attached_energy.assign(energies(attached))
	return card