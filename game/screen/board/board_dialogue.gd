extends Panel

# Fun fact, this is the same stuff I used in the Soul Extractor! I just keep everything in a folder on my desktop lmao
const FONT := preload("res://assets/textFonts/DeterminationMonoWebRegular-Z5oq.ttf")
const SOUND := preload("res://game/screen/board/snd_text.wav")
const FONT_SIZE := 28
const LINE_PITCH := 31

var body: RichTextLabel
var sound: AudioStreamPlayer
var elapsed := 0.0

func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.border_color = Color.WHITE
	style.set_border_width_all(6)
	add_theme_stylebox_override("panel", style)
	body = RichTextLabel.new()
	body.position = Vector2(28, 24)
	body.size = Vector2(744, 162)
	body.bbcode_enabled = true
	body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_font_override("normal_font", FONT)
	body.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	body.add_theme_constant_override("line_separation", LINE_PITCH - int(FONT.get_height(FONT_SIZE)))
	add_child(body)
	sound = AudioStreamPlayer.new()
	sound.stream = SOUND
	sound.volume_db = -16
	sound.max_polyphony = 6
	add_child(sound)
	gui_input.connect(_on_input)

func message(text: String) -> void:
	if not text.is_empty() and text.right(1) not in [".", "?", "!"] and not text.ends_with(".)"):
		text += "."
	text = text if text.begins_with("*") else "* " + text
	if body.text == text:
		return
	body.text = text
	body.visible_characters = 0
	elapsed = 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree() or body.visible_characters < 0:
		return
	elapsed += delta
	var count := mini(int(elapsed * 42), body.get_total_character_count())
	if count > body.visible_characters:
		var text := body.get_parsed_text()
		if not text.substr(body.visible_characters, count - body.visible_characters).strip_edges().is_empty():
			play_typing()
		body.visible_characters = count

func skip_typing() -> bool:
	if not is_visible_in_tree() or body.visible_characters < 0 or body.visible_characters >= body.get_total_character_count():
		return false
	body.visible_characters = -1
	return true

func play_typing() -> void:
	sound.play()

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if skip_typing():
			accept_event()
