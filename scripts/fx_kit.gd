class_name FXKit
extends RefCounted
## Shared textures/materials for effects (soft glow dots, additive blending, character tint).

const TINT_SHADER := preload("res://shaders/tint.gdshader")

static var _soft: Texture2D = null
static var _add: CanvasItemMaterial = null
static var _font: Font = null


static func soft_circle() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft = t
	return _soft


static func additive() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add


static func tint_material(col: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TINT_SHADER
	m.set_shader_parameter("tint", col)
	return m


static func game_font() -> Font:
	return UIKit.font()


## Jetpack flame particles (attach to a nozzle).
static func jet_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = soft_circle()
	p.material = additive()
	p.amount = 26
	p.lifetime = 0.32
	p.local_coords = false
	p.direction = Vector2(0, 1)
	p.spread = 14.0
	p.initial_velocity_min = 260.0
	p.initial_velocity_max = 360.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.34
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.15))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.98, 0.8, 1.0))
	g.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	g.add_point(0.25, Color(1.0, 0.8, 0.2, 0.95))
	g.add_point(0.6, Color(1.0, 0.4, 0.08, 0.6))
	p.color_ramp = g
	p.emitting = false
	return p
