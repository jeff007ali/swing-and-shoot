extends Node
## Player settings (§3.7, §4.12), saved to user://settings.cfg. Tests can point PATH elsewhere with
## path_override so they never touch the player's file.

signal changed

const PATH: String = "user://settings.cfg"
const SECTION: String = "settings"

var haptics_enabled: bool = true
var sfx_volume: float = 0.8
var music_volume: float = 0.6
var show_debug: bool = false
var bot_difficulty: String = "normal"
## Mode id (data/modes), as last picked in the main menu or the LAN lobby.
var last_mode: String = "vs_bot"
## The mode picked on the PLAY page; last_mode can also be Free Fly or the tutorial.
var play_mode: String = "vs_bot"
## Arena id from ArenaRegistry, as last picked in the main menu.
var last_arena: String = "station"
## Write a CSV per match to user://playtest/ (§4.13).
var playtest_logging: bool = true
## Accessibility (§6.7): melee and fire buttons on the left, their size, colorblind-safe colors.
var left_handed: bool = false
var button_scale: float = 1.0
var colorblind: bool = false
## Rope stick (D39): a drag-to-aim rope control in the corner, besides tapping anywhere.
var rope_stick: bool = false
## The tutorial was finished once (the menu stops marking it NEW).
var tutorial_done: bool = false


func _ready() -> void:
	load_settings()
	apply()


var path_override: String = ""


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path()) != OK:
		return
	haptics_enabled = cfg.get_value(SECTION, "haptics", haptics_enabled)
	sfx_volume = cfg.get_value(SECTION, "sfx_volume", sfx_volume)
	music_volume = cfg.get_value(SECTION, "music_volume", music_volume)
	show_debug = cfg.get_value(SECTION, "show_debug", show_debug)
	bot_difficulty = cfg.get_value(SECTION, "bot_difficulty", bot_difficulty)
	last_mode = cfg.get_value(SECTION, "last_mode", last_mode)
	play_mode = cfg.get_value(SECTION, "play_mode", last_mode)
	playtest_logging = cfg.get_value(SECTION, "playtest_logging", playtest_logging)
	last_arena = cfg.get_value(SECTION, "last_arena", last_arena)
	left_handed = cfg.get_value(SECTION, "left_handed", left_handed)
	button_scale = cfg.get_value(SECTION, "button_scale", button_scale)
	colorblind = cfg.get_value(SECTION, "colorblind", colorblind)
	rope_stick = cfg.get_value(SECTION, "rope_stick", rope_stick)
	tutorial_done = cfg.get_value(SECTION, "tutorial_done", tutorial_done)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "haptics", haptics_enabled)
	cfg.set_value(SECTION, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(SECTION, "show_debug", show_debug)
	cfg.set_value(SECTION, "bot_difficulty", bot_difficulty)
	cfg.set_value(SECTION, "last_mode", last_mode)
	cfg.set_value(SECTION, "play_mode", play_mode)
	cfg.set_value(SECTION, "playtest_logging", playtest_logging)
	cfg.set_value(SECTION, "last_arena", last_arena)
	cfg.set_value(SECTION, "left_handed", left_handed)
	cfg.set_value(SECTION, "button_scale", button_scale)
	cfg.set_value(SECTION, "colorblind", colorblind)
	cfg.set_value(SECTION, "rope_stick", rope_stick)
	cfg.set_value(SECTION, "tutorial_done", tutorial_done)
	cfg.save(_path())


func _path() -> String:
	return PATH if path_override.is_empty() else path_override


func apply() -> void:
	_set_bus_volume(&"SFX", sfx_volume)
	_set_bus_volume(&"Music", music_volume)
	changed.emit()


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
