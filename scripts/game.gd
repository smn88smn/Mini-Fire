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
var input_enabled := true  # set false to drive the local player from code (tests, replays)


# ================================================================ drawing helpers
class _MapDraw extends Node2D:
	var map: Dictionary

	func _draw() -> void:
		var size: Vector2 = map["size"]
		var bg: Color = map["bg"]
		var solid: Color = map["solid"]
		# outside area
		draw_rect(Rect2(-2000, -2000, size.x + 4000, size.y + 4000), bg.darkened(0.55))
		# sky gradient
		var bands := 12
		for i in bands:
			var f := float(i) / bands
			draw_rect(Rect2(0, size.y * f, size.x, size.y / bands + 1), bg.lightened(0.12 * (1.0 - f)))
		# stars / dust
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		for i in 160:
			var p := Vector2(rng.randf() * size.x, rng.randf() * size.y * 0.7)
			draw_circle(p, rng.randf_range(0.8, 2.2), Color(1, 1, 1, rng.randf_range(0.08, 0.35)))
		# distant hills
		var hill := PackedVector2Array()
		hill.append(Vector2(0, size.y))
		var x := 0.0
		while x <= size.x:
			hill.append(Vector2(x, size.y * 0.62 + sin(x * 0.0031) * 120.0 + sin(x * 0.011) * 40.0))
			x += 60.0
		hill.append(Vector2(size.x, size.y))
		draw_colored_polygon(hill, bg.darkened(0.3))
		# solids
		for r in map["rects"]:
			var rect := Rect2(r[0], r[1], r[2], r[3])
			draw_rect(rect, solid)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5)), solid.lightened(0.3))
			draw_rect(Rect2(rect.position.x, rect.end.y - 4, rect.size.x, 4), solid.darkened(0.3))
			draw_rect(rect, solid.darkened(0.45), false, 2.0)


class _FX extends Node2D:
	var game: Node
	var explosions: Array = []  # {pos, t, r}
	var sparks: Array = []      # {pos, vel, t, col}

	func spark(pos: Vector2, col: Color, n: int = 6, speed: float = 260.0) -> void:
		for i in n:
			sparks.append({"pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.3, speed), "t": randf_range(0.2, 0.45), "col": col})
		if sparks.size() > 400:
			sparks = sparks.slice(sparks.size() - 400)

	func explode(pos: Vector2, r: float) -> void:
		explosions.append({"pos": pos, "t": 0.0, "r": r})
		spark(pos, Color(1, 0.6, 0.2), 24, 520.0)

	func _process(delta: float) -> void:
		for i in range(sparks.size() - 1, -1, -1):
			var s: Dictionary = sparks[i]
			s["t"] -= delta
			if s["t"] <= 0.0:
				sparks.remove_at(i)
				continue
			s["vel"] = (s["vel"] as Vector2) + Vector2(0, 900) * delta
			s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
		for i in range(explosions.size() - 1, -1, -1):
			explosions[i]["t"] += delta
			if explosions[i]["t"] > 0.45:
				explosions.remove_at(i)
		queue_redraw()

	func _draw() -> void:
		for b in game.bullets:
			var dir: Vector2 = (b["vel"] as Vector2).normalized()
			var p: Vector2 = b["pos"]
			if b["w"] == "rocket":
				draw_circle(p, 6.0, Color(0.9, 0.9, 0.9))
				draw_circle(p - dir * 9.0, 5.0, Color(1, 0.6, 0.1, 0.9))
				draw_circle(p - dir * 18.0, 7.0, Color(0.6, 0.6, 0.6, 0.35))
			elif b["w"] == "sniper":
				draw_line(p - dir * 60.0, p, Color(1, 1, 0.8, 0.9), 2.5)
			else:
				draw_line(p - dir * 18.0, p, Color(1, 0.9, 0.5, 0.95), 2.0)
		for s in sparks:
			var c: Color = s["col"]
			c.a = clampf(s["t"] * 3.0, 0.0, 1.0)
			draw_rect(Rect2((s["pos"] as Vector2) - Vector2(2, 2), Vector2(4, 4)), c)
		for e in explosions:
			var f: float = e["t"] / 0.45
			var r: float = e["r"] * (0.4 + f * 0.8)
			draw_circle(e["pos"], r, Color(1, 0.55, 0.15, 0.55 * (1.0 - f)))
			draw_circle(e["pos"], r * 0.55, Color(1, 0.95, 0.6, 0.8 * (1.0 - f)))


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
	camera.zoom = Vector2(1.1, 1.1) if Profile.use_touch_controls() else Vector2(1.0, 1.0)
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
	hud.show_center("Waiting for players...")
	_bots_only = not Network.has_humans_besides_me()
	Network.player_left.connect(_on_player_left)
	Network.report_loaded.call_deferred()


func _build_world() -> void:
	var md := _MapDraw.new()
	md.map = map
	md.z_index = -10
	add_child(md)
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


func _spawn_player(id: int, info: Dictionary) -> void:
	var p := Player.new()
	p.setup(id, info, self)
	var sp: Array = map["spawns"][int(info.get("team", 0)) % 2]
	p.position = sp[0]
	players_node.add_child(p)
	p.do_die()  # hidden until the match begins
	stats[id] = {"k": 0, "d": 0}


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
	if p and p.alive:
		var look := Vector2.ZERO
		if not hud.touch.visible:
			look = (get_global_mouse_position() - p.global_position).limit_length(400.0) * 0.25
		else:
			look = p.in_aim.normalized() * 90.0
		camera.global_position = p.global_position + look
	_shake = maxf(0.0, _shake - delta)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * _shake / 0.25 if _shake > 0.0 else Vector2.ZERO


func _update_hud(delta: float) -> void:
	var lp := local_player()
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
	if now - int(_last_fire.get(key, -100000)) < int(float(w["fire_delay"]) * 1000.0 * 0.7):
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
	_all("_net_death", [vid, killer_id, weapon_id, stats, team_score])
	_check_win()


@rpc("authority", "call_local", "reliable")
func _net_hp(id: int, hp: int, attacker_id: int) -> void:
	var p := get_player(id)
	if p == null:
		return
	p.hp = hp
	p.flash = 0.08
	var me := multiplayer.get_unique_id()
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
		fx.spark(v.global_position, v.body_color, 22, 420.0)
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
