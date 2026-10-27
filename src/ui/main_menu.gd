class_name MainMenu
extends Control
## Main menu (§4.12). Home: PLAY, then Tutorial (marked NEW until finished once, §6.7), Free Fly and
## LAN Party, with Settings in the corner. PLAY opens the match setup page (§6.5): the mode, the arena
## and the bot level, then START. The picks go to Settings, which the match reads when it starts.

const MATCH_SCENE: String = "res://src/match/match.tscn"
const LOBBY_SCENE: String = "res://src/ui/lobby_screen.tscn"
const BACKGROUND: Texture2D = preload("res://assets/art/arena/darkPurple.png")
const STARFIELD: Script = preload("res://src/arenas/starfield.gd")
const FLOATERS: Array[StringName] = [&"alien_green", &"alien_pink", &"alien_yellow", &"alien_purple"]
## Floating astronauts in the background: drift speed (px/s) and spin (rad/s). Visual only.
const FLOAT_SPEED: float = 40.0
const FLOAT_SPIN: float = 0.4
## Space kept clear around the screen edge (phone notches and rounded corners).
const EDGE: Vector2 = Vector2(64, 40)

## Tests turn this off to check what a button does without leaving the scene.
var change_scene: bool = true
var setup: MatchSetup

var _home: Control
var _play: Control
var _summary: Label
var _version: Label
var _settings: SettingsScreen
var _floaters: Array[Sprite2D] = []
var _floater_velocity: Array[Vector2] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build_background()
	_build_home()
	_build_play()

	_version = Label.new()
	var version := _version
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0")
	version.add_theme_font_size_override("font_size", 22)
	version.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -EDGE.x
	version.offset_bottom = -EDGE.y * 0.5
	add_child(version)

	_settings = SettingsScreen.new()
	add_child(_settings)
	_show_home()


func _build_home() -> void:
	_home = Control.new()
	_home.set_anchors_preset(Control.PRESET_FULL_RECT)
	_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_home)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := UiTheme.label("SWING AND SHOOT", 100, UiTheme.ACCENT)
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.12))
	column.add_child(title)
	var subtitle := UiTheme.label("zero-g grapple brawler", 34, UiTheme.TEXT_DIM)
	subtitle.add_theme_font_override("font", UiTheme.FONT_THIN)
	column.add_child(subtitle)
	column.add_child(_spacer(40))

	var play := UiTheme.button("PLAY", _open_play, UiTheme.PRIMARY, Vector2(960, 124))
	play.name = "Play"
	play.add_theme_font_size_override("font_size", 52)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(play)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	var tutorial := UiTheme.button("TUTORIAL", func() -> void: start_match(&"tutorial"), &"", Vector2(304, 96))
	if not Settings.tutorial_done:
		tutorial.add_child(_badge("NEW"))
	row.add_child(tutorial)
	row.add_child(UiTheme.button("FREE FLY", func() -> void: start_match(&"free_fly"), &"", Vector2(304, 96)))
	row.add_child(UiTheme.button("LAN PARTY", _open_lobby, &"", Vector2(304, 96)))

	var settings := UiTheme.button("SETTINGS", _open_settings, UiTheme.GHOST, Vector2(0, 72))
	settings.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	settings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	settings.offset_right = -EDGE.x * 0.5
	settings.offset_top = EDGE.y * 0.5
	settings.add_theme_font_size_override("font_size", 24)
	_home.add_child(settings)


func _build_play() -> void:
	_play = MarginContainer.new()
	_play.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		_play.add_theme_constant_override("margin_" + side, int(EDGE.x))
	for side in ["top", "bottom"]:
		_play.add_theme_constant_override("margin_" + side, int(EDGE.y))
	add_child(_play)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	_play.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	column.add_child(header)
	header.add_child(UiTheme.back_button(_show_home))
	header.add_child(UiTheme.label("PLAY", 56, UiTheme.ACCENT))

	column.add_child(_expander())
	setup = MatchSetup.new(false, StringName(Settings.play_mode), StringName(Settings.last_arena), Settings.bot_difficulty)
	setup.changed.connect(_on_setup_changed)
	column.add_child(setup)
	column.add_child(_expander())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 32)
	column.add_child(footer)
	_summary = UiTheme.label("", 24, UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_summary)
	var start := UiTheme.button("START", func() -> void: start_match(setup.mode_id), UiTheme.PRIMARY, Vector2(440, 104))
	start.name = "Start"
	start.add_theme_font_size_override("font_size", 44)
	footer.add_child(start)
	_summary.text = setup.summary()


func _process(delta: float) -> void:
	var area := get_viewport_rect().size
	for i in _floaters.size():
		var s := _floaters[i]
		s.position += _floater_velocity[i] * delta
		s.rotation += FLOAT_SPIN * delta * (1.0 if i % 2 == 0 else -1.0)
		s.position.x = wrapf(s.position.x, -100.0, area.x + 100.0)
		s.position.y = wrapf(s.position.y, -100.0, area.y + 100.0)


## Saves the mode and opens the match (the bots use the picked difficulty).
func start_match(mode: StringName) -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	Settings.last_mode = String(mode)
	Settings.save_settings()
	if change_scene:
		get_tree().change_scene_to_file(MATCH_SCENE)


func _on_setup_changed() -> void:
	Settings.play_mode = String(setup.mode_id)
	Settings.last_arena = String(setup.arena_id)
	Settings.bot_difficulty = setup.difficulty
	Settings.save_settings()
	_summary.text = setup.summary()


func _open_play() -> void:
	_set_page(false)
	(_play.find_child("Start", true, false) as Button).grab_focus.call_deferred()


func _show_home() -> void:
	_set_page(true)
	(_home.find_child("Play", true, false) as Button).grab_focus.call_deferred()


## The floating astronauts and the version only show on the home page, behind nothing important.
func _set_page(home: bool) -> void:
	_home.visible = home
	_play.visible = not home
	_version.visible = home
	for s in _floaters:
		s.visible = home


func _open_lobby() -> void:
	if change_scene:
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _open_settings() -> void:
	_settings.open()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _settings == null or _settings.visible:
		return
	if _play.visible:
		_show_home()
	else:
		get_tree().quit()


## A small pink tag on a button's top-right corner.
func _badge(text: String) -> Control:
	var tag := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.ACCENT_2
	box.set_corner_radius_all(10)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	tag.add_theme_stylebox_override("panel", box)
	tag.add_child(UiTheme.label(text, 16, UiTheme.BUTTON_TEXT))
	tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tag.offset_top = -12
	tag.offset_right = 12
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tag


func _expander() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


func _build_background() -> void:
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var stars := Node2D.new()
	stars.set_script(STARFIELD)
	add_child(stars)
	var area := Vector2(1920, 1080)
	for i in FLOATERS.size():
		var skin := SkinDef.load_by_id(FLOATERS[i])
		if skin == null:
			continue
		var s := Sprite2D.new()
		s.texture = skin.sprite_frames.get_frame_texture(&"kick", 0)
		s.scale = Vector2.ONE * skin.sprite_scale * 1.2
		s.modulate = Color(1, 1, 1, 0.45)
		s.position = Vector2(area.x * (0.12 + 0.25 * i), area.y * (0.2 + 0.6 * float(i % 2)))
		add_child(s)
		_floaters.append(s)
		_floater_velocity.append(Vector2.from_angle(0.7 + i * 1.9) * FLOAT_SPEED)
