class_name CardButton
extends Button
## A button that acts on a card, such as "Play Susie (Lightner)". Hovering it shows the card's
## full text, the same tooltip as CardChip.

var _bbcode: String = ""


## Shows card's text when the button is hovered.
func show_card(card: CardData, terms: Dictionary = CardText.DELTARUNE) -> void:
	_bbcode = CardText.describe(card, terms)
	# A tooltip only appears when tooltip_text is not empty.
	tooltip_text = card.name

## Shows the text of a card in play, with its damage and attached Energy, when hovered.
func show_in_play(in_play: CardInPlay, terms: Dictionary = CardText.DELTARUNE) -> void:
	_bbcode = CardText.describe_in_play(in_play, terms)
	tooltip_text = in_play.card.name

func _make_custom_tooltip(_for_text: String) -> Object:
	return CardChip.make_tooltip(_bbcode)