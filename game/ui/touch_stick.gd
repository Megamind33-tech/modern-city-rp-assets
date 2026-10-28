class_name TouchStick
extends Control
## Floating virtual stick. Tracks its own touch index so it works alongside other
## simultaneous touches (holding the action button while walking).

const RADIUS := 85.0

var value := Vector2.ZERO  # x right, y up
var _touch := -1
var _center := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center = size / 2


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed and _touch == -1 and get_global_rect().has_point(t.position):
			_touch = t.index
			_center = t.position - global_position
			value = Vector2.ZERO
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif not t.pressed and t.index == _touch:
			release()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _touch:
			var v := (d.position - global_position - _center) / RADIUS
			if v.length() > 1.0:
				v = v.normalized()
			value = Vector2(v.x, -v.y)
			get_viewport().set_input_as_handled()
			queue_redraw()


func release() -> void:
	_touch = -1
	value = Vector2.ZERO
	_center = size / 2
	queue_redraw()


func _draw() -> void:
	var c := _center if _touch != -1 else size / 2
	draw_circle(c, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(c, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0, true)
	draw_circle(c + Vector2(value.x, -value.y) * RADIUS, 38, Color(0.96, 0.92, 0.85, 0.75))
