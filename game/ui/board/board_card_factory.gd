extends CardFactory

const CARD_SCENE := preload("res://game/ui/board/board_card.tscn")
var database: CardDatabase
var textures: Dictionary = {}

func preload_card_data() -> void:
	database = DataLoader.load_card_database()
	for file: String in DirAccess.get_files_at("res://assets/cards/fronts"):
		if file.get_extension().to_lower() not in ["png", "jpg", "webp"]:
			continue
		var key := file.get_basename().to_lower().replace("_", "").replace("card", "")
		textures[key] = load("res://assets/cards/fronts/" + file)

func create_card(card_name: String, target: CardContainer) -> Card:
	return create_from_data(database.make(card_name), target)

func texture_for(data: CardData) -> Texture2D:
	var texture: Texture2D = null
	var key := data.id.to_lower().replace("_", "")
	if textures.has(key):
		texture = textures[key] as Texture2D
	elif not data.image_url.is_empty() and ResourceLoader.exists(data.image_url):
		texture = load(data.image_url) as Texture2D
	if texture == null:
		texture = _placeholder(data.name, data.hp)
	return texture

func create_from_data(data: CardData, target: CardContainer) -> Card:
	if data == null:
		return null
	var card := _create_visual(target, texture_for(data))
	card.card_name = data.name
	card.card_info = {"data": data}
	return card

func create_hidden(target: CardContainer) -> Card:
	var card := _create_visual(target, _placeholder("?", 0))
	card.card_name = ""
	card.card_info = {}
	card.show_front = false
	card.can_be_interacted_with = false
	return card

func _create_visual(target: CardContainer, texture: Texture2D) -> Card:
	var card := CARD_SCENE.instantiate() as Card
	card.card_size = target.get_meta("display_size", card_size)
	card.size = card.card_size
	card.hover_scale = 1.8 if target is Hand else 1.08
	card.hover_distance = 0
	card.hover_rotation = 0.0
	card.moving_speed = 1800
	target.cards_node.add_child(card)
	card.set_faces(texture, _placeholder("?", 0))
	target.add_card(card)
	return card

func _placeholder(title: String, hp: int) -> Texture2D:
	var label := title.xml_escape()
	var detail := ("HP %d" % hp) if hp > 0 else "DELTARUNE TCG"
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="560"><rect x="3" y="3" width="394" height="554" rx="0" fill="#111" stroke="white" stroke-width="6"/><text x="200" y="75" text-anchor="middle" fill="white" font-size="22">%s</text><path d="M200 150L300 280L200 410L100 280Z" fill="#292136" stroke="#aa85da" stroke-width="4"/><text x="200" y="500" text-anchor="middle" fill="white" font-size="18">%s</text></svg>' % [label, detail]
	var image := Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)
