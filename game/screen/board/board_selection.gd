extends RefCounted

const LAYOUT := preload("res://game/screen/board/board_layout.gd")
const WORDS := preload("res://game/presentation/board_text.gd")

var ui
var hand_mode := false
var browser_mode := false
var readonly_side := ""
var browser_scroll: ScrollContainer
var card_row: HBoxContainer
var confirm: Button
var show_all := false
var clicked_copy: CardData
var token := ""
var items: Array[Dictionary] = []
var hand_marks: Array[Control] = []
var candidates: Array[CardData] = []
var locations: Dictionary = {}
var location_names: Dictionary = {}

func _init(controller) -> void:
	ui = controller
	browser_scroll = ScrollContainer.new()
	browser_scroll.position = LAYOUT.BROWSER_ORIGIN
	browser_scroll.size = LAYOUT.BROWSER_SIZE
	browser_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	browser_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	browser_scroll.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			browser_scroll.scroll_horizontal += -120 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 120
			browser_scroll.accept_event())
	var bar := browser_scroll.get_h_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = Color.BLACK
	track.border_color = Color.WHITE
	track.set_border_width_all(3)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	bar.add_theme_stylebox_override("scroll", track)
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = Color.WHITE
	thumb.content_margin_left = 24
	thumb.content_margin_right = 24
	bar.add_theme_stylebox_override("grabber", thumb)
	var active := thumb.duplicate() as StyleBoxFlat
	active.bg_color = Color.YELLOW
	bar.add_theme_stylebox_override("grabber_highlight", active)
	bar.add_theme_stylebox_override("grabber_pressed", active)
	ui.overlay.add_child(browser_scroll)
	card_row = HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 18)
	browser_scroll.add_child(card_row)
	browser_scroll.hide()

func reset() -> void:
	readonly_side = ""
	hand_mode = false
	browser_mode = false
	browser_scroll.hide()
	items.clear()
	for mark: Control in hand_marks:
		if is_instance_valid(mark) and not mark.is_queued_for_deletion():
			if mark.get_parent() != null:
				mark.get_parent().remove_child(mark)
			mark.queue_free()
	hand_marks.clear()

func reset_choice() -> void:
	reset()
	clicked_copy = null
	candidates.clear()
	token = ""
	locations.clear()
	location_names.clear()

func present(view: PlayerView) -> bool:
	if view.choice_kind != PendingChoice.KIND_PICK_CARDS:
		return false
	var zone := str(view.choice_details.get("zone", ""))
	var next_token := str(view.event_count) + ":" + str(view.choice_details.get("about", "")) + ":" + zone
	if next_token != token:
		token = next_token
		if (view.choice_details.get("picked", []) as Array).is_empty():
			clicked_copy = null
			candidates.clear()
	for option: Dictionary in view.choice_options:
		var value: Variant = option.get("value")
		if value is CardData and not candidates.has(value):
			candidates.append(value as CardData)
	if zone == PendingChoice.ZONE_HAND:
		hand_mode = true
		ui._open_choices(WORDS.selection_prompt(view, ui.board.session.cards), false)
		ui.choices_scroll.hide()
		_add_confirm(view)
		_highlight_hand(view)
		return true
	browser_mode = true
	ui._open_choices(WORDS.selection_prompt(view, ui.board.session.cards), true)
	ui.choice_card_view.hide()
	ui.choices_scroll.hide()
	_add_confirm(view)
	var toggle: Button = ui._button(WORDS.SHOW_ALL_CARDS, Vector2(320, 80))
	toggle.toggle_mode = true
	toggle.button_pressed = show_all
	toggle.toggled.connect(func(pressed: bool) -> void:
		show_all = pressed
		_render_cards(ui.board.player_view))
	ui.controls.add_child(toggle)
	_render_cards(view)
	return true

func _add_confirm(view: PlayerView) -> void:
	var picked: int = (view.choice_details.get("picked", []) as Array).size()
	var maximum := int(view.choice_details.get("maximum", 1))
	var action: Dictionary = {}
	for index: int in range(view.choice_options.size()):
		if view.choice_options[index].get("pick") == PendingChoice.PICK_CONFIRM:
			action = ui._choice_action(index)
	confirm = ui._button(WORDS.confirm_text(picked, maximum), Vector2(320, 80))
	confirm.disabled = action.is_empty()
	if not action.is_empty():
		confirm.set_meta("action", action)
		confirm.pressed.connect(ui.submit.bind(action))
	ui.controls.position = Vector2(ui.dialogue.position.x, ui.dialogue.position.y + ui.dialogue.size.y + 20)
	ui.controls.add_child(confirm)

func _highlight_hand(view: PlayerView) -> void:
	var picked := view.choice_details.get("picked", []) as Array
	for card: Card in ui.board.get_node("CardManager/PlayerHand")._held_cards:
		var chosen := picked.has(card.card_info["data"])
		if int(view.choice_details.get("maximum", 1)) == 1 and clicked_copy != null:
			chosen = card.card_info["data"] == clicked_copy and not picked.is_empty()
		if not chosen:
			continue
		var mark := Panel.new()
		mark.name = "SelectionHighlight"
		mark.size = card.card_size
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 0, 0.12)
		style.border_color = Color.YELLOW
		style.set_border_width_all(4)
		mark.add_theme_stylebox_override("panel", style)
		card.add_child(mark)
		hand_marks.append(mark)

func click_hand(point: Vector2) -> bool:
	if not hand_mode or ui.menu_hidden:
		return false
	var card: Card = ui.hand_card_at(point)
	if card == null:
		return false
	_select_card(card.card_info["data"], _is_eligible(card.card_info["data"]))
	return true

func browse_discard(side: String) -> void:
	reset()
	readonly_side = side
	browser_mode = true
	ui._clear(ui.grid)
	ui._clear(ui.controls)
	ui._open_choices(WORDS.OWN_DISCARD if side == "Player" else WORDS.OPPONENT_DISCARD, true)
	ui.choice_card_view.hide()
	ui.choices_scroll.hide()
	var close: Button = ui._button(WORDS.BACK.to_upper(), Vector2(320, 80))
	close.pressed.connect(ui.close_browser)
	ui.controls.position = Vector2(ui.dialogue.position.x, ui.dialogue.position.y + ui.dialogue.size.y + 20)
	ui.controls.add_child(close)
	_render_cards(ui.board.player_view)

func _pool(view: PlayerView) -> Array[CardData]:
	if not readonly_side.is_empty():
		return view.me().discard if readonly_side == "Player" else view.opponent().discard
	if view.choice_details.get("zone") == PendingChoice.ZONE_DISCARD:
		return view.opponent().discard if view.choice_details.get("side") == PendingChoice.SIDE_OPPONENT else view.me().discard
	if view.choice_details.get("zone") == PendingChoice.ZONE_IN_PLAY:
		return _in_play_pool(view)
	return view.revealed if not view.revealed.is_empty() else candidates

func _in_play_pool(view: PlayerView) -> Array[CardData]:
	locations.clear()
	location_names.clear()
	var energies: Array[CardData] = []
	var holders: Array[String] = []
	var sides: Array[int] = []
	for side: PlayerView.SideView in view.sides:
		var darkners: Array[CardInPlay] = [side.active]
		darkners.append_array(side.bench)
		for index: int in range(darkners.size()):
			var darkner := darkners[index]
			if darkner == null:
				continue
			var key := "%d:%d" % [side.index, index - 1]
			for energy: CardData in darkner.attached_energy:
				energies.append(energy)
				locations[energy] = key
				location_names[energy] = WORDS.energy_location(side.index == view.viewer, index - 1, darkner.card.name)
				if candidates.has(energy):
					if not holders.has(key): holders.append(key)
					if not sides.has(side.index): sides.append(side.index)
	var pool: Array[CardData] = []
	for energy: CardData in energies:
		var key: String = locations[energy]
		var included := holders.has(key)
		if view.choice_details.get("about") == PendingChoice.ABOUT_DISCARD_IN_PLAY:
			included = sides.has(int(key.get_slice(":", 0)))
		if included:
			pool.append(energy)
	return pool

func _equivalent_copy(a: CardData, b: CardData, view: PlayerView) -> bool:
	if a == null or b == null or a.id != b.id:
		return false
	if view.choice_details.get("zone") == PendingChoice.ZONE_IN_PLAY:
		return locations.has(a) and locations.get(a) == locations.get(b)
	return true

func _render_cards(view: PlayerView) -> void:
	var scroll := browser_scroll.scroll_horizontal
	ui._clear(card_row)
	items.clear()
	var pool := _pool(view)
	var eligible: Array[CardData] = []
	if view.choice_details.get("zone") == PendingChoice.ZONE_DECK:
		eligible = CardFilter.select(pool, view.choice_details.get("filter", []) as Array, [])
	else:
		for data: CardData in pool:
			if not readonly_side.is_empty() or _is_eligible(data):
				eligible.append(data)
	var excluded := view.choice_details.get("excluded", []) as Array
	for index: int in range(pool.size()):
		var data: CardData = pool[index]
		var valid := not readonly_side.is_empty() or (eligible.has(data) and not excluded.has(data.name))
		if valid or show_all:
			items.append({"data": data, "eligible": valid, "order": index})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order: int = a["data"].name.naturalnocasecmp_to(b["data"].name)
		return a["order"] < b["order"] if order == 0 else order < 0)
	var totals := {}
	var copies := {}
	for data: CardData in pool:
		totals[data.id] = int(totals.get(data.id, 0)) + 1
	for item: Dictionary in items:
		var data: CardData = item["data"]
		copies[data.id] = int(copies.get(data.id, 0)) + 1
		var button := _card_button(data, bool(item["eligible"]), int(copies[data.id]), int(totals[data.id]), view)
		card_row.add_child(button)
	browser_scroll.show()
	browser_scroll.set_deferred("scroll_horizontal", scroll)

func _option_for(data: CardData, view: PlayerView) -> int:
	var equivalent := -1
	for index: int in range(view.choice_options.size()):
		var option: Dictionary = view.choice_options[index]
		if option.get("pick") not in [PendingChoice.PICK_ADD, PendingChoice.PICK_UNDO]:
			continue
		var offered := option.get("value") as CardData
		if offered == data:
			return index
		if int(view.choice_details["maximum"]) == 1 and _equivalent_copy(offered, data, view):
			equivalent = index
	return equivalent

func _card_button(data: CardData, valid: bool, copy: int, total: int, view: PlayerView) -> Button:
	var in_play: bool = readonly_side.is_empty() and view.choice_details.get("zone") == PendingChoice.ZONE_IN_PLAY
	var button: Button = ui._button("", Vector2(210, 356 if in_play else 330))
	button.set_meta("card_data", data)
	button.set_meta("eligible", valid)
	var option := _option_for(data, view) if valid and readonly_side.is_empty() else -1
	if option >= 0:
		button.set_meta("action", ui._choice_action(option))
	var picked: Array = (view.choice_details.get("picked", []) as Array) if readonly_side.is_empty() else []
	var chosen := picked.has(data)
	if int(view.choice_details.get("maximum", 1)) == 1 and clicked_copy != null:
		chosen = data == clicked_copy and not picked.is_empty()
	if chosen:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.BLACK
		style.border_color = Color.YELLOW
		style.set_border_width_all(4)
		button.add_theme_stylebox_override("normal", style)
	if not valid:
		button.modulate = Color(0.35, 0.35, 0.35)
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(image)
	ui.board._layout_card_art(image, data, ui.board.get_node("CardManager").card_factory.call("texture_for", data), Rect2(10, 10, 190, 270))
	var label := Label.new()
	label.position = Vector2(8, 285)
	label.size = Vector2(194, 40)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = data.name + (" (%d/%d)" % [copy, total] if total > 1 else "")
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_child(label)
	if in_play:
		var origin := Label.new()
		origin.position = Vector2(8, 326)
		origin.size = Vector2(194, 24)
		origin.text = str(location_names.get(data, ""))
		origin.add_theme_font_size_override("font_size", 12)
		origin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		origin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(origin)
	button.pressed.connect(func() -> void: _select_card(data, valid))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			ui.board.inspect_data(data)
			button.accept_event())
	return button

func _is_eligible(data: CardData) -> bool:
	for candidate: CardData in candidates:
		if candidate == data or (int(ui.board.player_view.choice_details["maximum"]) == 1 and _equivalent_copy(candidate, data, ui.board.player_view)):
			return true
	return false

func _select_card(data: CardData, valid: bool) -> void:
	if not readonly_side.is_empty():
		ui.board.inspect_data(data)
		return
	if not valid or ui.menu_hidden or ui.board.get_node("Pause").visible:
		return
	var view: PlayerView = ui.board.player_view
	var index := _option_for(data, view)
	if index < 0:
		var picked := view.choice_details.get("picked", []) as Array
		if picked.size() < int(view.choice_details["maximum"]) or picked.is_empty():
			return
		var oldest := _option_for(picked[0] as CardData, view)
		if oldest < 0 or not ui.submit(ui._choice_action(oldest)):
			return
		view = ui.board.player_view
		index = _option_for(data, view)
		if index < 0:
			return
	if view.choice_options[index].get("pick") == PendingChoice.PICK_ADD:
		clicked_copy = data
	elif int(view.choice_details.get("maximum", 1)) == 1 and clicked_copy != null and clicked_copy != data:
		clicked_copy = data
		if browser_mode:
			_render_cards(view)
		else:
			for mark: Control in hand_marks:
				mark.queue_free()
			hand_marks.clear()
			_highlight_hand(view)
		return
	ui.submit(ui._choice_action(index))

func set_menu_visible(open: bool) -> void:
	browser_scroll.visible = open and browser_mode
	for mark: Control in hand_marks:
		if is_instance_valid(mark):
			mark.visible = open
