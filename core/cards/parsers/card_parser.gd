class_name CardParser
extends RefCounted
## Turns one raw card object into CardData. Every card source (TCGdex, Deltarune) extends
## this, so CardDatabase does not depend on where its cards come from. Pure logic: no file access.

## Problems that make a card unusable. parse() returns null when it adds one.
var errors: Array[String] = []
## Problems that leave the card usable but incomplete.
var warnings: Array[String] = []


func clear_messages() -> void:
	errors.clear()
	warnings.clear()


## Returns the card, or null when it cannot be used. Subclasses override this.
func parse(_raw: Dictionary) -> CardData:
	push_error("CardParser: parse() is not implemented by %s" % get_script().resource_path)
	return null