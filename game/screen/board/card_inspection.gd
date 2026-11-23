extends Control

const LAYOUT := preload("res://game/screen/board/board_layout.gd")
const REGIONS := preload("res://game/screen/board/card_regions.gd")
const AREA := LAYOUT.INSPECTION_AREA
var board
var area := AREA
var artwork: TextureRect
var base_artwork: TextureRect
var energy: Control
var hotspots: Control
var layers: Array[Dictionary] = []
var bounds := Rect2()
var signature := ""

func _init(owner: Control) -> void:
	board = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_artwork = _image()
	artwork = _image()
	energy = board._create_energy_row(self, "AttachedEnergy")
	hotspots = Control.new()
	hotspots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hotspots)
	hide()

func _image() -> TextureRect:
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	return image

func show_card(data: CardData, state: CardInPlay = null, zone: String = "", interactive: bool = false) -> void:
	var base: CardData = null
	if data.stage == CardData.STAGE_BREAK and state != null and not state.evolved_from.is_empty():
		base = state.evolved_from.back()
	var key := data.id + ":" + (base.id if base != null else "")
	if key != signature:
		signature = key
		_layout(data, base)
	board._show_inspection_energy(energy, state, layers.front()["rect"], LAYOUT.INSPECTION_ENERGY_SIZE)
	board.interaction._clear(hotspots)
	if interactive:
		_add_actions(data, state, zone)
	show()

func _texture(data: CardData) -> Texture2D:
	return board.get_node("CardManager").card_factory.call("texture_for", data)

func _layout(data: CardData, base: CardData) -> void:
	layers.clear()
	if base == null:
		base_artwork.hide()
		board._layout_card_art(artwork, data, _texture(data), area)
		bounds = board._displayed_art_bounds(data, _texture(data), area)
		layers.append({"data": data, "rect": bounds})
		return
	var base_texture := _texture(base)
	var top_texture := _texture(data)
	var base_ratio := base_texture.get_size().x / base_texture.get_size().y
	var top_ratio := top_texture.get_size().x / top_texture.get_size().y
	var content := REGIONS.content_start(base.id)
	var height := top_ratio + 1.0 - content
	var scale := minf(area.size.x, area.size.y / height)
	var top_size := Vector2(scale, scale * top_ratio)
	var base_size := Vector2(scale * base_ratio, scale)
	var top := Rect2(Vector2(area.get_center().x - top_size.x / 2.0, area.position.y), top_size)
	var underneath := Rect2(Vector2(area.get_center().x - base_size.x / 2.0, top.end.y - scale * content), base_size)
	board._layout_card_art(base_artwork, base, base_texture, underneath)
	board._layout_card_art(artwork, data, top_texture, top)
	base_artwork.show()
	bounds = Rect2(top.position, Vector2(top.size.x, underneath.end.y - top.position.y))
	layers.append({"data": base, "rect": underneath, "visible": Rect2(Vector2(underneath.position.x, top.end.y), Vector2(underneath.size.x, underneath.end.y - top.end.y))})
	layers.append({"data": data, "rect": top})

func contains(point: Vector2) -> bool:
	for layer: Dictionary in layers:
		if layer.get("visible", layer["rect"]).has_point(point):
			return true
	return energy.visible and Rect2(energy.position, energy.size).has_point(point)

func _add_actions(data: CardData, state: CardInPlay, zone: String) -> void:
	if board.player_view == null or not board.session.is_human_turn() or board.player_view.chooser >= 0:
		return
	var own := zone == "PlayerBattle" or zone.begins_with("PlayerField")
	var slot := -1 if zone == "PlayerBattle" else int(zone.trim_prefix("PlayerField")) - 1
	for layer: Dictionary in layers:
		var printed: CardData = layer["data"]
		for region: Dictionary in REGIONS.regions(printed.id):
			var action: Dictionary = {}
			if own and state != null:
				for offered: Dictionary in board.player_view.legal_actions:
					if region["kind"] == "attack" and offered["type"] == "attack" and zone == "PlayerBattle":
						var attack: AttackData = state.attacks()[int(offered["attack_index"])]
						if state.card_with_attack(attack).id == printed.id and printed.attacks[int(region["index"])].name == attack.name:
							action = offered
					elif region["kind"] == "ability" and offered["type"] == "use_power" and int(offered["slot"]) == slot:
						if printed.powers[int(region["index"])].name == str(offered["power"]):
							action = offered
			if not action.is_empty():
				_hotspot(_region_rect(layer, region["rect"]), action)
		if own and state != null and printed.id == state.base_card().id and zone == "PlayerBattle":
			for offered: Dictionary in board.player_view.legal_actions:
				if offered["type"] == "retreat":
					var button := _hotspot(_region_rect(layer, [0.65, 0.885, 0.26, 0.08]), {})
					button.tooltip_text = board.WORDS.FLEE
					button.pressed.connect(board.interaction.begin_flee)
					break
	if zone == "Area":
		for offered: Dictionary in board.player_view.legal_actions:
			if offered["type"] == "use_area":
				_hotspot(_region_rect(layers.back(), [0.04, 0.75, 0.92, 0.14]), offered)

func _region_rect(layer: Dictionary, values: Array) -> Rect2:
	var rect: Rect2 = layer["rect"]
	var result := Rect2(rect.position + Vector2(values[0], values[1]) * rect.size, Vector2(values[2], values[3]) * rect.size)
	return result.intersection(layer.get("visible", rect))

func _hotspot(rect: Rect2, action: Dictionary) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("pressed", empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 0, 0.14)
	hover.border_color = Color.YELLOW
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", empty)
	if not action.is_empty():
		button.set_meta("action", action)
		button.tooltip_text = ActionText.label(board.player_view, action, board.session.cards)
		button.pressed.connect(board.interaction.submit.bind(action))
	hotspots.add_child(button)
	return button
