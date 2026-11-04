class_name Widgets
extends RefCounted
## Small reusable controls: gun preview, color swatches.


class GunPreview extends Control:
	var weapon_id := "rifle"
	var skin_id := "default"
	var gun_scale := 3.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.12, 0.6))
		var w: Dictionary = Catalog.weapon(weapon_id)
		var L := float(w["length"]) * gun_scale
		var origin := Vector2(size.x * 0.5 - L * 0.35, size.y * 0.5)
		draw_set_transform(origin, 0.0, Vector2.ONE)
		GunArt.draw_gun(self, weapon_id, skin_id, gun_scale, Time.get_ticks_msec() / 1000.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Row of clickable color swatches. on_pick(index) is called on click.
static func color_row(selected: int, on_pick: Callable, swatch: float = 40.0) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for i in Catalog.PLAYER_COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(swatch, swatch)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Catalog.PLAYER_COLORS[i]
		sb.set_corner_radius_all(int(swatch / 2))
		sb.set_border_width_all(4 if i == selected else 0)
		sb.border_color = Color.WHITE
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		var idx := i
		b.pressed.connect(func():
			Sfx.play("ui", 0.6, 0.0)
			on_pick.call(idx))
		row.add_child(b)
	return row
