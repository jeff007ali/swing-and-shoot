class_name PauseMenu
extends CanvasLayer
## Pause menu (§4.12): Resume, Restart, Settings, Main Menu. Pausing stops MatchSim offline only; in a
## LAN match the game keeps running behind the menu and Restart is hidden.

signal restart_requested
signal main_menu_requested

var _settings: SettingsScreen
var _restart_button: Button
var _menu_button: Button

## LAN match: never pause the shared simulation.
var networked: bool = false:
	set(value):
		networked = value
		if _restart_button != null:
			_restart_button.visible = not value
			_menu_button.text = "LEAVE MATCH" if value else "MAIN MENU"


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)

	_add_button(box, "RESUME", close)
	_restart_button = _add_button(box, "RESTART", func() -> void: restart_requested.emit())
	_add_button(box, "SETTINGS", func() -> void: _settings.open())
	_menu_button = _add_button(box, "MAIN MENU", func() -> void: main_menu_requested.emit())

	_settings = SettingsScreen.new()
	add_child(_settings)


func open() -> void:
	visible = true
	if not networked:
		get_tree().paused = true


func close() -> void:
	visible = false
	if not networked:
		get_tree().paused = false


func toggle() -> void:
	if _settings.visible:
		return
	if visible:
		close()
	else:
		open()


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(480, 92)
	button.pressed.connect(func() -> void:
		Sfx.play(&"ui_click", Vector2.ZERO)
		action.call())
	parent.add_child(button)
	return button
