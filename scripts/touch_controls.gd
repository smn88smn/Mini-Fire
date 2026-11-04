class_name TouchControls
extends Control
## Mini-Militia style dual-stick touch controls.
## Left stick: move (push up = jetpack). Right stick: aim, and fires while pushed past the ring.
## Extra buttons: reload, switch weapon. Fully multi-touch.

signal reload_pressed
signal switch_pressed

const STICK_RADIUS := 85.0
const KNOB_RADIUS := 34.0
const FIRE_THRESHOLD := 0.55
const JET_THRESHOLD := 0.45

var move := 0.0
var jet := false
var aim := Vector2.ZERO
var fire := false

var _left_touch := -1
var _right_touch := -1
var _left_center := Vector2.ZERO
var _right_center := Vector2.ZERO
var _left_vec := Vector2.ZERO
var _right_vec := Vector2.ZERO
var _btn_touch := {}  # index -> button name


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _default_left() -> Vector2:
	return Vector2(160, size.y - 150)


func _default_right() -> Vector2:
	return Vector2(size.x - 170, size.y - 150)


func _buttons() -> Dictionary:
	return {
		"reload": Rect2(size.x - 335, size.y - 115, 84, 84),
		"switch": Rect2(size.x - 125, size.y - 345, 88, 88),
	}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			for b in _buttons():
				if _buttons()[b].has_point(e.position):
					_btn_touch[e.index] = b
					if b == "reload":
						reload_pressed.emit()
					else:
						switch_pressed.emit()
					get_viewport().set_input_as_handled()
					return
			if e.position.y < 90.0:
				return  # leave the top bar for HUD buttons
			if e.position.x < size.x * 0.5 and _left_touch == -1:
				_left_touch = e.index
				_left_center = e.position
				_left_vec = Vector2.ZERO
			elif e.position.x >= size.x * 0.5 and _right_touch == -1:
				_right_touch = e.index
				_right_center = e.position
				_right_vec = Vector2.ZERO
		else:
			_btn_touch.erase(e.index)
			if e.index == _left_touch:
				_left_touch = -1
				_left_vec = Vector2.ZERO
			elif e.index == _right_touch:
				_right_touch = -1
				_right_vec = Vector2.ZERO
		_recompute()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _left_touch:
			_left_vec = ((d.position - _left_center) / STICK_RADIUS).limit_length(1.0)
		elif d.index == _right_touch:
			_right_vec = ((d.position - _right_center) / STICK_RADIUS).limit_length(1.0)
		_recompute()


func _recompute() -> void:
	move = _left_vec.x if absf(_left_vec.x) > 0.15 else 0.0
	jet = _left_vec.y < -JET_THRESHOLD
	if _right_vec.length() > 0.2:
		aim = _right_vec.normalized()
	fire = _right_touch != -1 and _right_vec.length() > FIRE_THRESHOLD
	queue_redraw()


func reset() -> void:
	_left_touch = -1
	_right_touch = -1
	_left_vec = Vector2.ZERO
	_right_vec = Vector2.ZERO
	_btn_touch.clear()
	_recompute()


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var lc := _left_center if _left_touch != -1 else _default_left()
	var rc := _right_center if _right_touch != -1 else _default_right()
	_draw_stick(lc, _left_vec, Color(0.45, 0.75, 1.0), jet)
	_draw_stick(rc, _right_vec, Color(1.0, 0.35, 0.25) if fire else Color(1.0, 0.65, 0.35), fire)
	for b in _buttons():
		var r: Rect2 = _buttons()[b]
		var held: bool = b in _btn_touch.values()
		var c := r.get_center()
		var rad := minf(r.size.x, r.size.y) * 0.5
		draw_circle(c + Vector2(0, 3), rad, Color(0, 0, 0, 0.3))
		draw_circle(c, rad, Color(0.08, 0.1, 0.2, 0.62 if held else 0.45))
		draw_arc(c, rad - 1.5, 0, TAU, 40, Color(1, 1, 1, 0.55 if held else 0.35), 3.0, true)
		draw_arc(c, rad - 6.0, PI * 1.15, PI * 1.85, 16, Color(1, 1, 1, 0.25), 3.0, true)
		if b == "reload":
			var t := UIKit.icon_tex("reload")
			draw_texture_rect(t, Rect2(c - Vector2(rad, rad) * 0.62, Vector2(rad, rad) * 1.24), false)
		else:
			var g := GunArt.texture("pistol")
			var w := rad * 1.3
			var h := w * g.get_height() / g.get_width()
			draw_texture_rect(g, Rect2(c - Vector2(w * 0.5, h * 0.62), Vector2(w, h)), false)
			var font := UIKit.font()
			draw_string_outline(font, Vector2(c.x - rad, c.y + rad * 0.62), "SWAP", HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 15, 4, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(c.x - rad, c.y + rad * 0.62), "SWAP", HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 15, Color.WHITE)


func _draw_stick(c: Vector2, v: Vector2, col: Color, active: bool) -> void:
	draw_circle(c, STICK_RADIUS + 4, Color(0, 0, 0, 0.18))
	draw_circle(c, STICK_RADIUS, Color(col.r * 0.2, col.g * 0.2, col.b * 0.3, 0.35))
	draw_arc(c, STICK_RADIUS, 0, TAU, 48, Color(col.r, col.g, col.b, 0.75 if active else 0.45), 3.0, true)
	draw_arc(c, STICK_RADIUS * FIRE_THRESHOLD, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0, true)
	var k := c + v * STICK_RADIUS
	draw_circle(k + Vector2(0, 3), KNOB_RADIUS, Color(0, 0, 0, 0.3))
	draw_circle(k, KNOB_RADIUS, Color(col.r * 0.75, col.g * 0.75, col.b * 0.75, 0.85))
	draw_circle(k, KNOB_RADIUS - 5, Color(col.r, col.g, col.b, 0.9))
	draw_circle(k + Vector2(0, -KNOB_RADIUS * 0.35), KNOB_RADIUS * 0.5, Color(1, 1, 1, 0.28))
	draw_arc(k, KNOB_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
