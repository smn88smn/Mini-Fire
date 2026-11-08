extends Node
## LAN networking: hosting, joining, Wi-Fi host discovery, lobby state and match flow.
## Topology: one device hosts (authoritative server + player), others join over Wi-Fi.
## Practice mode uses OfflineMultiplayerPeer, so the same game code runs with bots only.

signal lobby_updated
signal hosts_updated(hosts: Array)
signal connection_failed(reason: String)
signal joined_lobby
signal player_left(id: int)
signal online_room_ready(code: String)
signal online_room_failed(reason: String)

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAGIC := "MINIFIRE"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var players: Dictionary = {}  # id(int) -> info Dictionary
var settings: Dictionary = {"mode": Catalog.MODE_FFA, "map": 0, "time": 1, "bots": 1}
var in_match := false
var offline := false
var online := false          # true while hosting/joining an internet room by code
var room_code := ""          # host: the share code of the online room
var last_message := ""  # shown by the main menu after a disconnect

var _peer: MultiplayerPeer = null
var _ip_req: HTTPRequest = null
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

# ================================================================ online rooms (by code)
## Host a room that friends anywhere on the internet can join with a short code.
## Opens the UDP port via UPnP and encodes the public IP + port into the code.
func host_online() -> void:
	var err := host_lan()
	if err != OK:
		online_room_failed.emit("Could not host (port %d busy?)" % PORT)
		return
	online = true
	_setup_online_room()

func _setup_online_room() -> void:
	# 1) try UPnP: open the port and read the external IP
	var ext := ""
	var upnp := UPNP.new()
	if upnp.discover() == OK:
		upnp.add_port_mapping(PORT, PORT, "MiniFire", "UDP")
		ext = str(upnp.query_external_address())
	if ext.is_valid_ip_address() and not ext.begins_with("0."):
		_finish_online_room(ext)
		return
	# 2) fallback: ask an external service for the public IP
	_ip_req = HTTPRequest.new()
	_ip_req.timeout = 8.0
	_ip_req.request_completed.connect(_on_ip_fetched)
	add_child(_ip_req)
	var err := _ip_req.request("https://api.ipify.org")
	if err != OK:
		online_room_failed.emit("Could not detect your public IP (no internet?)")

func _on_ip_fetched(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var ip := body.get_string_from_utf8().strip_edges()
		if ip.is_valid_ip_address():
			_finish_online_room(ip)
			return
	online_room_failed.emit("Could not detect your public IP (no internet?)")

func _finish_online_room(ip: String) -> void:
	room_code = encode_room_code(ip, PORT)
	online_room_ready.emit(room_code)

## Join an online room from its share code (XXXXX-XXXXX).
func join_by_code(code: String) -> Error:
	var decoded := decode_room_code(code)
	if decoded.is_empty():
		return ERR_INVALID_PARAMETER
	var err := join(decoded)
	if err == OK:
		online = true
	return err

const ROOM_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

## Public IP (4 bytes) + port (2 bytes) -> 10 Crockford-base32 chars.
func encode_room_code(ip: String, port: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var n := 0
	for i in 4:
		var b := int(parts[i])
		if b < 0 or b > 255:
			return ""
		n = (n << 8) | b
	n = (n << 16) | (port & 0xFFFF)
	var out := ""
	for i in 10:
		out = ROOM_ALPHABET[n % 32] + out
		n >>= 5
	return out.substr(0, 5) + "-" + out.substr(5)

## Inverse of encode_room_code. Returns the IP, or "" when the code is invalid.
func decode_room_code(code: String) -> String:
	var clean := code.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if clean.length() != 10:
		return ""
	var n := 0
	for c in clean:
		# Crockford-style confusion fixes
		var ch := c
		if c == "I" or c == "L":
			ch = "1"
		elif c == "O":
			ch = "0"
		elif c == "U":
			ch = "V"
		var idx := ROOM_ALPHABET.find(ch)
		if idx < 0:
			return ""
		n = (n << 5) | idx
	var port := n & 0xFFFF
	n >>= 16
	var ip := "%d.%d.%d.%d" % [n >> 24 & 255, n >> 16 & 255, n >> 8 & 255, n & 255]
	if port != PORT:
		return ""
	return ip


## Leaves the current session. go_menu=true returns to the main menu.
func leave(go_menu: bool = true) -> void:
	_stop_broadcast()
	if _ip_req:
		_ip_req.queue_free()
		_ip_req = null
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	_loaded.clear()
	in_match = false
	offline = false
	online = false
	room_code = ""
	if go_menu:
		get_tree().change_scene_to_file(MENU_SCENE)


func _reset_lobby() -> void:
	players.clear()
	_loaded.clear()
	in_match = false
	_next_bot_id = -1
	settings = {"mode": Catalog.MODE_FFA, "map": 0, "time": 1, "bots": Profile.bot_level}
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
	players[id] = _sanitize(info)
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
	var ch := str(info.get("char", "trooper"))
	if not Catalog.CHAR_SKINS.has(ch):
		ch = "trooper"
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
	var glvls := {}
	var g_in = info.get("gun_levels", {})
	if g_in is Dictionary:
		for k in Catalog.WEAPON_ORDER:
			glvls[k] = clampi(int(g_in.get(k, 1)), 1, Catalog.GUN_LEVEL_MAX)
	else:
		for k in Catalog.WEAPON_ORDER:
			glvls[k] = 1
	var color := clampi(int(info.get("color", 0)), 0, Catalog.PLAYER_COLORS.size() - 1)
	return {
		"powers": powers,
		"name": name_str,
		"color": color,
		"char": ch,
		"skins": skins,
		"gun_levels": glvls,
		# In Team Deathmatch the color IS the team (see Catalog.PLAYER_COLORS).
		"team": clampi(int(info.get("team", color)), 0, Catalog.PLAYER_COLORS.size() - 1),
		"bot": false,
	}


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
	for k in ["name", "color", "char", "skins", "powers", "gun_levels", "team"]:
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
	settings["bots"] = clampi(int(settings.get("bots", 1)), 0, Catalog.BOT_LEVELS.size() - 1)
	if key == "bots":
		Profile.bot_level = int(settings["bots"])
		Profile.save_profile()
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
	var glvls := {}
	for k in Catalog.WEAPON_ORDER:
		glvls[k] = 1
	var col := randi() % Catalog.PLAYER_COLORS.size()
	players[id] = {
		"name": "BOT " + names[absi(id) % names.size()],
		"color": col,
		"char": Catalog.CHAR_ORDER[randi() % Catalog.CHAR_ORDER.size()],
		"skins": skins,
		"gun_levels": glvls,
		"team": col,
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
		players[id]["team"] = clampi(team, 0, Catalog.PLAYER_COLORS.size() - 1)
		players[id]["color"] = players[id]["team"]
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
