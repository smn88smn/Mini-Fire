extends Control
## Main menu: profile (name + color), host / join over Wi-Fi, practice vs bots, shop, settings.

var _content: Control
var _join_list: VBoxContainer
var _ip_edit: LineEdit
var _join_status: Label


func _ready() -> void:
	get_tree().paused = false
	var root := UIKit.screen_root(self, "menu", 0.18)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## Page with a title bar + BACK button; returns the body container.
func _page(title: String) -> VBoxContainer:
	_clear()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UIKit.glass_button("BACK", "dark", _show_home, Vector2(140, 58)))
	head.add_child(UIKit.spacer(0, 10))
	var t := UIKit.label(title, 40, UIKit.ACCENT2)
	t.add_theme_constant_override("outline_size", 8)
	head.add_child(t)
	head.add_child(UIKit.hfill())
	head.add_child(UIKit.wallet_chips())
	v.add_child(head)
	return v


# ================================================================ home
func _show_home() -> void:
	_clear()
	# --- top bar: profile chip (left) + wallet (right)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 60
	_content.add_child(top)
	var who := UIKit.glass_button("  " + Profile.player_name, "dark", _show_settings, Vector2(0, 54), 22)
	who.alignment = HORIZONTAL_ALIGNMENT_LEFT
	who.icon = preload("res://assets/char/head.png")
	who.expand_icon = true
	who.add_theme_constant_override("icon_max_width", 34)
	who.custom_minimum_size = Vector2(220, 54)
	top.add_child(who)
	top.add_child(UIKit.hfill())
	top.add_child(UIKit.wallet_chips())

	# --- center: logo + big glass buttons
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.add_theme_constant_override("separation", 14)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.custom_minimum_size = Vector2(440, 0)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_content.add_child(center)
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(440, 160)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(logo)
	center.add_child(UIKit.glass_button("PRACTICE VS BOTS", "green", Network.host_practice, Vector2(420, 78), 30))
	center.add_child(UIKit.glass_button("HOST WI-FI GAME", "orange", _on_host, Vector2(420, 78), 30))
	center.add_child(UIKit.glass_button("JOIN WI-FI GAME", "blue", _show_join, Vector2(420, 78), 30))
	for c in center.get_children():
		c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(UIKit.spacer(30))

	# --- right column: small shop / powers / settings buttons
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.grow_vertical = Control.GROW_DIRECTION_BOTH
	right.add_theme_constant_override("separation", 8)
	_content.add_child(right)
	right.add_child(UIKit.icon_button("gold_crate", "SHOP", "yellow", func(): _open_shop("skins"), 82))
	right.add_child(UIKit.icon_button("armor", "POWERS", "purple", func(): _open_shop("powers"), 82))
	right.add_child(UIKit.icon_button("gear", "SETTINGS", "dark", _show_settings, 82))

	# --- left: loadout card
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.glass_panel())
	card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(300, 0)
	_content.add_child(card)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	card.add_child(lv)
	lv.add_child(UIKit.label("LOADOUT", 24, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	var prev := Widgets.CharacterPreview.new()
	prev.custom_minimum_size = Vector2(250, 150)
	prev.color = Catalog.color_by_index(Profile.color_index)
	prev.weapon_id = Profile.primary_weapon
	prev.skin_id = Profile.skin_for(Profile.primary_weapon)
	lv.add_child(prev)
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_child(UIKit.glass_button("<", "blue", func(): _cycle_weapon(-1), Vector2(52, 52), 26))
	var wl := UIKit.label(str(Catalog.weapon(Profile.primary_weapon)["name"]), 24, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	wl.custom_minimum_size = Vector2(130, 0)
	wl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrow.add_child(wl)
	wrow.add_child(UIKit.glass_button(">", "blue", func(): _cycle_weapon(1), Vector2(52, 52), 26))
	lv.add_child(wrow)
	var colors := Widgets.color_row(Profile.color_index, func(i: int):
		Profile.color_index = i
		Profile.save_profile()
		_show_home(), 34)
	colors.alignment = FlowContainer.ALIGNMENT_CENTER
	lv.add_child(colors)
	var kd := float(Profile.total_kills) / maxf(1.0, float(Profile.total_deaths))
	lv.add_child(UIKit.label("Wins %d   Kills %d   K/D %.2f" % [Profile.wins, Profile.total_kills, kd], 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func _cycle_weapon(dir: int) -> void:
	var list: Array = Catalog.PRIMARY_WEAPONS
	var i := list.find(Profile.primary_weapon)
	Profile.primary_weapon = list[(i + dir + list.size()) % list.size()]
	Profile.save_profile()
	_show_home()


func _on_host() -> void:
	var err := Network.host_lan()
	if err != OK:
		UIKit.toast(self, "Could not host (port %d busy?)" % Network.PORT, UIKit.BAD)


func _open_shop(tab: String = "skins") -> void:
	var s := ShopPanel.new()
	s.start_tab = tab
	s.closed.connect(_show_home)
	add_child(s)


# ================================================================ join
func _show_join() -> void:
	var page := _page("JOIN WI-FI GAME")
	var ips := Network.local_ips()
	page.add_child(UIKit.label("Be on the same Wi-Fi (or hotspot) as the host. Your IP: %s" % (", ".join(ips) if ips.size() > 0 else "not connected"), 16, UIKit.MUTED))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	var lp := UIKit.panel()
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lp)
	var lv := VBoxContainer.new()
	lp.add_child(lv)
	lv.add_child(UIKit.label("Games found on your network", 20, UIKit.ACCENT2))
	var sc := UIKit.DragScroll.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	_join_list = VBoxContainer.new()
	_join_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_join_list)
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
	rv.add_child(UIKit.glass_button("JOIN", "green", func(): _join_ip(_ip_edit.text), Vector2(0, 64), 28))
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
		var b := UIKit.glass_button(txt, "blue", func(): _join_ip(ip), Vector2(0, 60), 20)
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
	var page := _page("SETTINGS")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	# profile
	var p1 := UIKit.panel()
	p1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p1)
	var v1 := VBoxContainer.new()
	p1.add_child(v1)
	v1.add_child(UIKit.label("PLAYER NAME", 24, UIKit.ACCENT2))
	var name_edit := LineEdit.new()
	name_edit.text = Profile.player_name
	name_edit.max_length = 16
	name_edit.placeholder_text = "Your name"
	name_edit.custom_minimum_size = Vector2(0, 58)
	name_edit.add_theme_font_size_override("font_size", 26)
	v1.add_child(name_edit)
	var save := func():
		var clean := name_edit.text.strip_edges()
		if clean == "":
			UIKit.toast(self, "Name cannot be empty", UIKit.BAD)
			return
		Profile.player_name = clean
		Profile.save_profile()
		UIKit.toast(self, "Name saved", UIKit.GOOD)
	name_edit.text_submitted.connect(func(_t): save.call())
	v1.add_child(UIKit.glass_button("SAVE NAME", "green", save, Vector2(0, 60), 24))
	v1.add_child(UIKit.spacer(8))
	v1.add_child(UIKit.label("COLOR", 20, UIKit.ACCENT2))
	v1.add_child(Widgets.color_row(Profile.color_index, func(i: int):
		Profile.color_index = i
		Profile.save_profile(), 40))
	v1.add_child(UIKit.label("Matches %d   Wins %d   Kills %d" % [Profile.matches_played, Profile.wins, Profile.total_kills], 16, UIKit.MUTED))
	# game
	var p2 := UIKit.panel()
	p2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p2)
	var v := VBoxContainer.new()
	p2.add_child(v)
	v.add_child(UIKit.label("SOUND VOLUME", 20, UIKit.ACCENT2))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Profile.sfx_volume
	sl.custom_minimum_size = Vector2(300, 44)
	sl.value_changed.connect(func(val: float):
		Profile.sfx_volume = val
		Profile.save_profile()
		Sfx.play("ui", 1.0, 0.0))
	v.add_child(sl)
	v.add_child(UIKit.label("TOUCH CONTROLS", 20, UIKit.ACCENT2))
	var opts := HBoxContainer.new()
	var names := ["AUTO", "ON", "OFF"]
	for i in 3:
		var idx := i
		opts.add_child(UIKit.glass_button(names[i], "orange" if i == Profile.touch_controls else "dark", func():
			Profile.touch_controls = idx
			Profile.save_profile()
			_show_settings(), Vector2(110, 56), 20))
	v.add_child(opts)
	v.add_child(UIKit.spacer(6))
	var help := UIKit.label("Phone: left stick moves (push up = jetpack), right stick aims and fires.\nPC: A/D move, W/Space jetpack, mouse aim + click fire, R reload, Q switch, Tab score, Esc pause.", 15, UIKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	v.add_child(UIKit.label("Mini Fire v%s" % ProjectSettings.get_setting("application/config/version", "1.0.0"), 14, UIKit.MUTED))
