class_name ShopPanel
extends Control
## Shop: gun skins, powers (permanent upgrades) and gems.
## Skins/powers cost MFC (earned by playing) or Gems (earned by playing in v1,
## watched ads, or bought with real money once the billing plugin is wired).
## Lists scroll by dragging with a finger (UIKit.DragScroll).

signal closed

var start_tab := "skins"
var _tab := "skins"
var _weapon := "rifle"
var _tab_row: HBoxContainer
var _body: Control


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
	_weapon = Profile.primary_weapon
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
	for pair in [["skins", "SKINS", "orange"], ["powers", "POWERS", "purple"], ["gems", "GEMS", "blue"]]:
		var id: String = pair[0]
		var b := UIKit.glass_button(pair[1], pair[2] if id == _tab else "dark", func():
			_tab = id
			_refresh(), Vector2(130, 58), 22)
		_tab_row.add_child(b)
	UIKit.clear(_body)
	match _tab:
		"powers":
			_body.add_child(_powers_page())
		"gems":
			_body.add_child(_gems_page())
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
	for w in Catalog.PRIMARY_WEAPONS + [Catalog.SECONDARY_WEAPON]:
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
	return scroll


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
		Network.update_my_info({"skins": li["skins"], "powers": li.get("powers", {})})


func _on_reward(g: int) -> void:
	UIKit.toast(self, "+%d Gems" % g, UIKit.ACCENT2)
	_refresh()


func _on_purchase(_pid: String, g: int) -> void:
	UIKit.toast(self, "Purchased %d Gems" % g, UIKit.GOOD)
	_refresh()


func _on_purchase_failed(_pid: String, reason: String) -> void:
	UIKit.toast(self, "Purchase failed: " + reason, UIKit.BAD)
