class_name MainMenu
extends Control
## Main menu (§4.12): Free Fly, Tutorial (§6.7, marked NEW until finished once), Play with a mode picker (§6.5: Duel, Free-for-all, 2v2, King of the
## Swing, Hot Potato, Gun Game...), an Easy / Normal / Hard bot picker, an arena picker, LAN Party,
## Settings and the version. The picks go to Settings, which the match reads when it starts.

const MATCH_SCENE: String = "res://src/match/match.tscn"
const LOBBY_SCENE: String = "res://src/ui/lobby_screen.tscn"
const BACKGROUND: Texture2D = preload("res://assets/art/arena/darkPurple.png")
const STARFIELD: Script = preload("res://src/arenas/starfield.gd")
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
const FLOATERS: Array[StringName] = [&"alien_green", &"alien_pink", &"alien_yellow", &"alien_purple"]
## Floating astronauts in the background: drift speed (px/s) and spin (rad/s). Visual only.
const FLOAT_SPEED: float = 40.0
const FLOAT_SPIN: float = 0.4

## Tests turn this off to check what a button does without leaving the scene.
var change_scene: bool = true

var _difficulty_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _mode_info: Label
## The mode PLAY starts.
var _play_mode: StringName = &"vs_bot"
var _arena_buttons: Dictionary = {}
var _settings: SettingsScreen
var _floaters: Array[Sprite2D] = []
var _floater_velocity: Array[Vector2] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build_background()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)

	var title := Label.new()
	title.text = "SWING AND SHOOT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.12))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "zero-g grapple brawler"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", UiTheme.FONT_THIN)
	subtitle.add_theme_font_size_override("font_size", 34)
	subtitle.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	column.add_child(subtitle)
	column.add_child(_spacer(12))

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 20)
	var free_fly := _menu_button("FREE FLY", func() -> void: start_match(&"free_fly"))
	free_fly.custom_minimum_size.x = 380
	top.add_child(free_fly)
	var play := _menu_button("PLAY", func() -> void: start_match(_play_mode))
	play.custom_minimum_size.x = 380
	top.add_child(play)
	var tutorial := _menu_button("TUTORIAL" if Settings.tutorial_done else "TUTORIAL (NEW)", func() -> void: start_match(&"tutorial"))
	tutorial.custom_minimum_size.x = 380
	top.add_child(tutorial)
	column.add_child(top)

	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 12)
	var mode_group := ButtonGroup.new()
	for def in ModeDef.all():
		if not def.offline or def.id == &"free_fly":
			continue
		var b := Button.new()
		b.text = def.short_name if not def.short_name.is_empty() else def.display_name.to_upper()
		b.toggle_mode = true
		b.button_group = mode_group
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(170, 60)
		b.pressed.connect(_pick_mode.bind(def.id))
		modes.add_child(b)
		_mode_buttons[def.id] = b
	column.add_child(modes)
	_mode_info = Label.new()
	_mode_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_info.add_theme_font_override("font", UiTheme.FONT_THIN)
	_mode_info.add_theme_font_size_override("font_size", 22)
	_mode_info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	column.add_child(_mode_info)
	var last := StringName(Settings.last_mode)
	_show_mode(last if _mode_buttons.has(last) else &"vs_bot")

	var picker := HBoxContainer.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_theme_constant_override("separation", 14)
	var group := ButtonGroup.new()
	for level in DIFFICULTIES:
		var b := Button.new()
		b.text = level.to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(186, 56)
		b.pressed.connect(_pick_difficulty.bind(level))
		picker.add_child(b)
		_difficulty_buttons[level] = b
	column.add_child(picker)
	_show_difficulty(Settings.bot_difficulty if Settings.bot_difficulty in DIFFICULTIES else "normal")

	var arenas := HBoxContainer.new()
	arenas.alignment = BoxContainer.ALIGNMENT_CENTER
	arenas.add_theme_constant_override("separation", 14)
	var arena_group := ButtonGroup.new()
	for info in ArenaRegistry.ARENAS:
		var b := Button.new()
		b.text = String(info["name"]).to_upper()
		b.toggle_mode = true
		b.button_group = arena_group
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(150, 56)
		b.pressed.connect(_pick_arena.bind(String(info["id"])))
		arenas.add_child(b)
		_arena_buttons[String(info["id"])] = b
	column.add_child(arenas)
	_show_arena(Settings.last_arena if StringName(Settings.last_arena) in ArenaRegistry.ids() else String(ArenaRegistry.DEFAULT))

	column.add_child(_spacer(6))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 20)
	var lan := _menu_button("LAN PARTY", _open_lobby)
	lan.custom_minimum_size.x = 380
	bottom.add_child(lan)
	var settings := _menu_button("SETTINGS", _open_settings)
	settings.custom_minimum_size.x = 380
	bottom.add_child(settings)
	column.add_child(bottom)

	var version := Label.new()
	version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0")
	version.add_theme_font_size_override("font_size", 22)
	version.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -28
	version.offset_bottom = -20
	add_child(version)

	_settings = SettingsScreen.new()
	add_child(_settings)
	free_fly.grab_focus.call_deferred()


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


func _pick_mode(mode_id: StringName) -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	_show_mode(mode_id)


func _show_mode(mode_id: StringName) -> void:
	_play_mode = mode_id
	for key: StringName in _mode_buttons:
		(_mode_buttons[key] as Button).set_pressed_no_signal(key == mode_id)
	var def := ModeDef.load_by_id(mode_id)
	_mode_info.text = def.description if def != null else ""


func _pick_difficulty(level: String) -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	Settings.bot_difficulty = level
	Settings.save_settings()
	_show_difficulty(level)


func _pick_arena(arena_id: String) -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	Settings.last_arena = arena_id
	Settings.save_settings()
	_show_arena(arena_id)


func _show_arena(arena_id: String) -> void:
	for key: String in _arena_buttons:
		(_arena_buttons[key] as Button).set_pressed_no_signal(key == arena_id)


func _show_difficulty(level: String) -> void:
	for key: String in _difficulty_buttons:
		(_difficulty_buttons[key] as Button).set_pressed_no_signal(key == level)


func _open_lobby() -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	if change_scene:
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _open_settings() -> void:
	Sfx.play(&"ui_click", Vector2.ZERO)
	_settings.open()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _settings != null and not _settings.visible:
		get_tree().quit()


func _menu_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(586, 80)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	return b


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
		s.modulate = Color(1, 1, 1, 0.75)
		s.position = Vector2(area.x * (0.12 + 0.25 * i), area.y * (0.2 + 0.6 * float(i % 2)))
		add_child(s)
		_floaters.append(s)
		_floater_velocity.append(Vector2.from_angle(0.7 + i * 1.9) * FLOAT_SPEED)
