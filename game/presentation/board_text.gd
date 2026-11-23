extends RefCounted

const ZONES := {"Battle": "Battle Zone", "Field": "Field", "Mercy": "Mercy Cards", "Deck": "Deck", "Discard": "Discard\nPile", "Area": "Area", "Hand": "Hand"}
const PASS := "Pass Turn"
const ENEMY_TURN := "Enemy Turn"
const ENEMY := "Opponent"
const PLAYER := "Player"

const PAUSED := "Paused"
const MENU := "Menu"
const RESUME := "Resume"
const SETTINGS := "Settings"
const CONCEDE := "Concede"
const BACK := "Back"
const ANIMATION_SPEED := "Animation speed"
const CONCEDE_NOTE := "Not available yet"
const EXIT_GAME := "Exit Game"
const COUNT_HINT := "Deck | Hand"

const SESSION_ERROR := "Could not start combat: %s"

const DONE := "Done"
const FLEE := "Flee"
const SELECT_FLEE := "Choose a highlighted Darkner to switch into the Battle Zone"
const PLAY_AGAIN := "New game"
const NEXT_ROUND := "Next round"

const OWN_DISCARD := "Your discard pile"
const OPPONENT_DISCARD := "Opponent's discard pile"

const SPARE := "SPARE"
const FIGHT := "FIGHT"

const SPARE_FIGHT_PROMPT := "You took your last Mercy Card: Spare or Fight?\n(Spare: win the round, but your opponent draws 3 extra cards next round. Fight: knock out a Darkner to win with no extra cards for your opponent, lose the round if one of your Darkners is knocked out.)"

const YES := "YES"
const NO := "NO"

const SHOW_ALL_CARDS := "SHOW ALL CARDS"
const SHOW_SELECTION := "Show selection"
const HIDE_SELECTION := "Hide selection"
const CONFIRM := "CONFIRM"

const TOSS_COIN := "TOSS COIN"
const COIN_FIRST_PURPOSE := "decide who goes first"

static func score_text(round_number: int, own: int, opponent: int) -> String:
	return "Round %d   •   %d – %d" % [round_number, own, opponent]

static func status_text(view: PlayerView, cards: CardDatabase) -> String:
	if view.is_over:
		return "Round won" if view.winner == view.viewer else "Round lost" if view.winner >= 0 else "Sudden Death"
	var prompt := ActionText.prompt(view, cards)
	if not prompt.is_empty():
		return prompt
	if view.chooser >= 0:
		return "Opponent is choosing"
	return "Your turn" if view.current == view.viewer else "Opponent's turn"

static func result_text(view: PlayerView, combat_over: bool) -> String:
	if view.winner < 0:
		return "Sudden Death"
	if combat_over:
		return "You won the match!" if view.winner == view.viewer else "Your opponent won the match"
	return "You won the round!" if view.winner == view.viewer else "Your opponent won the round"

static func confirm_text(picked: int, maximum: int) -> String:
	return CONFIRM if picked >= maximum else "%s (%d/%d)" % [CONFIRM, picked, maximum]

static func coin_prompt(local_tosser: bool, purpose: String = COIN_FIRST_PURPOSE) -> String:
	return ("Toss the coin to " if local_tosser else "Your opponent is tossing the coin to ") + purpose + "!"

static func selection_prompt(view: PlayerView, cards: CardDatabase) -> String:
	if view.choice_details.get("about") == PendingChoice.ABOUT_SEARCH_DECK:
		var filters := view.choice_details["filter"] as Array
		var maximum := int(view.choice_details["maximum"])
		var nouns: PackedStringArray = []
		for filter: String in filters:
			var noun := str(ActionText.FILTERS.get(filter, "card"))
			if noun.ends_with("Energy"):
				noun += " card"
			if maximum > 1:
				noun = "cards" if filter == CardFilter.ANY else noun + "s"
			elif filter != CardFilter.ANY:
				noun = ("an " if noun.left(1).to_lower() in ["a","e","i","o","u"] else "a ") + noun
			nouns.append(noun)
		var text := "Search your deck for " + ("up to %d " % maximum if maximum > 1 else "") + " or ".join(nouns)
		match str(view.choice_details.get("destination", "")):
			CardMoves.TO_BENCH:
				text += " to put onto your Field"
			CardMoves.TO_DISCARD:
				text += " to discard"
		var excluded := view.choice_details.get("excluded", []) as Array
		if not excluded.is_empty():
			text += " (except " + ", ".join(PackedStringArray(excluded)) + ")"
		return text + "."
	var text := ActionText.prompt(view, cards)
	var picked: int = (view.choice_details.get("picked", []) as Array).size()
	return text.trim_suffix(" (%d/%d chosen)" % [picked, int(view.choice_details["maximum"])])

static func energy_location(own: bool, slot: int, darkner_name: String) -> String:
	return ("YOUR " if own else "ENEMY ") + ("BATTLE" if slot == -1 else "FIELD %d" % (slot + 1)) + ": " + darkner_name
