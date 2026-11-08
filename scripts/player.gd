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
const FUEL_DRAIN := 0.2		# ~5 s of full thrust
const FUEL_REGEN_GROUND := 0.5
const FUEL_REGEN_AIR := 0.08
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
var max_hp: int = Catalog.MAX_HEALTH
var burn_t := 0.0   # seconds of burning left (visual only; damage is host-side)
var fuel_mult := 1.0
var alive := true
var fuel := 1.0
var jet_on := false
var aim_angle := 0.0
var slot := 0  # 0 primary, 1 secondary
var weapons: Array = []
var dual: Array = [false, false]  # dual wield per slot (Uzi / Desert Eagle)
var ammo: Array = [0, 0]
var _dual_side := 0
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
var _ai_trigger := true
var _ai_loot_t := 0.0
var _ai_loot: Vector2 = Vector2.ZERO
var _lvl: Dictionary = {}


func setup(id: int, p_info: Dictionary, p_game: Node) -> void:
	peer_id = id
	info = p_info
	game = p_game
	is_bot = bool(info.get("bot", false))
	team = int(info.get("team", 0))
	body_color = Catalog.color_by_index(int(info.get("color", 0)))
	weapons = Catalog.START_WEAPONS.duplicate()
	dual = [false, false]
	max_hp = Catalog.max_health_for(info)
	hp = max_hp
	fuel_mult = Catalog.fuel_factor_for(info)
	ammo = [mag_slot(0), mag_slot(1)]
	_lvl = Catalog.bot_level(int(Network.settings.get("bots", 1)))
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
	_build_visuals()


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


func mag_of(weapon_id: String) -> int:
	return Catalog.mag_for(info, weapon_id)


## Magazine size of a slot (doubled when dual wielding).
func mag_slot(i: int) -> int:
	return mag_of(weapons[i]) * (2 if dual[i] else 1)


func is_dual() -> bool:
	return bool(dual[slot])


## Host -> everyone: new guns after a pickup. refill = slot whose magazine is refilled (-1 none).
func set_loadout(w: Array, d: Array, refill: int, new_slot: int) -> void:
	var before := current_weapon()
	weapons = w.duplicate()
	dual = d.duplicate()
	if new_slot == 0 or new_slot == 1:
		slot = new_slot
	if refill == 0 or refill == 1:
		ammo[refill] = mag_slot(refill)
		if refill == slot:
			reloading = 0.0
	for i in 2:
		ammo[i] = mini(int(ammo[i]), mag_slot(i))
	if current_weapon() != before:
		cooldown = maxf(cooldown, 0.2)
		reloading = 0.0
	if is_local_human():
		Sfx.play("reload", 0.6)


func reload_of(weapon_id: String) -> float:
	return Catalog.reload_for(info, weapon_id)


func muzzle_global() -> Vector2:
	var m := GunArt.muzzle_offset(current_weapon())
	if is_dual() and _dual_side == 1:
		m += DUAL_OFFSET
	var from := global_position + SHOULDER
	var to := from + m.rotated(aim_angle)
	if not is_inside_tree():
		return to
	# never spawn bullets inside a wall when the barrel pokes through it
	var q := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return from + (hit["position"] - from) * 0.85
	return to


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
			ammo[slot] = mag_slot(slot)
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
		fuel = maxf(0.0, fuel - FUEL_DRAIN / fuel_mult * delta)
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
	cooldown = float(w["fire_delay"]) * (Catalog.DUAL_FIRE_FACTOR if is_dual() else 1.0)
	_dual_side = (1 - _dual_side) if is_dual() else 0
	# small recoil push
	velocity -= Vector2.from_angle(aim_angle) * float(w["recoil"])
	if game:
		game.request_fire(self, current_weapon(), muzzle_global(), aim_angle)
	if ammo[slot] <= 0:
		start_reload()


func start_reload() -> void:
	if reloading > 0.0 or not alive:
		return
	if ammo[slot] >= mag_slot(slot):
		return
	reloading = reload_of(current_weapon())
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
	hp = max_hp
	alive = true
	fuel = 1.0
	slot = 0
	reloading = 0.0
	cooldown = 0.3
	protect = 1.5
	weapons = Catalog.START_WEAPONS.duplicate()
	dual = [false, false]
	ammo = [mag_slot(0), mag_slot(1)]
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
		var react: Array = _lvl.get("react", [0.3, 0.6])
		_ai_think = randf_range(float(react[0]), float(react[1]))
		_ai_target = _find_target()
		_ai_strafe = randf_range(-1.0, 1.0)
		var ae := float(_lvl.get("aim", 0.12))
		_ai_aim_err = randf_range(-ae, ae)
		_ai_trigger = randf() < float(_lvl.get("burst", 0.8))
		# loot: walk to a better gun lying around
		_ai_loot = Vector2.ZERO
		if randf() < float(_lvl.get("loot", 0.5)):
			var near_d := 900.0 if _ai_target == null else 380.0
			_ai_loot = game.bot_loot_target(self, near_d)
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
	if _ai_loot != Vector2.ZERO:
		goal = _ai_loot
		if global_position.distance_to(_ai_loot) < Catalog.PICK_RADIUS * 0.8:
			game.bot_try_pick(self)
			_ai_loot = Vector2.ZERO
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
	if current_weapon() in ["sniper", "svd", "woodpecker"]:
		ideal = 800.0
	elif current_weapon() in ["smg", "mp5", "mp40", "pistol"]:
		ideal = 300.0
	var dodge := float(_lvl.get("dodge", 0.3))
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
		if los and randf() < dodge * 0.08:
			_ai_strafe = -_ai_strafe  # juke
	# jetpack: climb toward goal, over walls, or out of pits (not while pinned under a ceiling)
	var need_up := (to_goal.y < -60.0 and not (is_on_ceiling() and _ai_detour > 0.0)) or is_on_wall() or (not los and randf() < 0.02)
	if global_position.y > game.map_size().y - 150.0:
		need_up = true
	if los and dist < ideal + 200.0 and fuel > 0.5 and randf() < dodge * 0.04:
		need_up = true  # hop to dodge bullets
	if in_jet:
		in_jet = need_up and fuel > 0.05
	else:
		in_jet = need_up and fuel > 0.35
	# aim + shoot
	if los and _ai_target:
		var w := weapon_data()
		var lead := float(_lvl.get("lead", 0.5)) * dist / maxf(200.0, float(w["speed"]))
		var aim_pt := _ai_target.global_position + Vector2(0, -10) + _ai_target.velocity * lead
		in_aim = Vector2.from_angle((aim_pt - muzzle_global()).angle() + _ai_aim_err)
		var rng := float(w["speed"]) * float(w["life"]) * 0.9
		in_fire = dist < rng and _ai_trigger
		# switch to pistol if primary is reloading and target is close
		if reloading > 0.6 and slot == 0 and dist < 500.0 and randf() < 0.02:
			switch_weapon()
		elif slot == 1 and reloading <= 0.0 and ammo[0] > 0 and randf() < 0.01:
			switch_weapon()
	else:
		in_aim = Vector2(signf(in_move) if in_move != 0.0 else 1.0, 0.0)
		if ammo[slot] < mag_slot(slot) and reloading <= 0.0:
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


# ================================================================ visuals
const LEG_TEX := preload("res://assets/char/leg.png")
const NOZZLE := Vector2(-9, 11)
const DUAL_OFFSET := Vector2(-6, 6)  # second gun sits a little behind/below

var _vis: Node2D            # flips with facing
var _torso: Node2D          # bobs while walking
var _head: Sprite2D
var _body: Sprite2D
var _legs: Array = []
var _pivot: Node2D          # shoulder, rotated to aim
var _gun: Sprite2D
var _gun2: Sprite2D
var _shown_dual := false
var _arms: _Arms
var _flash_node: _MuzzleFlash
var _jet_fx: CPUParticles2D
var _overlay: _Overlay
var _tint_mat: ShaderMaterial
var _shown_weapon := ""
var _shown_skin := ""
var _walk_t := 0.0


func _build_visuals() -> void:
	_tint_mat = FXKit.tint_material(body_color)
	_vis = Node2D.new()
	add_child(_vis)
	_jet_fx = FXKit.jet_particles()
	_jet_fx.position = NOZZLE
	_vis.add_child(_jet_fx)
	for lx in [-4.0, 4.0]:
		var leg := Sprite2D.new()
		leg.texture = LEG_TEX
		leg.centered = false
		leg.offset = Vector2(-32, 0)
		leg.scale = Vector2(0.13, 0.095)
		leg.position = Vector2(lx, 6)
		leg.material = _tint_mat
		_vis.add_child(leg)
		_legs.append(leg)
	_torso = Node2D.new()
	_vis.add_child(_torso)
	var cs: Dictionary = Catalog.char_skin(str(info.get("char", "trooper")))
	_body = Sprite2D.new()
	_body.texture = load("res://assets/char/%s.png" % cs["body"])
	_body.scale = Vector2(0.109, 0.109)
	_body.material = _tint_mat
	_torso.add_child(_body)
	_head = Sprite2D.new()
	_head.texture = load("res://assets/char/%s.png" % cs["head"])
	_head.scale = Vector2(0.135, 0.135)
	_head.position = Vector2(2, -20)
	_head.material = _tint_mat
	_torso.add_child(_head)
	# gun pivot lives outside the flipped node so aim rotation stays simple
	_pivot = Node2D.new()
	_pivot.position = SHOULDER
	add_child(_pivot)
	_arms = _Arms.new()
	_arms.color = body_color
	_arms.back = true
	_pivot.add_child(_arms)
	_gun2 = Sprite2D.new()
	_gun2.modulate = Color(0.78, 0.78, 0.82)
	_gun2.visible = false
	_pivot.add_child(_gun2)
	_gun = Sprite2D.new()
	_pivot.add_child(_gun)
	var front := _Arms.new()
	front.color = body_color
	front.back = false
	_pivot.add_child(front)
	_arms.set_meta("front", front)
	_flash_node = _MuzzleFlash.new()
	_flash_node.material = FXKit.additive()
	_pivot.add_child(_flash_node)
	_overlay = _Overlay.new()
	_overlay.player = self
	_overlay.z_index = 5
	add_child(_overlay)
	_refresh_gun()


func _refresh_gun() -> void:
	var w := current_weapon()
	var sk := skin_of(w)
	var dd := is_dual()
	if w == _shown_weapon and sk == _shown_skin and dd == _shown_dual:
		return
	_shown_weapon = w
	_shown_skin = sk
	_shown_dual = dd
	GunArt.setup_sprite(_gun, w, sk)
	_gun2.visible = dd
	if dd:
		GunArt.setup_sprite(_gun2, w, sk)
		_gun2.position += DUAL_OFFSET
	var h := GunArt.hands(w)
	var front: _Arms = _arms.get_meta("front")
	front.target = h[0]
	_arms.target = h[1] if h[1] != null else h[0] + Vector2(-3, 3)
	_flash_node.position = GunArt.muzzle_offset(w)
	if dd:
		_arms.target = h[0] + DUAL_OFFSET
	_arms.queue_redraw()
	front.queue_redraw()


## Level-6 fire bullets: show flames on this player for `dur` seconds.
func apply_burn_fx(dur: float) -> void:
	burn_t = maxf(burn_t, dur)


func _process(delta: float) -> void:
	if _vis == null:
		return
	_refresh_gun()
	var facing := 1.0 if cos(aim_angle) >= 0.0 else -1.0
	_vis.scale.x = facing
	_pivot.rotation = aim_angle
	_pivot.scale = Vector2(1, facing)
	var on_floor := is_on_floor() if is_controlled_here() else absf(velocity.y) < 30.0
	var walking := absf(velocity.x) > 40.0 and on_floor
	if walking:
		_walk_t += delta * 13.0 * signf(velocity.x) * facing
	else:
		_walk_t = lerpf(_walk_t, roundf(_walk_t / PI) * PI, clampf(delta * 10.0, 0.0, 1.0))
	var swing := sin(_walk_t) * 0.55 if walking else 0.0
	if not on_floor:
		swing = 0.35 if jet_on else 0.18
		_legs[0].rotation = lerpf(_legs[0].rotation, swing, delta * 8.0)
		_legs[1].rotation = lerpf(_legs[1].rotation, -swing * 0.4, delta * 8.0)
	else:
		_legs[0].rotation = swing
		_legs[1].rotation = -swing
	_torso.position.y = -absf(sin(_walk_t)) * 1.6 if walking else 0.0
	# head looks a little toward the aim
	var look := clampf(sin(aim_angle) * facing, -1.0, 1.0)
	_head.rotation = look * 0.25
	_jet_fx.emitting = jet_on and alive
	var t := Time.get_ticks_msec() / 1000.0
	var a := 0.4 if protect > 0.0 and fmod(t * 8.0, 1.0) < 0.5 else 1.0
	modulate.a = a
	var f := clampf(flash / 0.12, 0.0, 1.0)
	_tint_mat.set_shader_parameter("flash", f * 0.85)
	if _gun.material is ShaderMaterial:
		_gun.material.set_shader_parameter("flash", f * 0.6)
	if is_dual():
		_flash_node.position = GunArt.muzzle_offset(current_weapon()) + (DUAL_OFFSET if _dual_side == 0 else Vector2.ZERO)
		_flash_node.amount = clampf(muzzle_flash / 0.06, 0.0, 1.0)
		_flash_node.visible = muzzle_flash > 0.0
		_flash_node.queue_redraw()
	_overlay.queue_redraw()
	# burning: flame sparks + warm tint (damage is applied host-side)
	if burn_t > 0.0:
		burn_t = maxf(0.0, burn_t - delta)
		if game and randf() < delta * 22.0:
			game.fx.spark(global_position + Vector2(randf_range(-8, 8), randf_range(-22, 8)),
				Color(randf_range(0.9, 1.0), randf_range(0.35, 0.6), 0.1), 2, 150.0)
		modulate = Color(1.0, 0.72, 0.55)
	else:
		modulate = Color.WHITE


func _draw() -> void:
	if not alive:
		return
	# soft contact shadow
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, 220), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(q) if is_inside_tree() else {}
	if not hit.is_empty():
		var d: float = hit["position"].y - global_position.y
		var k := clampf(1.0 - (d - 26.0) / 190.0, 0.0, 1.0)
		if k > 0.0:
			draw_set_transform(Vector2(0, d), 0.0, Vector2(1.0, 0.28))
			draw_circle(Vector2.ZERO, 20.0 * (0.6 + 0.4 * k), Color(0, 0, 0, 0.35 * k))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if int(Network.settings.get("mode", 0)) == Catalog.MODE_TDM:
		var tc: Color = Catalog.color_by_index(team)
		tc.a = 0.7
		draw_set_transform(Vector2(0, 27), 0.0, Vector2(1.0, 0.32))
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 28, tc, 5.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _Arms extends Node2D:
	var color := Color.WHITE
	var target := Vector2(10, 0)
	var back := false

	func _draw() -> void:
		var sleeve := color.darkened(0.25 if not back else 0.45)
		var start := Vector2(-3, 4) if not back else Vector2(1, 2)
		draw_line(start, target, Color(0.08, 0.08, 0.1), 7.5, true)
		draw_line(start, target, sleeve, 5.0, true)
		draw_circle(target, 4.2, Color(0.08, 0.08, 0.1))
		draw_circle(target, 3.2, Color(0.22, 0.2, 0.2) if back else Color(0.3, 0.27, 0.26))


class _MuzzleFlash extends Node2D:
	var amount := 1.0

	func _draw() -> void:
		var tex := FXKit.soft_circle()
		var s := 0.6 + amount * 0.6
		draw_texture_rect(tex, Rect2(Vector2(-14, -14) * s + Vector2(6, 0), Vector2(28, 28) * s), false, Color(1.0, 0.6, 0.15, 0.9))
		draw_texture_rect(tex, Rect2(Vector2(-6, -6) * s + Vector2(3, 0), Vector2(12, 12) * s), false, Color(1, 1, 0.85, 1))
		var pts := PackedVector2Array([Vector2(0, -5 * s), Vector2(26 * s, 0), Vector2(0, 5 * s)])
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.4, 0.85))


class _Overlay extends Node2D:
	var player: Player

	func _draw() -> void:
		if player == null or not player.alive:
			return
		var font := FXKit.game_font()
		var nm := str(player.info.get("name", "?"))
		var name_col := Color(1, 1, 1, 0.95)
		if int(Network.settings.get("mode", 0)) == Catalog.MODE_TDM:
			name_col = Catalog.color_by_index(player.team).lightened(0.35)
		var y := -52.0
		draw_string_outline(font, Vector2(-70, y), nm, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, 4, Color(0, 0, 0, 0.75))
		draw_string(font, Vector2(-70, y), nm, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, name_col)
		if not player.is_local_human():
			var frac := clampf(float(player.hp) / float(maxi(1, player.max_hp)), 0.0, 1.0)
			var r := Rect2(-20, -47, 40, 6)
			draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), Color(0.35, 1.0, 0.45).lerp(Color(1, 0.25, 0.2), 1.0 - frac))
			draw_rect(Rect2(r.position, Vector2(r.size.x * frac, 2)), Color(1, 1, 1, 0.35))
