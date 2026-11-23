@tool
extends Control

var displayed_value: float = 40.0:
	set(next):
		displayed_value = next
		queue_redraw()
var fill_tween: Tween

@export_range(0, 100) var value: float = 40.0:
	set(next):
		var target := clampf(next, 0.0, 100.0)
		if is_equal_approx(value, target):
			return
		value = target
		if is_instance_valid(fill_tween):
			fill_tween.kill()
		if Engine.is_editor_hint() or not is_inside_tree():
			displayed_value = value
			return
		fill_tween = create_tween()
		fill_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		fill_tween.tween_property(self, "displayed_value", value, 0.4)
@export var horizontal: bool = false:
	set(next):
		horizontal = next
		queue_redraw()

const TP_ART := preload("res://assets/ui/board/tp_lettering.png")
const MAX_ART := preload("res://assets/ui/board/max_lettering.png")
const REFERENCE_BAR := Rect2(41, 19, 24, 246)
const PERCENT_REFERENCE_BAR := Rect2(123, 51, 54, 558)
const TP_INK := Rect2(318, 162, 660, 972)
const MAX_INK := Rect2(473, 165, 660, 1698)

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

const FONT := preload("res://assets/textFonts/DeterminationMonoWebRegular-Z5oq.ttf")

func _ready() -> void:
	displayed_value = value
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var polygon: PackedVector2Array
	var cut: float
	var clip: PackedVector2Array
	if horizontal:
		var slant := minf(size.y, 28.0)
		polygon = PackedVector2Array([Vector2(slant, 0), Vector2(size.x, 0), Vector2(size.x - slant, size.y), Vector2(0, size.y)])
		cut = size.x * displayed_value / 100.0
		clip = PackedVector2Array([Vector2(0, 0), Vector2(cut, 0), Vector2(cut, size.y), Vector2(0, size.y)])
	else:
		var x := _bar_left()
		var width := size.x - x
		polygon = PackedVector2Array([Vector2(size.x, 0), Vector2(x, width), Vector2(x, size.y), Vector2(size.x, size.y - width)])
		cut = size.y * (1.0 - displayed_value / 100.0)
		clip = PackedVector2Array([Vector2(0, cut), Vector2(size.x, cut), Vector2(size.x, size.y), Vector2(0, size.y)])
	draw_colored_polygon(polygon, Color("850000"))
	if displayed_value > 0.0:
		for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon, clip):
			if not Geometry2D.triangulate_polygon(part).is_empty():
				draw_colored_polygon(part, Color("ffdf32") if displayed_value >= 100.0 else Color("ff9e38"))
	if displayed_value > 0.0 and displayed_value < 100.0:
		if horizontal:
			draw_line(Vector2(cut, 0), Vector2(cut, size.y), Color.WHITE, 4.0)
		else:
			var inset := maxf(0.0, size.x - _bar_left() - cut)
			var end := size.x - maxf(0.0, cut - (size.y - (size.x - _bar_left())))
			draw_line(Vector2(_bar_left() + inset, cut), Vector2(end, cut), Color.WHITE, 6.0 * size.y / PERCENT_REFERENCE_BAR.size.y)
	if horizontal:
		draw_string(FONT, Vector2(0, size.y - 5), "%d%%" % int(displayed_value), HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE)
	else:
		var factor := size.y / REFERENCE_BAR.size.y
		var origin := Vector2(_bar_left(), 0) - REFERENCE_BAR.position * factor
		var maximum := displayed_value >= 100.0
		if maximum:
			_draw_art(TP_ART, TP_INK, origin.x + 24.0 * factor, origin.y + 60.0 * factor, 42.0 * factor)
			_draw_art(MAX_ART, MAX_INK, origin.x + 26.0 * factor, origin.y + 114.0 * factor, 77.0 * factor)
		else:
			_draw_percentage()

func _draw_percentage() -> void:
	var factor := size.y / PERCENT_REFERENCE_BAR.size.y
	var origin := Vector2(_bar_left(), 0) - PERCENT_REFERENCE_BAR.position * factor
	_draw_art(TP_ART, TP_INK, origin.x + 84.0 * factor, origin.y + 144.0 * factor, 96.0 * factor)
	var digits := str(int(displayed_value))
	var ink_width := 36.0 + (digits.length() - 1) * 42.0
	var left := 63.0 - ink_width / 2.0
	draw_set_transform(origin, 0.0, Vector2.ONE * factor)
	for index: int in range(digits.length()):
		draw_char(FONT, Vector2(left + index * 42.0 - 6.0, 321), digits[index], 96)
	draw_char(FONT, Vector2(33, 396), "%", 96)
	draw_set_transform(Vector2.ZERO)

func _bar_left() -> float:
	return size.x - size.y * REFERENCE_BAR.size.x / REFERENCE_BAR.size.y

func _draw_art(texture: Texture2D, ink: Rect2, right: float, top: float, height: float) -> void:
	var factor := height / ink.size.y
	var at := Vector2(right - ink.end.x * factor, top - ink.position.y * factor)
	# Draw the entire original PNG; ink bounds only account for its transparent margins.
	draw_texture_rect(texture, Rect2(at, texture.get_size() * factor), false)
