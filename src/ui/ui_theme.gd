class_name UiTheme
## The game's look for menus and the HUD: Kenney's Kenvector font on dark rounded tiles, with one
## filled green button for the main action on each screen. Built once in code and shared.

const FONT: Font = preload("res://assets/fonts/kenvector_future.ttf")
const FONT_THIN: Font = preload("res://assets/fonts/kenvector_future_thin.ttf")

const ACCENT: Color = Color("7be0a8")
const ACCENT_2: Color = Color("ff8fc0")
const TEXT: Color = Color("eef2ff")
const TEXT_DIM: Color = Color(0.93, 0.95, 1.0, 0.55)
const BUTTON_TEXT: Color = Color("1b2238")
const PANEL: Color = Color(0.05, 0.06, 0.12, 0.88)
## Button and card fills and their thin outline.
const SURFACE: Color = Color(0.10, 0.11, 0.21, 0.94)
const SURFACE_HI: Color = Color(0.15, 0.17, 0.30, 0.96)
const LINE: Color = Color(1, 1, 1, 0.12)
const FONT_SIZE: int = 30

## Okabe-Ito colors for colorblind-safe mode (§6.7): one per player slot / skin, and the two teams.
const SAFE_PLAYER_COLORS: Dictionary = {
	&"alien_green": Color("56b4e9"), &"alien_pink": Color("e69f00"), &"alien_yellow": Color("f0e442"), &"alien_purple": Color("cc79a7"),
}
const TEAM_COLORS: Array[Color] = [Color(0.35, 0.65, 1.0), Color(1.0, 0.4, 0.35)]
const SAFE_TEAM_COLORS: Array[Color] = [Color("0072b2"), Color("e69f00")]

## Theme type variations: button.theme_type_variation = UiTheme.PRIMARY.
const PRIMARY: StringName = &"PrimaryButton"
const GHOST: StringName = &"GhostButton"
const CARD: StringName = &"Card"

static var _theme: Theme


## A fighter's color on ropes, the HUD, markers and the minimap.
static func player_color(skin_id: StringName) -> Color:
	if Settings.colorblind and SAFE_PLAYER_COLORS.has(skin_id):
		return SAFE_PLAYER_COLORS[skin_id]
	var skin := SkinDef.load_by_id(skin_id)
	return skin.rope_color if skin != null else Color.WHITE


static func team_color(team: int) -> Color:
	var colors := SAFE_TEAM_COLORS if Settings.colorblind else TEAM_COLORS
	return colors[team % colors.size()]


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = FONT_SIZE

	# Buttons: dark rounded tiles. A pressed toggle (the picked mode, arena or level) glows green.
	t.set_stylebox(&"normal", &"Button", _flat(SURFACE, LINE, 2))
	t.set_stylebox(&"hover", &"Button", _flat(SURFACE_HI, Color(ACCENT, 0.55), 2))
	t.set_stylebox(&"pressed", &"Button", _flat(Color(0.12, 0.26, 0.24, 0.96), ACCENT, 3))
	t.set_stylebox(&"hover_pressed", &"Button", _flat(Color(0.14, 0.30, 0.27, 0.96), ACCENT, 3))
	t.set_stylebox(&"disabled", &"Button", _flat(Color(SURFACE, 0.5), Color(LINE, 0.05), 2))
	t.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	for c in [&"font_color", &"font_focus_color"]:
		t.set_color(c, &"Button", TEXT)
	t.set_color(&"font_hover_color", &"Button", Color.WHITE)
	t.set_color(&"font_pressed_color", &"Button", ACCENT)
	t.set_color(&"font_hover_pressed_color", &"Button", ACCENT)
	t.set_color(&"font_disabled_color", &"Button", Color(TEXT, 0.3))

	# The one main action on a screen (PLAY, START, HOST): filled green with dark text.
	t.set_type_variation(PRIMARY, &"Button")
	t.set_stylebox(&"normal", PRIMARY, _flat(ACCENT, Color.TRANSPARENT, 0))
	t.set_stylebox(&"hover", PRIMARY, _flat(ACCENT.lightened(0.15), Color.TRANSPARENT, 0))
	t.set_stylebox(&"pressed", PRIMARY, _flat(ACCENT.darkened(0.15), Color.TRANSPARENT, 0))
	t.set_stylebox(&"hover_pressed", PRIMARY, _flat(ACCENT.darkened(0.15), Color.TRANSPARENT, 0))
	t.set_stylebox(&"disabled", PRIMARY, _flat(Color(ACCENT, 0.2), Color.TRANSPARENT, 0))
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		t.set_color(c, PRIMARY, BUTTON_TEXT)
	t.set_color(&"font_disabled_color", PRIMARY, Color(TEXT, 0.35))

	# Back and other quiet actions: text only until hovered.
	t.set_type_variation(GHOST, &"Button")
	var ghost := _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0)
	t.set_stylebox(&"normal", GHOST, ghost)
	t.set_stylebox(&"disabled", GHOST, ghost)
	t.set_stylebox(&"hover", GHOST, _flat(Color(1, 1, 1, 0.06), Color.TRANSPARENT, 0))
	t.set_stylebox(&"pressed", GHOST, _flat(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0))
	t.set_stylebox(&"hover_pressed", GHOST, _flat(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0))
	for c in [&"font_color", &"font_focus_color"]:
		t.set_color(c, GHOST, Color(TEXT, 0.75))
	for c in [&"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		t.set_color(c, GHOST, Color.WHITE)

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(18)
	panel.set_border_width_all(3)
	panel.border_color = Color(ACCENT, 0.6)
	panel.set_content_margin_all(36)
	t.set_stylebox(&"panel", &"PanelContainer", panel)

	# A quiet box that groups part of a screen (the join code, the player list).
	t.set_type_variation(CARD, &"PanelContainer")
	var card := _flat(Color(0.06, 0.07, 0.14, 0.82), LINE, 2)
	card.set_corner_radius_all(20)
	card.set_content_margin_all(28)
	t.set_stylebox(&"panel", CARD, card)

	var field := _flat(Color(0, 0, 0, 0.35), LINE, 2)
	field.content_margin_left = 20
	field.content_margin_right = 20
	t.set_stylebox(&"normal", &"LineEdit", field)
	t.set_stylebox(&"focus", &"LineEdit", _flat(Color.TRANSPARENT, ACCENT, 2))
	t.set_stylebox(&"read_only", &"LineEdit", field)
	t.set_color(&"font_color", &"LineEdit", TEXT)
	t.set_color(&"font_placeholder_color", &"LineEdit", Color(TEXT, 0.35))
	t.set_color(&"caret_color", &"LineEdit", ACCENT)
	t.set_color(&"selection_color", &"LineEdit", Color(ACCENT, 0.35))

	t.set_color(&"font_color", &"Label", TEXT)
	t.set_color(&"font_color", &"CheckButton", TEXT)
	t.set_color(&"font_hover_color", &"CheckButton", ACCENT)
	t.set_color(&"font_pressed_color", &"CheckButton", TEXT)
	t.set_color(&"font_hover_pressed_color", &"CheckButton", ACCENT)
	# CheckButton inherits Button's styles: give it a quiet row instead of the white Kenney button.
	var row := StyleBoxFlat.new()
	row.bg_color = Color(1, 1, 1, 0.05)
	row.set_corner_radius_all(10)
	row.set_content_margin_all(12)
	var row_hover := row.duplicate() as StyleBoxFlat
	row_hover.bg_color = Color(1, 1, 1, 0.1)
	for state in [&"normal", &"pressed", &"disabled"]:
		t.set_stylebox(state, &"CheckButton", row)
	for state in [&"hover", &"hover_pressed"]:
		t.set_stylebox(state, &"CheckButton", row_hover)
	t.set_stylebox(&"focus", &"CheckButton", StyleBoxEmpty.new())

	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox(&"slider", &"HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	_theme = t
	return t


static func _flat(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(14)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	box.anti_aliasing = true
	return box


## A label with the game's usual settings.
static func label(text: String, size: int, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A small dim caption over a group of controls (MODE, ARENA, BOTS).
static func caption(text: String) -> Label:
	return label(text, 20, Color(ACCENT, 0.8), HORIZONTAL_ALIGNMENT_LEFT)


## A button that clicks when pressed. variation is PRIMARY, GHOST or empty for a normal tile.
static func button(text: String, action: Callable, variation: StringName = &"", min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.pressed.connect(func() -> void:
		Sfx.play(&"ui_click", Vector2.ZERO)
		action.call())
	return b


## A drawn triangle pointing left (-1) or right (1); the menu font has no arrow characters.
static func arrow(direction: int, size: float = 18.0, color: Color = TEXT) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var mid := c.size * 0.5
		var h := size * 0.5
		var tip := Vector2(h * 0.8 * direction, 0)
		c.draw_colored_polygon(PackedVector2Array([mid + tip, mid + Vector2(-tip.x, -h), mid + Vector2(-tip.x, h)]), color))
	return c


## The ghost BACK button in a screen's top-left corner, with a drawn arrow.
static func back_button(action: Callable, text: String = "BACK") -> Button:
	var b := button(text, action, GHOST, Vector2(0, 72))
	b.add_theme_font_size_override("font_size", 26)
	# Room on the left for the arrow.
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var box := get_theme().get_stylebox(state, GHOST).duplicate() as StyleBox
		box.content_margin_left = 64
		b.add_theme_stylebox_override(state, box)
	var glyph := arrow(-1, 20.0)
	glyph.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	glyph.offset_left = 26
	glyph.offset_top = -10
	glyph.offset_right = 46
	glyph.offset_bottom = 10
	b.add_child(glyph)
	return b
