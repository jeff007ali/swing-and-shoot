class_name WeaponSystem
extends RefCounted
## Weapons and projectiles (§6.3; WPN-01 to WPN-06, PHY-06, CTL-05, MEL-04, HP-03).
## Part of the sim: stepped by MatchSim, tick-based, seeded randomness, full get_state/set_state.
##   - Spawner: fills free weapon spawn points every WEAPON_SPAWN_INTERVAL, weighted by WeaponDef.
##   - Items drift and spin, bounce off walls, and despawn after WEAPON_LIFETIME unless claimed.
##   - A rope fetches an item (Rope FETCH mode); it is equipped on contact. Grabbing a second weapon
##     drops the first with a small push.
##   - Fire: guns shoot with light auto-aim and recoil; an empty gun is thrown; blades swing.
##   - Projectiles hit the first wall or fighter on their path; a well-timed melee parries them.
##   - WPN-04: now and then a legendary weapon is announced, then appears in a dangerous spot (next
##     to a vent, a tank or a black hole, or mid-arena).

## Floating items closer than this to a spawn point keep it occupied (px).
const SPAWN_CLEARANCE: float = 160.0
## A legendary needs this much open space around it (px).
const LEGENDARY_CLEARANCE: float = 90.0
## Thrown weapons fly at most this long (s).
const THROW_LIFETIME: float = 1.5

var sim: MatchSim
var spawn_points: Array[Vector2] = []
var bounds: Rect2 = Rect2(0, 0, 1920, 1080)
var items: Array[WeaponItem] = []
var projectiles: Array[Projectile] = []
## Spawner on/off (modes and tests switch it off).
var spawning: bool = true
## Weapon ids the spawner may pick (empty = all with spawn_weight > 0). Game modes narrow it.
var allowed: Array[StringName] = []
var next_spawn_tick: int = 0
var next_legendary_tick: int = SimIds.NO_TICK
## The announced legendary: {def, pos, at}, or empty.
var legendary_pending: Dictionary = {}

var _defs: Array[WeaponDef] = []


func setup(match_sim: MatchSim, points: Array[Vector2], arena_bounds: Rect2) -> void:
	sim = match_sim
	spawn_points = points
	bounds = arena_bounds
	_defs = WeaponDef.all()
	next_spawn_tick = SimIds.ticks(TuningDB.t.weapon_spawn_interval * 0.5)
	next_legendary_tick = SimIds.ticks(TuningDB.t.legendary_first_delay)


func get_item(item_id: int) -> WeaponItem:
	for item in items:
		if item.id == item_id:
			return item
	return null


func held_by(fighter: Fighter) -> WeaponItem:
	return get_item(fighter.weapon_id) if fighter.weapon_id >= 0 else null


## A fresh item, not yet in the arena list.
func make_item(def: WeaponDef, at: Vector2, velocity: Vector2) -> WeaponItem:
	var item := WeaponItem.new()
	item.id = sim.next_entity_id()
	item.def = def
	item.pos = at
	item.prev_pos = at
	item.vel = velocity
	item.ammo = def.ammo
	item.spin = TuningDB.t.weapon_spin * (1.0 if sim.rng.randf() < 0.5 else -1.0)
	item.expire_tick = sim.tick + SimIds.ticks(TuningDB.t.weapon_lifetime)
	return item


## Places a weapon in the arena (spawner, legendary events, tests).
func spawn(def: WeaponDef, at: Vector2, velocity: Vector2 = Vector2.ZERO) -> WeaponItem:
	var item := make_item(def, at, velocity)
	items.append(item)
	sim.queue_event(&"weapon_spawned", [item.id, def.id, at])
	return item


func step(tick: int) -> void:
	_step_spawner(tick)
	_step_legendary(tick)
	_step_items(tick)
	_step_projectiles(tick)


# --- Items -------------------------------------------------------------------------------------

func _step_spawner(tick: int) -> void:
	if not spawning or spawn_points.is_empty() or tick < next_spawn_tick:
		return
	next_spawn_tick = tick + SimIds.ticks(TuningDB.t.weapon_spawn_interval)
	var free: Array[Vector2] = []
	for p in spawn_points:
		var taken := false
		for item in items:
			if item.state == WeaponItem.State.FLOATING and item.pos.distance_to(p) < SPAWN_CLEARANCE:
				taken = true
				break
		if not taken:
			free.append(p)
	if free.is_empty():
		return
	var def := _pick_def()
	if def == null:
		return
	var at := free[sim.rng.randi_range(0, free.size() - 1)]
	var t := TuningDB.t
	var drift := Vector2.from_angle(sim.rng.randf() * TAU) * sim.rng.randf_range(t.weapon_drift_min, t.weapon_drift_max)
	spawn(def, at, drift)


func _step_legendary(tick: int) -> void:
	if not spawning:
		return
	var t := TuningDB.t
	if not legendary_pending.is_empty():
		if tick >= int(legendary_pending["at"]):
			var def := WeaponDef.load_by_id(legendary_pending["def"])
			if def != null:
				spawn(def, legendary_pending["pos"])
			legendary_pending = {}
			next_legendary_tick = tick + SimIds.ticks(t.legendary_interval)
		return
	if tick < next_legendary_tick:
		return
	var pool: Array[WeaponDef] = []
	for def in _defs:
		if def.legendary and (allowed.is_empty() or def.id in allowed):
			pool.append(def)
	if pool.is_empty():
		next_legendary_tick = tick + SimIds.ticks(t.legendary_interval)
		return
	var pick := pool[sim.rng.randi_range(0, pool.size() - 1)]
	var at := danger_spot()
	legendary_pending = {"def": pick.id, "pos": at, "at": tick + SimIds.ticks(t.legendary_countdown)}
	sim.queue_event(&"legendary_incoming", [pick.id, at, t.legendary_countdown])


## A dangerous place for a legendary (WPN-04): beside an airlock vent, a fuel tank or a black hole,
## or the middle of the arena.
func danger_spot() -> Vector2:
	var spots: Array[Vector2] = [bounds.get_center()]
	for vent in sim.hazards.vents:
		spots.append(vent["pos"] - vent["outward"] * 220.0)
	for obj in sim.hazards.breakables:
		if obj.explosive and obj.active:
			spots.append(obj.center() + Vector2(0, -obj.pivot_radius() - 90.0))
	for hole in sim.hazards.black_holes:
		spots.append(hole + Vector2.from_angle(sim.rng.randf() * TAU) * sim.hazards.black_hole_radius(sim.tick) * 3.0)
	var open := spots.filter(func(p: Vector2) -> bool: return _is_open(p))
	if open.is_empty():
		open = spot_points_or_center()
	return open[sim.rng.randi_range(0, open.size() - 1)]


func spot_points_or_center() -> Array:
	return spawn_points.duplicate() if not spawn_points.is_empty() else [bounds.get_center()]


## Nothing solid within LEGENDARY_CLEARANCE of p.
func _is_open(p: Vector2) -> bool:
	if not bounds.grow(-LEGENDARY_CLEARANCE).has_point(p) or not sim.is_inside_tree():
		return false
	var shape := CircleShape2D.new()
	shape.radius = LEGENDARY_CLEARANCE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, p)
	query.collision_mask = Layers.WORLD_HOOKABLE | Layers.WORLD_SMOOTH
	return sim.get_viewport().world_2d.direct_space_state.intersect_shape(query, 1).is_empty()


func _pick_def() -> WeaponDef:
	var pool: Array[WeaponDef] = []
	var total := 0.0
	for def in _defs:
		if def.spawn_weight <= 0.0 or def.legendary:
			continue
		if not allowed.is_empty() and not def.id in allowed:
			continue
		pool.append(def)
		total += def.spawn_weight
	if pool.is_empty():
		return null
	var roll := sim.rng.randf() * total
	for def in pool:
		roll -= def.spawn_weight
		if roll <= 0.0:
			return def
	return pool[pool.size() - 1]


func _step_items(tick: int) -> void:
	var t := TuningDB.t
	for item in items.duplicate():
		item.prev_pos = item.pos
		match item.state:
			WeaponItem.State.HELD:
				var holder := sim.get_fighter(item.holder_id)
				if holder == null:
					_float_free(item, tick)
					continue
				item.pos = holder.global_position
				item.angle = holder.facing.angle()
			WeaponItem.State.FETCHED:
				item.angle += item.spin * SimIds.DT * 4.0
				item.pos += item.vel * SimIds.DT
			WeaponItem.State.FLOATING:
				item.angle += item.spin * SimIds.DT
				_drift(item, t.weapon_radius)
				if tick >= item.expire_tick:
					items.erase(item)
					sim.queue_event(&"weapon_despawned", [item.id, item.pos])


## Straight drift that bounces off walls and obstacles and stays inside the arena.
func _drift(item: WeaponItem, radius: float) -> void:
	var to: Vector2 = item.pos + item.vel * SimIds.DT
	var hit := cast(item.pos, to + item.vel.normalized() * radius)
	if not hit.is_empty():
		var n: Vector2 = hit["normal"]
		item.vel = item.vel.bounce(n)
		to = item.pos
	item.pos = to.clamp(bounds.position + Vector2(radius, radius), bounds.end - Vector2(radius, radius))


func _float_free(item: WeaponItem, tick: int) -> void:
	item.state = WeaponItem.State.FLOATING
	item.holder_id = -1
	item.fetcher_id = -1
	item.expire_tick = tick + SimIds.ticks(TuningDB.t.weapon_lifetime)


## A rope reached its fetched item: equip it, dropping any weapon already held (§6.3).
func equip(fighter: Fighter, item: WeaponItem) -> void:
	var current := held_by(fighter)
	if current != null and current != item:
		drop(fighter, -fighter.facing)
	item.state = WeaponItem.State.HELD
	item.holder_id = fighter.fighter_id
	item.fetcher_id = -1
	item.vel = Vector2.ZERO
	fighter.weapon_id = item.id
	sim.queue_event(&"weapon_picked", [fighter.fighter_id, item.id, item.def.id])


## Takes an item out of play at once (Gun Game hands out its own weapons).
func discard(item: WeaponItem) -> void:
	if item.state == WeaponItem.State.HELD:
		var holder := sim.get_fighter(item.holder_id)
		if holder != null and holder.weapon_id == item.id:
			holder.weapon_id = -1
	items.erase(item)
	sim.queue_event(&"weapon_despawned", [item.id, item.pos])


## Lets go of the held weapon with a push along dir (zero: just release it in place).
func drop(fighter: Fighter, dir: Vector2) -> void:
	var item := held_by(fighter)
	fighter.weapon_id = -1
	if item == null:
		return
	var t := TuningDB.t
	_float_free(item, sim.tick)
	var push := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.ZERO
	item.pos = fighter.global_position + push * (t.fighter_radius + t.weapon_radius + 4.0)
	item.vel = push * t.weapon_drop_push
	sim.queue_event(&"weapon_dropped", [fighter.fighter_id, item.id, item.pos])


## The first item a hook segment touches, as {item, t} (t in 0..1), or {}.
func item_on_segment(from: Vector2, to: Vector2, fetcher_id: int) -> Dictionary:
	var radius := TuningDB.t.weapon_radius
	var best: WeaponItem = null
	var best_t := INF
	for item in items:
		if item.state == WeaponItem.State.HELD or item.fetcher_id == fetcher_id:
			continue
		var hit_t := Rope._segment_circle(from, to - from, item.pos, radius)
		if hit_t >= 0.0 and hit_t < best_t:
			best = item
			best_t = hit_t
	return {} if best == null else {"item": best, "t": best_t}


# --- Firing ------------------------------------------------------------------------------------

## Fire button (CTL-05): guns shoot, empty guns are thrown, blades swing.
func fire(fighter: Fighter, cmd: InputCommand, tick: int) -> void:
	var item := held_by(fighter)
	if item == null or tick < fighter.fire_ready_tick:
		return
	var def := item.def
	match def.kind:
		WeaponDef.Kind.BLADE:
			if fighter.can_melee(tick):
				fighter.start_melee(tick, cmd.aim_dir if cmd != null else Vector2.ZERO)
		WeaponDef.Kind.GUN:
			var aim := aim_for(fighter, cmd, def.projectile_speed * def.projectile_lifetime)
			if item.ammo <= 0:
				throw_weapon(fighter, item, aim, tick)
				return
			shoot(fighter, item, aim, tick)
		WeaponDef.Kind.SPECIAL:
			sim.special_weapons.fire(fighter, item, cmd, tick)


func shoot(fighter: Fighter, item: WeaponItem, aim: Vector2, tick: int) -> void:
	var def := item.def
	var t := TuningDB.t
	item.ammo -= 1
	fighter.fire_ready_tick = tick + SimIds.ticks(def.fire_cooldown)
	var muzzle := fighter.global_position + aim * (t.fighter_radius + 12.0)
	var n := maxi(1, def.projectile_count)
	for i in n:
		var offset := 0.0 if n == 1 else lerpf(-def.spread_deg * 0.5, def.spread_deg * 0.5, float(i) / float(n - 1))
		var dir := aim.rotated(deg_to_rad(offset))
		var p := Projectile.new()
		p.id = sim.next_entity_id()
		p.kind = Projectile.Kind.BULLET
		p.def = def
		p.owner_id = fighter.fighter_id
		p.pos = muzzle
		p.prev_pos = muzzle
		p.vel = dir * def.projectile_speed
		p.damage = def.projectile_damage
		p.knockback = def.projectile_knockback
		p.radius = def.projectile_radius
		p.expire_tick = tick + SimIds.ticks(def.projectile_lifetime)
		projectiles.append(p)
	apply_recoil(fighter, aim, def.recoil_impulse)
	sim.queue_event(&"weapon_fired", [fighter.fighter_id, def.id, muzzle, aim])


## PHY-06: a push opposite the shot. A clinging shooter is pushed off its surface.
func apply_recoil(fighter: Fighter, aim: Vector2, impulse: float) -> void:
	if impulse <= 0.0:
		return
	if fighter.is_clinging():
		fighter.leave_surface()
	fighter.velocity -= aim * impulse


## WPN-05: an empty gun becomes a projectile.
func throw_weapon(fighter: Fighter, item: WeaponItem, aim: Vector2, tick: int) -> void:
	var t := TuningDB.t
	fighter.weapon_id = -1
	items.erase(item)
	fighter.fire_ready_tick = tick + SimIds.ticks(item.def.fire_cooldown)
	var p := Projectile.new()
	p.id = sim.next_entity_id()
	p.kind = Projectile.Kind.THROWN
	p.def = item.def
	p.owner_id = fighter.fighter_id
	p.pos = fighter.global_position + aim * (t.fighter_radius + 10.0)
	p.prev_pos = p.pos
	p.vel = aim * t.throw_speed + fighter.velocity * 0.5
	p.knockback = t.throw_knockback
	p.radius = t.weapon_radius * 0.6
	p.expire_tick = tick + SimIds.ticks(THROW_LIFETIME)
	projectiles.append(p)
	sim.queue_event(&"weapon_thrown", [fighter.fighter_id, item.def.id, p.pos])


## Light auto-aim (CTL-05): an explicit aim (bots) wins; otherwise the nearest enemy within the cone
## of the fighter's facing and in range, at its lead position; otherwise straight ahead.
func aim_for(fighter: Fighter, cmd: InputCommand, reach: float) -> Vector2:
	if cmd != null and cmd.aim_dir.length_squared() > 0.0001:
		return cmd.aim_dir.normalized()
	var t := TuningDB.t
	var half := deg_to_rad(t.fire_autoaim_cone_deg) * 0.5
	var best_angle := INF
	var best := fighter.facing
	for other in sim.fighters:
		if other == fighter or other.is_ko() or not sim.are_enemies(fighter, other):
			continue
		var offset := other.global_position - fighter.global_position
		var dist := offset.length()
		if dist < 1.0 or dist > reach:
			continue
		var angle := absf(fighter.facing.angle_to(offset))
		if angle <= half and angle < best_angle:
			best_angle = angle
			best = offset / dist
	return best.normalized()


# --- Projectiles -------------------------------------------------------------------------------

func _step_projectiles(tick: int) -> void:
	for p in projectiles.duplicate():
		if p.extra.get("special", false):
			sim.special_weapons.step_projectile(p, tick)
			continue
		if p.extra.has("caught_by"):
			continue
		p.prev_pos = p.pos
		var to: Vector2 = p.pos + p.vel * SimIds.DT
		var hit := cast(p.pos, to)
		var world_t: float = p.pos.distance_to(hit["position"]) / maxf(p.pos.distance_to(to), 0.001) if not hit.is_empty() else 2.0
		var victim: Fighter = null
		var victim_t := INF
		if sim.authoritative:
			var shooter := sim.get_fighter(p.owner_id)
			for f in sim.fighters:
				if f.fighter_id == p.owner_id or not f.can_be_hit(tick):
					continue
				# No friendly fire in team modes; the Survival boss's shots spare its own side.
				if shooter != null and not sim.are_enemies(shooter, f):
					continue
				if p.extra.get("boss", false) and int(sim.teams.get(f.fighter_id, 0)) == 1:
					continue
				var ft := Rope._segment_circle(p.pos, to - p.pos, f.global_position, TuningDB.t.fighter_radius + p.radius)
				if ft >= 0.0 and ft < victim_t:
					victim = f
					victim_t = ft
		if victim != null and victim_t <= world_t:
			var point: Vector2 = p.pos.lerp(to, victim_t)
			if victim.is_parrying(tick, p.vel):
				reflect(p, victim, point)
				continue
			if sim.special_weapons._shield_blocks(victim, p.vel):
				projectiles.erase(p)
				sim.queue_event(&"projectile_blocked", [point, p.def.id if p.def != null else &""])
				continue
			hit_fighter(p, victim, point, tick)
			projectiles.erase(p)
			continue
		if not hit.is_empty():
			projectiles.erase(p)
			var obj := hit["collider"] as ArenaObject
			if obj != null and sim.mode != null and sim.mode.on_object_hit(obj, hit["position"], _impact_damage(p), p.owner_id, tick):
				continue
			if obj != null and obj.is_breakable():
				# ARN-08 / ARN-09: shots damage breakables and set off fuel tanks.
				sim.hazards.damage_object(obj, _impact_damage(p), p.owner_id, tick)
			sim.queue_event(&"projectile_blocked", [hit["position"], p.def.id if p.def != null else &""])
			continue
		p.pos = to
		if tick >= p.expire_tick:
			projectiles.erase(p)


func _impact_damage(p: Projectile) -> float:
	return TuningDB.t.throw_damage_base if p.kind == Projectile.Kind.THROWN else p.damage


## Damage and knockback from a projectile; thrown weapons hit harder the faster they close.
func hit_fighter(p: Projectile, victim: Fighter, point: Vector2, tick: int) -> void:
	var t := TuningDB.t
	var dir: Vector2 = p.vel.normalized()
	var dmg: float = p.damage
	var cause := &"shot"
	if p.kind == Projectile.Kind.THROWN:
		var closing: float = maxf(0.0, (p.vel - victim.velocity).dot(dir))
		dmg = t.throw_damage_base + t.throw_damage_per_speed * closing
		cause = &"thrown"
	elif p.kind == Projectile.Kind.DEBRIS:
		cause = &"debris"
	sim.queue_event(&"hit_landed", [p.owner_id, victim.fighter_id, dmg, p.knockback, false])
	victim.take_hit(tick, p.owner_id, dmg, dir * p.knockback, t.projectile_hitstop_ticks, cause)
	if not victim.is_ko():
		victim.freeze_ticks = maxi(victim.freeze_ticks, t.projectile_hitstop_ticks)


## MEL-04: a parried projectile flies back at whoever fired it and now belongs to the parrier.
func reflect(p: Projectile, parrier: Fighter, point: Vector2) -> void:
	var shooter := sim.get_fighter(p.owner_id)
	var speed: float = p.vel.length()
	var back: Vector2 = -p.vel.normalized()
	if shooter != null and not shooter.is_ko():
		back = (shooter.global_position - point).normalized()
	p.vel = back * speed
	p.pos = point + back * (TuningDB.t.fighter_radius + p.radius + 2.0)
	p.owner_id = parrier.fighter_id
	p.expire_tick = sim.tick + SimIds.ticks(p.def.projectile_lifetime if p.def != null else 1.0)
	sim.queue_event(&"parried", [parrier.fighter_id, point])


func cast(from: Vector2, to: Vector2) -> Dictionary:
	var space := sim.get_viewport().world_2d.direct_space_state if sim.is_inside_tree() else null
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to, Layers.WORLD_HOOKABLE | Layers.WORLD_SMOOTH)
	return space.intersect_ray(query)


# --- State -------------------------------------------------------------------------------------

func get_state() -> Dictionary:
	var item_states: Array = []
	for item in items:
		item_states.append(item.get_state())
	var projectile_states: Array = []
	for p in projectiles:
		projectile_states.append(p.get_state())
	return {"items": item_states, "projectiles": projectile_states, "next_spawn": next_spawn_tick, "next_legendary": next_legendary_tick, "legendary": legendary_pending.duplicate()}


func set_state(s: Dictionary) -> void:
	items.clear()
	for item_state: Dictionary in s["items"]:
		items.append(WeaponItem.from_state(item_state))
	projectiles.clear()
	for p_state: Dictionary in s["projectiles"]:
		projectiles.append(Projectile.from_state(p_state))
	next_spawn_tick = s["next_spawn"]
	next_legendary_tick = s.get("next_legendary", SimIds.NO_TICK)
	legendary_pending = s.get("legendary", {}).duplicate()
