class_name Rope
extends Node
## A fighter's grapple (§4.6). Stepped by its Fighter; never reads input itself.
## After attaching, the rope is a straight line and does not wrap around obstacles (D13).
##
## Surface modes, picked when the hook attaches:
##   REEL  - pulled in toward the hook point (ROPE-01)
##   ORBIT - swung around the object like a ball on a string, slowly tightening (ROPE-04)
##   SWING - dragged around by a rotating obstacle (ROPE-05)
## Hooking an enemy instead pulls them in (PULL, ROPE-03); hooking a weapon fetches it (FETCH, ROPE-02).
## Phase 6: hooking a thrown projectile catches it and whips it back (CATCH, ROPE-06); crossing an
## enemy's rope locks both into a tap duel (DUEL, ROPE-07, run by SpecialWeapons). Hooking a
## shield holder from the front rips the shield away instead of pulling them.

var fighter: Fighter
var state: SimIds.RopeState = SimIds.RopeState.IDLE
var mode: SimIds.RopeMode = SimIds.RopeMode.NONE
## True once the finger that fired this rope has lifted: the rope then finishes on its own.
var latched: bool = false
## Drawn end of the rope. While orbiting a round object it sits on the surface facing the fighter.
var hook_pos: Vector2 = Vector2.ZERO
## Hook position at the start of the tick, for interpolating views.
var prev_hook_pos: Vector2 = Vector2.ZERO
var anchor_object: ArenaObject = null
## The enemy being pulled (mode PULL), else null.
var pull_target: Fighter = null
## The weapon being fetched (mode FETCH), else -1.
var fetch_item_id: int = -1
## The projectile being hauled in (mode CATCH), else -1.
var caught_id: int = -1
## Taut length, measured from pivot_world(). It only shrinks.
var length: float = 0.0
var attach_tick: int = 0
## 0..1, how hard the rope pulled this tick. View and sound only.
var tension: float = 0.0

var _hook_dir: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0
var _anchor_local: Vector2 = Vector2.ZERO
## Orbiting a round object pivots on its center instead of the hook point (§4.6 Orbit).
var _pivot_on_center: bool = false
var _pivot_radius: float = 0.0
## Swing: anchor-to-fighter direction in the moving object's local space, so it turns with it.
var _swing_local_dir: Vector2 = Vector2.RIGHT
var _retract_ticks_left: int = 0
var _retract_total: int = 1
var _retract_from: Vector2 = Vector2.ZERO


func is_out() -> bool:
	return state == SimIds.RopeState.FLYING or state == SimIds.RopeState.ATTACHED


func is_attached() -> bool:
	return state == SimIds.RopeState.ATTACHED


func is_swinging() -> bool:
	return state == SimIds.RopeState.ATTACHED and mode == SimIds.RopeMode.SWING


## The attach point in world space. It moves with moving objects.
func anchor_world() -> Vector2:
	if anchor_object == null:
		return hook_pos
	return anchor_object.to_global(_anchor_local)


## The point the fighter circles: the object's center when orbiting a round object, else the anchor.
func pivot_world() -> Vector2:
	if _pivot_on_center and anchor_object != null:
		return anchor_object.global_position
	return anchor_world()


func fire(tick: int, target: Vector2) -> void:
	var origin := fighter.global_position
	var dir := target - origin
	_hook_dir = dir.normalized() if dir.length_squared() > 0.0001 else fighter.facing
	state = SimIds.RopeState.FLYING
	mode = SimIds.RopeMode.NONE
	latched = false
	anchor_object = null
	_pivot_on_center = false
	_pivot_radius = 0.0
	hook_pos = origin
	prev_hook_pos = origin
	_traveled = 0.0
	fighter.rope_cooldown_until_tick = tick + SimIds.ticks(TuningDB.t.rope_cooldown)
	fighter.emit_event(&"rope_fired", [fighter.fighter_id, target])


## Lets go. The fighter keeps its velocity (PHY-04, ROPE-12). Releasing an orbit or swing adds the
## slingshot bonus unless fling is false (the rope detaching because the fighter clung).
func release(fling: bool = true) -> void:
	if not is_out():
		return
	var fling_mode := SimIds.RopeMode.NONE
	if fling and state == SimIds.RopeState.ATTACHED and mode != SimIds.RopeMode.PULL:
		var t := TuningDB.t
		match mode:
			SimIds.RopeMode.ORBIT:
				fling_mode = mode
				fighter.velocity = (fighter.velocity * t.slingshot_release_bonus).limit_length(t.max_speed)
			SimIds.RopeMode.SWING:
				fling_mode = mode
				fighter.velocity = (fighter.velocity * t.swing_release_bonus).limit_length(t.max_speed)
	_start_retract()
	fighter.on_rope_released()
	fighter.emit_event(&"rope_released", [fighter.fighter_id, fling_mode])


func reset() -> void:
	_end_pull()
	_end_fetch()
	_end_catch()
	state = SimIds.RopeState.IDLE
	mode = SimIds.RopeMode.NONE
	anchor_object = null
	_pivot_on_center = false
	_pivot_radius = 0.0
	latched = false
	tension = 0.0
	hook_pos = fighter.global_position
	prev_hook_pos = hook_pos


## §3.3 step 3c.
func step(tick: int) -> void:
	prev_hook_pos = hook_pos
	tension = 0.0
	match state:
		SimIds.RopeState.FLYING:
			_step_flying(tick)
		SimIds.RopeState.ATTACHED:
			_step_attached(tick)
		SimIds.RopeState.RETRACTING:
			_step_retracting()


## Where a swinging fighter should be this tick (§4.6 Swing): rope length out from the moving anchor,
## along a direction that turns with the object, so the fighter is carried round at the object's
## speed. The fighter moves there with collision and takes the displacement as its velocity.
##
## Deviation from §4.6, which places the fighter along its *current* direction from the anchor: a
## point dragged that way around a circle of radius R settles at radius sqrt(R² - L²), inside the
## turbine arm's sweep (about 130 px for the Hangar turbine), so it would always hit the arm.
func swing_target() -> Vector2:
	var dir := anchor_object.global_transform.basis_xform(_swing_local_dir).normalized()
	return anchor_world() + dir * length


## Taut rope after the fighter moved (§4.6). Swing needs nothing: its move already lands on the circle.
func post_move() -> void:
	if state != SimIds.RopeState.ATTACHED:
		return
	match mode:
		SimIds.RopeMode.REEL:
			_constrain(anchor_world(), false)
		SimIds.RopeMode.ORBIT:
			var pivot := pivot_world()
			_constrain(pivot, true)
			hook_pos = _orbit_hook_point(pivot)


func get_state() -> Dictionary:
	return {
		"state": state,
		"mode": mode,
		"latched": latched,
		"hook_pos": hook_pos,
		"hook_dir": _hook_dir,
		"traveled": _traveled,
		"anchor_obj": anchor_object.object_id if anchor_object != null else -1,
		"pull_target": pull_target.fighter_id if pull_target != null else -1,
		"fetch_item": fetch_item_id,
		"caught": caught_id,
		"anchor_local": _anchor_local,
		"pivot_on_center": _pivot_on_center,
		"pivot_radius": _pivot_radius,
		"swing_local_dir": _swing_local_dir,
		"length": length,
		"attach_tick": attach_tick,
		"retract_left": _retract_ticks_left,
		"retract_total": _retract_total,
		"retract_from": _retract_from,
	}


func set_state(s: Dictionary) -> void:
	state = s["state"]
	mode = s["mode"]
	latched = s["latched"]
	hook_pos = s["hook_pos"]
	prev_hook_pos = hook_pos
	_hook_dir = s["hook_dir"]
	_traveled = s["traveled"]
	var obj_id: int = s["anchor_obj"]
	anchor_object = fighter.sim.get_object(obj_id) if obj_id >= 0 and fighter.sim != null else null
	_anchor_local = s["anchor_local"]
	var target_id: int = s["pull_target"]
	pull_target = fighter.sim.get_fighter(target_id) if target_id >= 0 and fighter.sim != null else null
	fetch_item_id = s.get("fetch_item", -1)
	caught_id = s.get("caught", -1)
	_pivot_on_center = s["pivot_on_center"]
	_pivot_radius = s["pivot_radius"]
	_swing_local_dir = s["swing_local_dir"]
	length = s["length"]
	attach_tick = s["attach_tick"]
	_retract_ticks_left = s["retract_left"]
	_retract_total = s["retract_total"]
	_retract_from = s["retract_from"]


func _step_flying(tick: int) -> void:
	var t := TuningDB.t
	var step_len := minf(t.hook_speed * SimIds.DT, t.rope_range - _traveled)
	var to := hook_pos + _hook_dir * step_len
	var hit := _cast(hook_pos, to)
	var target_t := 2.0
	var target := _first_fighter_on(hook_pos, to)
	if target != null:
		target_t = _segment_circle(hook_pos, to - hook_pos, target.global_position, t.fighter_radius)
	var world_t := hook_pos.distance_to(hit["position"]) / step_len if not hit.is_empty() and step_len > 0.0 else 2.0
	var item_hit := {}
	if fighter.sim != null and fighter.sim.authoritative:
		item_hit = fighter.sim.weapons.item_on_segment(hook_pos, to, fighter.fighter_id)
	var item_t: float = item_hit.get("t", 2.0)
	var catch_hit := {}
	var rope_hit := {}
	if fighter.sim != null and fighter.sim.authoritative:
		catch_hit = fighter.sim.special_weapons.catchable_on_segment(hook_pos, to, fighter)
		rope_hit = fighter.sim.special_weapons.rope_on_segment(hook_pos, to, fighter)
	var catch_t: float = catch_hit.get("t", 2.0)
	var rope_t: float = rope_hit.get("t", 2.0)
	if not catch_hit.is_empty() and catch_t <= world_t and catch_t < target_t and catch_t < item_t and catch_t < rope_t:
		var at := hook_pos.lerp(to, catch_t)
		_traveled += hook_pos.distance_to(at)
		hook_pos = at
		_hit_projectile(tick, catch_hit["projectile"], at)
		return
	if not rope_hit.is_empty() and rope_t <= world_t and rope_t < target_t and rope_t < item_t:
		var at := hook_pos.lerp(to, rope_t)
		_traveled += hook_pos.distance_to(at)
		hook_pos = at
		fighter.sim.special_weapons.start_duel(fighter, rope_hit["fighter"], at, tick)
		return
	if not item_hit.is_empty() and item_t <= world_t and item_t < target_t:
		var at := hook_pos.lerp(to, item_t)
		_traveled += hook_pos.distance_to(at)
		hook_pos = at
		_hit_item(tick, item_hit["item"], at)
		return
	if target != null and target_t <= world_t:
		var point := hook_pos.lerp(to, target_t)
		_traveled += hook_pos.distance_to(point)
		hook_pos = point
		_hit_fighter(tick, target, point)
		return
	if not hit.is_empty():
		var point: Vector2 = hit["position"]
		hook_pos = point
		var obj := hit["collider"] as ArenaObject
		if obj != null and obj.hookable:
			_attach_surface(tick, obj, point)
		else:
			# Smooth panels (Phase 4) bounce the hook.
			_start_retract()
		return
	hook_pos = to
	_traveled += step_len
	var leaving := fighter.sim != null and fighter.sim.hazards.wrap and not fighter.sim.hazards.bounds.has_point(hook_pos)
	if leaving or _traveled >= t.rope_range - 0.01:
		_start_retract()
		fighter.emit_event(&"rope_missed", [fighter.fighter_id])
		if fighter.is_clinging():
			# A rope fired from a wall that finds nothing still pushes off toward where it was aimed,
			# so a tap out of rope range never leaves the fighter stuck (D38).
			fighter.kick_toward(_hook_dir)


## ROPE-03: hooking an enemy pulls them in, unless they are pull immune (CNT-03) or invulnerable:
## then the hook clinks off.
func _hit_fighter(tick: int, target: Fighter, point: Vector2) -> void:
	if target.is_parrying(tick, _hook_dir):
		# CNT-02 / MEL-04: a well-timed melee knocks the incoming hook away.
		_start_retract()
		fighter.emit_event(&"parried", [target.fighter_id, point])
		return
	if not target.can_be_pulled(tick):
		_start_retract()
		fighter.emit_event(&"rope_bounced", [fighter.fighter_id, point])
		return
	var shield := fighter.sim.weapons.held_by(target) if fighter.sim != null else null
	if shield != null and shield.def.projectile_kind == &"shield" and target.facing.dot(-_hook_dir) > 0.0:
		# The shield is torn off and fetched instead of its holder.
		fighter.sim.weapons.drop(target, -_hook_dir)
		fighter.emit_event(&"shield_ripped", [target.fighter_id, point])
		_hit_item(tick, shield, shield.pos)
		return
	pull_fighter(target, tick)
	if fighter.sim != null:
		fighter.sim.on_contact(fighter, target, &"rope")


## Starts pulling target, with no checks (a hook hit, or winning a tug-of-war).
func pull_fighter(target: Fighter, tick: int) -> void:
	if state == SimIds.RopeState.ATTACHED:
		_end_pull()
		_end_fetch()
		_end_catch()
	state = SimIds.RopeState.ATTACHED
	mode = SimIds.RopeMode.PULL
	pull_target = target
	attach_tick = tick
	hook_pos = target.global_position
	length = fighter.global_position.distance_to(hook_pos)
	target.begin_pulled(fighter.fighter_id, tick)
	fighter.emit_event(&"rope_attached", [fighter.fighter_id, mode, hook_pos])


## ROPE-06: the hook caught a thrown projectile; it is hauled in, then whipped back (_step_catch).
func _hit_projectile(tick: int, p: Projectile, point: Vector2) -> void:
	state = SimIds.RopeState.ATTACHED
	mode = SimIds.RopeMode.CATCH
	caught_id = p.id
	attach_tick = tick
	hook_pos = point
	p.extra["caught_by"] = fighter.fighter_id
	p.vel = Vector2.ZERO
	fighter.emit_event(&"projectile_caught", [fighter.fighter_id, point])


## ROPE-07: locked at point until the duel ends (SpecialWeapons decides the winner).
func enter_duel(point: Vector2, tick: int) -> void:
	_end_pull()
	_end_fetch()
	_end_catch()
	state = SimIds.RopeState.ATTACHED
	mode = SimIds.RopeMode.DUEL
	anchor_object = null
	_pivot_on_center = false
	attach_tick = tick
	hook_pos = point
	length = fighter.global_position.distance_to(point)
	if fighter.state != SimIds.FighterState.KO:
		fighter.enter_rope_state(SimIds.FighterState.REELING)


## ROPE-02: hooking a weapon pulls it in; it is equipped when it reaches the fighter. A weapon already
## being fetched by someone else can be snatched.
func _hit_item(tick: int, item: WeaponItem, point: Vector2) -> void:
	if item.fetcher_id >= 0 and item.fetcher_id != fighter.fighter_id:
		var rival := fighter.sim.get_fighter(item.fetcher_id)
		if rival != null and rival.rope.fetch_item_id == item.id:
			rival.rope.release(false)
	state = SimIds.RopeState.ATTACHED
	mode = SimIds.RopeMode.FETCH
	fetch_item_id = item.id
	attach_tick = tick
	hook_pos = item.pos
	length = fighter.global_position.distance_to(item.pos)
	item.state = WeaponItem.State.FETCHED
	item.fetcher_id = fighter.fighter_id
	fighter.emit_event(&"rope_attached", [fighter.fighter_id, mode, point])


func _attach_surface(tick: int, obj: ArenaObject, point: Vector2) -> void:
	state = SimIds.RopeState.ATTACHED
	anchor_object = obj
	_anchor_local = obj.to_local(point)
	attach_tick = tick
	mode = pick_surface_mode(obj, point)
	_pivot_on_center = mode == SimIds.RopeMode.ORBIT and obj.orbit_pivot
	_pivot_radius = obj.pivot_radius() if _pivot_on_center else 0.0
	length = fighter.global_position.distance_to(pivot_world())
	match mode:
		SimIds.RopeMode.ORBIT:
			fighter.enter_rope_state(SimIds.FighterState.ORBITING)
			hook_pos = _orbit_hook_point(pivot_world())
		SimIds.RopeMode.SWING:
			var out := fighter.global_position - point
			if out.length_squared() < 0.0001:
				out = -_hook_dir
			_swing_local_dir = obj.global_transform.basis_xform_inv(out.normalized())
			fighter.enter_rope_state(SimIds.FighterState.SWINGING)
		_:
			fighter.enter_rope_state(SimIds.FighterState.REELING)
	fighter.emit_event(&"rope_attached", [fighter.fighter_id, mode, point])


## Mode table in §4.6, checked at the moment the hook attaches.
func pick_surface_mode(obj: ArenaObject, point: Vector2) -> SimIds.RopeMode:
	if obj.is_moving:
		return SimIds.RopeMode.SWING
	var t := TuningDB.t
	var v := fighter.velocity
	var to_anchor := point - fighter.global_position
	if v.length_squared() < 0.0001 or to_anchor.length_squared() < 0.0001:
		return SimIds.RopeMode.REEL
	var dir := to_anchor.normalized()
	var tangential := absf(v.cross(dir))
	var angle := rad_to_deg(absf(v.angle_to(dir)))
	if tangential >= t.orbit_min_tangent_speed and angle >= t.orbit_min_angle:
		return SimIds.RopeMode.ORBIT
	return SimIds.RopeMode.REEL


func _step_attached(tick: int) -> void:
	match mode:
		SimIds.RopeMode.REEL:
			hook_pos = anchor_world()
			_step_reel(tick)
		SimIds.RopeMode.ORBIT:
			_step_orbit(tick)
		SimIds.RopeMode.SWING:
			hook_pos = anchor_world()
			_step_swing(tick)
		SimIds.RopeMode.PULL:
			_step_pull(tick)
		SimIds.RopeMode.FETCH:
			_step_fetch()
		SimIds.RopeMode.CATCH:
			_step_catch(tick)
		SimIds.RopeMode.DUEL:
			fighter.velocity *= SpecialWeapons.DUEL_DAMP


## ROPE-01: accelerate toward the anchor, capping only the speed toward it.
func _step_reel(tick: int) -> void:
	var t := TuningDB.t
	var to_anchor := hook_pos - fighter.global_position
	var dist := to_anchor.length()
	if dist < 0.001:
		return
	var dir := to_anchor / dist
	var v := fighter.velocity + dir * t.reel_accel * SimIds.DT
	var along := v.dot(dir)
	if along > t.reel_max_speed:
		v -= dir * (along - t.reel_max_speed)
	fighter.velocity = v
	tension = clampf(v.dot(dir) / t.reel_max_speed, 0.0, 1.0)
	if latched and tick - attach_tick >= SimIds.ticks(t.reel_max_time):
		release()


## ROPE-03 / ROPE-13: accelerate the target toward the puller's current position (capping its speed
## toward the puller); the puller lurches a little the other way. The pull ends on arrival or
## timeout, and the target keeps its velocity, so it flies past the puller: that is the moment to
## melee. Hits, clinging and releases end it from elsewhere.
func _step_pull(tick: int) -> void:
	var t := TuningDB.t
	var target := pull_target
	if target == null or target.is_ko():
		release(false)
		return
	hook_pos = target.global_position
	var to_puller := fighter.global_position - target.global_position
	var dist := to_puller.length()
	if dist <= t.pull_arrive_dist or tick - attach_tick >= SimIds.ticks(t.pull_max_time):
		release(false)
		return
	var dir := to_puller / dist
	target.last_pulled_by_id = fighter.fighter_id
	target.last_pulled_tick = tick
	if target.is_clinging():
		# CNT-01: the target holds on and its cling drains faster; the puller is dragged toward it
		# instead, a tug-of-war it wins once the target's grip runs out.
		target.cling_ticks_left -= int(t.cling_pull_drain_mult) - 1
		if not fighter.is_clinging():
			fighter.velocity -= dir * t.pull_accel * t.cling_pull_resistance * SimIds.DT
		tension = t.cling_pull_resistance
		return
	var v := target.velocity + dir * t.pull_accel * SimIds.DT
	var along := v.dot(dir)
	if along > t.pull_max_speed:
		v -= dir * (along - t.pull_max_speed)
	target.velocity = v
	if not fighter.is_clinging():
		fighter.velocity -= dir * t.pull_reaction * t.pull_accel * SimIds.DT
	tension = clampf(v.dot(dir) / t.pull_max_speed, 0.0, 1.0)


## ROPE-02: haul the weapon in at pull speed and equip it on arrival.
func _step_fetch() -> void:
	var t := TuningDB.t
	var item := fighter.sim.weapons.get_item(fetch_item_id) if fighter.sim != null else null
	if item == null or item.state != WeaponItem.State.FETCHED or item.fetcher_id != fighter.fighter_id:
		release(false)
		return
	hook_pos = item.pos
	var offset := fighter.global_position - item.pos
	if offset.length() <= t.fighter_radius + t.weapon_radius:
		fighter.sim.weapons.equip(fighter, item)
		release(false)
		return
	item.vel = offset.normalized() * t.pull_max_speed
	tension = 0.5


## ROPE-06: haul the caught projectile in fast; at the fighter it is whipped back at the nearest
## enemy (or straight ahead) and now belongs to the catcher.
func _step_catch(tick: int) -> void:
	var p := _caught()
	if p == null:
		release(false)
		return
	var offset := fighter.global_position - hook_pos
	var t := TuningDB.t
	if offset.length() <= t.fighter_radius + p.radius + 8.0:
		var aim := fighter.sim.weapons.aim_for(fighter, null, 1600.0)
		p.extra.erase("caught_by")
		p.owner_id = fighter.fighter_id
		p.pos = fighter.global_position + aim * (t.fighter_radius + p.radius + 4.0)
		p.prev_pos = p.pos
		p.vel = aim * maxf(SpecialWeapons.WHIP_SPEED, p.def.projectile_speed if p.def != null else 0.0)
		p.expire_tick = maxi(p.expire_tick, tick + SimIds.ticks(1.2))
		if p.extra.get("kind") == &"boomerang":
			p.extra["back"] = false
			p.extra["traveled"] = 0.0
		caught_id = -1
		fighter.emit_event(&"projectile_whipped", [fighter.fighter_id, p.pos])
		release(false)
		return
	hook_pos += offset.normalized() * minf(offset.length(), t.pull_max_speed * 1.3 * SimIds.DT)
	p.prev_pos = p.pos
	p.pos = hook_pos
	p.expire_tick = maxi(p.expire_tick, tick + 2)
	tension = 0.5


func _caught() -> Projectile:
	if caught_id < 0 or fighter.sim == null:
		return null
	for p in fighter.sim.weapons.projectiles:
		if p.id == caught_id:
			return p
	return null


## A caught projectile that never arrived drops where it is.
func _end_catch() -> void:
	var p := _caught()
	caught_id = -1
	if p != null:
		p.extra.erase("caught_by")


## ROPE-04: no reel force. The rope tightens slowly and angular momentum is kept
## (v_tangential × length stays constant), so orbiting longer makes you faster: the slingshot.
func _step_orbit(tick: int) -> void:
	var t := TuningDB.t
	var pivot := pivot_world()
	var offset := fighter.global_position - pivot
	var dist := offset.length()
	var out := offset / dist if dist > 0.001 else Vector2.RIGHT
	var tangent := out.orthogonal()
	var vt := fighter.velocity.dot(tangent)
	var min_len := minf(t.orbit_min_length + _pivot_radius, length)
	var new_len := maxf(length - t.orbit_reel_speed * SimIds.DT, min_len)
	if new_len < length:
		var vr := fighter.velocity.dot(out)
		vt = clampf(vt * length / new_len, -t.max_speed, t.max_speed)
		fighter.velocity = tangent * vt + out * vr
		length = new_len
	hook_pos = _orbit_hook_point(pivot)
	tension = clampf(absf(vt) / t.reel_max_speed, 0.0, 1.0)
	if latched and tick - attach_tick >= SimIds.ticks(t.latched_orbit_max_time):
		release()


## ROPE-05: reel in to SWING_MIN_LENGTH, then hold it. The fighter's move (Fighter._move) goes to
## swing_target(), so the turbine carries it around.
func _step_swing(tick: int) -> void:
	var t := TuningDB.t
	var min_len := minf(t.swing_min_length, length)
	length = maxf(length - t.reel_max_speed * SimIds.DT, min_len)
	tension = clampf(fighter.velocity.length() / t.reel_max_speed, 0.0, 1.0)
	if latched and tick - attach_tick >= SimIds.ticks(t.latched_orbit_max_time):
		release()


## Pulls the fighter back onto the rope circle and handles outward speed. Reel removes it (taut,
## inelastic rope). Orbit turns it along the circle at the same speed instead: each tick's
## straight-line step drifts slightly outward, and dropping that part would bleed off the speed
## the slingshot depends on.
func _constrain(center: Vector2, keep_speed: bool) -> void:
	var offset := fighter.global_position - center
	var dist := offset.length()
	if dist > length and dist > 0.001:
		var out := offset / dist
		fighter.global_position = center + out * length
		var outward := fighter.velocity.dot(out)
		if outward > 0.0:
			var speed := fighter.velocity.length()
			fighter.velocity -= out * outward
			if keep_speed and fighter.velocity.length_squared() > 0.0001:
				fighter.velocity = fighter.velocity.normalized() * speed
		dist = length
	length = minf(length, dist)


func _orbit_hook_point(pivot: Vector2) -> Vector2:
	if not _pivot_on_center:
		return pivot
	var out := fighter.global_position - pivot
	if out.length_squared() < 0.0001:
		return pivot
	return pivot + out.normalized() * _pivot_radius


func _start_retract() -> void:
	_end_pull()
	_end_fetch()
	_end_catch()
	state = SimIds.RopeState.RETRACTING
	mode = SimIds.RopeMode.NONE
	anchor_object = null
	_pivot_on_center = false
	_pivot_radius = 0.0
	tension = 0.0
	_retract_from = hook_pos
	_retract_total = maxi(1, SimIds.ticks(TuningDB.t.rope_retract_time))
	_retract_ticks_left = _retract_total


func _step_retracting() -> void:
	_retract_ticks_left -= 1
	if _retract_ticks_left <= 0:
		state = SimIds.RopeState.IDLE
		hook_pos = fighter.global_position
		return
	var k := float(_retract_ticks_left) / float(_retract_total)
	hook_pos = fighter.global_position.lerp(_retract_from, k)


## A fetched weapon that didn't arrive floats free again.
func _end_fetch() -> void:
	if fetch_item_id < 0:
		return
	var item := fighter.sim.weapons.get_item(fetch_item_id) if fighter.sim != null else null
	fetch_item_id = -1
	if item != null and item.state == WeaponItem.State.FETCHED and item.fetcher_id == fighter.fighter_id:
		item.state = WeaponItem.State.FLOATING
		item.fetcher_id = -1
		item.expire_tick = fighter.sim.tick + SimIds.ticks(TuningDB.t.weapon_lifetime)


## Every way a pull ends goes through here: the target keeps its velocity and gets pull immunity.
func _end_pull() -> void:
	if pull_target == null:
		return
	var target := pull_target
	pull_target = null
	target.end_pulled(fighter.sim.tick if fighter.sim != null else 0)


## Hooks hit fighters by a segment-vs-circle test on sim positions, not physics queries: Godot
## applies a kinematic body's new transform in the physics server only at the next physics step.
func _first_fighter_on(from: Vector2, to: Vector2) -> Fighter:
	# Only the authoritative sim (offline or LAN host) decides fighter hits; clients pass through and
	# take the result from the next snapshot (§6.2).
	if fighter.sim == null or not fighter.sim.authoritative:
		return null
	var radius := TuningDB.t.fighter_radius
	var best: Fighter = null
	var best_t := INF
	for other in fighter.sim.fighters:
		if other == fighter or other.is_ko():
			continue
		var hit_t := _segment_circle(from, to - from, other.global_position, radius)
		if hit_t >= 0.0 and hit_t < best_t:
			best = other
			best_t = hit_t
	return best


## First t in [0, 1] where from + seg * t touches the circle, 0 if it starts inside, -1 for a miss.
static func _segment_circle(from: Vector2, seg: Vector2, center: Vector2, radius: float) -> float:
	var m := from - center
	var c := m.dot(m) - radius * radius
	if c <= 0.0:
		return 0.0
	var a := seg.dot(seg)
	if a < 0.000001:
		return -1.0
	var b := m.dot(seg)
	var disc := b * b - a * c
	if disc < 0.0:
		return -1.0
	var hit_t := (-b - sqrt(disc)) / a
	return hit_t if hit_t >= 0.0 and hit_t <= 1.0 else -1.0


func _cast(from: Vector2, to: Vector2) -> Dictionary:
	var exclude: Array[RID] = [fighter.get_rid()]
	var query := PhysicsRayQueryParameters2D.create(from, to, Layers.HOOK_MASK, exclude)
	return fighter.get_world_2d().direct_space_state.intersect_ray(query)
