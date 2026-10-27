class_name NetMatch
extends Node
## In-match LAN sync (§6.2, D5 host-authoritative with client prediction).
##
## Host: runs the authoritative MatchSim at 60 Hz once every client has loaded, feeding remote
## fighters from buffered client inputs and bots from BotControllers. Sends a full snapshot 30 times
## a second (unreliable ordered) and forwards each tick's events (reliable).
##
## Client: steps its own copy of the sim every tick with its own input and empty input for everyone
## else (D29: the whole world is predicted, not interpolated), sends its last few commands every tick,
## and on each snapshot rewinds (set_state) and replays its unacknowledged inputs. Corrections under
## SMOOTH_MAX px are blended out by the fighter views over ~100 ms. It runs a little ahead of the host
## so its inputs arrive in time: the host reports how far ahead they arrive and the client speeds up
## or slows down by one tick to keep that between LEAD_MIN and LEAD_MAX.

## Ticks of own input kept for replay.
const HISTORY_TICKS: int = 180
## Client starts this many ticks ahead of the first snapshot.
const INITIAL_LEAD: int = 4
const LEAD_MIN: int = 1
const LEAD_MAX: int = 5
## Position corrections up to this size are smoothed, bigger ones snap (§6.2).
const SMOOTH_MAX: float = 150.0
## Events that only the host decides: clients drop their own copies and take the host's.
const AUTHORITATIVE_EVENTS: Array[StringName] = [
	&"hit_landed", &"fighter_ko", &"fighter_respawned", &"rope_bounced", &"parried", &"rope_cut", &"rammed",
	&"weapon_spawned", &"weapon_despawned", &"weapon_picked", &"weapon_dropped", &"projectile_blocked",
	&"shocked", &"vent_changed", &"object_broken", &"object_restored", &"tank_exploded", &"match_event",
	&"match_ended", &"bomb_passed", &"bomb_exploded", &"level_up", &"teammate_thrown",
	&"legendary_incoming", &"frozen", &"tethered", &"tether_smash", &"grenade_stuck", &"mine_triggered",
	&"wrecking_ball", &"rope_clash", &"rope_duel_started", &"rope_duel_ended", &"projectile_caught",
	&"shield_ripped", &"wave_started", &"boss_hit",
]

var session: NetSession
var sim: MatchSim
## Live input for the local fighter: the TouchRouter, or a scripted source in tests.
var router: Object
var local_fighter_id: int = 0

# Host
var _remote_inputs: Dictionary = {}
var _peer_fighters: Dictionary = {}
var _started: bool = false
# Client
var _history: Dictionary = {}
var _pending_snapshot: Dictionary = {}
var _applied_snapshot_tick: int = -1
var _lead: int = INITIAL_LEAD
var _running: bool = false


## Feeds one remote fighter on the host from the inputs its client sent.
class RemoteInput:
	extends RefCounted
	var commands: Dictionary = {}
	var latest_tick: int = -1
	var last: InputCommand = InputCommand.new()

	func receive(cmd: InputCommand) -> void:
		if not commands.has(cmd.tick):
			commands[cmd.tick] = cmd
		latest_tick = maxi(latest_tick, cmd.tick)

	func build_command(tick: int) -> InputCommand:
		var cmd: InputCommand = commands.get(tick)
		if cmd == null:
			cmd = NetProtocol.held_only(last, tick)
		else:
			last = cmd
		for t: int in commands.keys():
			if t <= tick:
				commands.erase(t)
		return cmd


## The client's own fighter: live input from the router, recorded for replay.
class LocalInput:
	extends RefCounted
	var owner: NetMatch

	func build_command(tick: int) -> InputCommand:
		return owner._local_command(tick)


## Fighters a client doesn't control: predicted with no input.
class NoInput:
	extends RefCounted

	func build_command(_tick: int) -> InputCommand:
		return InputCommand.new()


func setup(net: NetSession, match_sim: MatchSim, touch_router: Object, local_id: int, bots: Dictionary) -> void:
	session = net
	sim = match_sim
	router = touch_router
	local_fighter_id = local_id
	sim.auto_step = false
	if session.is_host():
		sim.authoritative = true
		sim.event_sink = _forward_events
		for slot: Dictionary in session.match_config["slots"]:
			var fighter_id: int = slot["fighter"]
			if slot["peer"] == 1:
				sim.set_input_source(fighter_id, router)
			elif slot["peer"] != 0:
				var remote := RemoteInput.new()
				_remote_inputs[fighter_id] = remote
				_peer_fighters[slot["peer"]] = fighter_id
				sim.set_input_source(fighter_id, remote)
		for fighter_id: int in bots:
			sim.set_input_source(fighter_id, bots[fighter_id])
		session.peer_left.connect(_on_peer_left)
	else:
		sim.authoritative = false
		sim.event_filter = _keep_own_prediction
		for f in sim.fighters:
			if f.fighter_id == local_fighter_id:
				var local := LocalInput.new()
				local.owner = self
				sim.set_input_source(f.fighter_id, local)
			else:
				sim.set_input_source(f.fighter_id, NoInput.new())
		session.report_ready()


## Host: the fighter a client was playing is now driven by this source (a bot after a disconnect).
func replace_input(fighter_id: int, source: Object) -> void:
	_remote_inputs.erase(fighter_id)
	sim.set_input_source(fighter_id, source)


func _physics_process(_delta: float) -> void:
	# A session that ended (this device left, or the host did) stops syncing at once.
	if session == null or sim == null or not session.is_active():
		return
	if session.is_host():
		_host_tick()
	else:
		_client_tick()


# --- Host --------------------------------------------------------------------------------------

func _host_tick() -> void:
	if not _started:
		if not session.is_all_ready():
			return
		_started = true
	sim.step()
	if sim.tick % (SimIds.TICK_RATE / NetProtocol.SNAPSHOT_RATE) == 0:
		_send_snapshots()


func _send_snapshots() -> void:
	var bytes := var_to_bytes(sim.get_state())
	var packed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
	for peer: int in session.ready_peers():
		var fighter_id: int = _peer_fighters.get(peer, -1)
		var remote: RemoteInput = _remote_inputs.get(fighter_id)
		var lead := (remote.latest_tick - sim.tick) if remote != null else INITIAL_LEAD
		_snapshot.rpc_id(peer, sim.tick, packed, bytes.size(), lead)


func _forward_events(events: Array) -> void:
	if events.is_empty():
		return
	for peer: int in session.ready_peers():
		_events.rpc_id(peer, events)


func _on_peer_left(peer: int) -> void:
	if not _peer_fighters.has(peer):
		return
	var fighter_id: int = _peer_fighters[peer]
	_peer_fighters.erase(peer)
	get_parent().call("replace_with_bot", fighter_id)


@rpc("any_peer", "call_remote", "unreliable", NetProtocol.CHANNEL_INPUTS)
func _inputs(packed: Array) -> void:
	if not session.is_host():
		return
	var fighter_id: int = _peer_fighters.get(multiplayer.get_remote_sender_id(), -1)
	var remote: RemoteInput = _remote_inputs.get(fighter_id)
	if remote == null:
		return
	for a: Array in packed:
		var cmd := NetProtocol.unpack_command(a)
		if cmd.tick > sim.tick:
			remote.receive(cmd)


# --- Client ------------------------------------------------------------------------------------

func _client_tick() -> void:
	if not _running:
		if _pending_snapshot.is_empty():
			return
		_apply_snapshot(false)
		_running = true
		for i in INITIAL_LEAD:
			_step_live()
		return
	if not _pending_snapshot.is_empty():
		_apply_snapshot(true)
	var steps := 1
	if _lead < LEAD_MIN:
		steps = 2
	elif _lead > LEAD_MAX:
		steps = 0
	for i in steps:
		_step_live()


func _step_live() -> void:
	sim.step()
	var packed: Array = []
	for t in range(sim.tick - NetProtocol.INPUT_REDUNDANCY + 1, sim.tick + 1):
		if _history.has(t):
			packed.append(NetProtocol.pack_command(_history[t]))
	_inputs.rpc_id(1, packed)
	_history.erase(sim.tick - HISTORY_TICKS)


func _local_command(tick: int) -> InputCommand:
	if sim.replaying:
		var recorded: InputCommand = _history.get(tick)
		return InputCommand.from_dict(recorded.to_dict()) if recorded != null else InputCommand.new()
	var cmd: InputCommand = router.build_command(tick) if router != null else InputCommand.new()
	cmd.tick = tick
	_history[tick] = InputCommand.from_dict(cmd.to_dict())
	return cmd


## Rewinds to the latest snapshot and, when replay is on, re-simulates up to the current tick.
func _apply_snapshot(replay: bool) -> void:
	var snap := _pending_snapshot
	_pending_snapshot = {}
	var state: Dictionary = snap["state"]
	var current := sim.tick
	var before := {}
	for f in sim.fighters:
		before[f.fighter_id] = f.global_position
	sim.set_state(state)
	_applied_snapshot_tick = sim.tick
	if replay and current > sim.tick:
		sim.replaying = true
		while sim.tick < current:
			sim.step()
		sim.replaying = false
	for f in sim.fighters:
		var delta: Vector2 = before[f.fighter_id] - f.global_position
		if replay and delta.length() <= SMOOTH_MAX and f.view != null:
			f.view.add_correction(delta)
	for t: int in _history.keys():
		if t <= _applied_snapshot_tick - NetProtocol.INPUT_REDUNDANCY:
			_history.erase(t)


func _keep_own_prediction(signal_name: StringName, args: Array) -> bool:
	if signal_name in AUTHORITATIVE_EVENTS:
		return false
	if signal_name == &"rope_attached" and (args[1] == SimIds.RopeMode.PULL or args[1] == SimIds.RopeMode.FETCH):
		return false
	return args[0] == local_fighter_id


@rpc("authority", "call_remote", "unreliable_ordered", NetProtocol.CHANNEL_SNAPSHOTS)
func _snapshot(tick: int, packed: PackedByteArray, size: int, lead: int) -> void:
	if session.is_host() or tick <= _applied_snapshot_tick:
		return
	if not _pending_snapshot.is_empty() and int(_pending_snapshot["tick"]) >= tick:
		return
	var state: Dictionary = bytes_to_var(packed.decompress(size, FileAccess.COMPRESSION_ZSTD))
	_pending_snapshot = {"tick": tick, "state": state}
	_lead = lead


@rpc("authority", "call_remote", "reliable", NetProtocol.CHANNEL_RELIABLE)
func _events(events: Array) -> void:
	var keep := events.filter(func(e: Array) -> bool:
		var args: Array = e[1]
		var authoritative: bool = e[0] in AUTHORITATIVE_EVENTS or (e[0] == &"rope_attached" and (args[1] == SimIds.RopeMode.PULL or args[1] == SimIds.RopeMode.FETCH))
		return authoritative or args[0] != local_fighter_id)
	sim.emit_events(keep)
