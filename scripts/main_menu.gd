extends Control
## Main menu: profile (name + color), host / join over Wi-Fi, practice vs bots, shop, settings.

var _content: Control
var _join_list: VBoxContainer
var _ip_edit: LineEdit
var _join_status: Label
var _view_char := ""
var _room_code_label: Label = null
var _room_status: Label = null
var _code_edit: LineEdit = null


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
	Network.online_room_ready.connect(_on_room_ready)
	Network.online_room_failed.connect(_on_room_failed)
	Cloud.signed_in.connect(func(_email: String):
		UIKit.toast(self, "Signed in! Your progress is saved to the cloud.", UIKit.GOOD)
		_show_home())
	Cloud.sign_in_failed.connect(func(reason: String):
		UIKit.toast(self, "Google Sign-In failed: " + reason, UIKit.BAD))
	Cloud.cloud_loaded.connect(func():
		UIKit.toast(self, "Cloud save restored.", UIKit.GOOD))


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
	who.icon = load("res://assets/char/%s.png" % Catalog.char_skin(Profile.char_skin)["head"])
	who.expand_icon = true
	who.add_theme_constant_override("icon_max_width", 34)
	who.custom_minimum_size = Vector2(220, 54)
	top.add_child(who)
	top.add_child(UIKit.spacer(8))
	if Cloud.available():
		var acct: Button
		if Cloud.is_signed_in():
			acct = UIKit.glass_button("  " + Cloud.account_email(), "green", _cloud_account, Vector2(0, 54), 17)
		else:
			acct = UIKit.glass_button("SIGN IN WITH GOOGLE", "blue", Cloud.sign_in_google, Vector2(0, 54), 17)
		acct.alignment = HORIZONTAL_ALIGNMENT_LEFT
		acct.add_theme_constant_override("icon_max_width", 34)
		top.add_child(acct)
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
	center.add_child(UIKit.glass_button("PRACTICE VS BOTS", "green", Network.host_practice, Vector2(420, 72), 27))
	center.add_child(UIKit.glass_button("ONLINE ROOM", "purple", _show_online, Vector2(420, 72), 27))
	center.add_child(UIKit.glass_button("HOST WI-FI GAME", "orange", _on_host, Vector2(420, 72), 27))
	center.add_child(UIKit.glass_button("JOIN WI-FI GAME", "blue", _show_join, Vector2(420, 72), 27))
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
	lv.add_child(UIKit.label("CHARACTER", 24, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	if _view_char == "":
		_view_char = Profile.char_skin
	var cs: Dictionary = Catalog.char_skin(_view_char)
	var prev := Widgets.CharacterPreview.new()
	prev.custom_minimum_size = Vector2(250, 150)
	prev.color = Catalog.color_by_index(Profile.color_index)
	prev.char_id = _view_char
	prev.weapon_id = "smg"
	prev.skin_id = Profile.skin_for("smg")
	lv.add_child(prev)
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_child(UIKit.glass_button("<", "blue", func(): _cycle_char(-1), Vector2(52, 52), 26))
	var wl := UIKit.label(str(cs["name"]), 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	wl.custom_minimum_size = Vector2(150, 0)
	wl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrow.add_child(wl)
	wrow.add_child(UIKit.glass_button(">", "blue", func(): _cycle_char(1), Vector2(52, 52), 26))
	lv.add_child(wrow)
	if not Profile.owns_char(_view_char):
		var price := "%d %s" % [int(cs["price"]), "MFC" if cs["currency"] == "mfc" else "GEMS"]
		lv.add_child(UIKit.glass_button("UNLOCK  " + price, "yellow", func(): _open_shop("chars"), Vector2(0, 52), 20))
	elif _view_char != Profile.char_skin:
		lv.add_child(UIKit.glass_button("EQUIP", "green", func():
			Profile.equip_char(_view_char)
			_show_home(), Vector2(0, 52), 22))
	else:
		lv.add_child(UIKit.label("EQUIPPED", 18, UIKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var colors := Widgets.color_row(Profile.color_index, func(i: int):
		Profile.color_index = i
		Profile.save_profile()
		_show_home(), 34)
	colors.alignment = FlowContainer.ALIGNMENT_CENTER
	lv.add_child(colors)
	var kd := float(Profile.total_kills) / maxf(1.0, float(Profile.total_deaths))
	lv.add_child(UIKit.label("Wins %d   Kills %d   K/D %.2f" % [Profile.wins, Profile.total_kills, kd], 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func _cycle_char(dir: int) -> void:
	var list: Array = Catalog.CHAR_ORDER
	var i := list.find(_view_char)
	_view_char = list[(i + dir + list.size()) % list.size()]
	if Profile.owns_char(_view_char):
		Profile.equip_char(_view_char)
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


# ================================================================ cloud account
func _cloud_account() -> void:
	var dlg := PanelContainer.new()
	dlg.add_theme_stylebox_override("panel", UIKit.glass_panel())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	dlg.add_child(v)
	v.add_child(UIKit.label("Signed in as", 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label(Cloud.account_email(), 22, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Your wallet, characters, skins and gun levels are backed up. If you reinstall the game, sign in with the same Google account to restore everything.", 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.glass_button("SAVE NOW", "green", func():
		Cloud.save_now()
		UIKit.toast(self, "Saved to cloud.", UIKit.GOOD)
		dlg.queue_free(), Vector2(0, 54), 20))
	v.add_child(UIKit.glass_button("SIGN OUT", "red", func():
		Cloud.sign_out()
		dlg.queue_free()
		_show_home(), Vector2(0, 54), 20))
	v.add_child(UIKit.glass_button("CLOSE", "dark", func(): dlg.queue_free(), Vector2(0, 54), 20))
	add_child(dlg)
	dlg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

# ================================================================ online room
func _show_online() -> void:
	var page := _page("ONLINE ROOM")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	# create
	var cp := UIKit.panel()
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	cp.add_child(cv)
	cv.add_child(UIKit.label("CREATE A ROOM", 24, UIKit.ACCENT2))
	cv.add_child(UIKit.label("Up to %d players. You are the host. Share the room code with your friends - they can join from anywhere with internet." % Catalog.MAX_PLAYERS, 16, UIKit.MUTED))
	cv.add_child(UIKit.glass_button("CREATE ROOM", "green", func():
		if _room_status:
			_room_status.text = "Opening port and finding your IP..."
			_room_status.add_theme_color_override("font_color", UIKit.MUTED)
		Network.host_online(), Vector2(0, 64), 24))
	_room_code_label = UIKit.label("", 34, UIKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_room_code_label.add_theme_constant_override("outline_size", 6)
	cv.add_child(_room_code_label)
	_room_status = UIKit.label("", 15, UIKit.MUTED)
	_room_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_room_status)
	# join
	var jp := UIKit.panel()
	jp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(jp)
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 10)
	jp.add_child(jv)
	jv.add_child(UIKit.label("JOIN A ROOM", 24, UIKit.ACCENT2))
	jv.add_child(UIKit.label("Enter the room code the host shared (like AB2C7-H3K9Q).", 16, UIKit.MUTED))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "AB2C7-H3K9Q"
	_code_edit.text = ""
	_code_edit.custom_minimum_size = Vector2(0, 58)
	_code_edit.add_theme_font_size_override("font_size", 26)
	_code_edit.text_submitted.connect(func(_t): _join_code())
	jv.add_child(_code_edit)
	jv.add_child(UIKit.glass_button("JOIN ROOM", "blue", _join_code, Vector2(0, 64), 24))
	var note := UIKit.label("Both players need internet. If the host's router blocks the connection, use HOST/JOIN WI-FI GAME on the same network instead.", 14, UIKit.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)

func _on_room_ready(code: String) -> void:
	if _room_code_label and is_instance_valid(_room_code_label):
		_room_code_label.text = code
	if _room_status and is_instance_valid(_room_status):
		_room_status.text = "Room created! Share this code with your friends. They join from ONLINE ROOM -> JOIN A ROOM."
		_room_status.add_theme_color_override("font_color", UIKit.GOOD)

func _on_room_failed(reason: String) -> void:
	if _room_status and is_instance_valid(_room_status):
		_room_status.text = reason
		_room_status.add_theme_color_override("font_color", UIKit.BAD)

func _join_code() -> void:
	if _code_edit == null:
		return
	var err := Network.join_by_code(_code_edit.text)
	if err == ERR_INVALID_PARAMETER:
		if _room_status:
			_room_status.text = "That is not a valid room code."
			_room_status.add_theme_color_override("font_color", UIKit.BAD)
	elif err != OK:
		if _room_status:
			_room_status.text = "Could not start connection (%s)." % error_string(err)
			_room_status.add_theme_color_override("font_color", UIKit.BAD)

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
	v.add_child(UIKit.glass_button("EDIT CONTROLS", "blue", func(): add_child(ControlsEditor.new()), Vector2(0, 56), 22))
	var help := UIKit.label("Phone: left stick moves (push up = jetpack), right stick aims and fires. Stand on a gun to pick it up.\nPC: A/D move, W/Space jetpack, mouse aim + click fire, R reload, Q switch, F pick up, Z scope, Tab score, Esc pause.", 15, UIKit.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(help)
	v.add_child(UIKit.label("Mini Fire v%s" % ProjectSettings.get_setting("application/config/version", "1.0.0"), 14, UIKit.MUTED))
