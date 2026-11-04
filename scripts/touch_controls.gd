class_name TouchControls
extends Control
## Mini-Militia style dual-stick touch controls.
## Left stick: move (push up = jetpack). Right stick: aim, and fires while pushed past the ring.
## Buttons: reload, switch weapon (top right), scope zoom (top), pick up / swap ground gun
## (only shown while standing on one). Fully multi-touch.
## Layout is customizable: Profile.controls[id] = [x_frac, y_frac, scale]. In edit mode
## (controls editor in Settings) every control can be dragged and resized.

signal reload_pressed
signal switch_pressed
signal scope_pressed
signal pick_pressed
signal selection_changed(id: String)

const STICK_RADIUS := 85.0
const KNOB_RADIUS := 34.0
const FIRE_THRESHOLD := 0.55
const JET_THRESHOLD := 0.45
const IDS := ["lstick", "rstick", "reload", "switch", "scope", "pick"]
const BUTTONS := ["reload", "switch", "scope", "pick"]
const LABELS := {"lstick": "MOVE", "rstick": "AIM / FIRE", "reload": "RELOAD", "switch": "SWITCH", "scope": "SCOPE", "pick": "PICK UP"}
const MIN_SCALE := 0.6
const MAX_SCALE := 1.8

var move := 0.0
var jet := false
var aim := Vector2.ZERO
var fire := false

## Edit mode: drag controls around; nothing is emitted.
var editing := false
var selected := ""
var layout: Dictionary = {}

var _left_touch := -1
var _right_touch := -1
var _left_center := Vector2.ZERO
var _right_center := Vector2.ZERO
var _left_vec := Vector2.ZERO
var _right_vec := Vector2.ZERO
var _btn_touch := {}  # index -> button name
var _drag_index := -2
var _drag_off := Vector2.ZERO

# state shown on buttons (set by game every frame)
var pick_weapon := ""
var pick_kind := ""
var other_weapon := "pistol"
var scope_level := 1
var scope_available := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout = Profile.controls.duplicate(true)


func set_pick(w: String, kind: String) -> void:
	pick_weapon = w
	pick_kind = kind


func set_weapon_info(other: String, scope: int, has_scope: bool) -> void:
	other_weapon = other
	scope_level = scope
	scope_available = has_scope


# ---------------------------------------------------------------- layout
func default_center(id: String) -> Vector2:
	var w := size.x
	var h := size.y
	match id:
		"lstick": return Vector2(170, h - 150)
		"rstick": return Vector2(w - 175, h - 150)
		"reload": return Vector2(w - 360, h - 70)
		"switch": return Vector2(w - 62, 56)
		"scope": return Vector2(w - 166, 56)
		"pick": return Vector2(w - 365, h - 200)
	return Vector2(w, h) * 0.5


func base_radius(id: String) -> float:
	match id:
		"lstick", "rstick": return STICK_RADIUS
		"reload": return 42.0
		"switch": return 44.0
		"scope": return 40.0
		"pick": return 50.0
	return 40.0


func scale_of(id: String) -> float:
	var l = layout.get(id)
	if l is Array and l.size() >= 3:
		return clampf(float(l[2]), MIN_SCALE, MAX_SCALE)
	return 1.0


func center_of(id: String) -> Vector2:
	var l = layout.get(id)
	if l is Array and l.size() >= 2 and size.x > 0.0:
		return Vector2(clampf(float(l[0]), 0.0, 1.0) * size.x, clampf(float(l[1]), 0.0, 1.0) * size.y)
	return default_center(id)


func radius_of(id: String) -> float:
	return base_radius(id) * scale_of(id)


func set_center(id: String, c: Vector2) -> void:
	var r := radius_of(id) * 0.6
	c = c.clamp(Vector2(r, r), size - Vector2(r, r))
	layout[id] = [c.x / size.x, c.y / size.y, scale_of(id)]
	queue_redraw()


func set_control_scale(id: String, s: float) -> void:
	if id == "":
		return
	var c := center_of(id)
	layout[id] = [c.x / size.x, c.y / size.y, clampf(s, MIN_SCALE, MAX_SCALE)]
	queue_redraw()


func reset_layout() -> void:
	layout = {}
	queue_redraw()


func save_layout() -> void:
	Profile.controls = layout.duplicate(true)
	Profile.save_profile()


func _visible_buttons() -> Array:
	var out: Array = []
	for b in BUTTONS:
		if editing:
			out.append(b)
		elif b == "pick" and pick_weapon == "":
			continue
		elif b == "scope" and not scope_available:
			continue
		else:
			out.append(b)
	return out


func _button_at(pos: Vector2) -> String:
	for b in _visible_buttons():
		if pos.distance_to(center_of(b)) <= radius_of(b) * 1.1:
			return b
	return ""


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if editing:
		_edit_input(event)
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var b := _button_at(e.position)
			if b != "":
				_btn_touch[e.index] = b
				match b:
					"reload": reload_pressed.emit()
					"switch": switch_pressed.emit()
					"scope": scope_pressed.emit()
					"pick": pick_pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if e.position.y < 90.0:
				return  # leave the top bar for HUD buttons
			var lc := center_of("lstick")
			var rc := center_of("rstick")
			var near_l := e.position.distance_to(lc) < radius_of("lstick") * 1.5
			var near_r := e.position.distance_to(rc) < radius_of("rstick") * 1.5
			if (near_l or (e.position.x < size.x * 0.5 and not near_r)) and _left_touch == -1:
				_left_touch = e.index
				_left_center = lc if near_l else e.position
				_left_vec = ((e.position - _left_center) / radius_of("lstick")).limit_length(1.0) if near_l else Vector2.ZERO
			elif (near_r or e.position.x >= size.x * 0.5) and _right_touch == -1:
				_right_touch = e.index
				_right_center = rc if near_r else e.position
				_right_vec = ((e.position - _right_center) / radius_of("rstick")).limit_length(1.0) if near_r else Vector2.ZERO
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
			_left_vec = ((d.position - _left_center) / radius_of("lstick")).limit_length(1.0)
		elif d.index == _right_touch:
			_right_vec = ((d.position - _right_center) / radius_of("rstick")).limit_length(1.0)
		_recompute()


func _control_at(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in IDS:
		var d := pos.distance_to(center_of(id))
		if d <= radius_of(id) * 1.15 and d < best_d:
			best_d = d
			best = id
	return best


func _edit_input(event: InputEvent) -> void:
	var press := false
	var release := false
	var moved := false
	var pos := Vector2.ZERO
	var idx := -1
	if event is InputEventScreenTouch:
		press = event.pressed
		release = not event.pressed
		pos = event.position
		idx = event.index
	elif event is InputEventScreenDrag:
		moved = true
		pos = event.position
		idx = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
		press = event.pressed
		release = not event.pressed
		pos = event.position
		idx = 99
	elif event is InputEventMouseMotion and not DisplayServer.is_touchscreen_available():
		moved = true
		pos = event.position
		idx = 99
	else:
		return
	if press:
		var id := _control_at(pos)
		if id != "":
			selected = id
			_drag_index = idx
			_drag_off = center_of(id) - pos
			selection_changed.emit(id)
			get_viewport().set_input_as_handled()
			queue_redraw()
	elif release and idx == _drag_index:
		_drag_index = -2
	elif moved and idx == _drag_index and selected != "":
		set_center(selected, pos + _drag_off)
		get_viewport().set_input_as_handled()


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


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var lc := _left_center if _left_touch != -1 else center_of("lstick")
	var rc := _right_center if _right_touch != -1 else center_of("rstick")
	_draw_stick(lc, _left_vec, radius_of("lstick"), Color(0.45, 0.75, 1.0), jet)
	_draw_stick(rc, _right_vec, radius_of("rstick"), Color(1.0, 0.35, 0.25) if fire else Color(1.0, 0.65, 0.35), fire)
	var font := UIKit.font()
	for b in _visible_buttons():
		var c := center_of(b)
		var rad := radius_of(b)
		var held: bool = b in _btn_touch.values()
		var accent := Color(1, 1, 1)
		if b == "pick":
			accent = Color(1.0, 0.82, 0.25)
		draw_circle(c + Vector2(0, 3), rad, Color(0, 0, 0, 0.3))
		draw_circle(c, rad, Color(0.08, 0.1, 0.2, 0.62 if held else 0.45))
		if b == "pick":
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
			draw_arc(c, rad + 3.0, 0, TAU, 44, Color(accent.r, accent.g, accent.b, 0.35 + 0.4 * pulse), 4.0, true)
		draw_arc(c, rad - 1.5, 0, TAU, 40, Color(accent.r, accent.g, accent.b, 0.6 if held else 0.4), 3.0, true)
		draw_arc(c, rad - 6.0, PI * 1.15, PI * 1.85, 16, Color(1, 1, 1, 0.25), 3.0, true)
		var fs := int(14 * clampf(rad / 44.0, 0.8, 1.5))
		match b:
			"reload":
				var t := UIKit.icon_tex("reload")
				draw_texture_rect(t, Rect2(c - Vector2(rad, rad) * 0.62, Vector2(rad, rad) * 1.24), false)
			"switch":
				_draw_gun_icon(other_weapon, c + Vector2(0, -rad * 0.12), rad * 1.4)
				_label(font, c, rad, "SWAP", fs)
			"scope":
				draw_arc(c + Vector2(0, -rad * 0.12), rad * 0.42, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.5, true)
				draw_line(c + Vector2(-rad * 0.55, -rad * 0.12), c + Vector2(rad * 0.55, -rad * 0.12), Color(1, 1, 1, 0.7), 1.5)
				draw_line(c + Vector2(0, -rad * 0.67), c + Vector2(0, rad * 0.43), Color(1, 1, 1, 0.7), 1.5)
				_label(font, c, rad, "x%d" % scope_level if not editing else "x2", fs + 2)
			"pick":
				var w := pick_weapon if pick_weapon != "" else "mp5"
				_draw_gun_icon(w, c + Vector2(0, -rad * 0.15), rad * 1.45)
				var txt := "PICK"
				if pick_kind == "dual":
					txt = "DUAL x2"
				elif pick_kind == "ammo":
					txt = "AMMO"
				elif pick_kind == "swap":
					txt = "SWAP"
				_label(font, c, rad, txt, fs)
	if editing:
		for id in IDS:
			var c := center_of(id)
			var rad := radius_of(id)
			var sel: bool = id == selected
			draw_arc(c, rad + 8.0, 0, TAU, 48, Color(1.0, 0.85, 0.2, 0.95) if sel else Color(1, 1, 1, 0.35), 4.0 if sel else 2.0, true)
			var lt: String = LABELS[id]
			var ly := c.y - rad - 16.0
			if ly < 24.0:
				ly = c.y + rad + 26.0
			draw_string_outline(font, Vector2(c.x - 90, ly), lt, HORIZONTAL_ALIGNMENT_CENTER, 180, 16, 5, Color(0, 0, 0, 0.85))
			draw_string(font, Vector2(c.x - 90, ly), lt, HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(1.0, 0.9, 0.4) if sel else Color.WHITE)


func _draw_gun_icon(w: String, c: Vector2, width: float) -> void:
	var g := GunArt.texture(w)
	var h := width * g.get_height() / g.get_width()
	if h > width * 0.55:
		h = width * 0.55
		width = h * g.get_width() / g.get_height()
	draw_texture_rect(g, Rect2(c - Vector2(width * 0.5, h * 0.5), Vector2(width, h)), false)


func _label(font: Font, c: Vector2, rad: float, txt: String, fs: int) -> void:
	var p := Vector2(c.x - rad, c.y + rad * 0.62)
	draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, rad * 2, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, rad * 2, fs, Color.WHITE)


func _draw_stick(c: Vector2, v: Vector2, r: float, col: Color, active: bool) -> void:
	var kr := KNOB_RADIUS * r / STICK_RADIUS
	draw_circle(c, r + 4, Color(0, 0, 0, 0.18))
	draw_circle(c, r, Color(col.r * 0.2, col.g * 0.2, col.b * 0.3, 0.35))
	draw_arc(c, r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.75 if active else 0.45), 3.0, true)
	draw_arc(c, r * FIRE_THRESHOLD, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0, true)
	var k := c + v * r
	draw_circle(k + Vector2(0, 3), kr, Color(0, 0, 0, 0.3))
	draw_circle(k, kr, Color(col.r * 0.75, col.g * 0.75, col.b * 0.75, 0.85))
	draw_circle(k, kr - 5, Color(col.r, col.g, col.b, 0.9))
	draw_circle(k + Vector2(0, -kr * 0.35), kr * 0.5, Color(1, 1, 1, 0.28))
	draw_arc(k, kr, 0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
