extends RefCounted

const WORDS := preload("res://game/presentation/board_text.gd")

var ui

func _init(controller) -> void:
	ui = controller

static func heads_action(view: PlayerView) -> Dictionary:
	if view.choice_kind != PendingChoice.KIND_COIN_CALL or view.chooser != view.viewer:
		return {}
	for index: int in range(view.choice_options.size()):
		if view.choice_options[index].get("value") == true:
			return {"type": "choose", "option": index}
	return {}

static func prompt(local_tosser: bool, purpose: String = WORDS.COIN_FIRST_PURPOSE) -> String:
	return WORDS.coin_prompt(local_tosser, purpose)

# Yeah I'm just gonna skip the engine's request to pick heads or tails and default heads to meaning you won the coin toss, like in Pokémon
func present(local_tosser: bool, on_toss: Callable, purpose: String = WORDS.COIN_FIRST_PURPOSE, action: Dictionary = {}) -> void:
	ui.selection.reset()
	ui._clear(ui.grid)
	ui._clear(ui.controls)
	ui._open_choices(prompt(local_tosser, purpose), true)
	ui.choice_card_view.hide()
	if not local_tosser:
		return
	var button: Button = ui._button(WORDS.TOSS_COIN, Vector2(320, 85))
	if not action.is_empty():
		button.set_meta("action", action)
	button.pressed.connect(func() -> void:
		if button.disabled:
			return
		button.disabled = true
		if on_toss.is_valid():
			on_toss.call())
	ui.grid.add_child(button)
