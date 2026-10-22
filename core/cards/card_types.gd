class_name CardTypes
extends RefCounted
## The one list of type names. Every parser, the translator and the effect validator read
## it, so a type is added in one place.

## Deltarune TCG (Design Document 3.4).
const DELTARUNE := ["Holy", "Electric", "Virus", "Flower", "Fighting", "Fun", "Chaos", "Order", "Creative", "Darkness"]
## WOTC types still used by the legacy test data. Fighting is shared with DELTARUNE.
const LEGACY := ["Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting"]
## Colorless is a cost symbol that any Energy pays, and also a type: a Darkner can be
## Colorless, and a Special Energy can provide it (Double Colorless Energy). A Basic Energy
## never provides it.
const COLORLESS := "Colorless"