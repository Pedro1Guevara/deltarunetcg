class_name PendingChoice
extends RefCounted
## The one question a round can be waiting on (Design Document 8.4). While it is open,
## answering it is the only legal action. The chooser is explicit because it is not always the
## player taking the turn: a knocked out player promotes, and some effects ask the opponent.

## What the engine does with the answer.
const RESUME_SETUP := "setup"
const RESUME_PROMOTE := "promote"
const RESUME_RETREAT := "retreat"
const RESUME_EFFECT := "effect"

## Index of the player who answers.
var chooser: int
var prompt: String
## [{"label": String, "value": Variant}], one per legal answer. An option may also carry
## "shows": the card or Darkner in play it is about, for display only.
var options: Array
## One of the RESUME_ constants.
var resume: String
## Values the resume step needs, such as {"slot": int} for a flee.
var data: Dictionary
## Cards shown to the chooser while they answer, such as their deck during a search, in the
## order the effect gives them. Empty for most choices.
var revealed: Array[CardData] = []
## The suspended effect. Set only when resume is RESUME_EFFECT.
var resolver: EffectResolver = null
var context: EffectContext = null


func _init(answered_by: int, question: String, answers: Array, resume_with: String, resume_data: Dictionary) -> void:
	chooser = answered_by
	prompt = question
	options = answers
	resume = resume_with
	data = resume_data


## The option the player picked, by index in options.
func option(index: int) -> Dictionary:
	return options[index] as Dictionary