class_name UIKit
extends RefCounted
## Shared UI theme and widget helpers. All menus are built in code with these,
## so there are no fragile .tscn layouts to break.

const ACCENT := Color("ff5a1f")
const ACCENT2 := Color("ffd23f")
const BG := Color("0f1220")
const PANEL := Color("1a1f33")
const PANEL2 := Color("232a44")
const TEXT := Color("eef1ff")
const MUTED := Color("8d96b8")
const GOOD := Color("4dff88")
const BAD := Color("ff4d5e")

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	var btn := _box(PANEL2, 10, 2, Color("3a4570"))
	var btn_h := _box(Color("2e3760"), 10, 2, ACCENT)
	var btn_p := _box(ACCENT.darkened(0.25), 10, 2, ACCENT)
	var btn_d := _box(Color("1a1f33"), 10, 2, Color("2a3150"))
	for ty in ["Button", "OptionButton"]:
		t.set_stylebox("normal", ty, btn)
		t.set_stylebox("hover", ty, btn_h)
		t.set_stylebox("pressed", ty, btn_p)
		t.set_stylebox("disabled", ty, btn_d)
		t.set_stylebox("focus", ty, StyleBoxEmpty.new())
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, Color.WHITE)
		t.set_color("font_pressed_color", ty, Color.WHITE)
		t.set_color("font_disabled_color", ty, MUTED)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 14, 0, Color.TRANSPARENT))
	t.set_stylebox("panel", "Panel", _box(PANEL, 14, 0, Color.TRANSPARENT))
	var le := _box(Color("10142a"), 8, 2, Color("3a4570"))
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _box(Color("10142a"), 8, 2, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	var grab := _box(ACCENT, 8, 0, Color.TRANSPARENT)
	t.set_stylebox("slider", "HSlider", _box(PANEL2, 4, 0, Color.TRANSPARENT))
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	t.set_stylebox("panel", "PopupMenu", _box(PANEL2, 8, 2, Color("3a4570")))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_font_size("font_size", "PopupMenu", 20)
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


static func button(text: String, cb: Callable, min_w: float = 0.0, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 54)
	b.pressed.connect(func():
		Sfx.play("ui", 0.6, 0.0)
		cb.call())
	return b


static func accent_button(text: String, cb: Callable, min_w: float = 0.0, size: int = 24) -> Button:
	var b := button(text, cb, min_w, size)
	b.add_theme_stylebox_override("normal", _box(ACCENT, 10, 2, ACCENT.lightened(0.2)))
	b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.12), 10, 2, ACCENT2))
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.2), 10, 2, ACCENT2))
	return b


static func panel(bg: Color = PANEL, radius: int = 14) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(bg, radius, 0, Color.TRANSPARENT)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	return p


static func spacer(h: float = 0.0, w: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c


static func hfill() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Full-screen background with subtle gradient + root margin container.
static func screen_root(owner: Control) -> MarginContainer:
	owner.theme = theme()
	owner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	owner.add_child(m)
	return m


## Wallet chip: "MFC 1234   Gems 56"
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
	layer.add_child(c)
	var box := panel(Color(0.08, 0.09, 0.15, 0.92))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label(text, 22, color, HORIZONTAL_ALIGNMENT_CENTER))
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
