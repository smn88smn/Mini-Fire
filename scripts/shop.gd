class_name ShopPanel
extends Control
## Shop: gun skins, character skins (heroes), powers (permanent upgrades) and gems.
## Skins/powers cost MFC (earned by playing) or Gems (earned by playing in v1,
## watched ads, or bought with real money once the billing plugin is wired).
## Lists scroll by dragging with a finger (UIKit.DragScroll).

signal closed

var start_tab := "skins"
var _tab := "skins"
var _weapon := "smg"
var _tab_row: HBoxContainer
var _body: Control
var _spin_weapon := "smg"
var _spinning := false
var _spin_reel: Label = null
var _spin_result_label: Label = null
var _spin_t := 0.0
var _spin_prize: Dictionary = {}
var _spin_last_result := ""
var _code_edit: LineEdit = null


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root := UIKit.screen_root(self, "menu", 0.6)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	root.add_child(v)
	# header
	var head := HBoxContainer.new()
	head.add_child(UIKit.glass_button("BACK", "dark", _close, Vector2(140, 58)))
	head.add_child(UIKit.spacer(0, 6))
	var t := UIKit.label("SHOP", 40, UIKit.ACCENT2)
	t.add_theme_constant_override("outline_size", 8)
	head.add_child(t)
	head.add_child(UIKit.spacer(0, 16))
	_tab_row = HBoxContainer.new()
	head.add_child(_tab_row)
	head.add_child(UIKit.hfill())
	head.add_child(UIKit.wallet_chips())
	v.add_child(head)
	_body = MarginContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	_tab = start_tab
	_weapon = Profile.primary_weapon if Profile.primary_weapon in Catalog.WEAPON_ORDER else "smg"
	Profile.profile_changed.connect(_refresh)
	Monetization.reward_granted.connect(_on_reward)
	Monetization.purchase_completed.connect(_on_purchase)
	Monetization.purchase_failed.connect(_on_purchase_failed)
	_refresh()


func _exit_tree() -> void:
	if Profile.profile_changed.is_connected(_refresh):
		Profile.profile_changed.disconnect(_refresh)
	for pair in [[Monetization.reward_granted, _on_reward], [Monetization.purchase_completed, _on_purchase],
			[Monetization.purchase_failed, _on_purchase_failed]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _refresh() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(_tab_row)
	for pair in [["skins", "SKINS", "orange"], ["guns", "GUNS", "red"], ["chars", "HEROES", "green"],
			["powers", "POWERS", "purple"], ["spin", "SPIN", "yellow"], ["gems", "GEMS", "blue"]]:
		var id: String = pair[0]
		var b := UIKit.glass_button(pair[1], pair[2] if id == _tab else "dark", func():
			_tab = id
			_refresh(), Vector2(108, 58), 20)
		_tab_row.add_child(b)
	UIKit.clear(_body)
	match _tab:
		"powers":
			_body.add_child(_powers_page())
		"gems":
			_body.add_child(_gems_page())
		"chars":
			_body.add_child(_chars_page())
		"guns":
			_body.add_child(_guns_page())
		"spin":
			_body.add_child(_spin_page())
		_:
			_body.add_child(_skins_page())


# ================================================================ skins
func _skins_page() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	# weapon list (left)
	var wp := PanelContainer.new()
	wp.add_theme_stylebox_override("panel", UIKit.glass_panel())
	wp.custom_minimum_size = Vector2(230, 0)
	h.add_child(wp)
	var ws := UIKit.DragScroll.new()
	ws.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wp.add_child(ws)
	var wl := VBoxContainer.new()
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wl.add_theme_constant_override("separation", 8)
	ws.add_child(wl)
	for w in Catalog.WEAPON_ORDER:
		var wid: String = w
		var b := UIKit.glass_button("", "orange" if wid == _weapon else "dark", func():
			_weapon = wid
			_refresh(), Vector2(0, 76))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var gp := Widgets.GunPreview.new()
		gp.weapon_id = wid
		gp.skin_id = Profile.skin_for(wid)
		gp.padding = 0.14
		gp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		gp.offset_bottom = -18
		b.add_child(gp)
		var nl := UIKit.label(str(Catalog.weapon(wid)["name"]), 15, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		nl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		nl.offset_top = -24
		nl.offset_bottom = -4
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nl)
		wl.add_child(b)
	# skin grid (right)
	var scroll := UIKit.DragScroll.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var equipped := Profile.skin_for(_weapon)
	for sid in Catalog.SKIN_ORDER:
		grid.add_child(_skin_card(sid, equipped))
	return h


func _skin_card(sid: String, equipped: String) -> Control:
	var s := Catalog.skin(sid)
	var rarity := str(s.get("rarity", "common"))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.card_style(rarity))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 236)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(UIKit.label(rarity.to_upper(), 14, Catalog.RARITY_COLORS.get(rarity, UIKit.MUTED)))
	v.add_child(top)
	var prev := Widgets.GunPreview.new()
	prev.weapon_id = _weapon
	prev.skin_id = sid
	prev.padding = 0.04
	prev.custom_minimum_size = Vector2(0, 96)
	v.add_child(prev)
	v.add_child(UIKit.label(str(s["name"]), 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var owned := Profile.owns_skin(sid)
	if sid == equipped:
		var b := UIKit.glass_button("EQUIPPED", "green", func(): pass, Vector2(0, 56), 20)
		b.disabled = true
		b.add_theme_stylebox_override("disabled", UIKit.glass("green", true))
		v.add_child(b)
	elif owned:
		v.add_child(UIKit.glass_button("EQUIP", "blue", func(): _equip(sid), Vector2(0, 56), 20))
	else:
		var gem := str(s["currency"]) == "gem"
		var b := UIKit.glass_button("  %d" % int(s["price"]), "purple" if gem else "orange", func(): _buy(sid), Vector2(0, 56), 22)
		b.icon = UIKit.icon_tex("gem" if gem else "coin")
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 26)
		if not Profile.can_afford(s["currency"], int(s["price"])):
			b.modulate = Color(1, 1, 1, 0.6)
		v.add_child(b)
	return card


func _buy(sid: String) -> void:
	if Profile.buy_skin(sid):
		Profile.equip_skin(_weapon, sid)
		Sfx.play("buy", 0.8, 0.0)
		UIKit.toast(self, "Unlocked %s" % Catalog.skin(sid)["name"], UIKit.GOOD)
		_sync_lobby()
	else:
		UIKit.toast(self, "Not enough currency", UIKit.BAD)


func _equip(sid: String) -> void:
	Profile.equip_skin(_weapon, sid)
	_sync_lobby()


# ================================================================ heroes (character skins)
func _chars_page() -> Control:
	var scroll := UIKit.DragScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for cid in Catalog.CHAR_ORDER:
		grid.add_child(_char_card(cid))
	return scroll


func _char_card(cid: String) -> Control:
	var c: Dictionary = Catalog.char_skin(cid)
	var rarity := str(c.get("rarity", "common"))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.card_style(rarity))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 280)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.add_child(UIKit.label(rarity.to_upper(), 14, Catalog.RARITY_COLORS.get(rarity, UIKit.MUTED)))
	var prev := Widgets.CharacterPreview.new()
	prev.custom_minimum_size = Vector2(0, 140)
	prev.color = Catalog.color_by_index(Profile.color_index)
	prev.char_id = cid
	prev.weapon_id = "smg"
	prev.skin_id = Profile.skin_for("smg")
	v.add_child(prev)
	v.add_child(UIKit.label(str(c["name"]), 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if cid == Profile.char_skin:
		var b := UIKit.glass_button("EQUIPPED", "green", func(): pass, Vector2(0, 56), 20)
		b.disabled = true
		b.add_theme_stylebox_override("disabled", UIKit.glass("green", true))
		v.add_child(b)
	elif Profile.owns_char(cid):
		v.add_child(UIKit.glass_button("EQUIP", "blue", func():
			Profile.equip_char(cid)
			_sync_lobby(), Vector2(0, 56), 20))
	else:
		var gem := str(c["currency"]) == "gem"
		var b := UIKit.glass_button("  %d" % int(c["price"]), "purple" if gem else "orange", func(): _buy_char(cid), Vector2(0, 56), 22)
		b.icon = UIKit.icon_tex("gem" if gem else "coin")
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 26)
		if not Profile.can_afford(c["currency"], int(c["price"])):
			b.modulate = Color(1, 1, 1, 0.6)
		v.add_child(b)
	return card


func _buy_char(cid: String) -> void:
	if Profile.buy_char(cid):
		Profile.equip_char(cid)
		Sfx.play("buy", 0.8, 0.0)
		UIKit.toast(self, "Unlocked %s" % Catalog.char_skin(cid)["name"], UIKit.GOOD)
		_sync_lobby()
	else:
		UIKit.toast(self, "Not enough currency", UIKit.BAD)


# ================================================================ powers
func _powers_page() -> Control:
	var scroll := UIKit.DragScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for pid in Catalog.POWER_ORDER:
		grid.add_child(_power_card(pid))
	return scroll


func _power_card(pid: String) -> Control:
	var pw: Dictionary = Catalog.POWERS[pid]
	var lvl := Profile.power_level(pid)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.card_style("epic" if lvl >= Catalog.POWER_MAX else "rare"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	h.add_child(UIKit.icon(str(pw["icon"]), 96))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	v.add_child(UIKit.label(str(pw["name"]).to_upper(), 26, UIKit.TEXT))
	v.add_child(UIKit.label(str(pw["desc"]), 16, UIKit.MUTED))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	for i in Catalog.POWER_MAX:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(38, 12)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.bg_color = UIKit.ACCENT2 if i < lvl else Color(1, 1, 1, 0.15)
		pip.add_theme_stylebox_override("panel", sb)
		pips.add_child(pip)
	pips.add_child(UIKit.label("LV %d/%d" % [lvl, Catalog.POWER_MAX], 16, UIKit.ACCENT2))
	v.add_child(pips)
	var cost := Profile.next_power_cost(pid)
	if cost.is_empty():
		var b := UIKit.glass_button("MAXED", "green", func(): pass, Vector2(150, 56), 20)
		b.disabled = true
		b.add_theme_stylebox_override("disabled", UIKit.glass("green", true))
		h.add_child(b)
	else:
		var gem := str(cost["currency"]) == "gem"
		var b := UIKit.glass_button("  %d" % int(cost["price"]), "purple" if gem else "orange", func(): _buy_power(pid), Vector2(150, 56), 22)
		b.icon = UIKit.icon_tex("gem" if gem else "coin")
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 26)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not Profile.can_afford(cost["currency"], int(cost["price"])):
			b.modulate = Color(1, 1, 1, 0.6)
		h.add_child(b)
	return card


func _buy_power(pid: String) -> void:
	if Profile.buy_power(pid):
		Sfx.play("buy", 0.8, 0.0)
		UIKit.toast(self, "%s level %d" % [Catalog.POWERS[pid]["name"], Profile.power_level(pid)], UIKit.GOOD)
		_sync_lobby()
	else:
		UIKit.toast(self, "Not enough currency", UIKit.BAD)


# ================================================================ guns (weapon levels)
func _guns_page() -> Control:
	var scroll := UIKit.DragScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for wid in Catalog.WEAPON_ORDER:
		grid.add_child(_gun_level_card(wid))
	return scroll

func _gun_level_card(wid: String) -> Control:
	var w: Dictionary = Catalog.weapon(wid)
	var lvl := Profile.gun_level(wid)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.card_style("legend" if lvl >= Catalog.GUN_LEVEL_MAX else "rare"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var prev := Widgets.GunPreview.new()
	prev.weapon_id = wid
	prev.skin_id = Profile.skin_for(wid)
	prev.padding = 0.05
	prev.custom_minimum_size = Vector2(150, 70)
	h.add_child(prev)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	v.add_child(UIKit.label(str(w["name"]).to_upper(), 22, UIKit.TEXT))
	# level pips
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 5)
	for i in Catalog.GUN_LEVEL_MAX:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(30, 11)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		sb.bg_color = (UIKit.BAD if i == Catalog.GUN_LEVEL_MAX - 1 else UIKit.ACCENT2) if i < lvl else Color(1, 1, 1, 0.15)
		pip.add_theme_stylebox_override("panel", sb)
		pips.add_child(pip)
	pips.add_child(UIKit.label("LV %d/%d" % [lvl, Catalog.GUN_LEVEL_MAX], 15, UIKit.ACCENT2))
	v.add_child(pips)
	var dmg_now := Catalog.gun_level_damage(wid, lvl)
	var line := "Damage %d" % dmg_now
	if lvl < Catalog.GUN_LEVEL_MAX:
		line += "  ->  %d at LV%d" % [Catalog.gun_level_damage(wid, lvl + 1), lvl + 1]
	else:
		line += "  |  FIRE BULLETS: burn %d HP/s for %ds" % [int(Catalog.BURN_DPS), int(Catalog.BURN_TIME)]
	v.add_child(UIKit.label(line, 15, UIKit.MUTED))
	v.add_child(UIKit.glass_button("SPIN TO LEVEL UP", "yellow", func():
		_spin_weapon = wid
		_tab = "spin"
		_refresh(), Vector2(0, 46), 17))
	return card

# ================================================================ spin shop
func _spin_page() -> Control:
	var scroll := UIKit.DragScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	scroll.add_child(v)
	# weapon selector
	var sel := PanelContainer.new()
	sel.add_theme_stylebox_override("panel", UIKit.glass_panel())
	v.add_child(sel)
	var sv := VBoxContainer.new()
	sel.add_child(sv)
	sv.add_child(UIKit.label("LEVEL UP WHICH GUN?", 20, UIKit.ACCENT2))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	sv.add_child(wrow)
	for wid in Catalog.WEAPON_ORDER:
		var id := String(wid)
		var b := UIKit.glass_button(str(Catalog.weapon(wid)["name"]), "orange" if id == _spin_weapon else "dark", func():
			_spin_weapon = id
			_refresh(), Vector2(0, 52), 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrow.add_child(b)
	sv.add_child(UIKit.label("Selected: %s  LV %d/%d" % [Catalog.weapon(_spin_weapon)["name"], Profile.gun_level(_spin_weapon), Catalog.GUN_LEVEL_MAX], 16, UIKit.MUTED))
	# reel
	var reel_panel := PanelContainer.new()
	reel_panel.add_theme_stylebox_override("panel", UIKit.card_style("legend"))
	reel_panel.custom_minimum_size = Vector2(0, 190)
	v.add_child(reel_panel)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", 8)
	reel_panel.add_child(rv)
	_spin_reel = UIKit.label("SPIN THE WHEEL", 40, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER)
	rv.add_child(_spin_reel)
	_spin_result_label = UIKit.label(_spin_last_result, 18, UIKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	rv.add_child(_spin_result_label)
	# buttons
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 14)
	v.add_child(brow)
	var b1 := UIKit.glass_button("SPIN  %d MFC" % Catalog.SPIN_COST_MFC, "orange", func(): _do_spin("mfc"), Vector2(0, 74), 26)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not Profile.can_afford("mfc", Catalog.SPIN_COST_MFC):
		b1.modulate = Color(1, 1, 1, 0.55)
	brow.add_child(b1)
	var b2 := UIKit.glass_button("SPIN  %d GEMS" % Catalog.SPIN_COST_GEM, "purple", func(): _do_spin("gem"), Vector2(0, 74), 26)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not Profile.can_afford("gem", Catalog.SPIN_COST_GEM):
		b2.modulate = Color(1, 1, 1, 0.55)
	brow.add_child(b2)
	# prize list
	v.add_child(UIKit.label("POSSIBLE PRIZES", 18, UIKit.ACCENT2))
	var total_w := 0
	for pr in Catalog.SPIN_PRIZES:
		total_w += int(pr[0])
	for pr in Catalog.SPIN_PRIZES:
		v.add_child(UIKit.label("  %d%%   %s" % [int(round(100.0 * int(pr[0]) / total_w)), _prize_text(pr)], 16, UIKit.MUTED))
	return scroll

func _prize_text(pr: Dictionary) -> String:
	match str(pr[1]):
		"mfc":
			return "+%d MFC" % int(pr[2])
		"gems":
			return "+%d Gems" % int(pr[2])
		"gunlvl":
			return "%s +1 Level" % str(Catalog.weapon(_spin_weapon)["name"])
		"gunlvl2":
			return "%s +2 Levels" % str(Catalog.weapon(_spin_weapon)["name"])
	return "?"

func _do_spin(currency: String) -> void:
	if _spinning:
		return
	var cost := Catalog.SPIN_COST_MFC if currency == "mfc" else Catalog.SPIN_COST_GEM
	if not Profile.can_afford(currency, cost):
		UIKit.toast(self, "Not enough currency", UIKit.BAD)
		return
	# pick the weighted prize up front
	var total := 0
	for pr in Catalog.SPIN_PRIZES:
		total += int(pr[0])
	var roll := randi() % total
	var prize: Dictionary = Catalog.SPIN_PRIZES[Catalog.SPIN_PRIZES.size() - 1]
	for pr in Catalog.SPIN_PRIZES:
		roll -= int(pr[0])
		if roll < 0:
			prize = pr
			break
	# pay now, spin animation, grant when it stops
	if currency == "mfc":
		Profile.mfc -= cost
	else:
		Profile.gems -= cost
	Profile.save_profile()
	Profile.wallet_changed.emit()
	_spin_prize = prize
	_spin_last_result = ""
	_spinning = true
	_spin_t = 0.0
	if _spin_result_label and is_instance_valid(_spin_result_label):
		_spin_result_label.text = ""
	Sfx.play("ui", 0.8, 0.0)

func _process(delta: float) -> void:
	if not _spinning:
		return
	_spin_t += delta
	if _spin_t < 1.8:
		# reel animation: cycle random prize names
		if _spin_reel and is_instance_valid(_spin_reel) and fmod(_spin_t, 0.09) < delta:
			var r: Dictionary = Catalog.SPIN_PRIZES[randi() % Catalog.SPIN_PRIZES.size()]
			_spin_reel.text = _prize_text(r)
			Sfx.play("ui", 0.3, 0.0)
	else:
		_spinning = false
		_grant_spin_prize()

func _grant_spin_prize() -> void:
	var pr: Dictionary = _spin_prize
	var txt := _prize_text(pr)
	match str(pr[1]):
		"mfc":
			Profile.add_currency(int(pr[2]), 0)
		"gems":
			Profile.add_currency(0, int(pr[2]))
		"gunlvl":
			Profile.add_gun_levels(_spin_weapon, int(pr[2]))
		"gunlvl2":
			Profile.add_gun_levels(_spin_weapon, int(pr[2]))
	_spin_last_result = "YOU WON:  " + txt
	Sfx.play("buy", 0.9, 0.0)
	UIKit.toast(self, "You won " + txt, UIKit.GOOD)
	_refresh()

# ================================================================ gems
func _gems_page() -> Control:
	var scroll := UIKit.DragScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UIKit.glass_panel())
	v.add_child(info)
	var iv := VBoxContainer.new()
	info.add_child(iv)
	iv.add_child(UIKit.label("EARN BY PLAYING", 24, UIKit.ACCENT2))
	iv.add_child(UIKit.label("Every kill: +%d MFC.  Every match: +%d MFC.  Win: +%d MFC and +%d Gems.  Every %d kills: +1 Gem." % [
		Catalog.REWARD_MFC_PER_KILL, Catalog.REWARD_MFC_MATCH, Catalog.REWARD_MFC_WIN, Catalog.REWARD_GEM_WIN, Catalog.REWARD_GEM_PER_KILLS], 17, UIKit.MUTED))
	iv.add_child(UIKit.label("Matches against bots only give half rewards.", 15, UIKit.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	if Monetization.ads_available():
		row.add_child(_gem_card("FREE", "+%d" % Catalog.REWARDED_AD_GEMS, "WATCH AD", "green", Monetization.show_rewarded_ad))
	for pack in Catalog.GEM_PACKS:
		var pid: String = pack["product_id"]
		if Monetization.billing_available():
			row.add_child(_gem_card("PACK", str(pack["gems"]), "BUY", "purple", func(): Monetization.buy_gem_pack(pid)))
		else:
			row.add_child(_gem_card("PACK", str(pack["gems"]), "SOON", "disabled", func(): pass))
	# Telegram shop: buy gems from the game's Telegram store
	var tg := PanelContainer.new()
	tg.add_theme_stylebox_override("panel", UIKit.card_style("legend"))
	tg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tgv := VBoxContainer.new()
	tgv.add_theme_constant_override("separation", 6)
	tg.add_child(tgv)
	tgv.add_child(UIKit.label("BUY GEMS ON TELEGRAM", 22, UIKit.ACCENT2))
	tgv.add_child(UIKit.label("Open our Telegram shop, pay, and you get a gift code to redeem here.", 16, UIKit.MUTED))
	var tgrow := HBoxContainer.new()
	tgrow.add_theme_constant_override("separation", 10)
	tgv.add_child(tgrow)
	var openb := UIKit.glass_button("OPEN TELEGRAM SHOP", "blue", func(): OS.shell_open(Catalog.TELEGRAM_SHOP_URL), Vector2(0, 56), 20)
	openb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgrow.add_child(openb)
	var redb := UIKit.glass_button("REDEEM CODE", "green", _show_redeem, Vector2(0, 56), 20)
	redb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgrow.add_child(redb)
	v.add_child(tg)
	return scroll

func _show_redeem() -> void:
	var dlg := PanelContainer.new()
	dlg.add_theme_stylebox_override("panel", UIKit.glass_panel())
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dlg.add_child(dv)
	dv.add_child(UIKit.label("REDEEM GIFT CODE", 22, UIKit.ACCENT2))
	dv.add_child(UIKit.label("Paste the code you received on Telegram (like MF-XXXXXX-XXXXX-100).", 15, UIKit.MUTED))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "MF-..."
	_code_edit.custom_minimum_size = Vector2(0, 54)
	_code_edit.add_theme_font_size_override("font_size", 22)
	dv.add_child(_code_edit)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 10)
	dv.add_child(rrow)
	rrow.add_child(UIKit.glass_button("CANCEL", "dark", func(): dlg.queue_free(), Vector2(130, 54), 18))
	rrow.add_child(UIKit.glass_button("REDEEM", "green", func(): _redeem(dlg), Vector2(0, 54), 22))
	add_child(dlg)

func _redeem(dlg: PanelContainer) -> void:
	if _code_edit == null:
		return
	var res := Profile.redeem_code(_code_edit.text)
	if res > 0:
		Sfx.play("buy", 0.9, 0.0)
		UIKit.toast(self, "+%d Gems added to your account" % res, UIKit.GOOD)
		dlg.queue_free()
		_refresh()
	elif res == -2:
		UIKit.toast(self, "This code was already used", UIKit.BAD)
	else:
		UIKit.toast(self, "Invalid code. Check it and try again.", UIKit.BAD)


func _gem_card(tag: String, amount: String, action: String, color: String, cb: Callable) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.card_style("legend" if tag == "PACK" else "rare"))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	v.add_child(UIKit.label(tag, 14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var ic := UIKit.icon("gem", 80)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	v.add_child(UIKit.label(amount + " GEMS", 26, Color("9fe8ff"), HORIZONTAL_ALIGNMENT_CENTER))
	var b := UIKit.glass_button(action, color, cb, Vector2(0, 56), 22)
	b.disabled = color == "disabled"
	v.add_child(b)
	return card


# ================================================================ misc
func _sync_lobby() -> void:
	if Network.is_active() and not Network.in_match:
		var li := Profile.lobby_info()
		Network.update_my_info({"skins": li["skins"], "powers": li.get("powers", {}), "char": li["char"]})


func _on_reward(g: int) -> void:
	UIKit.toast(self, "+%d Gems" % g, UIKit.ACCENT2)
	_refresh()


func _on_purchase(_pid: String, g: int) -> void:
	UIKit.toast(self, "Purchased %d Gems" % g, UIKit.GOOD)
	_refresh()


func _on_purchase_failed(_pid: String, reason: String) -> void:
	UIKit.toast(self, "Purchase failed: " + reason, UIKit.BAD)
