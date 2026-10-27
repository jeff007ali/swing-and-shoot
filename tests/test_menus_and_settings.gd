extends GutTest
## M6 screens: the main menu sets mode and difficulty, the settings screen applies and saves, tuning
## presets round-trip. Saves go to a test file, and every setting is restored afterwards.

const MAIN_MENU: PackedScene = preload("res://src/ui/main_menu.tscn")
const TEST_SETTINGS: String = "user://test_settings.cfg"
const TEST_PRESET: String = "gut_test_preset"
const SAVED := ["haptics_enabled", "sfx_volume", "music_volume", "show_debug", "bot_difficulty", "last_mode", "playtest_logging", "last_arena", "left_handed", "button_scale", "colorblind", "tutorial_done", "rope_stick"]

var _saved: Dictionary = {}


func before_each() -> void:
	TuningDB.reset_to_default()
	for key: String in SAVED:
		_saved[key] = Settings.get(key)
	Settings.path_override = TEST_SETTINGS


func after_each() -> void:
	for key: String in SAVED:
		Settings.set(key, _saved[key])
	Settings.apply()
	Settings.path_override = ""
	DirAccess.remove_absolute(TEST_SETTINGS)
	DirAccess.remove_absolute(TuningDB.PRESET_DIR + TEST_PRESET + ".tres")
	TuningDB.reset_to_default()


func _menu() -> MainMenu:
	var menu := MAIN_MENU.instantiate() as MainMenu
	menu.change_scene = false
	add_child_autofree(menu)
	return menu


func test_menu_vs_bot_with_hard_saves_mode_and_difficulty() -> void:
	var menu := _menu()
	(menu._difficulty_buttons["hard"] as Button).pressed.emit()
	menu.start_match(&"vs_bot")
	assert_eq(Settings.bot_difficulty, "hard")
	assert_eq(Settings.last_mode, "vs_bot")
	assert_true((menu._difficulty_buttons["hard"] as Button).button_pressed)
	assert_false((menu._difficulty_buttons["normal"] as Button).button_pressed)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TEST_SETTINGS), OK, "saved to disk")
	assert_eq(cfg.get_value("settings", "bot_difficulty"), "hard")


func test_menu_arena_picker_saves_the_arena() -> void:
	var menu := _menu()
	(menu._arena_buttons["hangar"] as Button).pressed.emit()
	assert_eq(Settings.last_arena, "hangar")
	(menu._arena_buttons["station"] as Button).pressed.emit()
	assert_eq(Settings.last_arena, "station")
	assert_true((menu._arena_buttons["station"] as Button).button_pressed)


func test_menu_free_fly() -> void:
	var menu := _menu()
	menu.start_match(&"free_fly")
	assert_eq(Settings.last_mode, "free_fly")


func test_menu_shows_the_saved_difficulty() -> void:
	Settings.bot_difficulty = "easy"
	var menu := _menu()
	assert_true((menu._difficulty_buttons["easy"] as Button).button_pressed)


func test_menu_shows_the_version() -> void:
	var menu := _menu()
	var found := false
	for child in menu.get_children():
		if child is Label and (child as Label).text == "v" + str(ProjectSettings.get_setting("application/config/version")):
			found = true
	assert_true(found)


func test_settings_screen_applies_and_saves() -> void:
	var screen := SettingsScreen.new()
	add_child_autofree(screen)
	screen.open()
	var toggles := screen.find_children("*", "CheckButton", true, false)
	var haptics := toggles.filter(func(n: Node) -> bool: return (n as CheckButton).text == "Haptics")[0] as CheckButton
	haptics.button_pressed = not Settings.haptics_enabled
	var want := haptics.button_pressed
	assert_eq(Settings.haptics_enabled, want, "applies at once")
	var sliders := screen.find_children("*", "HSlider", true, false)
	(sliders[0] as HSlider).value = 0.25
	assert_almost_eq(Settings.sfx_volume, 0.25, 0.001)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), linear_to_db(0.25), 0.01, "bus volume follows")
	screen.close()
	Settings.haptics_enabled = not want
	Settings.load_settings()
	assert_eq(Settings.haptics_enabled, want, "persisted on close")


func test_tuning_preset_round_trip() -> void:
	TuningDB.t.kick_speed = 999.0
	TuningDB.t.melee_active_ticks = 9
	assert_eq(TuningDB.save_preset(TEST_PRESET), OK)
	assert_has(TuningDB.list_presets(), TEST_PRESET)
	TuningDB.reset_to_default()
	assert_eq(TuningDB.t.kick_speed, 750.0)
	assert_true(TuningDB.load_preset(TEST_PRESET))
	assert_eq(TuningDB.t.kick_speed, 999.0)
	assert_eq(TuningDB.t.melee_active_ticks, 9)
