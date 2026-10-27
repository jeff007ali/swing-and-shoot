class_name SettingsScreen
extends CanvasLayer
## Settings (§4.12): haptics, SFX and music volume, left-handed buttons, button size, colorblind
## colors (§6.7), debug overlay, playtest logging. Changes apply at
## once and are saved on close. Opened from the main menu and the pause menu, so it runs while paused.

signal closed

const ROW_WIDTH: float = 760.0
const MIN_BUTTON_SCALE: float = 0.7
const MAX_BUTTON_SCALE: float = 1.5


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = ROW_WIDTH
	panel.add_child(box)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)

	_toggle(box, "Haptics", Settings.haptics_enabled, func(on: bool) -> void: Settings.haptics_enabled = on)
	_slider(box, "SFX volume", Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v)
	_slider(box, "Music volume", Settings.music_volume, func(v: float) -> void: Settings.music_volume = v)
	_toggle(box, "Left-handed buttons", Settings.left_handed, func(on: bool) -> void: Settings.left_handed = on)
	_slider(box, "Button size", inverse_lerp(MIN_BUTTON_SCALE, MAX_BUTTON_SCALE, Settings.button_scale), func(v: float) -> void: Settings.button_scale = lerpf(MIN_BUTTON_SCALE, MAX_BUTTON_SCALE, v))
	_toggle(box, "Rope stick (drag to aim the rope)", Settings.rope_stick, func(on: bool) -> void: Settings.rope_stick = on)
	_toggle(box, "Colorblind-safe colors", Settings.colorblind, func(on: bool) -> void: Settings.colorblind = on)
	_toggle(box, "Show debug overlay", Settings.show_debug, func(on: bool) -> void: Settings.show_debug = on)
	_toggle(box, "Playtest logging", Settings.playtest_logging, func(on: bool) -> void: Settings.playtest_logging = on)

	var done := Button.new()
	done.text = "DONE"
	done.custom_minimum_size = Vector2(320, 84)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(close)
	box.add_child(done)


func open() -> void:
	visible = true


func close() -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	Settings.save_settings()
	visible = false
	closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


func _toggle(parent: Control, text: String, value: bool, apply: Callable) -> void:
	var toggle := CheckButton.new()
	toggle.text = text
	toggle.button_pressed = value
	toggle.toggled.connect(func(on: bool) -> void:
		apply.call(on)
		Settings.apply()
		Sfx.play(&"ui_click", Vector2.ZERO))
	parent.add_child(toggle)


func _slider(parent: Control, text: String, value: float, apply: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 340
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 40
	slider.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		Settings.apply())
	slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.play(&"ui_click", Vector2.ZERO))
	row.add_child(slider)
