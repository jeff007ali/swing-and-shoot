class_name MatchSim
extends Node
## The one tick driver (§3.1 rule 1, §3.3). Fighters, ropes and arena objects have no physics
## process of their own; this node steps them in a fixed order every physics tick.

## Emitted at the end of every tick, after its events. For observers that sample the sim per tick
## (the playtest logger); they must not change it.
signal ticked(tick: int)

## Tests and network clients turn this off and call step() themselves.
var auto_step: bool = true
## Only an authoritative sim (offline, or the LAN host) decides rope hits on fighters, melee hits,
## damage and KOs (§6.2). Clients predict everything else and take those from the host.
var authoritative: bool = true
## True while a client re-simulates ticks after a snapshot: events are not emitted again.
var replaying: bool = false
## Called with each tick's events before they are emitted; the LAN host forwards them to clients.
var event_sink: Callable
## Decides whether one of this sim's own events is emitted locally: (signal_name, args) -> bool.
var event_filter: Callable
var tick: int = 0
var fighters: Array[Fighter] = []
var arena_objects: Array[ArenaObject] = []
var spawn_points: Array[Vector2] = []
## Weapons and projectiles (§6.3) and the Phase 6 special behaviors.
var weapons := WeaponSystem.new()
var special_weapons := SpecialWeapons.new()
## Arena hazards and mid-match events (§6.4). Set up with the arena by the match.
var hazards := HazardSystem.new()
## The rules of this match (§6.5); null runs without scoring (tests).
var mode: GameMode
## Fighter id -> team. Fighters on the same team are not enemies (2v2, co-op). Empty: free-for-all.
var teams: Dictionary = {}
## "a:b" -> tick until which that pair can't ram again (MEL-05).
var ram_cooldowns: Dictionary = {}
var _entity_counter: int = 0
## Seeded match randomness (§3.1 rule 5). Visual-only randomness may use anything.
var rng := RandomNumberGenerator.new()

## fighter_id -> object with build_command(tick: int) -> InputCommand
var _input_sources: Dictionary = {}
var _events: Array = []


func setup(objects: Array[ArenaObject], spawns: Array[Vector2], match_seed: int, weapon_spawns: Array[Vector2] = [], arena_bounds: Rect2 = Rect2(0, 0, 1920, 1080)) -> void:
	arena_objects = objects
	spawn_points = spawns
	weapons.setup(self, weapon_spawns, arena_bounds)
	special_weapons.setup(self)
	for i in arena_objects.size():
		arena_objects[i].object_id = i
	rng.seed = match_seed
	tick = 0
	for obj in arena_objects:
		obj.step(tick)


func add_fighter(fighter: Fighter) -> void:
	fighter.sim = self
	fighters.append(fighter)


func set_input_source(fighter_id: int, source: Object) -> void:
	_input_sources[fighter_id] = source


func get_fighter(fighter_id: int) -> Fighter:
	for f in fighters:
		if f.fighter_id == fighter_id:
			return f
	return null


## Ids for weapons and projectiles, the same on every device.
func next_entity_id() -> int:
	_entity_counter += 1
	return _entity_counter


func are_enemies(a: Fighter, b: Fighter) -> bool:
	if a == b:
		return false
	if teams.is_empty():
		return true
	return teams.get(a.fighter_id, -1) != teams.get(b.fighter_id, -2)


func get_object(object_id: int) -> ArenaObject:
	if object_id < 0 or object_id >= arena_objects.size():
		return null
	return arena_objects[object_id]


## Rope aim assist for a sender (§4.5). Bind the shooter: aim_assist.bind(fighter).
func aim_assist(point: Vector2, shooter: Fighter) -> Vector2:
	return AimAssist.resolve(shooter, point, fighters, shooter.get_world_2d().direct_space_state, TuningDB.t, weapons.items)


func aim_direction(dir: Vector2, shooter: Fighter) -> Vector2:
	return AimAssist.resolve_direction(shooter, dir, fighters, TuningDB.t, weapons.items)


## A fighter was knocked out: the mode scores it (authoritative only).
func on_fighter_ko(victim: Fighter, killer_id: int, cause: StringName) -> void:
	if mode != null and authoritative and not mode.ended:
		mode.on_ko(victim, killer_id, cause)


## attacker's rope (kind rope) or melee (melee, throw) reached victim: Hot Potato passes the bomb.
func on_contact(attacker: Fighter, victim: Fighter, kind: StringName) -> void:
	if mode != null and authoritative and not mode.ended:
		mode.on_contact(attacker, victim, kind)


func queue_event(signal_name: StringName, args: Array) -> void:
	_events.append([signal_name, args])


func _physics_process(_delta: float) -> void:
	if auto_step:
		step()


func step() -> void:
	tick += 1
	# 1. Arena objects, then hazards that act before anyone moves
	for obj in arena_objects:
		obj.step(tick)
	hazards.pre_step(tick)
	# 2. One command per fighter
	var commands: Array[InputCommand] = []
	for f in fighters:
		var source: Object = _input_sources.get(f.fighter_id)
		var cmd: InputCommand = source.build_command(tick) if source != null else InputCommand.new()
		cmd.tick = tick
		commands.append(cmd)
	# 3. Fighters in fixed order, then weapons and projectiles
	for i in fighters.size():
		fighters[i].step(tick, commands[i])
	weapons.step(tick)
	special_weapons.step(tick)
	# 4. Melee hits and rams
	if authoritative:
		Melee.resolve(fighters, tick, TuningDB.t)
		Melee.resolve_rams(self, tick, TuningDB.t)
	hazards.post_step(tick)
	if mode != null:
		mode.step(tick)
	# 5. Soft separation (D14)
	_separate_fighters()
	# 6. Status timers
	for f in fighters:
		f.step_timers(tick)
	# 7. Events for views
	_flush_events()
	ticked.emit(tick)


## KO respawn (§4.8): the spawn point farthest from the nearest living enemy.
func respawn(fighter: Fighter) -> void:
	if spawn_points.is_empty():
		return
	var best := spawn_points[0]
	var best_dist := -1.0
	for point in spawn_points:
		var nearest := INF
		for other in fighters:
			if other != fighter and not other.is_ko():
				nearest = minf(nearest, point.distance_to(other.global_position))
		if nearest > best_dist:
			best_dist = nearest
			best = point
	fighter.respawn_at(best, tick)


func get_state() -> Dictionary:
	var fighter_states: Array = []
	for f in fighters:
		fighter_states.append(f.get_state())
	return {
		"tick": tick, "rng_state": rng.state, "fighters": fighter_states, "entities": _entity_counter,
		"weapons": weapons.get_state(), "special": special_weapons.get_state(), "rams": ram_cooldowns.duplicate(),
		"hazards": hazards.get_state(), "mode": mode.get_state() if mode != null else {},
	}


func set_state(s: Dictionary) -> void:
	tick = s["tick"]
	rng.state = s["rng_state"]
	_entity_counter = s.get("entities", 0)
	ram_cooldowns = s.get("rams", {}).duplicate()
	if s.has("weapons"):
		weapons.set_state(s["weapons"])
	if s.has("special"):
		special_weapons.set_state(s["special"])
	if s.has("hazards"):
		hazards.set_state(s["hazards"])
	if mode != null and not s.get("mode", {}).is_empty():
		mode.set_state(s["mode"])
	for obj in arena_objects:
		obj.step(tick)
	var fighter_states: Array = s["fighters"]
	for fs: Dictionary in fighter_states:
		var f := get_fighter(fs["id"])
		if f != null:
			f.set_state(fs)


func _separate_fighters() -> void:
	var t := TuningDB.t
	var min_dist := t.fighter_radius * 2.0
	var push := t.separation_speed * SimIds.DT
	for i in fighters.size():
		var a := fighters[i]
		if a.is_ko():
			continue
		for j in range(i + 1, fighters.size()):
			var b := fighters[j]
			if b.is_ko():
				continue
			var d := b.global_position - a.global_position
			var dist := d.length()
			if dist >= min_dist:
				continue
			var n := d / dist if dist > 0.001 else Vector2.RIGHT
			if not a.is_clinging():
				a.global_position -= n * push
			if not b.is_clinging():
				b.global_position += n * push


## Emits events that came from elsewhere (the LAN host) on this device.
func emit_events(events: Array) -> void:
	for e: Array in events:
		var args: Array = [e[0]]
		args.append_array(e[1])
		GameEvents.emit_signal.callv(args)


func _flush_events() -> void:
	var pending := _events
	_events = []
	if replaying:
		return
	if event_sink.is_valid():
		event_sink.call(pending)
	if event_filter.is_valid():
		pending = pending.filter(func(e: Array) -> bool: return event_filter.call(e[0], e[1]))
	emit_events(pending)
