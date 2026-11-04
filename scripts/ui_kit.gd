class_name UIKit
extends RefCounted
## Shared UI theme and widget helpers. All menus are built in code with these,
## so there are no fragile .tscn layouts to break. Glass buttons/panels are 9-patch PNGs.

const ACCENT := Color("ff7a1f")
const ACCENT2 := Color("ffd23f")
const BG := Color("0f1220")
const PANEL := Color("1a1f33")
const PANEL2 := Color("232a44")
const TEXT := Color("f4f6ff")
const MUTED := Color("a3acd0")
const GOOD := Color("5dff8f")
const BAD := Color("ff4d5e")

const GLASS_COLORS := ["orange", "blue", "green", "purple", "red", "yellow", "dark"]
const BTN_MARGIN := 22
const PANEL_MARGIN := 34

static var _theme: Theme = null
static var _font: Font = null
static var _styles: Dictionary = {}
static var _icons: Dictionary = {}
static var block_click_until := 0


## True right after a list was drag-scrolled: the finger release must not "click".
static func click_blocked() -> bool:
	return Time.get_ticks_msec() < block_click_until


static func font() -> Font:
	if _font == null:
		var f: FontFile = load("res://assets/fonts/LilitaOne-Regular.ttf")
		var fa: FontFile = load("res://assets/fonts/Vazirmatn-Bold.ttf")
		f.fallbacks = [fa]
		_font = f
	return _font


static func _tex_box(path: String, margin: int, content: Vector4 = Vector4(18, 10, 18, 12)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(path)
	s.texture_margin_left = margin
	s.texture_margin_right = margin
	s.texture_margin_top = margin
	s.texture_margin_bottom = margin
	s.content_margin_left = content.x
	s.content_margin_top = content.y
	s.content_margin_right = content.z
	s.content_margin_bottom = content.w
	return s


## Glass button style. color: orange, blue, green, purple, red, yellow, dark, disabled.
static func glass(color: String, pressed: bool = false) -> StyleBoxTexture:
	var key := color + ("_p" if pressed else "")
	if not _styles.has(key):
		var path := "res://assets/ui/btn_disabled.png" if color == "disabled" else "res://assets/ui/btn_%s%s.png" % [color, "_p" if pressed else ""]
		var s := _tex_box(path, BTN_MARGIN)
		if pressed:
			s.content_margin_top += 3
		_styles[key] = s
	return _styles[key]


static func glass_panel(solid: bool = false) -> StyleBoxTexture:
	var key := "panel_solid" if solid else "panel"
	if not _styles.has(key):
		_styles[key] = _tex_box("res://assets/ui/%s.png" % key, PANEL_MARGIN, Vector4(26, 22, 26, 24))
	return _styles[key]


static func card_style(rarity: String) -> StyleBoxTexture:
	var key := "card_" + rarity
	if not _styles.has(key):
		var r := rarity if rarity in ["common", "rare", "epic", "legend"] else "common"
		_styles[key] = _tex_box("res://assets/ui/card_%s.png" % r, PANEL_MARGIN, Vector4(16, 14, 16, 16))
	return _styles[key]


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22
	for ty in ["Button", "OptionButton"]:
		t.set_stylebox("normal", ty, glass("dark"))
		t.set_stylebox("hover", ty, glass("dark"))
		t.set_stylebox("pressed", ty, glass("dark", true))
		t.set_stylebox("disabled", ty, glass("disabled"))
		t.set_stylebox("focus", ty, StyleBoxEmpty.new())
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, Color.WHITE)
		t.set_color("font_pressed_color", ty, Color(1, 1, 1, 0.85))
		t.set_color("font_focus_color", ty, TEXT)
		t.set_color("font_disabled_color", ty, Color(0.75, 0.75, 0.8))
		t.set_color("font_outline_color", ty, Color(0, 0, 0, 0.55))
		t.set_constant("outline_size", ty, 4)
	t.set_stylebox("panel", "PanelContainer", glass_panel())
	t.set_stylebox("panel", "Panel", glass_panel())
	var le := _box(Color(0.04, 0.05, 0.1, 0.85), 12, 2, Color(1, 1, 1, 0.25))
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _box(Color(0.04, 0.05, 0.1, 0.9), 12, 2, ACCENT2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Label", 3)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	var grab := _box(ACCENT2, 8, 0, Color.TRANSPARENT)
	t.set_stylebox("slider", "HSlider", _box(Color(0, 0, 0, 0.45), 6, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	t.set_stylebox("panel", "PopupMenu", _box(Color("1b2140"), 10, 2, Color(1, 1, 1, 0.25)))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_font_size("font_size", "PopupMenu", 22)
	# slim, rounded scrollbars
	var sb_bg := _box(Color(0, 0, 0, 0.25), 4, 0, Color.TRANSPARENT)
	sb_bg.content_margin_left = 3
	sb_bg.content_margin_right = 3
	var sb_g := _box(Color(1, 1, 1, 0.35), 4, 0, Color.TRANSPARENT)
	for ty in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", ty, sb_bg)
		t.set_stylebox("grabber", ty, sb_g)
		t.set_stylebox("grabber_highlight", ty, sb_g)
		t.set_stylebox("grabber_pressed", ty, sb_g)
	_theme = t
	return t


static func _box(bg: Color, radius: int, border: int, border_col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func label(text: String, size: int = 20, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func _style_button(b: Button, color: String) -> void:
	b.add_theme_stylebox_override("normal", glass(color))
	b.add_theme_stylebox_override("hover", glass(color))
	b.add_theme_stylebox_override("pressed", glass(color, true))
	b.add_theme_stylebox_override("disabled", glass("disabled"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## Glossy colored button (press animation + click sound).
static func glass_button(text: String, color: String, cb: Callable, min_size: Vector2 = Vector2(0, 58), size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = min_size
	_style_button(b, color)
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2(0.96, 0.96))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	b.pressed.connect(func():
		if click_blocked():
			return
		Sfx.play("ui", 0.6, 0.0)
		cb.call())
	return b


static func button(text: String, cb: Callable, min_w: float = 0.0, size: int = 22) -> Button:
	return glass_button(text, "dark", cb, Vector2(min_w, 54), size)


static func accent_button(text: String, cb: Callable, min_w: float = 0.0, size: int = 24) -> Button:
	return glass_button(text, "orange", cb, Vector2(min_w, 58), size)


## Square glass button with an icon (and optional caption under it).
static func icon_button(icon_name: String, caption: String, color: String, cb: Callable, side: float = 74.0) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var b := glass_button("", color, cb, Vector2(side, side))
	var ic := icon(icon_name, side * 0.6)
	ic.custom_minimum_size = Vector2.ZERO
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = side * 0.18
	ic.offset_right = -side * 0.18
	ic.offset_top = side * 0.15
	ic.offset_bottom = -side * 0.21
	b.add_child(ic)
	box.add_child(b)
	if caption != "":
		box.add_child(label(caption, 16, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	return box


static func icon_tex(name: String) -> Texture2D:
	if not _icons.has(name):
		var path := "res://assets/icons/%s.png" % name
		_icons[name] = load(path) if ResourceLoader.exists(path) else null
	return _icons[name]


static func icon(name: String, side: float = 28.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon_tex(name)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(side, side)
	tr.size = Vector2(side, side)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func panel(bg: Color = PANEL, radius: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", glass_panel(bg.a > 0.95 and bg != PANEL))
	radius = radius
	return p


static func spacer(h: float = 0.0, w: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hfill() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Full-screen background image (+ dark overlay) and root margin container.
static func screen_root(owner: Control, image: String = "menu", dim: float = 0.45) -> MarginContainer:
	owner.theme = theme()
	owner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bgc := ColorRect.new()
	bgc.color = BG
	bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(bgc)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/bg/%s.jpg" % image)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(bg)
	var ov := ColorRect.new()
	ov.color = Color(0.02, 0.03, 0.08, dim)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(ov)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	owner.add_child(m)
	return m


## Small pill with an icon and a number.
static func chip(icon_name: String, text: String, color: Color = TEXT) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(0.03, 0.04, 0.09, 0.72), 22, 2, Color(1, 1, 1, 0.18))
	sb.content_margin_left = 8
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(icon(icon_name, 30))
	var l := label(text, 22, color)
	l.name = "Value"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	p.add_child(h)
	return p


## Live coin + gem chips.
static func wallet_chips() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := chip("coin", "0", ACCENT2)
	var g := chip("gem", "0", Color("9fe8ff"))
	row.add_child(c)
	row.add_child(g)
	var upd := func():
		if is_instance_valid(c):
			(c.find_child("Value", true, false) as Label).text = str(Profile.mfc)
			(g.find_child("Value", true, false) as Label).text = str(Profile.gems)
	upd.call()
	Profile.wallet_changed.connect(upd)
	row.tree_exiting.connect(func():
		if Profile.wallet_changed.is_connected(upd):
			Profile.wallet_changed.disconnect(upd))
	return row


## Old text wallet (kept for compatibility).
static func wallet_label() -> Label:
	var l := label("", 20, ACCENT2)
	var upd := func():
		if is_instance_valid(l):
			l.text = "MFC %d    Gems %d" % [Profile.mfc, Profile.gems]
	upd.call()
	Profile.wallet_changed.connect(upd)
	l.tree_exiting.connect(func():
		if Profile.wallet_changed.is_connected(upd):
			Profile.wallet_changed.disconnect(upd))
	return l


static func toast(owner: Node, text: String, color: Color = TEXT) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	owner.add_child(layer)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.theme = theme()
	layer.add_child(c)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", glass_panel(true))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label(text, 24, color, HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(box)
	var tw := owner.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(layer.queue_free)


## Safely removes all children (safe to call from a child's own signal).
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## ScrollContainer that scrolls by dragging anywhere (touch or mouse), like a phone list.
## A drag longer than a few pixels cancels the button press underneath.
class DragScroll extends ScrollContainer:
	var _down := false
	var _dragging := false
	var _start := Vector2.ZERO
	var _start_scroll := Vector2.ZERO
	var _vel := Vector2.ZERO
	var _last := Vector2.ZERO
	var _last_t := 0
	const THRESHOLD := 12.0

	func _init() -> void:
		follow_focus = false
		scroll_deadzone = 12

	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree():
			return
		var pos := Vector2.ZERO
		var pressed := false
		var is_press := false
		var is_motion := false
		if event is InputEventScreenTouch:
			if event.index != 0:
				return
			pos = event.position
			pressed = event.pressed
			is_press = true
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			pos = event.position
			pressed = event.pressed
			is_press = true
		elif event is InputEventScreenDrag:
			if event.index != 0:
				return
			pos = event.position
			is_motion = true
		elif event is InputEventMouseMotion and _down and not DisplayServer.is_touchscreen_available():
			pos = event.position
			is_motion = true
		else:
			return
		if is_press:
			if pressed:
				if get_global_rect().has_point(pos):
					_down = true
					_dragging = false
					_start = pos
					_last = pos
					_last_t = Time.get_ticks_msec()
					_start_scroll = Vector2(scroll_horizontal, scroll_vertical)
					_vel = Vector2.ZERO
			elif _down:
				_down = false
				if _dragging:
					_dragging = false
					UIKit.block_click_until = Time.get_ticks_msec() + 120
		elif is_motion and _down:
			var delta := pos - _start
			if not _dragging and delta.length() > THRESHOLD:
				_dragging = true
				UIKit.block_click_until = Time.get_ticks_msec() + 100000
			if _dragging:
				scroll_vertical = int(_start_scroll.y - delta.y)
				scroll_horizontal = int(_start_scroll.x - delta.x)
				var now := Time.get_ticks_msec()
				var dt := maxf(1.0, float(now - _last_t))
				_vel = (_last - pos) / dt * 16.0
				_last = pos
				_last_t = now

	func _exit_tree() -> void:
		if _dragging:
			UIKit.block_click_until = 0
		_down = false
		_dragging = false

	func _process(_d: float) -> void:
		if not _down and _vel.length() > 0.5:
			scroll_vertical += int(_vel.y)
			scroll_horizontal += int(_vel.x)
			_vel *= 0.9
