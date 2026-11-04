extends Node
## LAN networking: hosting, joining, Wi-Fi host discovery, lobby state and match flow.
## Topology: one device hosts (authoritative server + player), others join over Wi-Fi.
## Practice mode uses OfflineMultiplayerPeer, so the same game code runs with bots only.

signal lobby_updated
signal hosts_updated(hosts: Array)
signal connection_failed(reason: String)
signal joined_lobby
signal player_left(id: int)

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAGIC := "MINIFIRE"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var players: Dictionary = {}  # id(int) -> info Dictionary
var settings: Dictionary = {"mode": Catalog.MODE_FFA, "map": 0, "time": 1}
var in_match := false
var offline := false
var last_message := ""  # shown by the main menu after a disconnect

var _peer: MultiplayerPeer = null
var _loaded: Dictionary = {}
var _next_bot_id := -1

# discovery
var _bcast: PacketPeerUDP = null
var _bcast_targets: Array = []
var _bcast_timer := 0.0
var _listen: PacketPeerUDP = null
var _hosts: Dictionary = {}  # ip -> {name, players, mode, t}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_active() -> bool:
	return _peer != null


func is_host() -> bool:
	return _peer != null and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func human_ids() -> Array:
	var out: Array = []
	for id in players.keys():
		if not players[id].get("bot", false):
			out.append(id)
	return out


func has_humans_besides_me() -> bool:
	return human_ids().size() > 1


# ================================================================ host / join / leave
func host_lan() -> Error:
	leave(false)
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, Catalog.MAX_PLAYERS)
	if err != OK:
		return err
	_peer = p
	offline = false
	multiplayer.multiplayer_peer = p
	_reset_lobby()
	_start_broadcast()
	get_tree().change_scene_to_file(LOBBY_SCENE)
	return OK


func host_practice() -> void:
	leave(false)
	_peer = OfflineMultiplayerPeer.new()
	offline = true
	multiplayer.multiplayer_peer = _peer
	_reset_lobby()
	for i in 3:
		add_bot()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func join(ip: String) -> Error:
	leave(false)
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		return ERR_INVALID_PARAMETER
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, PORT)
	if err != OK:
		return err
	_peer = p
	offline = false
	multiplayer.multiplayer_peer = p
	Profile.last_join_ip = ip
	Profile.save_profile()
	return OK


## Leaves the current session. go_menu=true returns to the main menu.
func leave(go_menu: bool = true) -> void:
	_stop_broadcast()
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	_loaded.clear()
	in_match = false
	offline = false
	if go_menu:
		get_tree().change_scene_to_file(MENU_SCENE)


func _reset_lobby() -> void:
	players.clear()
	_loaded.clear()
	in_match = false
	_next_bot_id = -1
	settings = {"mode": Catalog.MODE_FFA, "map": 0, "time": 1}
	var info := Profile.lobby_info()
	players[1] = info


# ================================================================ lobby
func _on_connected_to_server() -> void:
	_register.rpc_id(1, Profile.lobby_info(), Catalog.GAME_VERSION)


func _on_connection_failed() -> void:
	leave(false)
	connection_failed.emit("Could not connect to host")


func _on_server_disconnected() -> void:
	last_message = "Host closed the game"
	leave(true)


func _on_peer_connected(_id: int) -> void:
	pass  # player is added when it sends _register


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(id):
		players.erase(id)
		_loaded.erase(id)
		player_left.emit(id)
		_remove_player_everywhere.rpc(id)
		_broadcast_lobby()
		_check_all_loaded()


@rpc("authority", "call_remote", "reliable")
func _remove_player_everywhere(id: int) -> void:
	players.erase(id)
	player_left.emit(id)
	lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary, version: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != Catalog.GAME_VERSION:
		reason = "Game version mismatch. Update the app."
	elif in_match:
		reason = "Match already in progress"
	elif players.size() >= Catalog.MAX_PLAYERS:
		reason = "Lobby is full"
	if reason != "":
		_kicked.rpc_id(id, reason)
		get_tree().create_timer(0.4).timeout.connect(func():
			if _peer is ENetMultiplayerPeer:
				(_peer as ENetMultiplayerPeer).disconnect_peer(id))
		return
	var clean := _sanitize(info)
	clean["team"] = _smallest_team()
	players[id] = clean
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _kicked(reason: String) -> void:
	last_message = reason
	leave(true)


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(p: Dictionary, s: Dictionary) -> void:
	var first := players.is_empty()
	players = p
	settings = s
	lobby_updated.emit()
	if first and not in_match:
		get_tree().change_scene_to_file(LOBBY_SCENE)
		joined_lobby.emit()


func _broadcast_lobby() -> void:
	if not multiplayer.is_server():
		return
	if not offline:
		_sync_lobby.rpc(players, settings)
	lobby_updated.emit()


func _sanitize(info: Dictionary) -> Dictionary:
	var name_str := str(info.get("name", "Player")).strip_edges().substr(0, 16)
	if name_str.is_empty():
		name_str = "Player"
	var w := str(info.get("weapon", "rifle"))
	if not w in Catalog.PRIMARY_WEAPONS:
		w = "rifle"
	var skins := {}
	var s_in = info.get("skins", {})
	if s_in is Dictionary:
		for k in Catalog.WEAPONS.keys():
			var sk := str(s_in.get(k, "default"))
			skins[k] = sk if Catalog.SKINS.has(sk) else "default"
	var powers := {}
	var p_in = info.get("powers", {})
	if p_in is Dictionary:
		for k in Catalog.POWERS.keys():
			powers[k] = clampi(int(p_in.get(k, 0)), 0, Catalog.POWER_MAX)
	return {
		"powers": powers,
		"name": name_str,
		"color": clampi(int(info.get("color", 0)), 0, Catalog.PLAYER_COLORS.size() - 1),
		"weapon": w,
		"skins": skins,
		"team": clampi(int(info.get("team", 0)), 0, 1),
		"bot": false,
	}


func _smallest_team() -> int:
	var c := [0, 0]
	for id in players:
		c[int(players[id].get("team", 0))] += 1
	return 0 if c[0] <= c[1] else 1


## Called by any peer to change its own lobby info (color, team, weapon, skins, name).
func update_my_info(changes: Dictionary) -> void:
	if not is_active():
		return
	if multiplayer.is_server():
		_apply_info(1, changes)
	else:
		_update_info.rpc_id(1, changes)


@rpc("any_peer", "call_remote", "reliable")
func _update_info(changes: Dictionary) -> void:
	if multiplayer.is_server() and not in_match:
		_apply_info(multiplayer.get_remote_sender_id(), changes)


func _apply_info(id: int, changes: Dictionary) -> void:
	if not players.has(id):
		return
	var merged: Dictionary = players[id].duplicate(true)
	for k in ["name", "color", "weapon", "skins", "powers", "team"]:
		if changes.has(k):
			merged[k] = changes[k]
	var clean := _sanitize(merged)
	clean["bot"] = players[id].get("bot", false)
	players[id] = clean
	_broadcast_lobby()


func set_setting(key: String, value) -> void:
	if not multiplayer.is_server() or in_match:
		return
	settings[key] = value
	settings["mode"] = clampi(int(settings["mode"]), 0, 1)
	settings["map"] = clampi(int(settings["map"]), 0, Catalog.MAPS.size() - 1)
	settings["time"] = clampi(int(settings["time"]), 0, Catalog.MATCH_TIMES.size() - 1)
	_broadcast_lobby()


func add_bot() -> void:
	if not multiplayer.is_server() or players.size() >= Catalog.MAX_PLAYERS:
		return
	var id := _next_bot_id
	_next_bot_id -= 1
	var names := ["Viper", "Ghost", "Rex", "Blaze", "Nova", "Tank", "Zed", "Hawk", "Spike", "Echo", "Rook"]
	var skins := {}
	for k in Catalog.WEAPONS.keys():
		skins[k] = "default"
	players[id] = {
		"name": "BOT " + names[absi(id) % names.size()],
		"color": randi() % Catalog.PLAYER_COLORS.size(),
		"weapon": Catalog.PRIMARY_WEAPONS[randi() % Catalog.PRIMARY_WEAPONS.size()],
		"skins": skins,
		"team": _smallest_team(),
		"bot": true,
	}
	_broadcast_lobby()


func remove_bot() -> void:
	if not multiplayer.is_server():
		return
	var ids := players.keys()
	ids.sort()
	for id in ids:
		if players[id].get("bot", false):
			players.erase(id)
			_broadcast_lobby()
			return


func set_bot_team(id: int, team: int) -> void:
	if multiplayer.is_server() and players.has(id) and players[id].get("bot", false):
		players[id]["team"] = clampi(team, 0, 1)
		_broadcast_lobby()


# ================================================================ match flow
func start_match() -> void:
	if not multiplayer.is_server() or in_match:
		return
	in_match = true
	_loaded.clear()
	if _peer is ENetMultiplayerPeer:
		_peer.refuse_new_connections = true
	_stop_broadcast()
	if offline:
		_load_match(players, settings)
	else:
		_load_match.rpc(players, settings)


@rpc("authority", "call_local", "reliable")
func _load_match(p: Dictionary, s: Dictionary) -> void:
	players = p
	settings = s
	in_match = true
	get_tree().change_scene_to_file(GAME_SCENE)


## Game scene calls this once it is ready.
func report_loaded() -> void:
	if multiplayer.is_server():
		_loaded[1] = true
		_check_all_loaded()
	else:
		_client_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _client_loaded() -> void:
	if multiplayer.is_server():
		_loaded[multiplayer.get_remote_sender_id()] = true
		_check_all_loaded()


func _check_all_loaded() -> void:
	if not multiplayer.is_server() or not in_match:
		return
	for id in human_ids():
		if not _loaded.has(id):
			return
	var game := get_tree().root.get_node_or_null("Game")
	if game and game.has_method("server_begin"):
		game.server_begin()


## Server: called by the game after the results screen.
func return_to_lobby() -> void:
	if not is_active() or not in_match or not multiplayer.is_server():
		return
	if offline:
		_back_to_lobby()
	else:
		_back_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _back_to_lobby() -> void:
	in_match = false
	_loaded.clear()
	if multiplayer.is_server():
		if _peer is ENetMultiplayerPeer:
			_peer.refuse_new_connections = false
			_start_broadcast()
		# refresh host info (skins may have been bought) and keep everyone
	get_tree().change_scene_to_file(LOBBY_SCENE)
	lobby_updated.emit()


# ================================================================ discovery
func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.contains(":"):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or _is_172_private(a):
			out.append(a)
	return out


func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var parts := a.split(".")
	if parts.size() < 2:
		return false
	var b := int(parts[1])
	return b >= 16 and b <= 31


func _start_broadcast() -> void:
	_stop_broadcast()
	_bcast = PacketPeerUDP.new()
	_bcast.set_broadcast_enabled(true)
	_bcast_targets = ["255.255.255.255"]
	for ip in local_ips():
		var parts: PackedStringArray = ip.split(".")
		if parts.size() == 4:
			# assumes /24 networks, which covers almost all home Wi-Fi / hotspots
			_bcast_targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	_bcast_timer = 0.0


func _stop_broadcast() -> void:
	if _bcast:
		_bcast.close()
	_bcast = null


func start_discovery() -> void:
	stop_discovery()
	_hosts.clear()
	_listen = PacketPeerUDP.new()
	var err := _listen.bind(DISCOVERY_PORT, "*")
	if err != OK:
		push_warning("Discovery bind failed: %s" % error_string(err))
		_listen = null


func stop_discovery() -> void:
	if _listen:
		_listen.close()
	_listen = null


func _process(delta: float) -> void:
	if _bcast and is_host() and not in_match:
		_bcast_timer -= delta
		if _bcast_timer <= 0.0:
			_bcast_timer = 1.0
			var msg := JSON.stringify({
				"m": MAGIC, "v": Catalog.GAME_VERSION,
				"name": str(players.get(1, {}).get("name", "Host")),
				"players": players.size(), "max": Catalog.MAX_PLAYERS,
				"mode": int(settings["mode"]),
			}).to_utf8_buffer()
			for t in _bcast_targets:
				_bcast.set_dest_address(t, DISCOVERY_PORT)
				_bcast.put_packet(msg)
	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet()
			var ip := _listen.get_packet_ip()
			var data = JSON.parse_string(pkt.get_string_from_utf8())
			if data is Dictionary and data.get("m", "") == MAGIC and ip != "":
				_hosts[ip] = {
					"ip": ip, "name": str(data.get("name", "Host")),
					"players": int(data.get("players", 1)), "max": int(data.get("max", 12)),
					"mode": int(data.get("mode", 0)), "v": int(data.get("v", 0)),
					"t": Time.get_ticks_msec(),
				}
				changed = true
		var now := Time.get_ticks_msec()
		for ip in _hosts.keys():
			if now - int(_hosts[ip]["t"]) > 3500:
				_hosts.erase(ip)
				changed = true
		if changed:
			hosts_updated.emit(_hosts.values())
