class_name NetSession
extends Node
## LAN session (§6.2): host or join over ENet (UDP), the lobby, the version handshake and match start.
## The game uses the "Net" autoload; tests make their own instances under separate multiplayer roots.
## Local only: no internet and no servers (D4). The host is also a player (peer 1).

signal lobby_changed
## Client: accepted into the lobby.
signal joined
## Client: could not join, with a reason to show.
signal join_failed(reason: String)
signal match_starting(config: Dictionary)
## Client: the host closed the game or dropped out.
signal host_left
## Host: a client dropped out (in the lobby or in a match).
signal peer_left(peer_id: int)
## Host: every client has loaded the match.
signal all_ready

enum Role { NONE, HOST, CLIENT }

const SKINS: Array[StringName] = [&"alien_green", &"alien_pink", &"alien_yellow", &"alien_purple"]
## How long a rejected client stays connected so the reason reaches it (s).
const REJECT_DELAY: float = 0.5

var role: Role = Role.NONE
## Lobby order is slot order: [{peer, name}], host first.
var players: Array = []
var fill_with_bots: bool = true
var bot_difficulty: String = "normal"
var mode: String = "vs_bot"
var arena: String = "station"
var player_name: String = "Player"
## Set when a match starts; read by the match scene.
var match_config: Dictionary = {}
var discovery: LanDiscovery
## The protocol version this device announces. Only tests change it.
var protocol_version: int = NetProtocol.VERSION

var _peer: ENetMultiplayerPeer
var _ready_peers: Dictionary = {}
var _joined_signalled: bool = false


func _ready() -> void:
	discovery = LanDiscovery.new()
	discovery.name = "Discovery"
	add_child(discovery)


func is_active() -> bool:
	return role != Role.NONE


func is_host() -> bool:
	return role == Role.HOST


func in_match() -> bool:
	return is_active() and not match_config.is_empty()


func my_peer_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


func host_game(display_name: String) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(NetProtocol.GAME_PORT, NetProtocol.MAX_CLIENTS)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	player_name = display_name
	players = [{"peer": 1, "name": display_name, "loadout": _clean_loadout(_loadout())}]
	_connect_signals()
	discovery.start_broadcasting(func() -> PackedByteArray: return NetProtocol.beacon(player_name, players.size(), mode, arena))
	lobby_changed.emit()
	return OK


func join_game(address: String, display_name: String) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, NetProtocol.GAME_PORT)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	player_name = display_name
	_joined_signalled = false
	_connect_signals()
	return OK


func leave() -> void:
	discovery.stop()
	if _peer != null:
		_disconnect_signals()
		_peer.close()
		multiplayer.multiplayer_peer = null
		_peer = null
	role = Role.NONE
	players = []
	match_config = {}
	_ready_peers = {}


## Host: starts the match for everyone. Fills empty slots with bots when fill_with_bots is on.
func start_match(match_seed: int = 0) -> void:
	if not is_host():
		return
	var slots: Array = []
	for i in players.size():
		slots.append({"fighter": i, "peer": players[i]["peer"], "name": players[i]["name"], "skin": SKINS[i], "bot": "", "loadout": players[i].get("loadout", {})})
	var def := ModeDef.load_by_id(StringName(mode))
	if fill_with_bots or slots.size() == 1:
		var fill := def.players if def != null and def.enemy_slots > 0 else NetProtocol.MAX_PLAYERS
		while slots.size() < maxi(fill, slots.size()):
			var i := slots.size()
			slots.append({"fighter": i, "peer": 0, "name": "Bot %d" % (i - players.size() + 1), "skin": SKINS[i], "bot": bot_difficulty})
	if def != null:
		# Co-op Survival enemies (§6.6), benched until their wave.
		for e in def.enemy_slots:
			slots.append({"fighter": slots.size(), "peer": 0, "name": "Drone %d" % (e + 1), "skin": "alien_purple", "bot": "easy"})
	match_config = {
		"protocol": NetProtocol.VERSION,
		"seed": match_seed if match_seed != 0 else randi(),
		"arena": arena,
		"mode": mode,
		"slots": slots,
	}
	_ready_peers = {}
	discovery.stop()
	for p in players:
		if p["peer"] != 1:
			_start.rpc_id(p["peer"], match_config)
	match_starting.emit(match_config)


## Client: tells the host this device has loaded the match.
func report_ready() -> void:
	if role == Role.CLIENT:
		_match_ready.rpc_id(1)


## Host: peers that have loaded the match.
func ready_peers() -> Array:
	return _ready_peers.keys()


func is_all_ready() -> bool:
	for p in players:
		if p["peer"] != 1 and not _ready_peers.has(p["peer"]):
			return false
	return true


## The fighter this device controls in the current match.
func local_fighter_id() -> int:
	var me := my_peer_id()
	for slot: Dictionary in match_config.get("slots", []):
		if slot["peer"] == me:
			return slot["fighter"]
	return 0


func _connect_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _disconnect_signals() -> void:
	for pair in [[multiplayer.peer_connected, _on_peer_connected], [multiplayer.peer_disconnected, _on_peer_disconnected],
			[multiplayer.connected_to_server, _on_connected], [multiplayer.connection_failed, _on_connection_failed],
			[multiplayer.server_disconnected, _on_server_disconnected]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var before := players.size()
	players = players.filter(func(p: Dictionary) -> bool: return p["peer"] != id)
	_ready_peers.erase(id)
	if players.size() != before:
		if match_config.is_empty():
			_broadcast_lobby()
		peer_left.emit(id)


func _on_connected() -> void:
	_hello.rpc_id(1, protocol_version, player_name, _loadout())


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("Can't reach the host. On guest or office Wi-Fi, try a phone hotspot instead.")


func _on_server_disconnected() -> void:
	var was_joined := _joined_signalled
	leave()
	if was_joined:
		host_left.emit()
	else:
		join_failed.emit("The host closed the connection.")


func _broadcast_lobby() -> void:
	var settings := {"fill": fill_with_bots, "bot": bot_difficulty, "mode": mode, "arena": arena}
	for p in players:
		if p["peer"] != 1:
			_lobby.rpc_id(p["peer"], players, settings)
	lobby_changed.emit()


## Host: lobby settings changed in the UI.
func update_settings() -> void:
	if is_host():
		_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int, display_name: String, loadout: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != NetProtocol.VERSION:
		reason = "Update the game to join (host v%d, you v%d)." % [NetProtocol.VERSION, version]
	elif not match_config.is_empty():
		reason = "That match has already started."
	elif players.size() >= NetProtocol.MAX_PLAYERS:
		reason = "The lobby is full."
	if not reason.is_empty():
		_rejected.rpc_id(id, reason)
		get_tree().create_timer(REJECT_DELAY).timeout.connect(func() -> void:
			if _peer != null:
				_peer.disconnect_peer(id))
		return
	players.append({"peer": id, "name": display_name.substr(0, 16), "loadout": _clean_loadout(loadout)})
	_broadcast_lobby()


## The local player's cosmetic loadout (§7), sent in the handshake so others can render it.
func _loadout() -> Dictionary:
	var profile := get_node_or_null("/root/ProfileStore")
	return profile.data.get("loadout", {}).duplicate() if profile != null else {}


## Only known keys with short string values come through.
static func _clean_loadout(loadout: Dictionary) -> Dictionary:
	var out := {}
	for key in ["skin_id", "trail_id", "hook_id", "kill_fx_id", "emote_id"]:
		var v: Variant = loadout.get(key, "")
		out[key] = String(v).substr(0, 32) if v is String or v is StringName else ""
	return out


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	leave()
	join_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _lobby(lobby_players: Array, settings: Dictionary) -> void:
	players = lobby_players
	fill_with_bots = settings.get("fill", true)
	bot_difficulty = settings.get("bot", "normal")
	mode = settings.get("mode", "vs_bot")
	arena = settings.get("arena", "station")
	if not _joined_signalled:
		_joined_signalled = true
		joined.emit()
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _start(config: Dictionary) -> void:
	match_config = config
	match_starting.emit(config)


@rpc("any_peer", "call_remote", "reliable")
func _match_ready() -> void:
	if not is_host():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	if is_all_ready():
		all_ready.emit()
