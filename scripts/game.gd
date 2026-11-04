extends Node2D
## Match scene. The host is authoritative for bullets, damage, kills, respawns, timer and win.
## Every peer simulates bullets visually; the host's result is final.

const SPAWN_PROTECT := 1.5
const END_SCREEN_TIME := 8.0
const SELF_SPLASH_FACTOR := 0.5

var map: Dictionary
var players_node: Node2D
var fx: _FX
var camera: Camera2D
var hud: HUD

var started := false
var ended := false
var time_left := 0.0
var stats: Dictionary = {}       # id -> {"k": int, "d": int}
var team_score: Array = [0, 0]
var bullets: Array = []          # Array[Dictionary]

var _bullet_seq := 0
var _last_fire: Dictionary = {}  # host: "id:weapon" -> msec
var _respawn_q: Dictionary = {}  # host: id -> seconds
var _time_sync := 0.0
var _bots_only := true
var _local_dead_timer := 0.0
var _score_refresh := 0.0
var _shake := 0.0
var pickups: Array = []         # {pos, kind, active, t}
var input_enabled := true  # set false to drive the local player from code (tests, replays)
var ground_guns: Dictionary = {}  # gid -> {w, pos, spot, t}  (spot >= 0: map weapon spot)
var _spots: Array = []            # host: map weapon spots {w, pos, gid, t}
var _drop_seq := 1000
var scope_idx := 0
var _scope_weapon := ""
var _base_zoom := 1.15
var near_gun := -1                # local: ground gun in reach (gid) or -1


# ================================================================ drawing helpers
class _MapDraw extends Node2D:
	var map: Dictionary
	var tex: Texture2D
	var texs := {}
	var props_tex: Array = []
	const PROP_NAMES := ["crate", "barrel", "sandbags", "locker", "lamp", "antenna"]
	const PROP_H := [64.0, 70.0, 46.0, 96.0, 190.0, 86.0]

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tex = load("res://assets/tex/%s.png" % str(map.get("tex", "metal")))
		for n in ["metal", "concrete", "dirt", "interior", "grass"]:
			texs[n] = load("res://assets/tex/%s.png" % n)
		for n in PROP_NAMES:
			props_tex.append(load("res://assets/props/%s.png" % n))
		if map.has("props"):
			var lights := _Lights.new()
			lights.map = map
			lights.material = FXKit.additive()
			lights.z_index = 1
			add_child(lights)

	func _draw() -> void:
		var size: Vector2 = map["size"]
		var tint: Color = map.get("tex_tint", Color.WHITE)
		var edge: Color = map.get("edge", Color(0.05, 0.05, 0.08))
		var lip: Color = map.get("lip", Color(0.9, 0.7, 0.2))
		var rocky := str(map.get("tex", "")) == "rock"
		var big := map.has("ground")
		# border walls outside the playable area (no empty void at the edges)
		var border_tex: Texture2D = texs["concrete"] if big else tex
		var dark := tint.darkened(0.55)
		for r in [Rect2(-1200, -1200, 1200, size.y + 2400), Rect2(size.x, -1200, 1200, size.y + 2400),
				Rect2(0, size.y, size.x, 1200)]:
			draw_texture_rect(border_tex, r, true, dark)
		draw_rect(Rect2(-1200, -1200, 1200, size.y + 2400), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(size.x, -1200, 1200, size.y + 2400), Color(0, 0, 0, 0.35))
		for gx in [0.0, size.x]:
			for i in 8:
				var w := 6.0 * (8 - i)
				var x: float = gx - w if gx == 0.0 else gx
				draw_rect(Rect2(x, -1200, w, size.y + 2400), Color(0, 0, 0, 0.06))
		# building interiors (behind everything solid)
		for r in map.get("rooms", []):
			var rect := Rect2(r[0], r[1], r[2], r[3])
			draw_texture_rect(texs["interior"], rect, true, Color(0.62, 0.58, 0.6))
			var steps := 5
			for i in steps:
				var f := float(i) / steps
				draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y * f, rect.size.x, rect.size.y / steps + 0.5), Color(0.02, 0.03, 0.06, 0.15 + 0.25 * f))
			draw_rect(rect, Color(0, 0, 0, 0.5), false, 6.0)
		# support beams
		for b in map.get("beams", []):
			var rect := Rect2(b[0], b[1], b[2], b[3])
			draw_texture_rect(texs["metal"], rect, true, Color(0.55, 0.58, 0.65))
			draw_rect(Rect2(rect.position.x + rect.size.x * 0.65, rect.position.y, rect.size.x * 0.35, rect.size.y), Color(0, 0, 0, 0.35))
			var y := rect.position.y + 30.0
			while y < rect.end.y - 10.0:
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y + 26.0), Color(0, 0, 0, 0.35), 2.0)
				y += 60.0
			draw_rect(rect, edge, false, 2.0)
		# rolling terrain
		if big:
			_draw_ground(size)
		# drop shadows first so they sit behind every block
		for r in map["rects"]:
			var st := str(r[4]) if r.size() > 4 else ""
			if st == "crate" or st == "sandbag":
				continue
			var rect := Rect2(r[0], r[1], r[2], r[3])
			draw_rect(Rect2(rect.position + Vector2(8, 12), rect.size), Color(0, 0, 0, 0.32))
		for r in map["rects"]:
			var rect := Rect2(r[0], r[1], r[2], r[3])
			var st := str(r[4]) if r.size() > 4 else ""
			match st:
				"crate":
					draw_texture_rect(props_tex[0], rect.grow(3), false)
					continue
				"sandbag":
					draw_texture_rect(props_tex[2], Rect2(rect.position.x - 6, rect.position.y - 8, rect.size.x + 12, rect.size.y + 10), false)
					continue
				"concrete":
					draw_texture_rect(texs["concrete"], rect, true, Color(0.9, 0.92, 0.98))
				"metal":
					draw_texture_rect(texs["metal"], rect, true, Color.WHITE)
				_:
					draw_texture_rect(tex, rect, true, tint)
			# vertical shading: lighter top, darker bottom
			var steps := 6
			for i in steps:
				var f := float(i) / steps
				var h := rect.size.y / steps
				draw_rect(Rect2(rect.position.x, rect.position.y + h * i, rect.size.x, h + 0.5), Color(0, 0, 0, 0.42 * f * f))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(rect.size.y, 12))), Color(1, 1, 1, 0.08))
			if st == "concrete":
				draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 4), Color(0.85, 0.88, 0.95, 0.85))
				draw_rect(Rect2(rect.position.x, rect.position.y + 4, rect.size.x, 2), Color(0, 0, 0, 0.35))
			else:
				_draw_lip(rect, lip, rocky)
			draw_rect(rect, edge, false, 3.0)
		# decorative props standing on surfaces
		for pr in map.get("props", []):
			var i := int(pr[2])
			var t: Texture2D = props_tex[i]
			var h: float = PROP_H[i] * float(pr[3])
			var w := h * t.get_width() / t.get_height()
			var base := Vector2(float(pr[0]), float(pr[1]))
			draw_set_transform(base + Vector2(0, 2), 0.0, Vector2(1, 0.22))
			draw_circle(Vector2.ZERO, w * 0.55, Color(0, 0, 0, 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_texture_rect(t, Rect2(base.x - w * 0.5, base.y - h + 3, w, h), false)

	func _draw_ground(size: Vector2) -> void:
		var top: Array = map["ground"]
		var pts := PackedVector2Array()
		for v in top:
			pts.append(v)
		pts.append(Vector2(size.x, size.y + 1200))
		pts.append(Vector2(0, size.y + 1200))
		var uvs := PackedVector2Array()
		for v in pts:
			uvs.append(v / 256.0)
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(map.get("ground_tint", Color.WHITE))
		draw_polygon(pts, cols, uvs, texs["dirt"])
		# darken with depth below the surface
		for k in 6:
			var off := 40.0 + k * 50.0
			var band := PackedVector2Array()
			for v in top:
				band.append(v + Vector2(0, off))
			for i in range(top.size() - 1, -1, -1):
				band.append(top[i] + Vector2(0, off + 50.0))
			draw_colored_polygon(band, Color(0.02, 0.01, 0.0, 0.1 + k * 0.04))
		var deep := PackedVector2Array()
		for v in top:
			deep.append(v + Vector2(0, 340))
		deep.append(Vector2(size.x, size.y + 1200))
		deep.append(Vector2(0, size.y + 1200))
		draw_colored_polygon(deep, Color(0.03, 0.02, 0.01, 0.45))
		# dark soil edge + grass along the top profile
		var line := PackedVector2Array()
		for v in top:
			line.append(v + Vector2(0, 4))
		draw_polyline(line, Color(0.12, 0.08, 0.04), 6.0)
		var gt: Texture2D = texs["grass"]
		var gh := 34.0
		var gw := gh * gt.get_width() / gt.get_height()
		var u := 0.0
		for i in top.size() - 1:
			var a: Vector2 = top[i]
			var b: Vector2 = top[i + 1]
			var len := a.distance_to(b)
			var du := len / gw
			var quad := PackedVector2Array([a + Vector2(0, -gh * 0.62), b + Vector2(0, -gh * 0.62), b + Vector2(0, gh * 0.38), a + Vector2(0, gh * 0.38)])
			var quv := PackedVector2Array([Vector2(u, 0), Vector2(u + du, 0), Vector2(u + du, 1), Vector2(u, 1)])
			draw_polygon(quad, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), quv, gt)
			u += du

	func _draw_lip(rect: Rect2, lip: Color, rocky: bool) -> void:
		var top := rect.position.y
		if rocky:
			# sandy wavy crust
			var pts := PackedVector2Array()
			pts.append(Vector2(rect.position.x, top + 8))
			var x := rect.position.x
			while x <= rect.end.x:
				pts.append(Vector2(x, top - 2.0 + sin(x * 0.09) * 1.6 + sin(x * 0.023) * 1.5))
				x += 10.0
			pts.append(Vector2(rect.end.x, top - 2.0))
			pts.append(Vector2(rect.end.x, top + 8))
			draw_colored_polygon(pts, lip)
			draw_rect(Rect2(rect.position.x, top + 6, rect.size.x, 3), lip.darkened(0.35))
			draw_polyline(pts.slice(1, pts.size() - 1), lip.lightened(0.35), 2.0)
		else:
			# hazard stripes on metal ledges
			var band := Rect2(rect.position.x, top, rect.size.x, 7)
			draw_rect(band, lip)
			var x := rect.position.x - 7.0
			while x < rect.end.x:
				var l := rect.position.x
				var rr := rect.end.x
				var poly := PackedVector2Array([Vector2(clampf(x + 7.0, l, rr), top), Vector2(clampf(x + 14.0, l, rr), top),
					Vector2(clampf(x + 7.0, l, rr), top + 7), Vector2(clampf(x, l, rr), top + 7)])
				if poly[1].x - poly[3].x > 1.0:
					draw_colored_polygon(poly, Color(0.08, 0.08, 0.1, 0.85))
				x += 22.0
			draw_rect(Rect2(rect.position.x, top, rect.size.x, 1.5), Color(1, 1, 1, 0.5))
			draw_rect(Rect2(rect.position.x, top + 7, rect.size.x, 2), Color(0, 0, 0, 0.45))


## Warm additive light from street lamps and antenna beacons.
class _Lights extends Node2D:
	var map: Dictionary

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var tex := FXKit.soft_circle()
		var t := Time.get_ticks_msec() / 1000.0
		for pr in map.get("props", []):
			var k := int(pr[2])
			var base := Vector2(float(pr[0]), float(pr[1]))
			var sc := float(pr[3])
			if k == 4:
				var c := base + Vector2(0, -175.0 * sc)
				var fl := 0.92 + 0.08 * sin(t * 11.0 + base.x)
				draw_texture_rect(tex, Rect2(c - Vector2(150, 150) * sc, Vector2(300, 300) * sc), false, Color(1.0, 0.7, 0.3, 0.32 * fl))
				draw_texture_rect(tex, Rect2(c - Vector2(36, 36) * sc, Vector2(72, 72) * sc), false, Color(1.0, 0.9, 0.6, 0.8 * fl))
				var cone := PackedVector2Array([c + Vector2(-8, 6), c + Vector2(8, 6), c + Vector2(70, 175 * sc), c + Vector2(-70, 175 * sc)])
				draw_colored_polygon(cone, Color(1.0, 0.75, 0.35, 0.07 * fl))
			elif k == 5:
				var blink := 1.0 if fmod(t + base.x * 0.001, 1.4) < 0.25 else 0.15
				var c2 := base + Vector2(10 * sc, -80.0 * sc)
				draw_texture_rect(tex, Rect2(c2 - Vector2(22, 22), Vector2(44, 44)), false, Color(1, 0.2, 0.15, 0.8 * blink))
			elif k == 1:
				pass


## Map art behind everything, with gentle parallax.
class _Backdrop extends CanvasLayer:
	var game: Node
	var rect: TextureRect

	func _init(image: String) -> void:
		layer = -20
		rect = TextureRect.new()
		rect.texture = load("res://assets/bg/%s.jpg" % image)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)

	func _process(_d: float) -> void:
		var vp := get_viewport().get_visible_rect().size
		var extra := vp * 0.14
		rect.size = vp + extra
		if game and game.camera:
			var ms: Vector2 = game.map["size"]
			var cam: Camera2D = game.camera
			var f: Vector2 = (cam.get_screen_center_position() / ms).clamp(Vector2.ZERO, Vector2.ONE)
			rect.position = -extra * f
		else:
			rect.position = -extra * 0.5


class _FX extends Node2D:
	var game: Node
	var explosions: Array = []  # {pos, t, r}
	var sparks: Array = []      # {pos, vel, t, col}
	var puffs: Array = []       # smoke {pos, vel, t, life, r, col}
	var casings: Array = []     # {pos, vel, t, rot, spin}
	var numbers: Array = []     # {pos, t, text, col}
	var glow: _Glow
	var _trail_t := 0.0

	func _ready() -> void:
		glow = _Glow.new()
		glow.fx = self
		glow.material = FXKit.additive()
		add_child(glow)

	func spark(pos: Vector2, col: Color, n: int = 6, speed: float = 260.0) -> void:
		for i in n:
			sparks.append({"pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.3, speed), "t": randf_range(0.2, 0.45), "col": col})
		if sparks.size() > 400:
			sparks = sparks.slice(sparks.size() - 400)

	func puff(pos: Vector2, vel: Vector2, r: float, life: float, col: Color) -> void:
		puffs.append({"pos": pos, "vel": vel, "t": 0.0, "life": life, "r": r, "col": col})
		if puffs.size() > 300:
			puffs = puffs.slice(puffs.size() - 300)

	func explode(pos: Vector2, r: float) -> void:
		explosions.append({"pos": pos, "t": 0.0, "r": r})
		spark(pos, Color(1, 0.6, 0.2), 30, 620.0)
		for i in 12:
			puff(pos + Vector2.from_angle(randf() * TAU) * randf() * r * 0.4, Vector2.from_angle(randf() * TAU) * randf_range(30, 140) + Vector2(0, -40),
				randf_range(r * 0.3, r * 0.6), randf_range(0.8, 1.4), Color(0.22, 0.2, 0.2))

	func casing(pos: Vector2, facing: float) -> void:
		casings.append({"pos": pos, "vel": Vector2(-facing * randf_range(60, 160), randf_range(-260, -160)), "t": 0.0,
			"rot": randf() * TAU, "spin": randf_range(-20, 20)})
		if casings.size() > 120:
			casings = casings.slice(casings.size() - 120)

	func number(pos: Vector2, amount: int, col: Color) -> void:
		numbers.append({"pos": pos + Vector2(randf_range(-10, 10), -40), "t": 0.0, "text": str(amount), "col": col})

	func dust(pos: Vector2) -> void:
		for i in 3:
			puff(pos, Vector2(randf_range(-40, 40), randf_range(-60, -10)), randf_range(5, 9), randf_range(0.35, 0.6), Color(0.55, 0.5, 0.42))

	func burst(pos: Vector2, col: Color) -> void:
		spark(pos, col.lightened(0.2), 26, 460.0)
		spark(pos, Color(1, 0.9, 0.6), 10, 300.0)
		for i in 7:
			puff(pos, Vector2.from_angle(randf() * TAU) * randf_range(40, 120), randf_range(14, 26), randf_range(0.5, 0.9), col.darkened(0.3))

	func _process(delta: float) -> void:
		for i in range(sparks.size() - 1, -1, -1):
			var s: Dictionary = sparks[i]
			s["t"] -= delta
			if s["t"] <= 0.0:
				sparks.remove_at(i)
				continue
			s["vel"] = (s["vel"] as Vector2) + Vector2(0, 900) * delta
			s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
		for i in range(puffs.size() - 1, -1, -1):
			var pf: Dictionary = puffs[i]
			pf["t"] += delta
			if pf["t"] >= pf["life"]:
				puffs.remove_at(i)
				continue
			pf["vel"] = (pf["vel"] as Vector2) * (1.0 - 1.8 * delta) + Vector2(0, -30) * delta
			pf["pos"] = (pf["pos"] as Vector2) + (pf["vel"] as Vector2) * delta
		for i in range(casings.size() - 1, -1, -1):
			var c: Dictionary = casings[i]
			c["t"] += delta
			if c["t"] > 0.9:
				casings.remove_at(i)
				continue
			c["vel"] = (c["vel"] as Vector2) + Vector2(0, 1100) * delta
			c["pos"] = (c["pos"] as Vector2) + (c["vel"] as Vector2) * delta
			c["rot"] += c["spin"] * delta
		for i in range(numbers.size() - 1, -1, -1):
			numbers[i]["t"] += delta
			numbers[i]["pos"] = (numbers[i]["pos"] as Vector2) + Vector2(0, -55) * delta
			if numbers[i]["t"] > 0.8:
				numbers.remove_at(i)
		for i in range(explosions.size() - 1, -1, -1):
			explosions[i]["t"] += delta
			if explosions[i]["t"] > 0.55:
				explosions.remove_at(i)
		# rocket smoke trails
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = 0.025
			for b in game.bullets:
				if b["w"] == "rocket":
					var dir: Vector2 = (b["vel"] as Vector2).normalized()
					puff((b["pos"] as Vector2) - dir * 14.0, -dir * 30.0 + Vector2(randf_range(-15, 15), randf_range(-15, 15)), randf_range(7, 11), 0.6, Color(0.55, 0.55, 0.58))
		queue_redraw()
		glow.queue_redraw()

	func _draw() -> void:
		# smoke (normal blend)
		var tex := FXKit.soft_circle()
		for pf in puffs:
			var f: float = pf["t"] / pf["life"]
			var r: float = pf["r"] * (0.6 + f * 1.1)
			var c: Color = pf["col"]
			c.a = 0.55 * (1.0 - f)
			draw_texture_rect(tex, Rect2((pf["pos"] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
		# rocket bodies
		for b in game.bullets:
			if b["w"] == "rocket":
				var dir: Vector2 = (b["vel"] as Vector2).normalized()
				var p: Vector2 = b["pos"]
				draw_set_transform(p, dir.angle(), Vector2.ONE)
				draw_rect(Rect2(-12, -3.5, 16, 7), Color(0.35, 0.4, 0.3))
				draw_colored_polygon(PackedVector2Array([Vector2(4, -3.5), Vector2(10, 0), Vector2(4, 3.5)]), Color(0.75, 0.2, 0.15))
				draw_colored_polygon(PackedVector2Array([Vector2(-12, -3.5), Vector2(-15, -7), Vector2(-9, -3.5)]), Color(0.25, 0.28, 0.22))
				draw_colored_polygon(PackedVector2Array([Vector2(-12, 3.5), Vector2(-15, 7), Vector2(-9, 3.5)]), Color(0.25, 0.28, 0.22))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for c in casings:
			draw_set_transform(c["pos"], c["rot"], Vector2.ONE)
			draw_rect(Rect2(-3, -1.3, 6, 2.6), Color(0.95, 0.72, 0.25, 1.0 - c["t"] / 0.9))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var font := FXKit.game_font()
		for n in numbers:
			var a := clampf(1.0 - (float(n["t"]) - 0.4) / 0.4, 0.0, 1.0)
			var col: Color = n["col"]
			col.a = a
			var pos: Vector2 = (n["pos"] as Vector2) - Vector2(40, 0)
			var fs := 22 if float(n["t"]) > 0.1 else 28
			draw_string_outline(font, pos, n["text"], HORIZONTAL_ALIGNMENT_CENTER, 80, fs, 5, Color(0, 0, 0, 0.8 * a))
			draw_string(font, pos, n["text"], HORIZONTAL_ALIGNMENT_CENTER, 80, fs, col)


## Additive glow layer: tracers, sparks, fire.
class _Glow extends Node2D:
	var fx: _FX

	func _draw() -> void:
		var tex := FXKit.soft_circle()
		for b in fx.game.bullets:
			var dir: Vector2 = (b["vel"] as Vector2).normalized()
			var p: Vector2 = b["pos"]
			match str(b["w"]):
				"rocket":
					var fl := p - dir * 14.0
					draw_texture_rect(tex, Rect2(fl - Vector2(16, 16), Vector2(32, 32)), false, Color(1, 0.5, 0.1, 0.9))
					draw_texture_rect(tex, Rect2(fl - Vector2(7, 7), Vector2(14, 14)), false, Color(1, 1, 0.8, 1))
				"sniper", "svd", "woodpecker":
					draw_line(p - dir * 90.0, p, Color(0.4, 0.8, 1.0, 0.35), 7.0)
					draw_line(p - dir * 90.0, p, Color(0.85, 0.95, 1.0, 0.95), 2.0)
				_:
					draw_line(p - dir * 26.0, p, Color(1, 0.6, 0.15, 0.35), 6.0)
					draw_line(p - dir * 22.0, p, Color(1, 0.95, 0.7, 1.0), 2.0)
					draw_texture_rect(tex, Rect2(p - Vector2(5, 5), Vector2(10, 10)), false, Color(1, 0.85, 0.4, 0.8))
		for s in fx.sparks:
			var c: Color = s["col"]
			c.a = clampf(s["t"] * 3.0, 0.0, 1.0)
			var v: Vector2 = s["vel"]
			draw_line(s["pos"], (s["pos"] as Vector2) - v * 0.025, c, 2.5)
		for e in fx.explosions:
			var f: float = e["t"] / 0.55
			var r: float = e["r"]
			var pos: Vector2 = e["pos"]
			var gr := r * (0.7 + f * 0.9)
			draw_texture_rect(tex, Rect2(pos - Vector2(gr, gr) * 1.3, Vector2(gr, gr) * 2.6), false, Color(1, 0.45, 0.1, 0.9 * (1.0 - f)))
			var cr := r * (0.35 + f * 0.4)
			draw_texture_rect(tex, Rect2(pos - Vector2(cr, cr), Vector2(cr, cr) * 2.0), false, Color(1, 0.95, 0.7, 1.0 - f))
			draw_arc(pos, r * (0.3 + f * 1.2), 0.0, TAU, 40, Color(1, 0.8, 0.5, 0.6 * (1.0 - f)), 4.0 * (1.0 - f) + 1.0)


## Medkits and ammo crates.
class _Pickups extends Node2D:
	var game: Node
	var icons := {}

	func _ready() -> void:
		icons["medkit"] = load("res://assets/icons/medkit.png")
		icons["ammo"] = load("res://assets/icons/ammo_crate.png")

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var glow := FXKit.soft_circle()
		for i in game.pickups.size():
			var pk: Dictionary = game.pickups[i]
			var base: Vector2 = pk["pos"]
			draw_set_transform(base + Vector2(0, 16), 0.0, Vector2(1, 0.25))
			draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.35 if pk["active"] else 0.15))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if not pk["active"]:
				continue
			var bob := sin(t * 3.0 + i) * 4.0
			var c := Color(0.3, 1.0, 0.45, 0.45) if pk["kind"] == "medkit" else Color(1.0, 0.8, 0.25, 0.45)
			var gs := 34.0 + sin(t * 4.0 + i) * 4.0
			draw_texture_rect(glow, Rect2(base + Vector2(-gs, -gs + bob - 4), Vector2(gs, gs) * 2.0), false, c)
			var tex: Texture2D = icons[pk["kind"]]
			var w := 46.0
			var h := w * tex.get_height() / tex.get_width()
			draw_texture_rect(tex, Rect2(base + Vector2(-w * 0.5, -h * 0.5 + bob - 4), Vector2(w, h)), false)


## Weapons lying on the ground (map spots + dropped by dead players).
class _GroundGuns extends Node2D:
	var game: Node

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var glow := FXKit.soft_circle()
		var font := FXKit.game_font()
		for gid in game.ground_guns:
			var g: Dictionary = game.ground_guns[gid]
			var w: String = g["w"]
			var base: Vector2 = g["pos"]
			if int(g["spot"]) < 0 and float(g["t"]) < 5.0 and fmod(t * 6.0, 1.0) < 0.4:
				continue  # blink before a dropped gun disappears
			var tier := int(Catalog.weapon(w).get("tier", 1))
			var tiers := [Color(0.8, 0.85, 1.0), Color(0.4, 0.8, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.7, 0.2)]
			var gc: Color = tiers[clampi(tier - 1, 0, 3)]
			var bob := sin(t * 2.6 + float(gid)) * 3.0
			draw_set_transform(base + Vector2(0, 24), 0.0, Vector2(1, 0.22))
			draw_circle(Vector2.ZERO, 30.0, Color(0, 0, 0, 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			gc.a = 0.32 + 0.1 * sin(t * 4.0 + float(gid))
			draw_texture_rect(glow, Rect2(base + Vector2(-46, -34 + bob), Vector2(92, 68)), false, gc)
			var tex: Texture2D = GunArt.texture(w)
			var gw := float(GunArt.art(w)["w"]) * 1.15
			var gh := gw * tex.get_height() / tex.get_width()
			draw_texture_rect(tex, Rect2(base + Vector2(-gw * 0.5, -gh * 0.5 + bob), Vector2(gw, gh)), false)
			if int(gid) == int(game.near_gun):
				var nm := str(Catalog.weapon(w)["name"]).to_upper()
				draw_string_outline(font, base + Vector2(-80, -30 + bob), nm, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, 4, Color(0, 0, 0, 0.8))
				draw_string(font, base + Vector2(-80, -30 + bob), nm, HORIZONTAL_ALIGNMENT_CENTER, 160, 15, Color(1, 0.92, 0.5))


# ================================================================ setup
func _ready() -> void:
	name = "Game"
	map = Catalog.MAPS[clampi(int(Network.settings.get("map", 0)), 0, Catalog.MAPS.size() - 1)]
	_build_world()
	players_node = Node2D.new()
	players_node.name = "Players"
	add_child(players_node)
	fx = _FX.new()
	fx.game = self
	fx.z_index = 5
	add_child(fx)
	var ids: Array = Network.players.keys()
	ids.sort()
	for id in ids:
		_spawn_player(int(id), Network.players[id])
	camera = Camera2D.new()
	_base_zoom = 1.3 if Profile.use_touch_controls() else 1.15
	camera.zoom = Vector2(_base_zoom, _base_zoom)
	camera.limit_left = -150
	camera.limit_top = -250
	camera.limit_right = int(map["size"].x) + 150
	camera.limit_bottom = int(map["size"].y) + 150
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	add_child(camera)
	var lp := local_player()
	camera.global_position = lp.global_position if lp else map["size"] * 0.5
	hud = HUD.new()
	add_child(hud)
	hud.setup(self)
	hud.touch.reload_pressed.connect(func():
		var p := local_player()
		if p: p.start_reload())
	hud.touch.switch_pressed.connect(func():
		var p := local_player()
		if p: p.switch_weapon())
	hud.touch.scope_pressed.connect(cycle_scope)
	hud.touch.pick_pressed.connect(request_pick)
	hud.show_center("Waiting for players...")
	_bots_only = not Network.has_humans_besides_me()
	Network.player_left.connect(_on_player_left)
	Network.report_loaded.call_deferred()


func _build_world() -> void:
	var bd := _Backdrop.new(str(map.get("bg_image", "outpost")))
	bd.game = self
	add_child(bd)
	var md := _MapDraw.new()
	md.map = map
	md.z_index = -10
	add_child(md)
	_build_pickups()
	var gg := _GroundGuns.new()
	gg.game = self
	gg.z_index = -4
	add_child(gg)
	var pk := _Pickups.new()
	pk.game = self
	pk.z_index = -5
	add_child(pk)
	_add_vignette()
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var size: Vector2 = map["size"]
	var rects: Array = map["rects"].duplicate()
	rects.append([-100, -2000, 100, size.y + 4000])     # left wall
	rects.append([size.x, -2000, 100, size.y + 4000])   # right wall
	rects.append([-100, -200, size.x + 200, 100])       # ceiling
	for r in rects:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(r[2], r[3])
		cs.shape = sh
		cs.position = Vector2(r[0], r[1]) + sh.size * 0.5
		body.add_child(cs)
	if map.has("ground"):
		var poly := PackedVector2Array()
		for v in map["ground"]:
			poly.append(v)
		poly.append(Vector2(size.x, size.y + 400))
		poly.append(Vector2(0, size.y + 400))
		var cp := CollisionPolygon2D.new()
		cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		cp.polygon = poly
		body.add_child(cp)


func _add_vignette() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 1
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.55))
	g.add_point(0.6, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(tr)
	add_child(cl)


## Pickup spots are derived from the map so every peer computes the same list.
func _build_pickups() -> void:
	pickups.clear()
	if map.has("pickups"):
		for pk in map["pickups"]:
			pickups.append({"pos": Vector2(float(pk[0]), float(pk[1])), "kind": str(pk[2]), "active": true, "t": 0.0})
		return
	var n := 0
	var rects: Array = map["rects"]
	for i in rects.size():
		var r: Array = rects[i]
		if float(r[2]) >= 300.0 and float(r[3]) == 40.0:
			n += 1
			if n % 2 == 1:
				continue
			var kind := "medkit" if (n / 2) % 2 == 1 else "ammo"
			pickups.append({"pos": Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) - 22.0), "kind": kind, "active": true, "t": 0.0})


func _server_pickups(delta: float) -> void:
	for i in pickups.size():
		var pk: Dictionary = pickups[i]
		if not pk["active"]:
			pk["t"] -= delta
			if pk["t"] <= 0.0:
				_all("_net_pickup_back", [i])
			continue
		for p in get_players():
			if not p.alive or p.global_position.distance_to(pk["pos"]) > 42.0:
				continue
			var need := false
			if pk["kind"] == "medkit":
				need = p.hp < p.max_hp
			else:
				need = p.ammo[0] < p.mag_slot(0) or p.ammo[1] < p.mag_slot(1)
			if need:
				pk["t"] = Catalog.PICKUP_RESPAWN
				_all("_net_pickup", [i, p.peer_id])
				break


@rpc("authority", "call_local", "reliable")
func _net_pickup(i: int, pid: int) -> void:
	if i < 0 or i >= pickups.size():
		return
	var pk: Dictionary = pickups[i]
	pk["active"] = false
	pk["t"] = Catalog.PICKUP_RESPAWN
	var p := get_player(pid)
	if p:
		if pk["kind"] == "medkit":
			p.hp = mini(p.max_hp, p.hp + Catalog.PICKUP_HEAL)
			fx.spark(pk["pos"], Color(0.4, 1.0, 0.5), 14, 260.0)
		else:
			p.ammo = [p.mag_slot(0), p.mag_slot(1)]
			p.reloading = 0.0
			fx.spark(pk["pos"], Color(1.0, 0.85, 0.3), 14, 260.0)
		if pid == multiplayer.get_unique_id():
			Sfx.play("buy", 0.6, 0.0)
			hud.show_center("+%d HP" % Catalog.PICKUP_HEAL if pk["kind"] == "medkit" else "AMMO FULL", 0.8)


@rpc("authority", "call_local", "reliable")
func _net_pickup_back(i: int) -> void:
	if i >= 0 and i < pickups.size():
		pickups[i]["active"] = true


func _spawn_player(id: int, info: Dictionary) -> void:
	var p := Player.new()
	p.setup(id, info, self)
	var sp: Array = map["spawns"][int(info.get("team", 0)) % 2]
	p.position = sp[0]
	players_node.add_child(p)
	p.do_die()  # hidden until the match begins
	stats[id] = {"k": 0, "d": 0}


# ================================================================ ground guns
## Map weapon spots: explicit list for big maps, otherwise one gun on a few wide ledges.
func _map_gun_spots() -> Array:
	if map.has("guns"):
		return map["guns"]
	var out: Array = []
	var pool := ["mp5", "rifle", "shotgun", "mp40", "woodpecker", "svd", "sniper", "rocket"]
	var n := 0
	for r in map["rects"]:
		if float(r[2]) >= 300.0 and float(r[3]) == 40.0 and float(r[1]) < map["size"].y - 150.0:
			n += 1
			if n % 2 == 0:
				continue
			out.append([float(r[0]) + float(r[2]) * 0.5 - 90.0, float(r[1]) - 26.0, pool[(n / 2) % pool.size()]])
	return out


func _server_init_ground_guns() -> void:
	_spots.clear()
	var list := _map_gun_spots()
	for i in list.size():
		var g: Array = list[i]
		var pos := Vector2(float(g[0]), float(g[1]))
		_spots.append({"w": str(g[2]), "pos": pos, "gid": i, "t": 0.0})
		_all("_net_ground_add", [i, str(g[2]), pos, i])


func _server_ground_tick(delta: float) -> void:
	for gid in ground_guns.keys():
		var g: Dictionary = ground_guns[gid]
		if int(g["spot"]) < 0:
			g["t"] = float(g["t"]) - delta
			if float(g["t"]) <= 0.0:
				_all("_net_ground_remove", [int(gid)])
	for i in _spots.size():
		var sp: Dictionary = _spots[i]
		if int(sp["gid"]) >= 0:
			continue
		sp["t"] = float(sp["t"]) - delta
		if float(sp["t"]) <= 0.0:
			sp["gid"] = i
			_all("_net_ground_add", [i, sp["w"], sp["pos"], i])


## Drops a weapon at a position (host). Rests on the floor below the point.
func _server_drop(w: String, pos: Vector2) -> void:
	var q := PhysicsRayQueryParameters2D.create(pos + Vector2(0, -10), pos + Vector2(0, 900), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	var at := pos
	if not hit.is_empty():
		at = (hit["position"] as Vector2) + Vector2(0, -26)
	var gid := _drop_seq
	_drop_seq += 1
	_all("_net_ground_add", [gid, w, at, -1])
	# keep the number of loose guns bounded
	var drops: Array = []
	for k in ground_guns:
		if int(ground_guns[k]["spot"]) < 0:
			drops.append(int(k))
	if drops.size() > 14:
		drops.sort()
		_all("_net_ground_remove", [drops[0]])


@rpc("authority", "call_local", "reliable")
func _net_ground_add(gid: int, w: String, pos: Vector2, spot: int) -> void:
	ground_guns[gid] = {"w": w, "pos": pos, "spot": spot, "t": Catalog.GROUND_GUN_LIFETIME}


@rpc("authority", "call_local", "reliable")
func _net_ground_remove(gid: int) -> void:
	if not ground_guns.has(gid):
		return
	var spot := int(ground_guns[gid]["spot"])
	ground_guns.erase(gid)
	if multiplayer.is_server() and spot >= 0 and spot < _spots.size():
		_spots[spot]["gid"] = -1
		_spots[spot]["t"] = Catalog.GUN_SPOT_RESPAWN


## Nearest ground gun within reach of a player, or -1.
func gun_near(p: Player) -> int:
	var best := -1
	var best_d: float = Catalog.PICK_RADIUS
	for gid in ground_guns:
		var d := (p.global_position + Vector2(0, 6)).distance_to(ground_guns[gid]["pos"])
		if d < best_d:
			best_d = d
			best = int(gid)
	return best


## What picking up `w` would do for p: "dual", "ammo" or "swap".
func pick_kind(p: Player, w: String) -> String:
	for i in 2:
		if p.weapons[i] == w:
			if bool(Catalog.weapon(w).get("dual", false)) and not bool(p.dual[i]):
				return "dual"
			return "ammo"
	return "swap"


func request_pick() -> void:
	var p := local_player()
	if p == null or not p.alive or not started or ended:
		return
	var gid := gun_near(p)
	if gid < 0:
		return
	if multiplayer.is_server():
		_server_pick(p, gid)
	else:
		_rpc_pick.rpc_id(1, gid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pick(gid: int) -> void:
	if multiplayer.is_server():
		var p := get_player(multiplayer.get_remote_sender_id())
		if p:
			_server_pick(p, gid)


func _server_pick(p: Player, gid: int) -> void:
	if p == null or not p.alive or not ground_guns.has(gid) or ended:
		return
	var g: Dictionary = ground_guns[gid]
	if p.global_position.distance_to(g["pos"]) > Catalog.PICK_RADIUS + 40.0:
		return
	var w: String = g["w"]
	var weapons: Array = p.weapons.duplicate()
	var dual: Array = p.dual.duplicate()
	var slot := p.slot
	var kind := pick_kind(p, w)
	var refill := -1
	if kind == "dual" or kind == "ammo":
		var i := weapons.find(w)
		if kind == "dual":
			dual[i] = true
			slot = i
		refill = i
	else:
		var old: String = weapons[slot]
		weapons[slot] = w
		dual[slot] = false
		refill = slot
		_server_drop(old, p.global_position)
	_all("_net_ground_remove", [gid])
	_all("_net_loadout", [p.peer_id, weapons, dual, refill, slot])


@rpc("authority", "call_local", "reliable")
func _net_loadout(pid: int, weapons: Array, dual: Array, refill: int, slot: int) -> void:
	var p := get_player(pid)
	if p == null:
		return
	p.set_loadout(weapons, dual, refill, slot)
	if pid == multiplayer.get_unique_id():
		var w: String = weapons[slot]
		hud.show_center(("DUAL " if dual[slot] else "") + str(Catalog.weapon(w)["name"]).to_upper(), 0.9)


## Bots: position of a better gun within `radius`, or ZERO.
func bot_loot_target(p: Player, radius: float) -> Vector2:
	var my_tier := int(Catalog.weapon(p.current_weapon()).get("tier", 1))
	var best := Vector2.ZERO
	var best_d := radius
	for gid in ground_guns:
		var g: Dictionary = ground_guns[gid]
		var d := p.global_position.distance_to(g["pos"])
		if d >= best_d:
			continue
		var k := pick_kind(p, g["w"])
		var good := k == "dual" or (k == "swap" and int(Catalog.weapon(g["w"]).get("tier", 1)) > my_tier)
		if k == "ammo" and p.ammo[p.slot] < p.mag_slot(p.slot) / 3:
			good = true
		if good:
			best = g["pos"]
			best_d = d
	return best


func bot_try_pick(p: Player) -> void:
	if multiplayer.is_server():
		var gid := gun_near(p)
		if gid >= 0:
			_server_pick(p, gid)


# ================================================================ scope
func scopes_of(w: String) -> Array:
	return Catalog.weapon(w).get("scopes", [1])


func scope_level() -> int:
	var p := local_player()
	if p == null:
		return 1
	var sc := scopes_of(p.current_weapon())
	return int(sc[clampi(scope_idx, 0, sc.size() - 1)])


func cycle_scope() -> void:
	var p := local_player()
	if p == null:
		return
	var sc := scopes_of(p.current_weapon())
	if sc.size() <= 1:
		return
	scope_idx = (scope_idx + 1) % sc.size()
	Sfx.play("reload", 0.3)


# ================================================================ queries
func get_players() -> Array[Player]:
	var out: Array[Player] = []
	for c in players_node.get_children():
		if c is Player and not c.is_queued_for_deletion():
			out.append(c)
	return out


func get_player(id: int) -> Player:
	var n := players_node.get_node_or_null(("B%d" % absi(id)) if id < 0 else ("P%d" % id))
	return n as Player


func local_player() -> Player:
	return get_player(multiplayer.get_unique_id())


func map_size() -> Vector2:
	return map["size"]


func listener_pos() -> Vector2:
	return camera.get_screen_center_position() if camera else Vector2.ZERO


func is_tdm() -> bool:
	return int(Network.settings.get("mode", 0)) == Catalog.MODE_TDM


## Calls `method` on every peer (including this one). Works in offline practice too.
func _all(method: StringName, args: Array) -> void:
	if Network.offline:
		callv(method, args)
	else:
		callv("rpc", [method] + args)


# ================================================================ match start (host)
func server_begin() -> void:
	if started or not multiplayer.is_server():
		return
	var t := float(Catalog.MATCH_TIMES[clampi(int(Network.settings.get("time", 1)), 0, Catalog.MATCH_TIMES.size() - 1)])
	var spawns := {}
	var used := {}
	for p in get_players():
		var list: Array = map["spawns"][p.team % 2] if is_tdm() else map["spawns"][0] + map["spawns"][1]
		var pos: Vector2 = list[randi() % list.size()]
		for i in list.size():
			var cand: Vector2 = list[(i + randi()) % list.size()]
			if not used.has(cand):
				pos = cand
				break
		used[pos] = true
		spawns[p.peer_id] = pos + Vector2(randf_range(-20, 20), 0)
	_server_init_ground_guns()
	_all("_begin", [t, spawns, stats])


@rpc("authority", "call_local", "reliable")
func _begin(t: float, spawns: Dictionary, s: Dictionary) -> void:
	started = true
	time_left = t
	stats = s
	for id in spawns:
		var p := get_player(int(id))
		if p:
			p.do_respawn(spawns[id])
	var lp := local_player()
	if lp:
		camera.global_position = lp.global_position
		camera.reset_smoothing()
	hud.show_center("FIGHT!", 1.5)
	Sfx.play("buy", 0.7, 0.0)


# ================================================================ per frame
func _physics_process(delta: float) -> void:
	_handle_local_input()
	_update_bullets(delta)
	if started and not ended:
		if multiplayer.is_server():
			_server_tick(delta)
		else:
			time_left = maxf(0.0, time_left - delta)
	_update_camera(delta)
	_update_hud(delta)


func _handle_local_input() -> void:
	var p := local_player()
	if p == null or not input_enabled:
		return
	if not started or ended or hud.is_paused() or not p.alive:
		p.in_move = 0.0
		p.in_jet = false
		p.in_fire = false
		return
	var kb_move := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		kb_move -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		kb_move += 1.0
	var kb_jet := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_UP)
	if hud.touch.visible:
		var t := hud.touch
		p.in_move = t.move if t.move != 0.0 else kb_move
		p.in_jet = t.jet or kb_jet
		p.in_fire = t.fire
		if t.aim != Vector2.ZERO:
			p.in_aim = t.aim
	else:
		p.in_move = kb_move
		p.in_jet = kb_jet
		p.in_aim = get_global_mouse_position() - (p.global_position + Player.SHOULDER)
		p.in_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var p := local_player()
		match event.physical_keycode:
			KEY_ESCAPE, KEY_P:
				hud.toggle_pause()
			KEY_R:
				if p: p.start_reload()
			KEY_Q, KEY_E:
				if p: p.switch_weapon()
			KEY_1:
				if p and p.slot != 0: p.switch_weapon()
			KEY_2:
				if p and p.slot != 1: p.switch_weapon()
			KEY_F, KEY_G:
				request_pick()
			KEY_Z, KEY_C:
				cycle_scope()
			KEY_TAB:
				hud.scoreboard.visible = true
	elif event is InputEventKey and not event.pressed and event.physical_keycode == KEY_TAB:
		hud.scoreboard.visible = false
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_RIGHT]:
			var p := local_player()
			if p: p.switch_weapon()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud:
		hud.toggle_pause()  # Android back button


func _update_camera(delta: float) -> void:
	var p := local_player()
	var sl := 1.0
	if p:
		if p.current_weapon() != _scope_weapon:
			_scope_weapon = p.current_weapon()
			scope_idx = 0
		sl = float(scope_level()) if p.alive else 1.0
	var want := _base_zoom / (1.0 + (sl - 1.0) * 0.12)
	var z := lerpf(camera.zoom.x, want, clampf(delta * 6.0, 0.0, 1.0))
	camera.zoom = Vector2(z, z)
	if p and p.alive:
		var look := Vector2.ZERO
		if not hud.touch.visible:
			look = (get_global_mouse_position() - p.global_position).limit_length(400.0 + (sl - 1.0) * 160.0) * (0.25 + (sl - 1.0) * 0.07)
		else:
			look = p.in_aim.normalized() * (90.0 + (sl - 1.0) * 110.0)
		camera.global_position = p.global_position + look
	_shake = maxf(0.0, _shake - delta)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * _shake / 0.25 if _shake > 0.0 else Vector2.ZERO


func _update_hud(delta: float) -> void:
	var lp := local_player()
	near_gun = gun_near(lp) if lp and lp.alive and started and not ended else -1
	if near_gun >= 0:
		var w: String = ground_guns[near_gun]["w"]
		hud.touch.set_pick(w, pick_kind(lp, w))
	else:
		hud.touch.set_pick("", "")
	if lp:
		var sc := scopes_of(lp.current_weapon())
		hud.touch.set_weapon_info(lp.weapons[1 - lp.slot], scope_level(), sc.size() > 1)
	hud.update_hud(lp, time_left, _score_text())
	if lp and not lp.alive and started and not ended:
		_local_dead_timer = maxf(0.0, _local_dead_timer - delta)
		hud.show_center("Respawning in %d" % int(ceil(_local_dead_timer)))
	_score_refresh -= delta
	if hud.scoreboard.visible and _score_refresh <= 0.0:
		_score_refresh = 0.5
		hud.set_scoreboard(_score_title(), _score_rows())


func _score_text() -> String:
	var limit: int = Catalog.KILL_LIMITS[1 if is_tdm() else 0]
	if is_tdm():
		return "RED %d  -  %d BLUE    (first to %d)" % [team_score[0], team_score[1], limit]
	var rows := _score_rows()
	var my_k := int(stats.get(multiplayer.get_unique_id(), {"k": 0})["k"])
	if rows.is_empty():
		return ""
	return "Leader: %s %d    You: %d    (first to %d)" % [rows[0]["name"], rows[0]["kills"], my_k, limit]


func _score_title() -> String:
	return "%s  -  %s" % [Catalog.MODE_NAMES[1 if is_tdm() else 0], map["name"]]


func _score_rows() -> Array:
	var rows: Array = []
	var me := multiplayer.get_unique_id()
	for id in stats:
		if not Network.players.has(id):
			continue
		var info: Dictionary = Network.players[id]
		var col: Color = Catalog.TEAM_COLORS[int(info.get("team", 0))] if is_tdm() else Catalog.color_by_index(int(info.get("color", 0)))
		rows.append({"id": id, "name": str(info.get("name", "?")), "kills": int(stats[id]["k"]), "deaths": int(stats[id]["d"]),
			"color": col, "me": int(id) == me, "team": int(info.get("team", 0))})
	rows.sort_custom(func(a, b):
		if a["kills"] != b["kills"]:
			return a["kills"] > b["kills"]
		return a["deaths"] < b["deaths"])
	return rows


# ================================================================ shooting
## Called by Player when the controlling peer fires.
func request_fire(p: Player, weapon_id: String, origin: Vector2, angle: float) -> void:
	if not started or ended:
		return
	p.muzzle_flash = 0.06
	if multiplayer.is_server():
		_server_fire(p.peer_id, weapon_id, origin, angle)
	else:
		_rpc_fire.rpc_id(1, weapon_id, origin, angle)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_fire(weapon_id: String, origin: Vector2, angle: float) -> void:
	if multiplayer.is_server():
		_server_fire(multiplayer.get_remote_sender_id(), weapon_id, origin, angle)


func _server_fire(id: int, weapon_id: String, origin: Vector2, angle: float) -> void:
	var p := get_player(id)
	if p == null or not p.alive or ended or not started:
		return
	if not weapon_id in p.weapons:
		return
	var w := Catalog.weapon(weapon_id)
	var now := Time.get_ticks_msec()
	var key := "%d:%s" % [id, weapon_id]
	var si := p.weapons.find(weapon_id)
	var fd := float(w["fire_delay"]) * (Catalog.DUAL_FIRE_FACTOR if si >= 0 and bool(p.dual[si]) else 1.0)
	if now - int(_last_fire.get(key, -100000)) < int(fd * 1000.0 * 0.7):
		return  # firing faster than the weapon allows
	_last_fire[key] = now
	if origin.distance_to(p.global_position) > 140.0:
		origin = p.muzzle_global()
	var angles := PackedFloat32Array()
	for i in int(w["pellets"]):
		angles.append(angle + randf_range(-float(w["spread"]), float(w["spread"])))
	var first := _bullet_seq
	_bullet_seq += angles.size()
	_all("_spawn_bullets", [id, weapon_id, origin, angles, first])


@rpc("authority", "call_local", "reliable")
func _spawn_bullets(id: int, weapon_id: String, origin: Vector2, angles: PackedFloat32Array, first: int) -> void:
	var w := Catalog.weapon(weapon_id)
	var p := get_player(id)
	var ex: Array[RID] = []
	if p:
		ex.append(p.get_rid())
		p.muzzle_flash = 0.06
		if not p.is_controlled_here() and p.is_dual():
			p._dual_side = 1 - p._dual_side
		if weapon_id != "rocket" and origin.distance_to(listener_pos()) < 1400.0:
			fx.casing(p.global_position + Player.SHOULDER + Vector2.from_angle(angles[0]) * 14.0, signf(cos(angles[0])))
		if is_tdm():
			for o in get_players():
				if o != p and o.team == p.team:
					ex.append(o.get_rid())
	for i in angles.size():
		bullets.append({"id": first + i, "owner": id, "w": weapon_id, "pos": origin,
			"vel": Vector2.from_angle(angles[i]) * float(w["speed"]), "life": float(w["life"]), "ex": ex})
	Sfx.play_at(str(w["sound"]), origin, listener_pos(), 0.9)


func _update_bullets(delta: float) -> void:
	if bullets.is_empty():
		return
	var space := get_world_2d().direct_space_state
	var server := multiplayer.is_server()
	# iterate a snapshot: hit handling may remove bullets or end the match
	for b in bullets.duplicate():
		if b.get("dead", false) or ended:
			continue
		b["life"] -= delta
		var from: Vector2 = b["pos"]
		var to: Vector2 = from + (b["vel"] as Vector2) * delta
		var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 2, b["ex"])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			b["pos"] = hit["position"]
			b["dead"] = true
			if server:
				_server_bullet_hit(b, hit["collider"], hit["position"])
			elif not hit["collider"] is Player:
				fx.spark(hit["position"], Color(1, 0.85, 0.5), 4)
				fx.dust(hit["position"])
			continue
		b["pos"] = to
		if b["life"] <= 0.0:
			b["dead"] = true
			if server and float(Catalog.weapon(b["w"])["splash"]) > 0.0:
				_server_explode(int(b["owner"]), b["w"], to)
	bullets = bullets.filter(func(x): return not x.get("dead", false))


func _remove_bullet(bid: int) -> void:
	for b in bullets:
		if int(b["id"]) == bid:
			b["dead"] = true
			return


func _server_bullet_hit(b: Dictionary, collider: Object, pos: Vector2) -> void:
	var w := Catalog.weapon(b["w"])
	if float(w["splash"]) > 0.0:
		_server_explode(int(b["owner"]), b["w"], pos)
		return
	if collider is Player:
		_all("_bullet_end", [int(b["id"]), pos, true])
		_server_damage(collider, int(w["damage"]), int(b["owner"]), b["w"])
	else:
		_all("_bullet_end", [int(b["id"]), pos, false])


@rpc("authority", "call_local", "reliable")
func _bullet_end(bid: int, pos: Vector2, hit_player: bool) -> void:
	_remove_bullet(bid)
	fx.spark(pos, Color(1, 0.2, 0.2) if hit_player else Color(1, 0.85, 0.5), 6 if hit_player else 4)
	if not hit_player:
		fx.dust(pos)


func _server_explode(owner_id: int, weapon_id: String, pos: Vector2) -> void:
	var w := Catalog.weapon(weapon_id)
	var radius := float(w["splash"])
	var shooter := get_player(owner_id)
	_all("_explosion", [pos, radius])
	for p in get_players():
		if not p.alive:
			continue
		var d := p.global_position.distance_to(pos)
		if d > radius:
			continue
		var dmg := float(w["damage"]) * (1.0 - (d / radius) * 0.6)
		if p.peer_id == owner_id:
			dmg *= SELF_SPLASH_FACTOR
		elif shooter and not shooter.is_enemy_of(p):
			continue
		_server_damage(p, int(dmg), owner_id, weapon_id)


@rpc("authority", "call_local", "reliable")
func _explosion(pos: Vector2, radius: float) -> void:
	fx.explode(pos, radius)
	Sfx.play_at("explosion", pos, listener_pos(), 1.0)
	var lp := local_player()
	if lp and lp.global_position.distance_to(pos) < radius * 2.5:
		_shake = 0.25


# ================================================================ damage / death (host)
func _server_damage(victim: Player, amount: int, attacker_id: int, weapon_id: String) -> void:
	if victim == null or not victim.alive or victim.protect > 0.0 or ended or amount <= 0:
		return
	if attacker_id != victim.peer_id:
		var a := get_player(attacker_id)
		if a and not a.is_enemy_of(victim):
			return
		if a and a.is_bot:
			amount = maxi(1, int(round(amount * float(a._lvl.get("dmg", 1.0)))))
	victim.hp -= amount
	if victim.hp <= 0:
		_server_kill(victim, attacker_id, weapon_id)
	else:
		_all("_net_hp", [victim.peer_id, victim.hp, attacker_id])


func _server_kill(victim: Player, killer_id: int, weapon_id: String) -> void:
	if not victim.alive:
		return
	var vid := victim.peer_id
	if stats.has(vid):
		stats[vid]["d"] += 1
	if killer_id != vid and stats.has(killer_id):
		stats[killer_id]["k"] += 1
		var k := get_player(killer_id)
		if k and is_tdm():
			team_score[k.team] += 1
	_respawn_q[vid] = Catalog.RESPAWN_TIME
	if weapon_id != "fall":
		_server_drop(victim.current_weapon(), victim.global_position)
	_all("_net_death", [vid, killer_id, weapon_id, stats, team_score])
	_check_win()


@rpc("authority", "call_local", "reliable")
func _net_hp(id: int, hp: int, attacker_id: int) -> void:
	var p := get_player(id)
	if p == null:
		return
	var dmg := p.hp - hp
	p.hp = hp
	p.flash = 0.08
	var me := multiplayer.get_unique_id()
	if dmg > 0 and (attacker_id == me or id == me):
		fx.number(p.global_position, dmg, Color(1, 0.35, 0.3) if id == me else Color(1, 0.9, 0.35))
	if attacker_id == me and id != me:
		Sfx.play("hit", 0.6, 0.0)
	if id == me:
		_shake = 0.15


@rpc("authority", "call_local", "reliable")
func _net_death(vid: int, killer_id: int, weapon_id: String, s: Dictionary, ts: Array) -> void:
	stats = s
	team_score = ts
	var v := get_player(vid)
	var k := get_player(killer_id)
	if v:
		fx.burst(v.global_position, v.body_color)
		Sfx.play_at("death", v.global_position, listener_pos(), 0.8)
		v.do_die()
	var vname := str(Network.players.get(vid, {}).get("name", "?"))
	var kname := str(Network.players.get(killer_id, {}).get("name", "?"))
	var me := multiplayer.get_unique_id()
	var text := ""
	if weapon_id == "fall":
		text = "%s fell" % vname
	elif killer_id == vid:
		text = "%s blew themselves up" % vname
	else:
		text = "%s  [%s]  %s" % [kname, Catalog.weapon(weapon_id)["name"], vname]
	var col := Color.WHITE
	if killer_id == me or vid == me:
		col = UIKit.ACCENT2
	elif k:
		col = k.body_color.lightened(0.2)
	hud.add_kill(text, col)
	if vid == me:
		_local_dead_timer = Catalog.RESPAWN_TIME
		_shake = 0.25
	elif killer_id == me:
		hud.show_center("+1  " + vname, 1.0)


func _server_tick(delta: float) -> void:
	time_left = maxf(0.0, time_left - delta)
	_time_sync -= delta
	if _time_sync <= 0.0 and not Network.offline:
		_time_sync = 1.0
		_net_time.rpc(time_left)
	# respawns
	for id in _respawn_q.keys():
		_respawn_q[id] -= delta
		if _respawn_q[id] <= 0.0:
			_respawn_q.erase(id)
			var p := get_player(int(id))
			if p:
				_all("_net_respawn", [int(id), _pick_spawn(p)])
	_server_pickups(delta)
	_server_ground_tick(delta)
	# fell out of the map
	var limit_y: float = map["size"].y + 150.0
	for p in get_players():
		if p.alive and p.global_position.y > limit_y:
			_server_kill(p, p.peer_id, "fall")
	if time_left <= 0.0:
		_server_end_match()


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_time(t: float) -> void:
	time_left = t


@rpc("authority", "call_local", "reliable")
func _net_respawn(id: int, pos: Vector2) -> void:
	var p := get_player(id)
	if p:
		p.do_respawn(pos)
		if id == multiplayer.get_unique_id():
			hud.show_center("")
			camera.global_position = pos
			camera.reset_smoothing()


func _pick_spawn(p: Player) -> Vector2:
	var list: Array = map["spawns"][p.team % 2] if is_tdm() else map["spawns"][0] + map["spawns"][1]
	var best: Vector2 = list[0]
	var best_score := -INF
	for cand in list:
		var nearest := 99999.0
		for o in get_players():
			if o != p and o.alive and p.is_enemy_of(o):
				nearest = minf(nearest, o.global_position.distance_to(cand))
		var score := nearest + randf_range(0.0, 250.0)
		if score > best_score:
			best_score = score
			best = cand
	return best + Vector2(randf_range(-20, 20), 0)


# ================================================================ end of match
func _check_win() -> void:
	if ended:
		return
	if is_tdm():
		if team_score[0] >= Catalog.KILL_LIMITS[1] or team_score[1] >= Catalog.KILL_LIMITS[1]:
			_server_end_match()
	else:
		for id in stats:
			if int(stats[id]["k"]) >= Catalog.KILL_LIMITS[0]:
				_server_end_match()
				return


func _server_end_match() -> void:
	if ended:
		return
	var winner_id := 0
	var winner_team := -1
	if is_tdm():
		if team_score[0] > team_score[1]:
			winner_team = 0
		elif team_score[1] > team_score[0]:
			winner_team = 1
	else:
		var rows := _score_rows()
		if rows.size() > 0:
			var tie: bool = rows.size() > 1 and rows[1]["kills"] == rows[0]["kills"] and rows[1]["deaths"] == rows[0]["deaths"]
			if not tie:
				winner_id = int(rows[0]["id"])
	_all("_end_match", [stats, team_score, winner_id, winner_team])
	get_tree().create_timer(END_SCREEN_TIME).timeout.connect(Network.return_to_lobby)


@rpc("authority", "call_local", "reliable")
func _end_match(s: Dictionary, ts: Array, winner_id: int, winner_team: int) -> void:
	ended = true
	stats = s
	team_score = ts
	bullets.clear()
	var me := multiplayer.get_unique_id()
	var my_team := int(Network.players.get(me, {}).get("team", 0))
	var won := false
	var title := "DRAW"
	var tcol := UIKit.ACCENT2
	if is_tdm():
		if winner_team >= 0:
			won = winner_team == my_team
			title = "%s TEAM WINS" % Catalog.TEAM_NAMES[winner_team].to_upper()
			tcol = UIKit.GOOD if won else UIKit.BAD
	elif winner_id != 0:
		won = winner_id == me
		title = "VICTORY" if won else "%s WINS" % str(Network.players.get(winner_id, {}).get("name", "?"))
		tcol = UIKit.GOOD if won else UIKit.BAD
	var my_stats: Dictionary = stats.get(me, {"k": 0, "d": 0})
	var reward := Profile.grant_match_rewards(int(my_stats["k"]), int(my_stats["d"]), won, _bots_only)
	hud.show_results(title, tcol, _score_rows(), reward, multiplayer.is_server())
	Sfx.play("buy" if won else "death", 0.8, 0.0)


func _on_player_left(id: int) -> void:
	var p := get_player(id)
	if p:
		hud.add_kill("%s left" % str(p.info.get("name", "?")), UIKit.MUTED)
		players_node.remove_child(p)
		p.queue_free()
	stats.erase(id)
	_respawn_q.erase(id)
	for i in range(bullets.size() - 1, -1, -1):
		if int(bullets[i]["owner"]) == id:
			bullets.remove_at(i)
