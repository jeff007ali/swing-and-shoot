class_name MatchSetup
extends HBoxContainer
## The match picker shared by PLAY and LAN hosting (§4.12): mode tiles on the left, the arena with
## its thumbnail and the bot level on the right. Owners read the picks and save them on `changed`.

signal changed

const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
const TILE_SIZE: Vector2 = Vector2(260, 112)
const THUMB_SIZE: Vector2 = Vector2(480, 270)
## Compact sizes, for the LAN host page where the join code shares the row.
const COMPACT_TILE_SIZE: Vector2 = Vector2(220, 100)
const COMPACT_THUMB_SIZE: Vector2 = Vector2(352, 198)

var mode_id: StringName = &""
var arena_id: StringName = ArenaRegistry.DEFAULT
var difficulty: String = "normal"
## LAN only: fill empty slots with bots.
var fill_bots: bool = true

## mode id -> tile Button
var mode_buttons: Dictionary = {}
## level -> Button
var difficulty_buttons: Dictionary = {}

var _lan: bool
var _tile_size: Vector2 = TILE_SIZE
var _thumb_size: Vector2 = THUMB_SIZE
var _mode_info: Label
var _thumb: TextureRect
var _arena_name: Label
var _arena_blurb: Label
var _dots: HBoxContainer
var _fill_toggle: CheckButton


## lan: list the LAN modes and show the bot-fill switch instead of the offline modes.
func _init(lan: bool = false, start_mode: StringName = &"", start_arena: StringName = ArenaRegistry.DEFAULT, start_difficulty: String = "normal", compact: bool = false) -> void:
	_lan = lan
	if compact:
		_tile_size = COMPACT_TILE_SIZE
		_thumb_size = COMPACT_THUMB_SIZE
	add_theme_constant_override("separation", 40 if compact else 48)
	alignment = BoxContainer.ALIGNMENT_CENTER
	var modes := modes_for(lan)
	_build_modes(modes)
	_build_right()
	var ids := modes.map(func(d: ModeDef) -> StringName: return d.id)
	show_mode(start_mode if start_mode in ids else ids[0])
	show_arena(start_arena if start_arena in ArenaRegistry.ids() else ArenaRegistry.DEFAULT)
	show_difficulty(start_difficulty if start_difficulty in DIFFICULTIES else "normal")


## The modes this picker offers, in menu order.
static func modes_for(lan: bool) -> Array[ModeDef]:
	var out: Array[ModeDef] = []
	for def in ModeDef.all():
		if (def.lan if lan else def.offline and def.id != &"free_fly"):
			out.append(def)
	return out


## A short "who plays" tag for a mode tile.
static func mode_tag(def: ModeDef) -> String:
	if def.enemy_slots > 0:
		return "CO-OP VS WAVES"
	if def.team_count == 2:
		return "2 VS 2"
	if def.players == 2:
		return "1 VS 1"
	return "%d FIGHTERS" % def.players


## One line for the footer: KING OF THE SWING · SOLAR · NORMAL BOTS.
func summary() -> String:
	var def := ModeDef.load_by_id(mode_id)
	var parts := PackedStringArray([def.display_name.to_upper() if def != null else "", String(ArenaRegistry.info(arena_id)["name"]).to_upper()])
	if not _lan or fill_bots:
		parts.append("%s BOTS" % difficulty.to_upper())
	return "  ·  ".join(parts)


func pick_mode(id: StringName) -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	show_mode(id)
	changed.emit()


func pick_arena(id: StringName) -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	show_arena(id)
	changed.emit()


func step_arena(step: int) -> void:
	var ids := ArenaRegistry.ids()
	pick_arena(ids[wrapi(ids.find(arena_id) + step, 0, ids.size())])


func pick_difficulty(level: String) -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	show_difficulty(level)
	changed.emit()


func show_mode(id: StringName) -> void:
	mode_id = id
	for key: StringName in mode_buttons:
		var tile := mode_buttons[key] as Button
		var on := key == id
		tile.set_pressed_no_signal(on)
		(tile.get_node("Text/Name") as Label).add_theme_color_override("font_color", UiTheme.ACCENT if on else UiTheme.TEXT)
	var def := ModeDef.load_by_id(id)
	_mode_info.text = def.description if def != null else ""


func show_arena(id: StringName) -> void:
	arena_id = id
	var info := ArenaRegistry.info(id)
	_thumb.texture = ArenaRegistry.thumbnail(id)
	_arena_name.text = String(info["name"]).to_upper()
	_arena_blurb.text = String(info.get("blurb", ""))
	var ids := ArenaRegistry.ids()
	for i in _dots.get_child_count():
		(_dots.get_child(i) as ColorRect).color = UiTheme.ACCENT if ids[i] == id else Color(1, 1, 1, 0.2)


func show_difficulty(level: String) -> void:
	difficulty = level
	for key: String in difficulty_buttons:
		(difficulty_buttons[key] as Button).set_pressed_no_signal(key == level)


func set_fill_bots(on: bool) -> void:
	fill_bots = on
	if _fill_toggle != null:
		_fill_toggle.set_pressed_no_signal(on)
	for b: Button in difficulty_buttons.values():
		b.disabled = not on


func _build_modes(modes: Array[ModeDef]) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	column.add_child(UiTheme.caption("MODE"))
	var grid := GridContainer.new()
	# Two rows: 7 offline modes fit 4 + 3, the 6 LAN modes 3 + 3.
	grid.columns = 4 if modes.size() > 6 else 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	column.add_child(grid)
	var group := ButtonGroup.new()
	for def in modes:
		var tile := Button.new()
		tile.toggle_mode = true
		tile.button_group = group
		tile.custom_minimum_size = _tile_size
		tile.pressed.connect(pick_mode.bind(def.id))
		var text := VBoxContainer.new()
		text.name = "Text"
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.add_theme_constant_override("separation", 6)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(text)
		var small := _tile_size.x < TILE_SIZE.x
		var title := UiTheme.label(def.short_name if not def.short_name.is_empty() else def.display_name.to_upper(), 26 if small else 28)
		title.name = "Name"
		text.add_child(title)
		text.add_child(UiTheme.label(mode_tag(def), 15 if small else 17, UiTheme.TEXT_DIM))
		grid.add_child(tile)
		mode_buttons[def.id] = tile
	_mode_info = UiTheme.label("", 22, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_mode_info.add_theme_font_override("font", UiTheme.FONT_THIN)
	_mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.custom_minimum_size = Vector2(_tile_size.x * grid.columns + 16 * (grid.columns - 1), 64)
	column.add_child(_mode_info)


func _build_right() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	column.add_child(UiTheme.caption("ARENA"))
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", 10)
	column.add_child(picker)
	picker.add_child(_arrow(-1))
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 6)
	picker.add_child(middle)
	var frame := PanelContainer.new()
	frame.theme_type_variation = UiTheme.CARD
	frame.add_theme_stylebox_override("panel", _thumb_frame())
	middle.add_child(frame)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = _thumb_size
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.mouse_filter = Control.MOUSE_FILTER_STOP
	_thumb.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			step_arena(1))
	frame.add_child(_thumb)
	_arena_name = UiTheme.label("", 30, UiTheme.TEXT)
	middle.add_child(_arena_name)
	_arena_blurb = UiTheme.label("", 20, UiTheme.TEXT_DIM)
	_arena_blurb.add_theme_font_override("font", UiTheme.FONT_THIN)
	_arena_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arena_blurb.custom_minimum_size.x = _thumb_size.x
	middle.add_child(_arena_blurb)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_dots.add_theme_constant_override("separation", 10)
	for i in ArenaRegistry.ARENAS.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(22, 6)
		_dots.add_child(dot)
	middle.add_child(_dots)
	picker.add_child(_arrow(1))

	column.add_child(_spacer(6))
	column.add_child(UiTheme.caption("BOTS"))
	if _lan:
		_fill_toggle = CheckButton.new()
		_fill_toggle.text = "Fill empty slots"
		_fill_toggle.add_theme_font_size_override("font_size", 22)
		_fill_toggle.button_pressed = fill_bots
		_fill_toggle.toggled.connect(func(on: bool) -> void:
			Sfx.play(&"ui_click", Vector2.ZERO)
			set_fill_bots(on)
			changed.emit())
		column.add_child(_fill_toggle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	for level in DIFFICULTIES:
		var b := Button.new()
		b.text = level.to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(160 if _thumb_size.x < THUMB_SIZE.x else 176, 64)
		b.pressed.connect(pick_difficulty.bind(level))
		row.add_child(b)
		difficulty_buttons[level] = b
	column.add_child(row)


func _arrow(step: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, _thumb_size.y + 8)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(step_arena.bind(step))
	var glyph := UiTheme.arrow(step, 22.0)
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(glyph)
	return b


func _thumb_frame() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.4)
	box.border_color = Color(UiTheme.ACCENT, 0.5)
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(4)
	return box


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c
