extends Control
## Lobby: player list, color/team/weapon choice, host match settings, bots, start.

var _content: VBoxContainer
var _list: VBoxContainer
var _side: VBoxContainer
var _actions: VBoxContainer


func _ready() -> void:
	var mp: Dictionary = Catalog.MAPS[clampi(int(Network.settings.get("map", 0)), 0, Catalog.MAPS.size() - 1)]
	var root := UIKit.screen_root(self, str(mp.get("bg_image", "menu")), 0.5)
	_content = VBoxContainer.new()
	root.add_child(_content)
	var head := HBoxContainer.new()
	var title := "PRACTICE LOBBY" if Network.offline else ("YOUR LOBBY" if Network.is_host() else "LOBBY")
	head.add_child(UIKit.glass_button("LEAVE", "red", func(): Network.leave(true), Vector2(140, 58)))
	head.add_child(UIKit.spacer(0, 6))
	var tl := UIKit.label(title, 40, UIKit.ACCENT2)
	tl.add_theme_constant_override("outline_size", 8)
	head.add_child(tl)
	head.add_child(UIKit.hfill())
	head.add_child(UIKit.wallet_chips())
	_content.add_child(head)
	if Network.is_host() and not Network.offline:
		var ips := Network.local_ips()
		var t := "Friends on the same Wi-Fi: open JOIN WI-FI GAME, or type IP  %s" % (" / ".join(ips) if ips.size() > 0 else "(no Wi-Fi detected - turn on Wi-Fi or hotspot)")
		_content.add_child(UIKit.label(t, 18, UIKit.ACCENT2))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)
	_content.add_child(row)
	var lp := UIKit.panel()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lp)
	var ls := UIKit.DragScroll.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(ls)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	ls.add_child(_list)
	var rp := UIKit.panel()
	rp.custom_minimum_size = Vector2(470, 0)
	row.add_child(rp)
	var rcol := VBoxContainer.new()
	rp.add_child(rcol)
	var rs := UIKit.DragScroll.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rcol.add_child(rs)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_side)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	rcol.add_child(_actions)
	Network.lobby_updated.connect(_refresh)
	# make sure the host's latest profile (skins bought, name) is in the lobby
	Network.update_my_info(Profile.lobby_info().merged({"team": _my_team()}, true))
	_refresh()


func _exit_tree() -> void:
	if Network.lobby_updated.is_connected(_refresh):
		Network.lobby_updated.disconnect(_refresh)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Network.leave(true)


func _my_team() -> int:
	return int(Network.players.get(Network.my_id(), {}).get("team", 0))


func _refresh() -> void:
	if not is_inside_tree() or _list == null:
		return
	var tdm := int(Network.settings.get("mode", 0)) == Catalog.MODE_TDM
	var host := Network.is_host()
	var me := Network.my_id()
	# ---------------- players
	UIKit.clear(_list)
	_list.add_child(UIKit.label("PLAYERS  %d / %d" % [Network.players.size(), Catalog.MAX_PLAYERS], 20, UIKit.ACCENT2))
	var ids: Array = Network.players.keys()
	ids.sort_custom(func(a, b):
		var ta := int(Network.players[a].get("team", 0)) if tdm else 0
		var tb := int(Network.players[b].get("team", 0)) if tdm else 0
		if ta != tb:
			return ta < tb
		return (a if a > 0 else 1000000000 - a) < (b if b > 0 else 1000000000 - b))
	for id in ids:
		var info: Dictionary = Network.players[id]
		var rowp := PanelContainer.new()
		var rsb := UIKit._box(Color(0.03, 0.04, 0.1, 0.55), 14, 2, Color(1, 1, 1, 0.12))
		if tdm:
			rsb.border_color = Catalog.TEAM_COLORS[int(info.get("team", 0))]
			rsb.border_width_left = 6
		elif int(id) == me:
			rsb.border_color = UIKit.ACCENT2
		rowp.add_theme_stylebox_override("panel", rsb)
		var r := HBoxContainer.new()
		rowp.add_child(r)
		var av := TextureRect.new()
		av.texture = preload("res://assets/char/head.png")
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.custom_minimum_size = Vector2(40, 40)
		av.material = FXKit.tint_material(Catalog.color_by_index(int(info.get("color", 0))))
		r.add_child(av)
		var nm := str(info.get("name", "?"))
		if int(id) == me:
			nm += "  (you)"
		if int(id) == 1:
			nm += "  [HOST]"
		var nl := UIKit.label(nm, 20, UIKit.TEXT)
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(nl)
		var gp := Widgets.GunPreview.new()
		var wpn := str(info.get("weapon", "rifle"))
		gp.weapon_id = wpn
		var sk = info.get("skins", {})
		gp.skin_id = str(sk.get(wpn, "default")) if sk is Dictionary else "default"
		gp.padding = 0.05
		gp.backlight = false
		gp.custom_minimum_size = Vector2(90, 40)
		r.add_child(gp)
		if tdm:
			var team := int(info.get("team", 0))
			var tl := UIKit.label(Catalog.TEAM_NAMES[team].to_upper(), 16, Catalog.TEAM_COLORS[team])
			tl.custom_minimum_size.x = 60
			r.add_child(tl)
			if host and info.get("bot", false):
				var bid := int(id)
				r.add_child(UIKit.glass_button("SWAP", "dark", func(): Network.set_bot_team(bid, 1 - team), Vector2(80, 44), 16))
		_list.add_child(rowp)
	if host:
		var br := HBoxContainer.new()
		br.add_child(UIKit.glass_button("+ BOT", "blue", Network.add_bot, Vector2(130, 54), 20))
		br.add_child(UIKit.glass_button("- BOT", "dark", Network.remove_bot, Vector2(130, 54), 20))
		_list.add_child(br)
	# ---------------- side panel
	UIKit.clear(_side)
	var my: Dictionary = Network.players.get(me, {})
	_side.add_child(UIKit.label("YOUR COLOR", 16, UIKit.MUTED))
	_side.add_child(Widgets.color_row(int(my.get("color", Profile.color_index)), func(i: int):
		Profile.color_index = i
		Profile.save_profile()
		Network.update_my_info({"color": i}), 34.0))
	_side.add_child(UIKit.label("WEAPON", 16, UIKit.MUTED))
	var wrow := HFlowContainer.new()
	wrow.add_theme_constant_override("h_separation", 6)
	wrow.add_theme_constant_override("v_separation", 6)
	for w in Catalog.PRIMARY_WEAPONS:
		var wid: String = w
		var b := UIKit.glass_button(Catalog.weapon(wid)["name"], "orange" if wid == str(my.get("weapon", "")) else "dark", func():
			Profile.primary_weapon = wid
			Profile.save_profile()
			Network.update_my_info({"weapon": wid}), Vector2(0, 50), 17)
		wrow.add_child(b)
	_side.add_child(wrow)
	if tdm:
		_side.add_child(UIKit.label("TEAM", 16, UIKit.MUTED))
		var trow := HBoxContainer.new()
		for t in 2:
			var tid := t
			var on := int(my.get("team", 0)) == t
			var b := UIKit.glass_button(Catalog.TEAM_NAMES[t].to_upper(), (["red", "blue"][t]) if on else "dark", func(): Network.update_my_info({"team": tid}), Vector2(140, 52), 20)
			trow.add_child(b)
		_side.add_child(trow)
	_side.add_child(UIKit.glass_button("SHOP  (SKINS / POWERS)", "yellow", _open_shop, Vector2(0, 54), 19))
	_side.add_child(UIKit.spacer(6))
	_side.add_child(UIKit.label("MATCH", 16, UIKit.MUTED))
	if host:
		_side.add_child(_cycle("Mode", Catalog.MODE_NAMES, int(Network.settings["mode"]), "mode"))
		var map_names: Array = []
		for m in Catalog.MAPS:
			map_names.append(m["name"])
		_side.add_child(_cycle("Map", map_names, int(Network.settings["map"]), "map"))
		var times: Array = []
		for s in Catalog.MATCH_TIMES:
			times.append("%d min" % int(s / 60))
		_side.add_child(_cycle("Time", times, int(Network.settings["time"]), "time"))
	else:
		var s := Network.settings
		_side.add_child(UIKit.label("%s  |  %s  |  %d min" % [Catalog.MODE_NAMES[int(s["mode"])], Catalog.MAPS[int(s["map"])]["name"],
			int(Catalog.MATCH_TIMES[int(s["time"])] / 60)], 18))
	# ---------------- fixed action area (always visible)
	UIKit.clear(_actions)
	if host:
		var start := UIKit.glass_button("START MATCH", "green", Network.start_match, Vector2(0, 74), 32)
		start.disabled = Network.players.size() < 2
		_actions.add_child(start)
		if Network.players.size() < 2:
			_actions.add_child(UIKit.label("Need at least 2 players (add a bot).", 14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		_actions.add_child(UIKit.label("Waiting for the host to start...", 18, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))


func _cycle(label_text: String, options: Array, current: int, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UIKit.label(label_text, 18, UIKit.MUTED)
	l.custom_minimum_size.x = 70
	h.add_child(l)
	h.add_child(UIKit.glass_button("<", "blue", func(): Network.set_setting(key, posmod(current - 1, options.size())), Vector2(50, 48), 20))
	var v := UIKit.label(str(options[current]), 18, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	h.add_child(UIKit.glass_button(">", "blue", func(): Network.set_setting(key, posmod(current + 1, options.size())), Vector2(50, 48), 20))
	return h


func _open_shop() -> void:
	var s := ShopPanel.new()
	s.closed.connect(func():
		var li := Profile.lobby_info()
		Network.update_my_info({"skins": li["skins"], "powers": li["powers"]}))
	add_child(s)
