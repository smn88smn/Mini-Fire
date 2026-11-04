class_name ControlsEditor
extends Control
## Full-screen editor for the touch layout: drag any control to move it,
## select one and use the slider to resize it. SAVE stores it in the profile.

var _touch: TouchControls
var _slider: HSlider
var _sel_label: Label
var _syncing := false


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	bg.texture = load("res://assets/bg/warzone.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_touch = TouchControls.new()
	_touch.editing = true
	_touch.visible = true
	add_child(_touch)
	_touch.selection_changed.connect(_on_select)
	# toolbar
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.glass_panel())
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.offset_top = 150
	bar.custom_minimum_size = Vector2(620, 0)
	add_child(bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bar.add_child(v)
	v.add_child(UIKit.label("EDIT CONTROLS", 26, UIKit.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	var hint := UIKit.label("Drag a control to move it. Tap one, then use the slider to resize.", 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var sr := HBoxContainer.new()
	_sel_label = UIKit.label("SIZE", 18, UIKit.TEXT)
	_sel_label.custom_minimum_size = Vector2(170, 0)
	sr.add_child(_sel_label)
	_slider = HSlider.new()
	_slider.min_value = TouchControls.MIN_SCALE
	_slider.max_value = TouchControls.MAX_SCALE
	_slider.step = 0.05
	_slider.value = 1.0
	_slider.editable = false
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(0, 44)
	_slider.value_changed.connect(func(val: float):
		if not _syncing:
			_touch.set_control_scale(_touch.selected, val))
	sr.add_child(_slider)
	v.add_child(sr)
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_theme_constant_override("separation", 12)
	br.add_child(UIKit.glass_button("RESET", "red", func():
		_touch.reset_layout()
		_on_select(_touch.selected), Vector2(150, 56), 20))
	br.add_child(UIKit.glass_button("CANCEL", "dark", queue_free, Vector2(150, 56), 20))
	br.add_child(UIKit.glass_button("SAVE", "green", func():
		_touch.save_layout()
		UIKit.toast(get_parent(), "Controls saved", UIKit.GOOD)
		queue_free(), Vector2(150, 56), 20))
	v.add_child(br)


func _on_select(id: String) -> void:
	if id == "":
		return
	_syncing = true
	_slider.editable = true
	_slider.value = _touch.scale_of(id)
	_sel_label.text = str(TouchControls.LABELS[id])
	_syncing = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		queue_free()
