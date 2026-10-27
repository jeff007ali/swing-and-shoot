class_name ResultsScreen
extends CanvasLayer
## End of match (§6.5): who won, the final ranking with scores, the match length, and Rematch
## (offline) or Main Menu. Opened by the match with the MatchResult record it just saved.

signal rematch_requested
signal main_menu_requested

## LAN matches can't be restarted from here: everyone goes back to the menu.
var allow_rematch: bool = true

var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _rematch: Button


func _ready() -> void:
	layer = 25
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
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	_title = _label("", 64, UiTheme.ACCENT)
	box.add_child(_title)
	_subtitle = _label("", 24, UiTheme.TEXT_DIM)
	box.add_child(_subtitle)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	box.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	_rematch = _button("REMATCH", func() -> void: rematch_requested.emit())
	_rematch.theme_type_variation = UiTheme.PRIMARY
	buttons.add_child(_rematch)
	buttons.add_child(_button("MAIN MENU", func() -> void: main_menu_requested.emit()))


## The big line: VICTORY / DEFEAT / DRAW, or which team won.
static func headline(result: Dictionary) -> String:
	var winner: int = result.get("winner", -1)
	if winner < 0:
		return "DRAW"
	if result.get("local_key", -2) == winner:
		return "VICTORY!"
	return "DEFEAT"


func open(result: Dictionary, mode: GameMode) -> void:
	_title.text = headline(result)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT if _title.text != "DEFEAT" else UiTheme.ACCENT_2)
	var seconds := int(result.get("duration", 0.0))
	_subtitle.text = "%s  ·  %d:%02d" % [mode.def.display_name.to_upper(), seconds / 60, seconds % 60]
	for child in _rows.get_children():
		child.queue_free()
	var place := 1
	for row: Dictionary in result["ranking"]:
		var line := HBoxContainer.new()
		var is_local: bool = row["key"] == result.get("local_key", -2)
		var color := UiTheme.ACCENT if is_local else UiTheme.TEXT
		if mode.is_team_mode():
			color = UiTheme.team_color(int(row["key"]))
		var who := _label("%d.  %s" % [place, String(row["name"]).to_upper()], 32, color)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(who)
		var score := _label(String(row["score"]), 32, color)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(score)
		_rows.add_child(line)
		place += 1
	_rematch.visible = allow_rematch
	visible = true
	if allow_rematch:
		_rematch.grab_focus.call_deferred()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 80)
	b.pressed.connect(func() -> void:
		Sfx.play(&"ui_click", Vector2.ZERO)
		action.call())
	return b
