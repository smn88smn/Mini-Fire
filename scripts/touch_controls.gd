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
		"reload": Rect2(size.x - 330, size.y - 110, 80, 80),
		"switch": Rect2(size.x - 120, size.y - 330, 90, 70),
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
	_draw_stick(lc, _left_vec, Color(0.6, 0.8, 1.0))
	_draw_stick(rc, _right_vec, Color(1.0, 0.45, 0.35) if fire else Color(1.0, 0.75, 0.6))
	var font := ThemeDB.fallback_font
	for b in _buttons():
		var r: Rect2 = _buttons()[b]
		var held: bool = b in _btn_touch.values()
		draw_rect(r, Color(1, 1, 1, 0.28 if held else 0.14))
		draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
		var label := "R" if b == "reload" else "SWAP"
		draw_string(font, Vector2(r.position.x, r.get_center().y + 7), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)


func _draw_stick(c: Vector2, v: Vector2, col: Color) -> void:
	draw_circle(c, STICK_RADIUS, Color(col.r, col.g, col.b, 0.12))
	draw_arc(c, STICK_RADIUS, 0, TAU, 40, Color(col.r, col.g, col.b, 0.45), 2.0)
	draw_circle(c + v * STICK_RADIUS, KNOB_RADIUS, Color(col.r, col.g, col.b, 0.5))
