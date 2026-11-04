class_name HUD
extends CanvasLayer
## In-match HUD: timer, score, health/fuel/ammo, kill feed, scoreboard, pause and results.

var game: Node = null
var touch: TouchControls = null
var root: Control
var timer_label: Label
var score_label: Label
var center_label: Label
var feed: VBoxContainer
var bars: _Bars
var scoreboard: PanelContainer
var score_rows: VBoxContainer
var pause_panel: Control
var results_panel: Control
var results_box: VBoxContainer
var _center_until := 0.0


class _Bars extends Control:
	var hp := 1.0
	var fuel := 1.0
	var weapon_name := ""
	var ammo_text := ""
	var reload_frac := 0.0

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# health
		draw_rect(Rect2(0, 0, 260, 22), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(2, 2, 256 * hp, 18), Color(0.3, 1.0, 0.45).lerp(Color(1, 0.25, 0.25), 1.0 - hp))
		draw_string(font, Vector2(8, 17), "HP %d" % int(round(hp * Catalog.MAX_HEALTH)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.BLACK)
		# fuel
		draw_rect(Rect2(0, 28, 260, 14), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(2, 30, 256 * fuel, 10), Color(1.0, 0.7, 0.2))
		draw_string(font, Vector2(8, 40), "JET", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
		# weapon + ammo
		draw_string(font, Vector2(0, 72), weapon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		draw_string(font, Vector2(150, 72), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.ACCENT2)
		if reload_frac > 0.0:
			draw_rect(Rect2(0, 80, 260, 6), Color(0, 0, 0, 0.55))
			draw_rect(Rect2(0, 80, 260 * reload_frac, 6), Color(0.6, 0.8, 1.0))


func setup(p_game: Node) -> void:
	game = p_game
	layer = 10
	root = Control.new()
	root.theme = UIKit.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# touch controls under everything else
	touch = TouchControls.new()
	touch.visible = Profile.use_touch_controls()
	root.add_child(touch)

	# top bar
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.add_child(UIKit.button("II", toggle_pause, 64))
	top.add_child(UIKit.button("SCORE", func(): scoreboard.visible = not scoreboard.visible, 110, 18))
	top.add_child(UIKit.hfill())
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	timer_label = UIKit.label("0:00", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_outline(timer_label)
	score_label = UIKit.label("", 18, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER)
	_outline(score_label)
	mid.add_child(timer_label)
	mid.add_child(score_label)
	top.add_child(mid)
	top.add_child(UIKit.hfill())
	top.add_child(UIKit.spacer(0, 174))

	# kill feed
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed.offset_left = -360
	feed.offset_right = -16
	feed.offset_top = 80
	feed.add_theme_constant_override("separation", 2)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)

	# status bars (top-left under buttons so thumbs do not cover them on phones)
	bars = _Bars.new()
	bars.position = Vector2(18, 80)
	bars.size = Vector2(270, 90)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars)

	# center message
	center_label = UIKit.label("", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_outline(center_label)
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_label.offset_top = -160
	center_label.offset_bottom = -100
	center_label.offset_left = -400
	center_label.offset_right = 400
	root.add_child(center_label)

	# scoreboard
	scoreboard = UIKit.panel(Color(0.06, 0.07, 0.12, 0.92))
	scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	scoreboard.custom_minimum_size = Vector2(560, 0)
	scoreboard.visible = false
	score_rows = VBoxContainer.new()
	score_rows.add_theme_constant_override("separation", 4)
	scoreboard.add_child(score_rows)
	root.add_child(scoreboard)

	# pause
	pause_panel = _overlay()
	var pv: VBoxContainer = pause_panel.get_meta("box")
	pv.add_child(UIKit.label("PAUSED", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	pv.add_child(UIKit.label("The match keeps running for everyone", 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	pv.add_child(UIKit.accent_button("RESUME", toggle_pause, 300))
	var tbtn := UIKit.button("", func(): pass, 300, 18)
	tbtn.text = "Touch controls: " + ("ON" if touch.visible else "OFF")
	tbtn.pressed.connect(func():
		touch.visible = not touch.visible
		touch.reset()
		tbtn.text = "Touch controls: " + ("ON" if touch.visible else "OFF"))
	pv.add_child(tbtn)
	pv.add_child(UIKit.button("LEAVE MATCH", func(): Network.leave(true), 300))

	# results
	results_panel = _overlay()
	results_box = results_panel.get_meta("box")


func _overlay() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(c)
	var p := UIKit.panel()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	dim.set_meta("box", v)
	return dim


func _outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)


func toggle_pause() -> void:
	if results_panel.visible:
		return
	pause_panel.visible = not pause_panel.visible
	touch.reset()


func is_paused() -> bool:
	return pause_panel.visible or results_panel.visible


# ---------------------------------------------------------------- per-frame
func update_hud(p: Player, time_left: float, score_text: String) -> void:
	var tl := maxi(0, int(ceil(time_left)))
	timer_label.text = "%d:%02d" % [tl / 60, tl % 60]
	timer_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if tl <= 30 else Color.WHITE)
	score_label.text = score_text
	if p:
		bars.hp = clampf(float(p.hp) / Catalog.MAX_HEALTH, 0.0, 1.0) if p.alive else 0.0
		bars.fuel = p.fuel
		var w := p.weapon_data()
		bars.weapon_name = str(w["name"])
		bars.ammo_text = "RELOADING" if p.reloading > 0.0 else "%d / %d" % [p.ammo[p.slot], int(w["mag"])]
		bars.reload_frac = 1.0 - p.reloading / float(w["reload"]) if p.reloading > 0.0 else 0.0
		bars.queue_redraw()
	if _center_until > 0.0 and Time.get_ticks_msec() / 1000.0 > _center_until:
		_center_until = 0.0
		center_label.text = ""


func show_center(text: String, seconds: float = 0.0) -> void:
	center_label.text = text
	_center_until = (Time.get_ticks_msec() / 1000.0 + seconds) if seconds > 0.0 else 0.0


func add_kill(text: String, color: Color = Color.WHITE) -> void:
	var l := UIKit.label(text, 16, color, HORIZONTAL_ALIGNMENT_RIGHT)
	_outline(l)
	feed.add_child(l)
	while feed.get_child_count() > 5:
		feed.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


## rows: Array of {name, kills, deaths, color, me}
func set_scoreboard(title: String, rows: Array) -> void:
	UIKit.clear(score_rows)
	score_rows.add_child(UIKit.label(title, 24, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	var head := _row("PLAYER", "K", "D", UIKit.MUTED)
	score_rows.add_child(head)
	for r in rows:
		var col: Color = r["color"]
		if r.get("me", false):
			col = col.lightened(0.35)
		score_rows.add_child(_row(("> " if r.get("me", false) else "") + str(r["name"]), str(r["kills"]), str(r["deaths"]), col))


func _row(a: String, b: String, c: String, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	var la := UIKit.label(a, 18, col)
	la.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(la)
	var lb := UIKit.label(b, 18, col, HORIZONTAL_ALIGNMENT_RIGHT)
	lb.custom_minimum_size.x = 60
	h.add_child(lb)
	var lc := UIKit.label(c, 18, col, HORIZONTAL_ALIGNMENT_RIGHT)
	lc.custom_minimum_size.x = 60
	h.add_child(lc)
	return h


func show_results(title: String, title_color: Color, rows: Array, reward: Dictionary, is_host: bool) -> void:
	pause_panel.visible = false
	scoreboard.visible = false
	touch.reset()
	UIKit.clear(results_box)
	results_box.add_child(UIKit.label(title, 40, title_color, HORIZONTAL_ALIGNMENT_CENTER))
	var sb := VBoxContainer.new()
	sb.add_theme_constant_override("separation", 2)
	sb.custom_minimum_size = Vector2(520, 0)
	sb.add_child(_row("PLAYER", "K", "D", UIKit.MUTED))
	for r in rows.slice(0, 8):
		var col: Color = r["color"]
		sb.add_child(_row(("> " if r.get("me", false) else "") + str(r["name"]), str(r["kills"]), str(r["deaths"]), col))
	results_box.add_child(sb)
	results_box.add_child(UIKit.label("+%d MFC     +%d Gems" % [int(reward.get("mfc", 0)), int(reward.get("gems", 0))], 28, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	var wait := "Returning to lobby..." if is_host else "Waiting for host..."
	results_box.add_child(UIKit.label(wait, 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	results_panel.visible = true
