extends Control
## Main menu: profile (name + color), host / join over Wi-Fi, practice vs bots, shop, settings.

var _content: Control
var _join_list: VBoxContainer
var _ip_edit: LineEdit
var _join_status: Label


func _ready() -> void:
	get_tree().paused = false
	var root := UIKit.screen_root(self)
	_content = VBoxContainer.new()
	root.add_child(_content)
	_show_home()
	if Network.last_message != "":
		UIKit.toast(self, Network.last_message, UIKit.BAD)
		Network.last_message = ""
	Network.connection_failed.connect(_on_connection_failed)
	Network.hosts_updated.connect(_on_hosts_updated)


func _exit_tree() -> void:
	Network.stop_discovery()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_show_home()


func _clear() -> void:
	Network.stop_discovery()
	UIKit.clear(_content)


# ================================================================ home
func _show_home() -> void:
	_clear()
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 30)
	_content.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	var title := UIKit.label("MINI FIRE", 64, UIKit.ACCENT)
	title.add_theme_color_override("font_outline_color", Color("6b1d00"))
	title.add_theme_constant_override("outline_size", 10)
	left.add_child(title)
	left.add_child(UIKit.label("Jetpack LAN battles", 18, UIKit.MUTED))
	left.add_child(UIKit.spacer(6))
	left.add_child(UIKit.accent_button("HOST WI-FI GAME", _on_host, 420))
	left.add_child(UIKit.button("JOIN WI-FI GAME", _show_join, 420))
	left.add_child(UIKit.button("PRACTICE VS BOTS", Network.host_practice, 420))
	var hb := HBoxContainer.new()
	hb.add_child(UIKit.button("SHOP", _open_shop, 205))
	hb.add_child(UIKit.button("SETTINGS", _show_settings, 205))
	left.add_child(hb)

	var right := UIKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var top := HBoxContainer.new()
	top.add_child(UIKit.label("PROFILE", 24, UIKit.ACCENT2))
	top.add_child(UIKit.hfill())
	top.add_child(UIKit.wallet_label())
	rv.add_child(top)
	var name_edit := LineEdit.new()
	name_edit.text = Profile.player_name
	name_edit.max_length = 16
	name_edit.placeholder_text = "Your name"
	name_edit.custom_minimum_size = Vector2(0, 50)
	name_edit.text_changed.connect(func(t: String):
		var clean := t.strip_edges()
		if clean != "":
			Profile.player_name = clean
			Profile.save_profile())
	rv.add_child(name_edit)
	rv.add_child(UIKit.label("Color", 16, UIKit.MUTED))
	rv.add_child(Widgets.color_row(Profile.color_index, func(i: int):
		Profile.color_index = i
		Profile.save_profile()
		_show_home()))
	rv.add_child(UIKit.label("Primary weapon", 16, UIKit.MUTED))
	var wrow := HFlowContainer.new()
	wrow.add_theme_constant_override("h_separation", 8)
	wrow.add_theme_constant_override("v_separation", 8)
	for w in Catalog.PRIMARY_WEAPONS:
		var wid: String = w
		var b := UIKit.button(Catalog.weapon(wid)["name"], func():
			Profile.primary_weapon = wid
			Profile.save_profile()
			_show_home(), 0, 18)
		if wid == Profile.primary_weapon:
			b.add_theme_stylebox_override("normal", UIKit._box(UIKit.PANEL2, 10, 2, UIKit.ACCENT))
			b.add_theme_color_override("font_color", UIKit.ACCENT2)
		wrow.add_child(b)
	rv.add_child(wrow)
	var prev := Widgets.GunPreview.new()
	prev.weapon_id = Profile.primary_weapon
	prev.skin_id = Profile.skin_for(Profile.primary_weapon)
	prev.custom_minimum_size = Vector2(0, 130)
	prev.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(prev)
	var kd := float(Profile.total_kills) / maxf(1.0, float(Profile.total_deaths))
	rv.add_child(UIKit.label("Matches %d   Wins %d   Kills %d   K/D %.2f" % [Profile.matches_played, Profile.wins, Profile.total_kills, kd], 16, UIKit.MUTED))


func _on_host() -> void:
	var err := Network.host_lan()
	if err != OK:
		UIKit.toast(self, "Could not host (port %d busy?)" % Network.PORT, UIKit.BAD)


func _open_shop() -> void:
	var s := ShopPanel.new()
	s.closed.connect(_show_home)
	add_child(s)


# ================================================================ join
func _show_join() -> void:
	_clear()
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("JOIN WI-FI GAME", 34, UIKit.ACCENT))
	head.add_child(UIKit.hfill())
	head.add_child(UIKit.button("BACK", _show_home, 140))
	_content.add_child(head)
	var ips := Network.local_ips()
	_content.add_child(UIKit.label("Be on the same Wi-Fi (or hotspot) as the host. Your IP: %s" % (", ".join(ips) if ips.size() > 0 else "not connected"), 16, UIKit.MUTED))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(row)
	var lp := UIKit.panel()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lp)
	var lv := VBoxContainer.new()
	lp.add_child(lv)
	lv.add_child(UIKit.label("Games found on your network", 20, UIKit.ACCENT2))
	_join_list = VBoxContainer.new()
	lv.add_child(_join_list)
	_join_list.add_child(UIKit.label("Searching...", 18, UIKit.MUTED))
	var rp := UIKit.panel()
	rp.custom_minimum_size = Vector2(400, 0)
	row.add_child(rp)
	var rv := VBoxContainer.new()
	rp.add_child(rv)
	rv.add_child(UIKit.label("Join by IP", 20, UIKit.ACCENT2))
	rv.add_child(UIKit.label("Ask the host for the IP shown in their lobby.", 14, UIKit.MUTED))
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.10"
	_ip_edit.text = Profile.last_join_ip
	_ip_edit.custom_minimum_size = Vector2(0, 50)
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip_edit.text_submitted.connect(func(_t): _join_ip(_ip_edit.text))
	rv.add_child(_ip_edit)
	rv.add_child(UIKit.accent_button("JOIN", func(): _join_ip(_ip_edit.text), 0))
	_join_status = UIKit.label("", 16, UIKit.MUTED)
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_join_status)
	Network.start_discovery()


func _on_hosts_updated(hosts: Array) -> void:
	if _join_list == null or not is_instance_valid(_join_list):
		return
	UIKit.clear(_join_list)
	if hosts.is_empty():
		_join_list.add_child(UIKit.label("Searching...", 18, UIKit.MUTED))
		return
	for h in hosts:
		var ip: String = h["ip"]
		var txt := "%s   %d/%d   %s" % [h["name"], int(h["players"]), int(h["max"]), Catalog.MODE_NAMES[clampi(int(h["mode"]), 0, 1)]]
		if int(h["v"]) != Catalog.GAME_VERSION:
			txt += "   (different version)"
		var b := UIKit.button(txt, func(): _join_ip(ip), 0, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_join_list.add_child(b)


func _join_ip(ip: String) -> void:
	var err := Network.join(ip)
	if err == ERR_INVALID_PARAMETER:
		_join_status.text = "That is not a valid IP address."
		_join_status.add_theme_color_override("font_color", UIKit.BAD)
	elif err != OK:
		_join_status.text = "Could not start connection (%s)." % error_string(err)
		_join_status.add_theme_color_override("font_color", UIKit.BAD)
	else:
		_join_status.text = "Connecting to %s ..." % ip.strip_edges()
		_join_status.add_theme_color_override("font_color", UIKit.MUTED)


func _on_connection_failed(reason: String) -> void:
	if _join_status and is_instance_valid(_join_status):
		_join_status.text = reason + ". Check the IP and that both devices are on the same Wi-Fi."
		_join_status.add_theme_color_override("font_color", UIKit.BAD)
	Network.start_discovery()


# ================================================================ settings
func _show_settings() -> void:
	_clear()
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("SETTINGS", 34, UIKit.ACCENT))
	head.add_child(UIKit.hfill())
	head.add_child(UIKit.button("BACK", _show_home, 140))
	_content.add_child(head)
	var p := UIKit.panel()
	_content.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UIKit.label("Sound volume", 20))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Profile.sfx_volume
	sl.custom_minimum_size = Vector2(400, 40)
	sl.value_changed.connect(func(val: float):
		Profile.sfx_volume = val
		Profile.save_profile()
		Sfx.play("ui", 1.0, 0.0))
	v.add_child(sl)
	v.add_child(UIKit.label("Touch controls", 20))
	var opts := HBoxContainer.new()
	var names := ["AUTO", "ALWAYS ON", "OFF"]
	for i in 3:
		var idx := i
		var b := UIKit.button(names[i], func():
			Profile.touch_controls = idx
			Profile.save_profile()
			_show_settings(), 160, 18)
		if i == Profile.touch_controls:
			b.add_theme_stylebox_override("normal", UIKit._box(UIKit.PANEL2, 10, 2, UIKit.ACCENT))
		opts.add_child(b)
	v.add_child(opts)
	v.add_child(UIKit.spacer(10))
	v.add_child(UIKit.label("PC controls: A/D move, W or Space jetpack, mouse aim + left click fire,\nR reload, Q / right click / wheel switch weapon, Tab scoreboard, Esc pause.", 16, UIKit.MUTED))
	v.add_child(UIKit.label("Phone: left stick moves (push up = jetpack), right stick aims and fires.", 16, UIKit.MUTED))
	v.add_child(UIKit.label("Mini Fire v%s" % ProjectSettings.get_setting("application/config/version", "1.0.0"), 14, UIKit.MUTED))
