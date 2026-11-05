extends Control
## Debug screen that chooses each player's deck from data/decks/decks.json, then opens the
## hotseat with them. The hotseat's Change decks button comes back here.

const HOTSEAT_SCENE := "res://game/screen/debug/hotseat/hotseat.tscn"
const FONT_SIZE := 22
## The decks each list starts on, by decks.json id, unless setup() names others.
const DEFAULT_DECKS: Array[String] = ["creative", "holy"]

var _deck_ids: Array[String] = []
var _deck_defs: Dictionary = {}
var _database: CardDatabase
var _lists: Array[ItemList] = []
var _details: Array[Label] = []
## One list of the selected deck's cards per player, under its list of decks.
var _contents: Array[VBoxContainer] = []
var _start_button: Button
## The decks to select when the screen opens.
var _initial: Array[String] = DEFAULT_DECKS.duplicate()


## Called before the screen enters the tree, with the decks to select (decks.json ids).
func setup(deck_ids: Array[String]) -> void:
	_initial = deck_ids.duplicate()


func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = FONT_SIZE
	theme = ui_theme
	add_child(WindowControls.new())
	_build_ui()
	_load_decks()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	var title := Label.new()
	title.text = "Choose the decks"
	page.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	for index in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		var heading := Label.new()
		heading.text = "Player %d" % (index + 1)
		column.add_child(heading)
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.select_mode = ItemList.SELECT_SINGLE
		list.item_selected.connect(_on_deck_selected.bind(index))
		column.add_child(list)
		_lists.append(list)
		# The selected deck's cards take the lower half of the column.
		var contents_scroll := ScrollContainer.new()
		contents_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		contents_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		column.add_child(contents_scroll)
		var contents := VBoxContainer.new()
		contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		contents_scroll.add_child(contents)
		_contents.append(contents)
		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(detail)
		_details.append(detail)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	page.add_child(buttons)
	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_start)
	buttons.add_child(_start_button)
	for entry: Array in [
		["Window / Fullscreen (F11)", WindowControls.toggle_windowed],
		["Quit (Esc)", get_tree().quit],
	]:
		var button := Button.new()
		button.text = str(entry[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1] as Callable)
		buttons.add_child(button)


func _load_decks() -> void:
	_database = DataLoader.load_card_database()
	var decks: Variant = DataLoader.read_json(DataLoader.DECKS_PATH)
	if _database.card_count() == 0 or not decks is Dictionary or (decks as Dictionary).is_empty():
		_details[0].text = "Could not load data/cards.json or data/decks.json. See the Output panel."
		_start_button.disabled = true
		return
	_deck_defs = decks as Dictionary
	for id: Variant in _deck_defs:
		_deck_ids.append(str(id))
	for index in _lists.size():
		for id in _deck_ids:
			_lists[index].add_item(str((_deck_defs[id] as Dictionary).get("name", id)))
		var wanted := _deck_ids.find(_initial[index]) if index < _initial.size() else -1
		var selected := wanted if wanted != -1 else mini(index, _deck_ids.size() - 1)
		_lists[index].select(selected)
		_on_deck_selected(selected, index)


## Shows the deck's cards in decks.json order, each with its count and its text on hover, then
## its size, what it is made of, and anything the round rules object to. Test decks are smaller
## than the rules require on purpose: they are reported, not blocked.
func _on_deck_selected(item: int, index: int) -> void:
	var deck_def := _deck_defs[_deck_ids[item]] as Dictionary
	var contents := _contents[index]
	for child in contents.get_children():
		contents.remove_child(child)
		child.queue_free()
	var counts := deck_def.get("cards", {}) as Dictionary
	for id: Variant in counts:
		var card := _database.make(str(id))
		if card == null:
			continue
		var chip := CardChip.for_card(card)
		chip.text = "%s: %d" % [card.name, int(counts[id])]
		contents.add_child(chip)

	var deck := _database.build_deck(deck_def)
	var darkners := 0
	var energy := 0
	for card in deck:
		if card.is_pokemon():
			darkners += 1
		elif card.is_energy():
			energy += 1
	var lines := PackedStringArray(["%d cards: %d Darkners, %d Energy, %d ACT" % [deck.size(), darkners, energy, deck.size() - darkners - energy]])
	for problem in DeckValidator.validate(deck, MatchRules.deltarune()):
		lines.append("Note: the deck %s" % problem)
	_details[index].text = "\n".join(lines)


func _picked() -> Array[String]:
	var picked: Array[String] = []
	for list in _lists:
		var selected := list.get_selected_items()
		picked.append(_deck_ids[selected[0] if not selected.is_empty() else 0])
	return picked


func _start() -> void:
	var hotseat: Node = (load(HOTSEAT_SCENE) as PackedScene).instantiate()
	hotseat.call("setup", _picked())
	var tree := get_tree()
	tree.root.add_child(hotseat)
	tree.current_scene = hotseat
	queue_free()