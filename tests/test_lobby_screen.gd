extends GutTest
## The LAN lobby screen builds every page and drives a NetSession (its own instance, not the game's).

const LOBBY: PackedScene = preload("res://src/ui/lobby_screen.tscn")

const TEST_SETTINGS: String = "user://test_settings_lobby.cfg"

var net: NetSession
var lobby: LobbyScreen
var _saved: Dictionary = {}


func before_each() -> void:
	# Host setup changes save the picks: keep them out of the player's settings file.
	for key in ["last_mode", "last_arena"]:
		_saved[key] = Settings.get(key)
	Settings.path_override = TEST_SETTINGS
	net = NetSession.new()
	add_child_autofree(net)
	lobby = LOBBY.instantiate() as LobbyScreen
	lobby.net = net
	lobby.change_scene = false
	add_child_autofree(lobby)


func after_each() -> void:
	net.leave()
	for key: String in _saved:
		Settings.set(key, _saved[key])
	Settings.path_override = ""
	DirAccess.remove_absolute(TEST_SETTINGS)


func _texts() -> PackedStringArray:
	var out := PackedStringArray()
	for n in lobby.find_children("*", "", true, false):
		if n is Label:
			out.append((n as Label).text)
		elif n is Button:
			out.append((n as Button).text)
	return out


func test_choose_page_offers_host_and_join() -> void:
	var texts := _texts()
	assert_has(texts, "HOST GAME")
	assert_has(texts, "JOIN GAME")


func test_hosting_shows_a_join_code_and_the_host_in_the_player_list() -> void:
	lobby._name_edit.text = "Tester"
	lobby._host()
	await wait_process_frames(2)
	assert_true(net.is_host())
	var texts := _texts()
	assert_has(texts, "JOIN CODE")
	assert_true(Array(texts).any(func(t: String) -> bool: return t.begins_with("1. TESTER")), "host listed first")
	assert_has(texts, "START")
	assert_has(texts, "ARENA", "the host picks the arena too")


func test_host_setup_changes_reach_the_session() -> void:
	lobby._host()
	await wait_process_frames(2)
	lobby._setup.pick_mode(&"koth")
	lobby._setup.pick_arena(&"solar")
	assert_eq(net.mode, "koth")
	assert_eq(net.arena, "solar")


func test_start_waits_for_a_friend_without_bots() -> void:
	lobby._host()
	await wait_process_frames(2)
	lobby._setup.set_fill_bots(false)
	lobby._on_host_setup_changed()
	assert_true(lobby._start.disabled)
	assert_string_contains(lobby._hint.text, "Waiting for a friend")


func test_browse_lists_a_nearby_game_with_its_mode() -> void:
	lobby._browse()
	await wait_process_frames(2)
	net.discovery.games["192.168.1.9"] = {"info": NetProtocol.parse_beacon(NetProtocol.beacon("Sam", 2, "koth", "solar")), "seen": Time.get_ticks_msec() + 60000}
	net.discovery.games_changed.emit()
	await wait_process_frames(2)
	var texts := _texts()
	assert_has(texts, "SAM'S GAME")
	assert_has(texts, "KING OF THE SWING  ·  SOLAR")


func test_back_from_hosting_closes_the_session() -> void:
	lobby._host()
	await wait_process_frames(2)
	lobby._go_back()
	await wait_process_frames(2)
	assert_false(net.is_active())
	assert_has(_texts(), "HOST GAME")


func test_a_bad_code_is_reported() -> void:
	lobby._browse()
	await wait_process_frames(2)
	lobby._join_typed("??")
	assert_string_contains(lobby._status.text, "doesn't look right")
