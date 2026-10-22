class_name CardChip
extends Label
## A card's name in the hotseat. Hovering it shows the card's full text; moving the mouse
## away hides it. Only for the text hotseat: drawn cards will use CardText the same way.

const TOOLTIP_WIDTH := 460
const TOOLTIP_FONT_SIZE := 18

var _bbcode: String = ""


static func for_card(card: CardData, terms: Dictionary = CardText.DELTARUNE) -> CardChip:
	var chip := CardChip.new()
	chip.text = card.name
	chip._bbcode = CardText.describe(card, terms)
	chip._enable_tooltip()
	return chip


static func for_in_play(in_play: CardInPlay, terms: Dictionary = CardText.DELTARUNE) -> CardChip:
	var chip := CardChip.new()
	var energy := ", ".join(PackedStringArray(in_play.energy_pool()))
	chip.text = "%s  %d/%d HP  [%s]" % [in_play.card.name, in_play.remaining_hp(), in_play.card.hp, energy]
	chip._bbcode = CardText.describe_in_play(in_play, terms)
	chip._enable_tooltip()
	return chip


func _enable_tooltip() -> void:
	# A tooltip only appears when tooltip_text is not empty and the control receives the mouse.
	tooltip_text = text
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP


func _make_custom_tooltip(_for_text: String) -> Object:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0)
	for font_size: String in ["normal_font_size", "bold_font_size"]:
		label.add_theme_font_size_override(font_size, TOOLTIP_FONT_SIZE)
	label.text = _bbcode
	return label