extends GutTest
## The LAN lobby screen builds every page and drives a NetSession (its own instance, not the game's).

const LOBBY: PackedScene = preload("res://src/ui/lobby_screen.tscn")

var net: NetSession
var lobby: LobbyScreen


func before_each() -> void:
	net = NetSession.new()
	add_child_autofree(net)
	lobby = LOBBY.instantiate() as LobbyScreen
	lobby.net = net
	lobby.change_scene = false
	add_child_autofree(lobby)


func after_each() -> void:
	net.leave()


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


func test_back_from_hosting_closes_the_session() -> void:
	lobby._host()
	await wait_process_frames(2)
	lobby._back()
	await wait_process_frames(2)
	assert_false(net.is_active())
	assert_has(_texts(), "HOST GAME")


func test_a_bad_code_is_reported() -> void:
	lobby._browse()
	await wait_process_frames(2)
	lobby._join_typed("??")
	assert_string_contains(lobby._status.text, "doesn't look right")
