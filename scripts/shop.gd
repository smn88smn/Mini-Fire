class_name ShopPanel
extends Control
## Gun skin shop. Skins cost MFC (earned by playing) or Gems (earned by playing in v1,
## watched ads, or bought with real money once the billing plugin is wired).

signal closed

var _weapon := "rifle"
var _preview: Widgets.GunPreview
var _grid: GridContainer
var _tabs: HBoxContainer
var _info: Label


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	add_child(m)
	var p := UIKit.panel()
	m.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	# header
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("GUN SKINS", 30, UIKit.ACCENT))
	head.add_child(UIKit.hfill())
	head.add_child(UIKit.wallet_label())
	head.add_child(UIKit.button("CLOSE", _close, 120))
	v.add_child(head)
	# weapon tabs
	_tabs = HBoxContainer.new()
	v.add_child(_tabs)
	# body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	body.add_child(left)
	_preview = Widgets.GunPreview.new()
	_preview.custom_minimum_size = Vector2(330, 170)
	left.add_child(_preview)
	_info = UIKit.label("", 16, UIKit.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(330, 0)
	left.add_child(_info)
	left.add_child(_gems_box())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
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


func _close() -> void:
	closed.emit()
	queue_free()


func _gems_box() -> Control:
	var box := VBoxContainer.new()
	box.add_child(UIKit.label("GET GEMS", 20, UIKit.ACCENT2))
	box.add_child(UIKit.label("Win matches: +%d Gems.  Every %d kills: +1 Gem." % [Catalog.REWARD_GEM_WIN, Catalog.REWARD_GEM_PER_KILLS], 14, UIKit.MUTED))
	if Monetization.ads_available():
		box.add_child(UIKit.button("Watch ad  +%d Gems" % Catalog.REWARDED_AD_GEMS, Monetization.show_rewarded_ad, 0, 18))
	if Monetization.billing_available():
		for pack in Catalog.GEM_PACKS:
			var pid: String = pack["product_id"]
			box.add_child(UIKit.button("Buy " + str(pack["label"]), func(): Monetization.buy_gem_pack(pid), 0, 18))
	else:
		box.add_child(UIKit.label("Gem store: coming soon", 14, UIKit.MUTED))
	return box


func _refresh() -> void:
	UIKit.clear(_tabs)
	var all_w: Array = Catalog.PRIMARY_WEAPONS + [Catalog.SECONDARY_WEAPON]
	for w in all_w:
		var wid: String = w
		var b := UIKit.button(Catalog.weapon(wid)["name"], func():
			_weapon = wid
			_refresh(), 0, 18)
		if wid == _weapon:
			b.add_theme_color_override("font_color", UIKit.ACCENT2)
			b.add_theme_stylebox_override("normal", UIKit._box(UIKit.PANEL2, 10, 2, UIKit.ACCENT))
		_tabs.add_child(b)
	var equipped := Profile.skin_for(_weapon)
	_preview.weapon_id = _weapon
	_preview.skin_id = equipped
	var wd := Catalog.weapon(_weapon)
	_info.text = "%s  |  Damage %d  |  Mag %d\nEquipped skin: %s" % [wd["name"], int(wd["damage"]) * int(wd["pellets"]), int(wd["mag"]), Catalog.skin(equipped)["name"]]
	UIKit.clear(_grid)
	for sid in Catalog.SKIN_ORDER:
		_grid.add_child(_skin_card(sid, equipped))


func _skin_card(sid: String, equipped: String) -> Control:
	var s := Catalog.skin(sid)
	var card := UIKit.panel(UIKit.PANEL2, 10)
	card.custom_minimum_size = Vector2(230, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var prev := Widgets.GunPreview.new()
	prev.weapon_id = _weapon
	prev.skin_id = sid
	prev.gun_scale = 1.8
	prev.custom_minimum_size = Vector2(200, 80)
	v.add_child(prev)
	v.add_child(UIKit.label(str(s["name"]), 18))
	var owned := Profile.owns_skin(sid)
	if sid == equipped:
		v.add_child(UIKit.label("EQUIPPED", 16, UIKit.GOOD))
	elif owned:
		v.add_child(UIKit.button("EQUIP", func(): _equip(sid), 0, 16))
	else:
		var cur := "MFC" if s["currency"] == "mfc" else "Gems"
		var b := UIKit.accent_button("BUY  %d %s" % [int(s["price"]), cur], func(): _buy(sid), 0, 16)
		b.disabled = not Profile.can_afford(s["currency"], int(s["price"]))
		v.add_child(b)
	return card


func _buy(sid: String) -> void:
	if Profile.buy_skin(sid):
		Profile.equip_skin(_weapon, sid)
		Sfx.play("buy", 0.8, 0.0)
		UIKit.toast(self, "Unlocked %s" % Catalog.skin(sid)["name"], UIKit.GOOD)
		_sync_lobby_skins()
	else:
		UIKit.toast(self, "Not enough currency", UIKit.BAD)


func _equip(sid: String) -> void:
	Profile.equip_skin(_weapon, sid)
	_sync_lobby_skins()


func _sync_lobby_skins() -> void:
	if Network.is_active() and not Network.in_match:
		Network.update_my_info({"skins": Profile.lobby_info()["skins"]})


func _on_reward(g: int) -> void:
	UIKit.toast(self, "+%d Gems" % g, UIKit.ACCENT2)
	_refresh()


func _on_purchase(_pid: String, g: int) -> void:
	UIKit.toast(self, "Purchased %d Gems" % g, UIKit.GOOD)
	_refresh()


func _on_purchase_failed(_pid: String, reason: String) -> void:
	UIKit.toast(self, "Purchase failed: " + reason, UIKit.BAD)
