class_name UiTheme
## The game's look for menus and the HUD: Kenney's Kenvector font and Space Shooter buttons on dark
## translucent panels. Built once in code and shared.

const FONT: Font = preload("res://assets/fonts/kenvector_future.ttf")
const FONT_THIN: Font = preload("res://assets/fonts/kenvector_future_thin.ttf")
const BUTTON_NORMAL: Texture2D = preload("res://assets/art/ui/buttonBlue.png")
const BUTTON_HOVER: Texture2D = preload("res://assets/art/ui/buttonGreen.png")
const BUTTON_PRESSED: Texture2D = preload("res://assets/art/ui/buttonYellow.png")

const ACCENT: Color = Color("7be0a8")
const ACCENT_2: Color = Color("ff8fc0")
const TEXT: Color = Color("eef2ff")
const TEXT_DIM: Color = Color(0.93, 0.95, 1.0, 0.55)
const BUTTON_TEXT: Color = Color("1b2238")
const PANEL: Color = Color(0.05, 0.06, 0.12, 0.88)
const FONT_SIZE: int = 30

## Okabe-Ito colors for colorblind-safe mode (§6.7): one per player slot / skin, and the two teams.
const SAFE_PLAYER_COLORS: Dictionary = {
	&"alien_green": Color("56b4e9"), &"alien_pink": Color("e69f00"), &"alien_yellow": Color("f0e442"), &"alien_purple": Color("cc79a7"),
}
const TEAM_COLORS: Array[Color] = [Color(0.35, 0.65, 1.0), Color(1.0, 0.4, 0.35)]
const SAFE_TEAM_COLORS: Array[Color] = [Color("0072b2"), Color("e69f00")]

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

	t.set_stylebox(&"normal", &"Button", _button(BUTTON_NORMAL, Color.WHITE))
	t.set_stylebox(&"hover", &"Button", _button(BUTTON_HOVER, Color.WHITE))
	t.set_stylebox(&"pressed", &"Button", _button(BUTTON_PRESSED, Color.WHITE))
	t.set_stylebox(&"hover_pressed", &"Button", _button(BUTTON_PRESSED, Color.WHITE))
	t.set_stylebox(&"disabled", &"Button", _button(BUTTON_NORMAL, Color(1, 1, 1, 0.4)))
	t.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		t.set_color(c, &"Button", BUTTON_TEXT)
	t.set_color(&"font_disabled_color", &"Button", Color(BUTTON_TEXT, 0.5))

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(18)
	panel.set_border_width_all(3)
	panel.border_color = Color(ACCENT, 0.6)
	panel.set_content_margin_all(36)
	t.set_stylebox(&"panel", &"PanelContainer", panel)

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


static func _button(texture: Texture2D, modulate: Color) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.set_texture_margin_all(8)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	box.modulate_color = modulate
	return box
