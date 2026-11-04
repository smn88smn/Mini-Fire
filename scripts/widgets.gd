class_name Widgets
extends RefCounted
## Small reusable controls: gun preview, character preview, color swatches.


## Shows a gun sprite with its skin shader, fitted inside the control.
class GunPreview extends Control:
	var weapon_id := "rifle":
		set(v):
			weapon_id = v
			_refresh()
	var skin_id := "default":
		set(v):
			skin_id = v
			_refresh()
	var gun_scale := 3.0  # kept for API compatibility (ignored, preview auto-fits)
	var padding := 0.12
	var _tr: TextureRect
	var _glow: TextureRect
	var backlight := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow = TextureRect.new()
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_glow.stretch_mode = TextureRect.STRETCH_SCALE
		_glow.texture = FXKit.soft_circle()
		_glow.modulate = Color(1, 1, 1, 0.16)
		add_child(_glow)
		_tr = TextureRect.new()
		_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(_tr)
		resized.connect(_layout)
		_refresh()

	func _layout() -> void:
		var p := size * padding
		_tr.position = p
		_tr.size = size - p * 2.0
		_glow.visible = backlight
		_glow.position = Vector2(size.x * 0.05, size.y * 0.1)
		_glow.size = Vector2(size.x * 0.9, size.y * 0.8)

	func _refresh() -> void:
		if _tr == null:
			return
		_tr.texture = GunArt.texture(weapon_id)
		if _tr.material is ShaderMaterial:
			GunArt.apply_skin(_tr.material, skin_id, weapon_id)
		else:
			_tr.material = GunArt.make_material(skin_id, weapon_id)
		_layout()


## Big soldier preview for menus: tinted character + equipped gun.
class CharacterPreview extends Control:
	var color := Color(0.9, 0.3, 0.3):
		set(v):
			color = v
			if _mat:
				_mat.set_shader_parameter("tint", v)
	var weapon_id := "rifle":
		set(v):
			weapon_id = v
			_refresh_gun()
	var skin_id := "default":
		set(v):
			skin_id = v
			_refresh_gun()
	var _root: Node2D
	var _gun: Sprite2D
	var _pivot: Node2D
	var _mat: ShaderMaterial
	var _hand: Node2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat = FXKit.tint_material(color)
		_root = Node2D.new()
		add_child(_root)
		var shadow := _Shadow.new()
		shadow.position = Vector2(0, 30)
		_root.add_child(shadow)
		for lx in [-4.0, 4.0]:
			var leg := Sprite2D.new()
			leg.texture = preload("res://assets/char/leg.png")
			leg.centered = false
			leg.offset = Vector2(-32, 0)
			leg.scale = Vector2(0.13, 0.095)
			leg.position = Vector2(lx, 6)
			leg.rotation = 0.12 if lx < 0 else -0.08
			leg.material = _mat
			_root.add_child(leg)
		var body := Sprite2D.new()
		body.texture = preload("res://assets/char/body.png")
		body.scale = Vector2(0.109, 0.109)
		body.material = _mat
		_root.add_child(body)
		var head := Sprite2D.new()
		head.texture = preload("res://assets/char/head.png")
		head.scale = Vector2(0.135, 0.135)
		head.position = Vector2(2, -20)
		head.material = _mat
		_root.add_child(head)
		_pivot = Node2D.new()
		_pivot.position = Vector2(0, -6)
		_pivot.rotation = -0.12
		_root.add_child(_pivot)
		_gun = Sprite2D.new()
		_pivot.add_child(_gun)
		_hand = _Hand.new()
		_pivot.add_child(_hand)
		resized.connect(_layout)
		_refresh_gun()

	func _layout() -> void:
		var k := minf(size.x / 150.0, size.y / 90.0)
		_root.scale = Vector2(k, k)
		_root.position = Vector2(size.x * 0.4, size.y * 0.55)

	func _process(_d: float) -> void:
		var t := Time.get_ticks_msec() / 1000.0
		_pivot.rotation = -0.12 + sin(t * 1.6) * 0.05

	func _refresh_gun() -> void:
		if _gun == null:
			return
		GunArt.setup_sprite(_gun, weapon_id, skin_id)
		_hand.position = GunArt.hands(weapon_id)[0]
		_layout()

	class _Hand extends Node2D:
		func _draw() -> void:
			draw_circle(Vector2.ZERO, 4.2, Color(0.08, 0.08, 0.1))
			draw_circle(Vector2.ZERO, 3.2, Color(0.3, 0.27, 0.26))

	class _Shadow extends Node2D:
		func _draw() -> void:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.25))
			draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.4))


## Row of glossy clickable color dots. on_pick(index) is called on click.
static func color_row(selected: int, on_pick: Callable, swatch: float = 40.0) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for i in Catalog.PLAYER_COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(swatch, swatch)
		b.focus_mode = Control.FOCUS_NONE
		var col: Color = Catalog.PLAYER_COLORS[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(swatch / 2))
		sb.set_border_width_all(4 if i == selected else 2)
		sb.border_color = Color.WHITE if i == selected else col.darkened(0.45)
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
		var sb_h := sb.duplicate() as StyleBoxFlat
		sb_h.bg_color = col.lightened(0.15)
		for st in ["normal", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("hover", sb_h)
		b.add_theme_stylebox_override("pressed", sb_h)
		# glossy highlight
		var gl := Panel.new()
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(1, 1, 1, 0.35)
		gs.set_corner_radius_all(int(swatch / 4))
		gl.add_theme_stylebox_override("panel", gs)
		gl.position = Vector2(swatch * 0.22, swatch * 0.12)
		gl.size = Vector2(swatch * 0.56, swatch * 0.26)
		b.add_child(gl)
		var idx := i
		b.pressed.connect(func():
			Sfx.play("ui", 0.6, 0.0)
			on_pick.call(idx))
		row.add_child(b)
	return row
