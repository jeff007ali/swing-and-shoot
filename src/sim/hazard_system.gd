class_name HazardSystem
extends RefCounted
## Arena hazards and mid-match events (§6.4; ARN-02, ARN-04, ARN-06, ARN-08, ARN-09, ARN-10, HP-02).
## Part of the sim: stepped by MatchSim, tick-based, seeded randomness, full get_state/set_state.
##   pre_step (before fighters move): vent doors and suction, black-hole pull, drifting asteroids.
##   post_step (after hits): hazard KOs, wrap-around edges, tank respawns, Closing Walls, Debris
##   Storm, and the event scheduler.
## A hazard KO counts for whoever hit or pulled the victim within KILL_CREDIT_TIME (§6.4).

enum VentState { CLOSED, WARNING, OPEN }

const EVENTS: Array[StringName] = [&"lights_out", &"vent_surge", &"closing_walls", &"debris_storm"]
## A fighter this far past the arena edge is lost to space (px).
const OUTSIDE_MARGIN: float = 30.0
## Closing Walls damages fighters outside the zone this often (ticks).
const CLOSING_DAMAGE_TICKS: int = 30

var sim: MatchSim
var bounds: Rect2 = Rect2(0, 0, 1920, 1080)
var wrap: bool = false
## [{pos, outward, width, door: ArenaObject, offset}]
var vents: Array[Dictionary] = []
var black_holes: Array[Vector2] = []
var breakables: Array[ArenaObject] = []
var drifting: Array[DriftingBody] = []
var allowed_events: Array[StringName] = []

# State
## object_id -> {hp, active, respawn}
var object_state: Dictionary = {}
var shock_until: Dictionary = {}
var asteroid_until: Dictionary = {}
var event_id: StringName = &""
var event_start: int = 0
var event_end: int = 0
var next_event_tick: int = SimIds.NO_TICK
var event_data: Dictionary = {}
var closing_next: Dictionary = {}


func setup(match_sim: MatchSim, arena: Arena) -> void:
	sim = match_sim
	bounds = arena.bounds
	wrap = arena.edge_mode == &"wrap"
	for h in arena.get_hazards():
		match h.kind:
			&"vent":
				var door := h.get_node_or_null(h.door) as ArenaObject
				vents.append({"pos": h.global_position, "outward": h.outward.normalized(), "width": h.width, "door": door, "offset": SimIds.ticks(h.cycle_offset)})
			&"black_hole":
				black_holes.append(h.global_position)
	for obj in sim.arena_objects:
		if obj is DriftingBody:
			drifting.append(obj)
		if obj.is_breakable():
			breakables.append(obj)
			var hp := obj.max_hp if obj.max_hp > 0.0 else TuningDB.t.tank_hp
			obj.hp = hp
			object_state[obj.object_id] = {"hp": hp, "active": true, "respawn": SimIds.NO_TICK}
	for e in arena.events:
		if e == &"vent_surge" and vents.is_empty():
			continue
		allowed_events.append(e)
	if not allowed_events.is_empty():
		next_event_tick = SimIds.ticks(TuningDB.t.event_first_delay)


# --- Queries for views and bots -----------------------------------------------------------------

func vent_state(index: int, tick: int) -> VentState:
	if event_id == &"vent_surge":
		return VentState.OPEN
	var t := TuningDB.t
	var cycle := maxi(1, SimIds.ticks(t.vent_cycle))
	var phase := posmod(tick + int(vents[index]["offset"]), cycle)
	var open_start := cycle - SimIds.ticks(t.vent_open)
	if phase >= open_start:
		return VentState.OPEN
	if phase >= open_start - SimIds.ticks(t.vent_warning):
		return VentState.WARNING
	return VentState.CLOSED


func black_hole_radius(tick: int) -> float:
	var t := TuningDB.t
	var k := clampf(float(tick) / maxf(1.0, t.black_hole_growth_time * SimIds.TICK_RATE), 0.0, 1.0)
	return lerpf(t.black_hole_start_radius, t.black_hole_end_radius, k)


## The Closing Walls safe zone right now, or the whole arena.
func safe_zone(tick: int) -> Rect2:
	if event_id != &"closing_walls":
		return bounds
	var t := TuningDB.t
	var shrink_ticks := maxf(1.0, (event_end - event_start) * 2.0 / 3.0)
	var k := clampf(float(tick - event_start) / shrink_ticks, 0.0, 1.0)
	var scale := lerpf(1.0, t.closing_walls_min, k)
	var size := bounds.size * scale
	return Rect2(bounds.get_center() - size * 0.5, size)


## Direction and strength (0..1) of the strongest pull at pos: for bots to escape.
func danger_at(pos: Vector2, tick: int) -> Vector2:
	var t := TuningDB.t
	var best := Vector2.ZERO
	for i in vents.size():
		if vent_state(i, tick) == VentState.OPEN:
			var vent_pos: Vector2 = vents[i]["pos"]
			var d := pos.distance_to(vent_pos)
			if d < t.vent_reach:
				var v: Vector2 = (vent_pos - pos).normalized() * (1.0 - d / t.vent_reach)
				if v.length() > best.length():
					best = v
	for hole in black_holes:
		var r := black_hole_radius(tick)
		var reach := r * t.black_hole_influence
		var d := pos.distance_to(hole)
		if d < reach:
			var v: Vector2 = (hole - pos).normalized() * (1.0 - d / reach)
			if v.length() > best.length():
				best = v
	return best


# --- Steps -------------------------------------------------------------------------------------

func pre_step(tick: int) -> void:
	var t := TuningDB.t
	for i in vents.size():
		var state := vent_state(i, tick)
		var door: ArenaObject = vents[i]["door"]
		if door != null:
			door.set_active(state != VentState.OPEN)
		if state != vent_state(i, tick - 1):
			sim.queue_event(&"vent_changed", [i, state])
		if state == VentState.OPEN:
			_suck(vents[i], t)
	for hole in black_holes:
		_pull_toward(hole, black_hole_radius(tick), t)
	for body in drifting:
		if body.active:
			_asteroid_contacts(body, tick, t)


func post_step(tick: int) -> void:
	var t := TuningDB.t
	if sim.authoritative:
		_lost_fighters(tick)
	_lost_things(tick)
	if wrap:
		_wrap_all()
	for obj in breakables:
		var st: Dictionary = object_state[obj.object_id]
		if not st["active"] and int(st["respawn"]) != SimIds.NO_TICK and tick >= int(st["respawn"]):
			st["active"] = true
			st["hp"] = obj.max_hp if obj.max_hp > 0.0 else t.tank_hp
			st["respawn"] = SimIds.NO_TICK
			obj.hp = st["hp"]
			obj.set_active(true)
			sim.queue_event(&"object_restored", [obj.object_id, obj.center()])
	_step_events(tick, t)


# --- Vents, black holes, asteroids --------------------------------------------------------------

func _suck(vent: Dictionary, t: Tuning) -> void:
	var at: Vector2 = vent["pos"]
	var out: Vector2 = vent["outward"]
	var target := at + out * 120.0
	for f in sim.fighters:
		if f.is_ko():
			continue
		var d := f.global_position.distance_to(at)
		if d >= t.vent_reach:
			continue
		var strength := t.vent_strength * (1.0 - d / t.vent_reach)
		if f.is_clinging():
			# Holding on: the grip drains faster, like being pulled (CNT-01).
			f.cling_ticks_left -= 1
			continue
		f.velocity += (target - f.global_position).normalized() * strength * SimIds.DT
	for item in sim.weapons.items:
		if item.state != WeaponItem.State.HELD and item.pos.distance_to(at) < t.vent_reach:
			item.vel += (target - item.pos).normalized() * t.vent_strength * (1.0 - item.pos.distance_to(at) / t.vent_reach) * SimIds.DT


func _pull_toward(hole: Vector2, radius: float, t: Tuning) -> void:
	var reach := radius * t.black_hole_influence
	for f in sim.fighters:
		if f.is_ko() or f.is_clinging():
			continue
		var d := f.global_position.distance_to(hole)
		if d < reach:
			f.velocity += (hole - f.global_position).normalized() * t.black_hole_strength * clampf(radius / maxf(d, radius), 0.0, 1.0) * SimIds.DT
	for item in sim.weapons.items:
		if item.state == WeaponItem.State.HELD:
			continue
		var d := item.pos.distance_to(hole)
		if d < reach:
			item.vel += (hole - item.pos).normalized() * t.black_hole_strength * clampf(radius / maxf(d, radius), 0.0, 1.0) * SimIds.DT
	for p in sim.weapons.projectiles:
		var d := p.pos.distance_to(hole)
		if d < reach:
			p.vel += (hole - p.pos).normalized() * t.black_hole_strength * clampf(radius / maxf(d, radius), 0.0, 1.0) * SimIds.DT


## ARN-02: a drifting asteroid shoves a fighter out of its way, with damage and knockback.
func _asteroid_contacts(body: DriftingBody, tick: int, t: Tuning) -> void:
	var radius := body.pivot_radius()
	for f in sim.fighters:
		if f.is_ko() or f.cling_object == body:
			continue
		var offset := f.global_position - body.global_position
		var d := offset.length()
		var touch := radius + t.fighter_radius + 2.0
		if d >= touch:
			continue
		var n := offset / d if d > 0.001 else Vector2.UP
		f.global_position = body.global_position + n * touch
		var key := "%d:%d" % [body.object_id, f.fighter_id]
		if not sim.authoritative or tick < int(asteroid_until.get(key, -1)) or not f.can_be_hit(tick):
			f.velocity += n * maxf(0.0, -f.velocity.dot(n))
			continue
		asteroid_until[key] = tick + SimIds.ticks(t.asteroid_hit_cooldown)
		var kb := n * t.asteroid_knockback + body.velocity
		f.take_hit(tick, -1, t.asteroid_damage, kb, 2, &"asteroid")


# --- Damage to objects ---------------------------------------------------------------------------

## Shots and blasts damage breakables and fuel tanks (ARN-08, ARN-09).
func damage_object(obj: ArenaObject, amount: float, owner_id: int, tick: int) -> void:
	if not sim.authoritative or not object_state.has(obj.object_id):
		return
	var st: Dictionary = object_state[obj.object_id]
	if not st["active"]:
		return
	st["hp"] = float(st["hp"]) - amount
	obj.hp = st["hp"]
	if float(st["hp"]) > 0.0:
		return
	if obj.explosive:
		_explode(obj, owner_id, tick)
	else:
		_break(obj, tick)


func _break(obj: ArenaObject, tick: int) -> void:
	var st: Dictionary = object_state[obj.object_id]
	st["active"] = false
	st["respawn"] = SimIds.NO_TICK
	obj.set_active(false)
	_release_clingers(obj)
	sim.queue_event(&"object_broken", [obj.object_id, obj.center()])


func _explode(obj: ArenaObject, owner_id: int, tick: int) -> void:
	var t := TuningDB.t
	var st: Dictionary = object_state[obj.object_id]
	st["active"] = false
	st["respawn"] = tick + SimIds.ticks(t.tank_respawn) if t.tank_respawn > 0.0 else SimIds.NO_TICK
	obj.set_active(false)
	_release_clingers(obj)
	var at := obj.center()
	sim.queue_event(&"tank_exploded", [obj.object_id, at, t.tank_radius])
	for f in sim.fighters:
		if f.is_ko() or not f.can_be_hit(tick):
			continue
		var offset := f.global_position - at
		var d := offset.length()
		if d >= t.tank_radius:
			continue
		var k := 1.0 - d / t.tank_radius
		var dir := offset / d if d > 0.001 else Vector2.UP
		f.take_hit(tick, owner_id, t.tank_damage * k, dir * t.tank_knockback * k, 4, &"explosion")
	for item in sim.weapons.items:
		if item.state != WeaponItem.State.HELD and item.pos.distance_to(at) < t.tank_radius:
			item.vel += (item.pos - at).normalized() * t.tank_knockback * 0.5
	for other in breakables:
		if other != obj and other.center().distance_to(at) < t.tank_radius:
			damage_object(other, t.tank_damage * (1.0 - other.center().distance_to(at) / t.tank_radius), owner_id, tick)


func _release_clingers(obj: ArenaObject) -> void:
	for f in sim.fighters:
		if f.cling_object == obj:
			f.leave_surface()


# --- Leaving the arena, wrap-around -------------------------------------------------------------

func _lost_fighters(tick: int) -> void:
	var t := TuningDB.t
	var r := black_hole_radius(tick)
	for f in sim.fighters:
		if f.is_ko():
			continue
		if not wrap and not bounds.grow(OUTSIDE_MARGIN).has_point(f.global_position):
			f.hazard_ko(tick, &"vent")
			continue
		for hole in black_holes:
			if f.global_position.distance_to(hole) < r:
				f.hazard_ko(tick, &"black_hole")
				break
	if event_id == &"closing_walls":
		var zone := safe_zone(tick)
		for f in sim.fighters:
			if f.is_ko() or zone.has_point(f.global_position):
				continue
			if f.is_clinging():
				f.leave_surface()
			var inward := (zone.get_center() - f.global_position).normalized()
			f.velocity += inward * t.closing_push * SimIds.DT
			if tick >= int(closing_next.get(f.fighter_id, -1)) and f.can_be_hit(tick):
				closing_next[f.fighter_id] = tick + CLOSING_DAMAGE_TICKS
				f.take_hit(tick, -1, t.closing_damage, f.velocity, 0, &"closing_walls")


func _lost_things(tick: int) -> void:
	var r := black_hole_radius(tick)
	for item in sim.weapons.items.duplicate():
		if item.state == WeaponItem.State.HELD:
			continue
		var gone := not wrap and not bounds.grow(OUTSIDE_MARGIN).has_point(item.pos)
		for hole in black_holes:
			gone = gone or item.pos.distance_to(hole) < r
		if gone:
			sim.weapons.items.erase(item)
			sim.queue_event(&"weapon_despawned", [item.id, item.pos])
	for p in sim.weapons.projectiles.duplicate():
		var gone := not wrap and not bounds.grow(OUTSIDE_MARGIN * 10.0).has_point(p.pos)
		for hole in black_holes:
			gone = gone or p.pos.distance_to(hole) < r
		if gone:
			sim.weapons.projectiles.erase(p)


## ARN-06: leave one side, come back on the other. A rope out at the time lets go.
func _wrap_all() -> void:
	for f in sim.fighters:
		var w := wrap_point(f.global_position)
		if w != f.global_position:
			if f.rope.is_out():
				f.rope.release(false)
			f.global_position = w
			f.prev_position = w
			f.reset_physics_interpolation()
	for item in sim.weapons.items:
		var w := wrap_point(item.pos)
		if w != item.pos:
			item.pos = w
			item.prev_pos = w
	for p in sim.weapons.projectiles:
		var w := wrap_point(p.pos)
		if w != p.pos:
			p.pos = w
			p.prev_pos = w


func wrap_point(p: Vector2) -> Vector2:
	return Vector2(
		wrapf(p.x, bounds.position.x, bounds.end.x),
		wrapf(p.y, bounds.position.y, bounds.end.y))


# --- Mid-match events ---------------------------------------------------------------------------

func _step_events(tick: int, t: Tuning) -> void:
	if not event_id.is_empty() and tick >= event_end:
		var ended := event_id
		event_id = &""
		event_data = {}
		closing_next.clear()
		sim.queue_event(&"match_event", [ended, false, 0.0])
	if event_id.is_empty() and next_event_tick != SimIds.NO_TICK and tick >= next_event_tick:
		next_event_tick = tick + SimIds.ticks(t.event_interval)
		start_event(allowed_events[sim.rng.randi_range(0, allowed_events.size() - 1)], tick)
	if event_id == &"debris_storm":
		_step_debris(tick, t)


## Starts a mid-match event now (the scheduler, or tests).
func start_event(id: StringName, tick: int) -> void:
	var t := TuningDB.t
	var seconds := 0.0
	match id:
		&"lights_out": seconds = t.lights_out_time
		&"vent_surge": seconds = t.vent_surge_time
		&"closing_walls": seconds = t.closing_walls_time
		&"debris_storm":
			seconds = t.debris_storm_time
			event_data = {"side": sim.rng.randi_range(0, 3), "next": tick}
	event_id = id
	event_start = tick
	event_end = tick + SimIds.ticks(seconds)
	sim.queue_event(&"match_event", [id, true, seconds])


func _step_debris(tick: int, t: Tuning) -> void:
	if tick < int(event_data.get("next", 0)):
		return
	event_data["next"] = tick + maxi(1, SimIds.ticks(1.0 / t.debris_rate))
	var side: int = event_data["side"]
	var along := sim.rng.randf()
	var start := Vector2.ZERO
	var dir := Vector2.ZERO
	match side:
		0:
			start = Vector2(bounds.position.x + 20.0, lerpf(bounds.position.y, bounds.end.y, along))
			dir = Vector2.RIGHT
		1:
			start = Vector2(bounds.end.x - 20.0, lerpf(bounds.position.y, bounds.end.y, along))
			dir = Vector2.LEFT
		2:
			start = Vector2(lerpf(bounds.position.x, bounds.end.x, along), bounds.position.y + 20.0)
			dir = Vector2.DOWN
		_:
			start = Vector2(lerpf(bounds.position.x, bounds.end.x, along), bounds.end.y - 20.0)
			dir = Vector2.UP
	var p := Projectile.new()
	p.id = sim.next_entity_id()
	p.kind = Projectile.Kind.DEBRIS
	p.owner_id = -1
	p.pos = start
	p.prev_pos = start
	p.vel = dir.rotated(sim.rng.randf_range(-0.25, 0.25)) * sim.rng.randf_range(t.debris_speed_min, t.debris_speed_max)
	p.damage = t.debris_damage
	p.knockback = t.debris_knockback
	p.radius = sim.rng.randf_range(20.0, 36.0)
	p.expire_tick = tick + SimIds.ticks(8.0)
	sim.weapons.projectiles.append(p)


# --- State -------------------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {
		"objects": object_state.duplicate(true), "shock": shock_until.duplicate(), "asteroid": asteroid_until.duplicate(),
		"event": [event_id, event_start, event_end, next_event_tick], "event_data": event_data.duplicate(true),
		"closing": closing_next.duplicate(),
	}


func set_state(s: Dictionary) -> void:
	object_state = s["objects"].duplicate(true)
	for obj in breakables:
		var st: Dictionary = object_state.get(obj.object_id, {})
		if st.is_empty():
			continue
		obj.hp = st["hp"]
		obj.set_active(st["active"])
	shock_until = s["shock"].duplicate()
	asteroid_until = s["asteroid"].duplicate()
	var ev: Array = s["event"]
	event_id = ev[0]
	event_start = ev[1]
	event_end = ev[2]
	next_event_tick = ev[3]
	event_data = s["event_data"].duplicate(true)
	closing_next = s["closing"].duplicate()
