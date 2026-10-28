class_name HoldButton
extends Control
## Large round context-action button supporting press-and-hold with multi-touch.

signal down
signal up

var text := "":
	set(v):
		text = v
		queue_redraw()
var enabled := true:
	set(v):
		enabled = v
		queue_redraw()
var fill_color := Color(0.89, 0.29, 0.23)
var font_size := 22
var _touch := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_down() -> bool:
	return _touch != -1


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		var inside := t.position.distance_to(global_position + size / 2) <= size.x / 2
		if t.pressed and _touch == -1 and inside:
			_touch = t.index
			get_viewport().set_input_as_handled()
			queue_redraw()
			down.emit()
		elif not t.pressed and t.index == _touch:
			force_release()


func force_release() -> void:
	if _touch == -1:
		return
	_touch = -1
	queue_redraw()
	up.emit()


func _draw() -> void:
	var r := size.x / 2
	var c := size / 2
	var col := fill_color if enabled else Color(0.35, 0.38, 0.42)
	if _touch != -1:
		col = col.lightened(0.2)
	draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.25))
	draw_circle(c, r, col)
	draw_arc(c, r - 3, 0, TAU, 48, Color(1, 1, 1, 0.55), 4.0, true)
	var font := get_theme_default_font()
	var lines := text.split("\n")
	var y := c.y - (lines.size() - 1) * font_size * 0.6
	for line in lines:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		draw_string(font, Vector2(c.x - w / 2, y + font_size * 0.35), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1))
		y += font_size * 1.2
