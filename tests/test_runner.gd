extends Node
## Automated smoke tests. Loaded as an extra autoload through a temporary override.cfg
## (see tests/run_tests.sh). Roles: practice, host, client, client_quit, host_quit.

var role := "practice"
var t := 0.0
var phase := 0
var log_kills := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	print("[TEST] role=", role)
	Engine.max_fps = 0
	get_tree().create_timer(1.0).timeout.connect(_start)


func _start() -> void:
	match role:
		"practice":
			Network.host_practice()
		"host", "host_quit":
			Network.host_lan()
			Network.add_bot.call_deferred()
		"client", "client_quit":
			Network.join("127.0.0.1")


func _process(delta: float) -> void:
	t += delta
	var game := get_tree().root.get_node_or_null("Game")
	if role == "host_quit" and phase == 2 and t > 6.0:
		print("[TEST] host quitting mid-match")
		Network.leave(false)
		get_tree().quit(0)
		return
	if role == "practice" or role.begins_with("host"):
		if phase == 0 and get_tree().current_scene and get_tree().current_scene.name == "Lobby":
			var need := 3 if role.begins_with("host") else 2
			if Network.players.size() >= need:
				print("[TEST] lobby players=", Network.players.size(), " starting match")
				Network.set_setting("mode", 1 if role == "host" else 0)
				Network.start_match()
				phase = 1
		elif phase == 1 and game and game.started:
			print("[TEST] match started at t=", snappedf(t, 0.1))
			phase = 2
			t = 0.0
		elif phase == 2:
			if int(t) % 5 == 0 and absf(t - round(t)) < delta:
				_report(game)
			if t > 45.0:
				print("[TEST] forcing match end")
				game.time_left = 0.0
				phase = 3
				t = 0.0
		elif phase == 3 and get_tree().current_scene and get_tree().current_scene.name == "Lobby" and t > 1.0:
			print("[TEST] back in lobby OK. MFC=", Profile.mfc, " gems=", Profile.gems)
			phase = 4
			t = 0.0
		elif phase == 4 and t > 1.0:
			print("[TEST] DONE ", role)
			get_tree().quit(0)
	else:
		# client: drive the local player with fake input
		if game and game.started and not game.ended:
			game.input_enabled = false
			var p: Player = game.local_player()
			if p and p.alive:
				# chase nearest enemy and shoot
				var tgt: Player = null
				for o in game.get_players():
					if o != p and o.alive and p.is_enemy_of(o):
						tgt = o
				if tgt:
					p.in_aim = (tgt.global_position - p.global_position)
					p.in_fire = true
					p.in_move = signf(tgt.global_position.x - p.global_position.x)
					p.in_jet = tgt.global_position.y < p.global_position.y - 50
			if phase == 0:
				print("[TEST] client sees match started; players=", game.get_players().size())
				phase = 1
				t = 0.0
			if role == "client_quit" and t > 8.0:
				print("[TEST] client quitting mid-match")
				Network.leave(false)
				get_tree().quit(0)
				return
			if int(t) % 5 == 0 and absf(t - round(t)) < delta:
				_report(game)
		if phase == 1 and get_tree().current_scene and get_tree().current_scene.name == "MainMenu":
			print("[TEST] client returned to menu after host left OK: ", Network.last_message)
			get_tree().quit(0)
			return
		if phase == 1 and get_tree().current_scene and get_tree().current_scene.name == "Lobby":
			print("[TEST] client back in lobby OK. MFC=", Profile.mfc)
			phase = 2
			t = 0.0
		if phase == 2 and t > 1.5:
			print("[TEST] DONE client")
			Network.leave(false)
			get_tree().quit(0)
		if t > 120:
			print("[TEST] client TIMEOUT")
			get_tree().quit(1)


func _report(game) -> void:
	if game == null:
		return
	var s := []
	for id in game.stats:
		s.append("%s:%d/%d" % [Network.players.get(id, {}).get("name", "?"), game.stats[id]["k"], game.stats[id]["d"]])
	var pos := []
	for p in game.get_players():
		pos.append("%s@(%d,%d)hp%d%s" % [p.name, p.global_position.x, p.global_position.y, p.hp, "" if p.alive else "X"])
	print("[TEST] t=%.0f time_left=%.0f bullets=%d stats=%s" % [t, game.time_left, game.bullets.size(), ", ".join(s)])
	print("       ", " ".join(pos))
