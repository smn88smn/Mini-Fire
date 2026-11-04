extends Node
## Captures screenshots of every screen (needs a display, e.g. xvfb-run).

const OUT := "/tmp/shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + n + ".png")
	print("[SHOT] ", n)


func _run() -> void:
	Profile.mfc = 1500
	Profile.gems = 90
	await _wait(1.0)
	await _shot("01_menu")
	var menu = get_tree().current_scene
	menu._show_join()
	await _wait(0.5)
	await _shot("02_join")
	menu._show_settings()
	await _wait(0.3)
	await _shot("03_settings")
	menu._show_home()
	menu._open_shop()
	await _wait(0.5)
	await _shot("04_shop")
	var shop: ShopPanel = null
	for c in menu.get_children():
		if c is ShopPanel:
			shop = c
	# drag-scroll the skins grid with the mouse (same code path as a finger)
	var start := Vector2(800, 560)
	_mouse_btn(start, true)
	for i in 12:
		await get_tree().process_frame
		_mouse_move(start - Vector2(0, 30 * (i + 1)))
	_mouse_btn(start - Vector2(0, 360), false)
	await _wait(0.6)
	await _shot("04b_shop_scrolled")
	shop._tab = "powers"
	shop._refresh()
	await _wait(0.3)
	await _shot("04c_powers")
	shop._tab = "gems"
	shop._refresh()
	await _wait(0.3)
	await _shot("04d_gems")
	shop._close()
	await _wait(0.3)
	Network.host_practice()
	await _wait(1.0)
	Network.set_setting("mode", 1)
	await _wait(0.5)
	await _shot("05_lobby")
	Profile.touch_controls = 1
	Network.start_match()
	await _wait(6.0)
	await _shot("06_game_touch")
	var g = get_tree().root.get_node("Game")
	g.hud.scoreboard.visible = true
	await _wait(0.7)
	await _shot("07_scoreboard")
	g.hud.scoreboard.visible = false
	g.hud.toggle_pause()
	await _wait(0.3)
	await _shot("08_pause")
	g.hud.toggle_pause()
	g.hud.touch.visible = false
	await _wait(3.0)
	await _shot("09_game_pc")
	g.time_left = 0.0
	await _wait(1.0)
	await _shot("10_results")
	Profile.touch_controls = 0
	get_tree().quit(0)


func _mouse_btn(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func _mouse_move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
