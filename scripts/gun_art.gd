class_name GunArt
extends RefCounted
## Procedural vector art for guns + skins. Used in-game and in the shop preview.
## All shapes are drawn pointing to +X, with the grip at the origin.


## Draws a gun on `ci` (a CanvasItem inside its _draw()).
## scale_f scales the whole gun; t is time in seconds (animated skins).
static func draw_gun(ci: CanvasItem, weapon_id: String, skin_id: String, scale_f: float = 1.0, t: float = 0.0) -> void:
	var s: Dictionary = Catalog.skin(skin_id)
	var base: Color = s["base"]
	var accent: Color = s["accent"]
	var pattern: String = s["pattern"]
	var w: Dictionary = Catalog.weapon(weapon_id)
	var L: float = float(w["length"]) * scale_f
	var H: float = 7.0 * scale_f
	var parts: Array = []  # list of Rect2 (body parts)
	match weapon_id:
		"pistol":
			parts = [Rect2(-2 * scale_f, -H * 0.5, L, H), Rect2(-2 * scale_f, 0, 7 * scale_f, 10 * scale_f)]
		"smg":
			parts = [Rect2(-4 * scale_f, -H * 0.5, L, H), Rect2(4 * scale_f, 0, 6 * scale_f, 13 * scale_f),
				Rect2(-4 * scale_f, 0, 5 * scale_f, 8 * scale_f)]
		"rifle":
			parts = [Rect2(-14 * scale_f, -H * 0.5, L * 0.8, H), Rect2(L * 0.62 - 14 * scale_f, -2 * scale_f, L * 0.45, 4 * scale_f),
				Rect2(6 * scale_f, 1 * scale_f, 6 * scale_f, 13 * scale_f), Rect2(-14 * scale_f, -2 * scale_f, 8 * scale_f, 9 * scale_f)]
		"shotgun":
			parts = [Rect2(-14 * scale_f, -H * 0.5, L, H * 1.1), Rect2(-14 * scale_f, -2 * scale_f, 10 * scale_f, 10 * scale_f),
				Rect2(8 * scale_f, H * 0.5, 16 * scale_f, 4 * scale_f)]
		"sniper":
			parts = [Rect2(-16 * scale_f, -H * 0.45, L * 0.65, H * 0.9), Rect2(L * 0.5 - 16 * scale_f, -1.5 * scale_f, L * 0.55, 3 * scale_f),
				Rect2(2 * scale_f, -H * 0.5 - 6 * scale_f, 18 * scale_f, 5 * scale_f), Rect2(-16 * scale_f, -2 * scale_f, 9 * scale_f, 10 * scale_f)]
		"rocket":
			parts = [Rect2(-18 * scale_f, -H * 0.85, L, H * 1.7), Rect2(0, H * 0.8, 6 * scale_f, 9 * scale_f)]
		_:
			parts = [Rect2(0, -H * 0.5, L, H)]
	for r in parts:
		ci.draw_rect(r, base)
	# pattern overlay on the main body (first part)
	var body: Rect2 = parts[0]
	match pattern:
		"stripes":
			var step := 7.0 * scale_f
			var x := body.position.x + 2.0
			while x < body.end.x - 2.0:
				ci.draw_line(Vector2(x, body.position.y), Vector2(x + 3.0 * scale_f, body.end.y), accent, 2.0 * scale_f)
				x += step
		"camo":
			var seed_v := weapon_id.hash()
			for i in 6:
				var fx := float((seed_v >> (i * 3)) & 7) / 7.0
				var fy := float((seed_v >> (i * 2 + 1)) & 3) / 3.0
				var p := body.position + Vector2(body.size.x * (0.1 + 0.8 * fx), body.size.y * fy)
				ci.draw_circle(p, 2.6 * scale_f, accent)
		"carbon":
			var y := body.position.y + 1.5
			while y < body.end.y:
				ci.draw_line(Vector2(body.position.x, y), Vector2(body.end.x, y), accent, 1.0)
				y += 2.5 * scale_f
		"gold":
			var shine_x := body.position.x + fposmod(t * 60.0 * scale_f, body.size.x + 20.0) - 10.0
			ci.draw_line(Vector2(shine_x, body.position.y), Vector2(shine_x + 5.0 * scale_f, body.end.y), Color(1, 1, 0.85, 0.85), 3.0 * scale_f)
			ci.draw_rect(body, accent, false, 1.2 * scale_f)
		"neon":
			var a := 0.55 + 0.45 * sin(t * 5.0)
			var glow := Color(accent.r, accent.g, accent.b, a)
			ci.draw_rect(body.grow(1.5 * scale_f), glow, false, 2.0 * scale_f)
			ci.draw_line(Vector2(body.position.x, body.get_center().y), Vector2(body.end.x, body.get_center().y), glow, 1.5 * scale_f)
		_:
			ci.draw_rect(body, accent, false, 1.0)
	# muzzle tip
	var tip := muzzle_offset(weapon_id) * scale_f
	ci.draw_rect(Rect2(tip.x - 3.0 * scale_f, -2.0 * scale_f, 3.0 * scale_f, 4.0 * scale_f), Color(0.08, 0.08, 0.1))


## Muzzle position (unscaled) relative to the grip, along +X.
static func muzzle_offset(weapon_id: String) -> Vector2:
	var w: Dictionary = Catalog.weapon(weapon_id)
	var L: float = float(w["length"])
	match weapon_id:
		"pistol":
			return Vector2(L - 2.0, 0)
		"smg":
			return Vector2(L - 4.0, 0)
		"rifle":
			return Vector2(L * 0.62 - 14.0 + L * 0.45, 0)
		"shotgun":
			return Vector2(L - 14.0, 0)
		"sniper":
			return Vector2(L * 0.5 - 16.0 + L * 0.55, 0)
		"rocket":
			return Vector2(L - 18.0, 0)
	return Vector2(L, 0)
