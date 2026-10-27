class_name DebugOverlay
extends CanvasLayer
## Debug overlay (§4.12), F1 on desktop or a three-finger tap on device: FPS, tick and the local
## fighter's state; a slider for every Tuning value; save/load tuning presets; world debug drawing.
## Touches on the panel are taken by the GUI, so they never reach the TouchRouter.

signal world_debug_toggled(enabled: bool)

const FONT_SIZE: int = 20
const PANEL_WIDTH: float = 600.0

var sim: MatchSim
var player: Fighter

var _info: Label
var _grid: GridContainer
var _preset_name: LineEdit
var _preset_list: OptionButton
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = Settings.show_debug

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font_size = FONT_SIZE
	root.theme = ui_theme
	add_child(root)

	_info = Label.new()
	_info.position = Vector2(140, 24)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_constant_override("outline_size", 6)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(_info)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH - 16.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.offset_bottom = -16.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.85)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var save_row := HBoxContainer.new()
	column.add_child(save_row)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "preset name"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_preset_name)
	_add_button(save_row, "Save", _on_save_preset)

	var load_row := HBoxContainer.new()
	column.add_child(load_row)
	_preset_list = OptionButton.new()
	_preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_preset_list)
	_add_button(load_row, "Load", _on_load_preset)
	_add_button(load_row, "Defaults", TuningDB.reset_to_default)

	var world_debug := CheckBox.new()
	world_debug.text = "World debug (hitboxes, anchors, aim assist)"
	world_debug.toggled.connect(func(on: bool) -> void: world_debug_toggled.emit(on))
	column.add_child(world_debug)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_build_sliders()
	_refresh_presets()
	TuningDB.changed.connect(_sync_sliders)
	Settings.changed.connect(func() -> void: visible = Settings.show_debug)


func toggle() -> void:
	visible = not visible
	Settings.show_debug = visible
	Settings.save_settings()


func _process(_delta: float) -> void:
	if visible:
		_info.text = _info_text()


func _info_text() -> String:
	var lines := PackedStringArray()
	lines.append("FPS %d   tick %d" % [Engine.get_frames_per_second(), sim.tick if sim != null else 0])
	if player == null:
		return "\n".join(lines)
	var tick := sim.tick if sim != null else 0
	var rope := player.rope
	lines.append("state %s   speed %d" % [SimIds.FighterState.keys()[player.state], roundi(player.velocity.length())])
	var rope_line := "rope %s" % SimIds.RopeState.keys()[rope.state]
	if rope.is_attached():
		rope_line += " %s  len %d" % [SimIds.RopeMode.keys()[rope.mode], roundi(rope.length)]
	if rope.is_out():
		rope_line += "  latched" if rope.latched else "  held"
	lines.append(rope_line)
	var cooldown := maxf(0.0, float(player.rope_cooldown_until_tick - tick) / SimIds.TICK_RATE)
	lines.append("cooldown %.2f s   cling %.2f s" % [cooldown, maxf(0.0, float(player.cling_ticks_left) / SimIds.TICK_RATE) if player.is_clinging() else 0.0])
	lines.append("hp %d   melee %s   freeze %d" % [ceili(player.hp), SimIds.MeleePhase.keys()[player.melee_phase(tick)], player.freeze_ticks])
	if sim != null:
		for other in sim.fighters:
			if other != player:
				lines.append("enemy %d: %s  hp %d%s" % [other.fighter_id, SimIds.FighterState.keys()[other.state], ceili(other.hp), "  pull-immune" if other.is_pull_immune(tick) else ""])
	return "\n".join(lines)


func _build_sliders() -> void:
	var group := ""
	for prop in TuningDB.t.get_property_list():
		var usage: int = prop["usage"]
		var prop_name: String = prop["name"]
		if usage & PROPERTY_USAGE_GROUP:
			group = prop_name
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or prop["hint"] != PROPERTY_HINT_RANGE:
			continue
		if not group.is_empty():
			_add_group_header(group)
			group = ""
		var range_parts: PackedStringArray = String(prop["hint_string"]).split(",")
		var name_label := Label.new()
		name_label.text = prop_name
		name_label.custom_minimum_size.x = 250.0
		_grid.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = float(range_parts[0])
		slider.max_value = float(range_parts[1])
		slider.step = float(range_parts[2]) if range_parts.size() > 2 else 0.01
		slider.custom_minimum_size = Vector2(200, 32)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value = TuningDB.t.get(prop_name)
		slider.value_changed.connect(_on_slider_changed.bind(prop_name))
		_grid.add_child(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 80.0
		_grid.add_child(value_label)
		_sliders[prop_name] = slider
		_value_labels[prop_name] = value_label
		_show_value(prop_name)


func _add_group_header(text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	_grid.add_child(header)
	_grid.add_child(Control.new())
	_grid.add_child(Control.new())


func _on_slider_changed(value: float, prop_name: String) -> void:
	if TuningDB.t.get(prop_name) is int:
		TuningDB.t.set(prop_name, roundi(value))
	else:
		TuningDB.t.set(prop_name, value)
	_show_value(prop_name)


func _sync_sliders() -> void:
	for prop_name: String in _sliders:
		var slider: HSlider = _sliders[prop_name]
		slider.set_value_no_signal(TuningDB.t.get(prop_name))
		_show_value(prop_name)


func _show_value(prop_name: String) -> void:
	var label: Label = _value_labels[prop_name]
	var value: Variant = TuningDB.t.get(prop_name)
	label.text = str(value) if value is int else "%.3f" % value


func _refresh_presets() -> void:
	_preset_list.clear()
	for preset in TuningDB.list_presets():
		_preset_list.add_item(preset)


func _on_save_preset() -> void:
	if TuningDB.save_preset(_preset_name.text) == OK:
		_refresh_presets()


func _on_load_preset() -> void:
	if _preset_list.selected >= 0:
		TuningDB.load_preset(_preset_list.get_item_text(_preset_list.selected))


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
