class_name Player
extends CharacterBody2D
## A soldier with a jetpack. Movement is simulated by the controlling peer
## (the human owner, or the host for bots) and streamed to everyone else.
## Health, damage, kills and respawns are decided by the host (see game.gd).

const GRAVITY := 1500.0
const MOVE_SPEED := 340.0
const GROUND_ACCEL := 2600.0
const AIR_ACCEL := 1500.0
const JET_ACCEL := 3000.0
const JET_MAX_UP := -560.0
const MAX_FALL := 1000.0
const FUEL_DRAIN := 0.42
const FUEL_REGEN_GROUND := 0.45
const FUEL_REGEN_AIR := 0.1
const NET_RATE := 1.0 / 30.0
const BODY_RADIUS := 14.0
const BODY_HEIGHT := 52.0
const SHOULDER := Vector2(0, -6)

var peer_id: int = 0
var info: Dictionary = {}
var team: int = 0
var is_bot := false
var body_color := Color.WHITE
var game: Node = null

# state
var hp: int = Catalog.MAX_HEALTH
var alive := true
var fuel := 1.0
var jet_on := false
var aim_angle := 0.0
var slot := 0  # 0 primary, 1 pistol
var weapons: Array = []
var ammo: Array = [0, 0]
var reloading := 0.0
var cooldown := 0.0
var protect := 0.0  # spawn protection (visual on clients, enforced on host)
var flash := 0.0
var muzzle_flash := 0.0

# input (set by game for local player, by AI for bots)
var in_move := 0.0
var in_jet := false
var in_fire := false
var in_aim := Vector2.RIGHT

# networking
var _net_timer := 0.0
var _net_pos := Vector2.ZERO
var _net_vel := Vector2.ZERO
var _has_net := false
var _jet_player: AudioStreamPlayer = null

# bot brain
var _ai_target: Player = null
var _ai_think := 0.0
var _ai_strafe := 0.0
var _ai_wander := Vector2.ZERO
var _ai_aim_err := 0.0
var _ai_detour := 0.0        # >0 while taking a detour
var _ai_detour_dir := 1.0
var _ai_last_pos := Vector2.ZERO
var _ai_stuck_t := 0.0


func setup(id: int, p_info: Dictionary, p_game: Node) -> void:
	peer_id = id
	info = p_info
	game = p_game
	is_bot = bool(info.get("bot", false))
	team = int(info.get("team", 0))
	body_color = Catalog.color_by_index(int(info.get("color", 0)))
	weapons = [str(info.get("weapon", "rifle")), Catalog.SECONDARY_WEAPON]
	ammo = [int(Catalog.weapon(weapons[0])["mag"]), int(Catalog.weapon(weapons[1])["mag"])]
	name = ("B%d" % absi(id)) if id < 0 else ("P%d" % id)
	set_multiplayer_authority(1 if is_bot else id)
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 6.0
	var shape := CapsuleShape2D.new()
	shape.radius = BODY_RADIUS
	shape.height = BODY_HEIGHT
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	_jet_player = AudioStreamPlayer.new()
	_jet_player.stream = Sfx.sounds.get("jet")
	add_child(_jet_player)


func is_controlled_here() -> bool:
	return get_multiplayer_authority() == multiplayer.get_unique_id()


func is_local_human() -> bool:
	return not is_bot and peer_id == multiplayer.get_unique_id()


func current_weapon() -> String:
	return weapons[slot]


func weapon_data() -> Dictionary:
	return Catalog.weapon(current_weapon())


func skin_of(weapon_id: String) -> String:
	var sk = info.get("skins", {})
	return str(sk.get(weapon_id, "default")) if sk is Dictionary else "default"


func muzzle_global() -> Vector2:
	var m := GunArt.muzzle_offset(current_weapon())
	return global_position + SHOULDER + m.rotated(aim_angle)


func is_enemy_of(other: Player) -> bool:
	if other == self:
		return false
	if int(Network.settings.get("mode", 0)) == Catalog.MODE_TDM:
		return other.team != team
	return true


# ================================================================ simulation
func _physics_process(delta: float) -> void:
	protect = maxf(0.0, protect - delta)
	flash = maxf(0.0, flash - delta)
	muzzle_flash = maxf(0.0, muzzle_flash - delta)
	if is_controlled_here():
		if is_bot:
			_bot_think(delta)
		_simulate(delta)
		_net_timer -= delta
		if _net_timer <= 0.0 and not Network.offline:
			_net_timer = NET_RATE
			var flags := (1 if jet_on else 0) | (2 if slot == 1 else 0) | (4 if reloading > 0.0 else 0)
			_net_state.rpc(global_position, velocity, aim_angle, flags)
	elif _has_net:
		# smooth remote players: extrapolate with velocity, then ease toward network position
		_net_pos += _net_vel * delta
		global_position = global_position.lerp(_net_pos, clampf(delta * 18.0, 0.0, 1.0))
		if global_position.distance_to(_net_pos) > 250.0:
			global_position = _net_pos
	_update_jet_sound()
	queue_redraw()


func _simulate(delta: float) -> void:
	if not alive:
		velocity = Vector2.ZERO
		jet_on = false
		return
	cooldown = maxf(0.0, cooldown - delta)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			reloading = 0.0
			ammo[slot] = int(weapon_data()["mag"])
	# aim
	if in_aim.length_squared() > 0.0001:
		aim_angle = in_aim.angle()
	# horizontal movement
	var target_vx := clampf(in_move, -1.0, 1.0) * MOVE_SPEED
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, target_vx, accel * delta)
	# jetpack + gravity
	jet_on = in_jet and fuel > 0.02
	if jet_on:
		fuel = maxf(0.0, fuel - FUEL_DRAIN * delta)
		velocity.y = maxf(JET_MAX_UP, velocity.y - JET_ACCEL * delta)
	else:
		fuel = minf(1.0, fuel + (FUEL_REGEN_GROUND if is_on_floor() else FUEL_REGEN_AIR) * delta)
	velocity.y = minf(MAX_FALL, velocity.y + GRAVITY * delta)
	move_and_slide()
	# fire
	if in_fire:
		try_fire()
	elif ammo[slot] <= 0 and reloading <= 0.0:
		start_reload()


func try_fire() -> void:
	if not alive or cooldown > 0.0 or reloading > 0.0:
		return
	if ammo[slot] <= 0:
		start_reload()
		return
	var w := weapon_data()
	ammo[slot] -= 1
	cooldown = float(w["fire_delay"])
	# small recoil push
	velocity -= Vector2.from_angle(aim_angle) * float(w["recoil"])
	if game:
		game.request_fire(self, current_weapon(), muzzle_global(), aim_angle)
	if ammo[slot] <= 0:
		start_reload()


func start_reload() -> void:
	if reloading > 0.0 or not alive:
		return
	var w := weapon_data()
	if ammo[slot] >= int(w["mag"]):
		return
	reloading = float(w["reload"])
	if is_local_human():
		Sfx.play("reload", 0.7)


func switch_weapon() -> void:
	if not alive:
		return
	slot = 1 - slot
	reloading = 0.0
	cooldown = maxf(cooldown, 0.25)
	if is_local_human():
		Sfx.play("reload", 0.4)


## Host -> owner: put the player back at a spawn point.
func do_respawn(pos: Vector2) -> void:
	global_position = pos
	_net_pos = pos
	velocity = Vector2.ZERO
	hp = Catalog.MAX_HEALTH
	alive = true
	fuel = 1.0
	slot = 0
	reloading = 0.0
	cooldown = 0.3
	protect = 1.5
	ammo = [int(Catalog.weapon(weapons[0])["mag"]), int(Catalog.weapon(weapons[1])["mag"])]
	visible = true
	collision_layer = 2
	_ai_target = null


func do_die() -> void:
	alive = false
	hp = 0
	jet_on = false
	visible = false
	velocity = Vector2.ZERO
	collision_layer = 0  # dead bodies do not block bullets


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector2, vel: Vector2, aim: float, flags: int) -> void:
	if not _has_net:
		global_position = pos
	_has_net = true
	_net_pos = pos
	_net_vel = vel
	velocity = vel
	aim_angle = aim
	jet_on = (flags & 1) != 0
	slot = 1 if (flags & 2) != 0 else 0
	reloading = 0.1 if (flags & 4) != 0 else 0.0


func _update_jet_sound() -> void:
	if _jet_player == null:
		return
	var want := jet_on and alive and visible
	if want:
		var listener: Vector2 = game.listener_pos() if game else global_position
		var att := clampf(1.0 - global_position.distance_to(listener) / 1400.0, 0.0, 1.0)
		var v := att * Profile.sfx_volume * 0.6
		if v < 0.02:
			want = false
		else:
			_jet_player.volume_db = linear_to_db(v)
	if want and not _jet_player.playing:
		_jet_player.play()
	elif not want and _jet_player.playing:
		_jet_player.stop()


# ================================================================ bot AI (runs on host only)
func _bot_think(delta: float) -> void:
	in_fire = false
	if not alive or game == null:
		in_move = 0.0
		in_jet = false
		return
	_ai_think -= delta
	if _ai_think <= 0.0:
		_ai_think = randf_range(0.3, 0.6)
		_ai_target = _find_target()
		_ai_strafe = randf_range(-1.0, 1.0)
		_ai_aim_err = randf_range(-0.12, 0.12)
		if _ai_target == null and (_ai_wander == Vector2.ZERO or global_position.distance_to(_ai_wander) < 80.0):
			var size: Vector2 = game.map_size()
			_ai_wander = Vector2(randf_range(200, size.x - 200), randf_range(200, size.y - 300))
	var goal := _ai_wander
	var los := false
	var dist := 99999.0
	if _ai_target and is_instance_valid(_ai_target) and _ai_target.alive:
		goal = _ai_target.global_position
		dist = global_position.distance_to(goal)
		los = _has_los(_ai_target.global_position + Vector2(0, -6))
	var to_goal := goal - global_position
	# stuck detection: barely moved for a while -> take a sideways detour
	_ai_stuck_t += delta
	if _ai_stuck_t > 1.2:
		if global_position.distance_to(_ai_last_pos) < 40.0 and not los:
			_ai_detour = randf_range(0.8, 1.6)
			_ai_detour_dir = -_ai_detour_dir if randf() < 0.5 else _ai_detour_dir
		_ai_last_pos = global_position
		_ai_stuck_t = 0.0
	if is_on_ceiling() and not los and _ai_detour <= 0.0:
		_ai_detour = randf_range(0.6, 1.2)
		_ai_detour_dir = 1.0 if randf() < 0.5 else -1.0
	_ai_detour = maxf(0.0, _ai_detour - delta)
	# movement: approach when far or blocked, strafe when fighting
	var ideal := 420.0 if current_weapon() != "shotgun" else 160.0
	if current_weapon() == "sniper":
		ideal = 800.0
	if _ai_detour > 0.0:
		in_move = _ai_detour_dir
	elif not los and absf(to_goal.x) < 220.0 and absf(to_goal.y) > 60.0:
		# goal is right above/below behind a platform: go around it
		_ai_detour = randf_range(0.7, 1.3)
		in_move = _ai_detour_dir
	elif not los or dist > ideal + 150.0:
		in_move = signf(to_goal.x) if absf(to_goal.x) > 30.0 else 0.0
	elif dist < ideal - 150.0:
		in_move = -signf(to_goal.x)
	else:
		in_move = _ai_strafe
	# jetpack: climb toward goal, over walls, or out of pits (not while pinned under a ceiling)
	var need_up := (to_goal.y < -60.0 and not (is_on_ceiling() and _ai_detour > 0.0)) or is_on_wall() or (not los and randf() < 0.02)
	if global_position.y > game.map_size().y - 150.0:
		need_up = true
	if in_jet:
		in_jet = need_up and fuel > 0.05
	else:
		in_jet = need_up and fuel > 0.35
	# aim + shoot
	if los and _ai_target:
		var aim_pt := _ai_target.global_position + Vector2(0, -10) + _ai_target.velocity * 0.08
		in_aim = Vector2.from_angle((aim_pt - muzzle_global()).angle() + _ai_aim_err)
		var w := weapon_data()
		var rng := float(w["speed"]) * float(w["life"]) * 0.9
		in_fire = dist < rng
		# switch to pistol if primary is reloading and target is close
		if reloading > 0.6 and slot == 0 and dist < 500.0 and randf() < 0.02:
			switch_weapon()
		elif slot == 1 and reloading <= 0.0 and ammo[0] > 0 and randf() < 0.01:
			switch_weapon()
	else:
		in_aim = Vector2(signf(in_move) if in_move != 0.0 else 1.0, 0.0)
		if ammo[slot] < int(weapon_data()["mag"]) and reloading <= 0.0:
			start_reload()


func _find_target() -> Player:
	var best: Player = null
	var best_d := INF
	for p in game.get_players():
		if p == self or not p.alive or not is_enemy_of(p):
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if _has_los(p.global_position):
			d *= 0.25  # prefer visible enemies
		if d < best_d:
			best_d = d
			best = p
	return best


func _has_los(target: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position + SHOULDER, target, 1)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# ================================================================ drawing
func _draw() -> void:
	if not alive:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var a := 0.45 if protect > 0.0 and fmod(t * 8.0, 1.0) < 0.5 else 1.0
	var col := body_color
	if flash > 0.0:
		col = Color.WHITE
	col.a = a
	var facing := 1.0 if cos(aim_angle) >= 0.0 else -1.0
	var half_h := BODY_HEIGHT * 0.5
	# team ring in TDM
	if int(Network.settings.get("mode", 0)) == Catalog.MODE_TDM:
		var tc: Color = Catalog.TEAM_COLORS[team]
		tc.a = 0.55 * a
		draw_arc(Vector2(0, half_h - 2), 18.0, PI * 0.1, PI * 0.9, 12, tc, 3.0)
	# jetpack
	var pack := Rect2(-facing * 14.0 - 6.0, -14.0, 12.0, 24.0)
	draw_rect(pack, Color(0.25, 0.27, 0.32, a))
	if jet_on:
		var fl := 14.0 + randf() * 12.0
		var base_x := pack.get_center().x
		draw_colored_polygon(PackedVector2Array([Vector2(base_x - 5, 10), Vector2(base_x + 5, 10), Vector2(base_x, 10 + fl)]), Color(1.0, 0.6, 0.1, 0.9 * a))
		draw_colored_polygon(PackedVector2Array([Vector2(base_x - 2.5, 10), Vector2(base_x + 2.5, 10), Vector2(base_x, 10 + fl * 0.6)]), Color(1.0, 0.95, 0.5, a))
	# legs
	var stride := sin(t * 14.0) * 5.0 if absf(velocity.x) > 40.0 and is_on_floor() else 0.0
	draw_line(Vector2(-4, 10), Vector2(-5 + stride, half_h), col.darkened(0.35), 6.0)
	draw_line(Vector2(4, 10), Vector2(5 - stride, half_h), col.darkened(0.35), 6.0)
	# torso
	draw_rect(Rect2(-10, -14, 20, 26), col)
	draw_rect(Rect2(-10, -14, 20, 26), Color(0, 0, 0, 0.35 * a), false, 1.5)
	# head + visor
	draw_circle(Vector2(0, -24), 10.0, col.lightened(0.15))
	draw_rect(Rect2(facing * 2.0 - (0.0 if facing > 0 else 9.0), -28, 9, 5), Color(0.1, 0.12, 0.18, a))
	# gun
	draw_set_transform(SHOULDER, aim_angle, Vector2(1, facing))
	GunArt.draw_gun(self, current_weapon(), skin_of(current_weapon()), 1.0, t)
	if muzzle_flash > 0.0:
		var m := GunArt.muzzle_offset(current_weapon())
		draw_circle(m, 7.0, Color(1, 0.85, 0.3, 0.9))
		draw_circle(m + Vector2(6, 0), 4.0, Color(1, 1, 0.8, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# name + health bar (not for yourself; your HUD shows it)
	var font := ThemeDB.fallback_font
	var nm := str(info.get("name", "?"))
	var name_col := Color(1, 1, 1, 0.9)
	if int(Network.settings.get("mode", 0)) == Catalog.MODE_TDM:
		name_col = Catalog.TEAM_COLORS[team].lightened(0.3)
	draw_string(font, Vector2(-60, -50), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, name_col)
	if not is_local_human():
		var frac := clampf(float(hp) / Catalog.MAX_HEALTH, 0.0, 1.0)
		draw_rect(Rect2(-18, -44, 36, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-18, -44, 36 * frac, 4), Color(0.3, 1.0, 0.4).lerp(Color(1, 0.25, 0.2), 1.0 - frac))
