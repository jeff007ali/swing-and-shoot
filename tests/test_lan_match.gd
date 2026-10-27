extends GutTest
## §6.2 end to end over real ENet on localhost: a host and a client in one process, each under its
## own SubViewport (own physics world) and its own MultiplayerAPI root, so node paths match the way
## they do on two phones.

const MATCH_SCENE: PackedScene = preload("res://src/match/match.tscn")
const ScriptedInput = preload("res://tests/helpers/scripted_input.gd")

var host_root: SubViewport
var client_root: SubViewport
var host_net: NetSession
var client_net: NetSession
var host_match: Node2D
var client_match: Node2D
var client_input: ScriptedInput
var hits: Array = []


func before_each() -> void:
	TuningDB.reset_to_default()
	hits = []
	host_root = _root("HostRoot")
	client_root = _root("ClientRoot")
	host_net = _session(host_root)
	client_net = _session(client_root)
	host_net.arena = "hangar"
	host_net.fill_with_bots = false
	GameEvents.hit_landed.connect(_on_hit)


func after_each() -> void:
	GameEvents.hit_landed.disconnect(_on_hit)
	for net in [client_net, host_net]:
		if is_instance_valid(net):
			net.leave()
	for r in [client_root, host_root]:
		if is_instance_valid(r):
			get_tree().set_multiplayer(null, r.get_path())
			r.queue_free()
	await wait_physics_frames(3)


func _on_hit(attacker: int, victim: int, damage: float, _kb: float, _combo: bool) -> void:
	hits.append([attacker, victim, damage])


func _root(root_name: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = root_name
	vp.size = Vector2i(1920, 1080)
	add_child(vp)
	get_tree().set_multiplayer(SceneMultiplayer.new(), vp.get_path())
	return vp


func _session(parent: Node) -> NetSession:
	var net := NetSession.new()
	net.name = "Net"
	parent.add_child(net)
	return net


func _wait_until(condition: Callable, max_frames: int = 240) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await wait_physics_frames(1)
	return condition.call()


func _join() -> void:
	assert_eq(host_net.host_game("Host"), OK, "host listens")
	assert_eq(client_net.join_game("127.0.0.1", "Client"), OK)
	assert_true(await _wait_until(func() -> bool: return host_net.players.size() == 2 and client_net.players.size() == 2), "client is in the lobby")


func _start() -> void:
	await _join()
	var started := [false]
	client_net.match_starting.connect(func(_c: Dictionary) -> void: started[0] = true)
	host_net.start_match(4242)
	assert_true(await _wait_until(func() -> bool: return started[0]), "client got the match config")
	host_match = _match(host_root, host_net)
	client_match = _match(client_root, client_net)
	client_input = ScriptedInput.new()
	(client_match.get("net_match") as NetMatch).router = client_input
	var host_sim: MatchSim = host_match.get("sim")
	assert_true(await _wait_until(func() -> bool: return host_sim.tick > 30), "host runs once the client is ready")


func _match(parent: Node, net: NetSession) -> Node2D:
	var m := MATCH_SCENE.instantiate() as Node2D
	m.set("net", net)
	m.set("log_playtest", false)
	m.set("record_results", false)
	parent.add_child(m)
	return m


func _client_fighter_on(m: Node2D) -> Fighter:
	return (m.get("sim") as MatchSim).get_fighter(1)


# --- Lobby -------------------------------------------------------------------------------------

func test_client_joins_the_lobby() -> void:
	await _join()
	assert_eq(host_net.players[1]["name"], "Client")
	assert_has(host_net.players[1]["loadout"], "skin_id", "the loadout came with the handshake (§7)")
	assert_eq(client_net.players[0]["name"], "Host")


func test_wrong_version_is_told_to_update() -> void:
	client_net.protocol_version = NetProtocol.VERSION + 1
	var reason := [""]
	client_net.join_failed.connect(func(r: String) -> void: reason[0] = r)
	host_net.host_game("Host")
	client_net.join_game("127.0.0.1", "Old")
	assert_true(await _wait_until(func() -> bool: return not reason[0].is_empty()))
	assert_string_contains(reason[0], "Update the game")
	assert_eq(host_net.players.size(), 1, "not added to the lobby")


func test_match_config_gives_each_device_its_own_fighter() -> void:
	await _start()
	assert_eq(host_net.local_fighter_id(), 0)
	assert_eq(client_net.local_fighter_id(), 1)
	assert_true((host_match.get("player") as Fighter).is_local_player)
	assert_eq((client_match.get("player") as Fighter).fighter_id, 1)


func test_the_hosts_mode_and_teams_reach_the_client() -> void:
	host_net.mode = "teams"
	await _start()
	var host_sim: MatchSim = host_match.get("sim")
	var client_sim: MatchSim = client_match.get("sim")
	assert_eq(client_sim.mode.def.id, &"teams")
	assert_eq(host_sim.mode.def.id, &"teams")
	assert_eq(client_sim.teams, host_sim.teams)
	assert_false(client_sim.are_enemies(client_sim.fighters[0], client_sim.fighters[2]) if client_sim.fighters.size() > 2 else false)


# --- Sync --------------------------------------------------------------------------------------

func test_client_input_moves_its_fighter_on_the_host_and_both_agree() -> void:
	await _start()
	var client_sim: MatchSim = client_match.get("sim")
	var start := _client_fighter_on(host_match).global_position
	# Rope from the right spawn (1770, 150) to Asteroid 2's west side.
	var cmd := client_input.at(client_sim.tick + 3)
	cmd.rope_fire = true
	cmd.rope_target = Vector2(1445, 280)
	assert_true(await _wait_until(func() -> bool: return _client_fighter_on(host_match).is_clinging() and _client_fighter_on(host_match).global_position.distance_to(start) > 100.0, 300), "the host saw the client's rope and moved its fighter")
	await wait_physics_frames(30)
	var on_host := _client_fighter_on(host_match).global_position
	var on_client := _client_fighter_on(client_match).global_position
	assert_almost_eq(on_client.distance_to(on_host), 0.0, 12.0, "client prediction matches the host")


func test_only_the_host_decides_hits_and_the_client_hears_about_them() -> void:
	await _start()
	var host_sim: MatchSim = host_match.get("sim")
	var victim := host_sim.get_fighter(1)
	var attacker := host_sim.get_fighter(0)
	victim.teleport(Vector2(1000, 930))
	attacker.teleport(Vector2(920, 930))
	(host_match.get("router") as TouchRouter).queue_melee()
	assert_true(await _wait_until(func() -> bool: return _client_fighter_on(client_match).hp < TuningDB.t.max_hp, 120), "damage reaches the client through snapshots")
	var forwarded := hits.filter(func(h: Array) -> bool: return h[0] == 0 and h[1] == 1)
	assert_eq(forwarded.size(), 2, "once on the host, once forwarded to the client")


func test_a_client_that_leaves_is_replaced_by_a_bot() -> void:
	await _start()
	client_net.leave()
	var host_sim: MatchSim = host_match.get("sim")
	assert_true(await _wait_until(func() -> bool: return host_sim._input_sources.get(1) is BotController, 240))
	assert_string_contains((host_sim.get_fighter(1)).display_name, "(bot)")


func test_host_leaving_ends_the_match_for_the_client() -> void:
	await _start()
	var left := [false]
	client_net.host_left.connect(func() -> void: left[0] = true)
	host_net.leave()
	assert_true(await _wait_until(func() -> bool: return left[0], 300), "client is told the host left")
