class_name BotController
extends RefCounted
## AI input source (§4.9). It produces one InputCommand per tick like a human player and never moves
## its fighter directly. Its randomness comes from MatchSim.rng, so a bot match replays exactly
## from its seed. Bots aim at exact points (no aim assist) and always latch their ropes.
##
## Perception runs every perception_interval_ticks. Rules, first match wins:
##   1. HITSTUN or KO: nothing.
##   1b. Hazards (§6.4): pulled by an open vent or a black hole, or outside the Closing Walls zone:
##       rope the anchor that leads most away from the danger.
##   2. Being pulled: with escape_chance (once per pull), rope the anchor most away from the puller.
##   3. Melee: the player is close and closing, or arriving from the bot's own pull.
##   3b. Armed (§6.3): shoot at the player in range and in sight (fire_rate per second), throw an empty
##       gun from close range. A blade just extends the melee reach. Phase 6 weapons: projectile
##       ones are aimed like guns (explosives not point-blank); repulsor, magnet and thruster are
##       used when they'd help. A thrusting bot steers at its target; in a rope duel it taps.
##   4. Rope the player when in range, in sight and pullable (aggression attempts per second).
##   4b. Unarmed: rope a floating weapon in reach (weapon_interest per perception).
##   5. Clinging too long, or drifting slowly (or, far from a mode goal (§6.5), clinging at all or
##      flying the wrong way): grapple to an anchor that keeps a good distance and
##      can see the player. While the player is ropeable a clinging bot stays put instead, so rule 4
##      keeps getting its chances (tuning after the M5 measurements; §4.9 roams regardless).
##   6. Otherwise keep doing the current action.

## A hazard pull at least this strong (0..1, HazardSystem.danger_at) makes the bot flee.
const HAZARD_DANGER: float = 0.25
## Closer than this to its mode goal, a bot fights normally (px).
const GOAL_REACHED: float = 260.0
## Phase 6 weapons a bot aims and fires like a gun, and the ones it won't fire at close range.
const AIMED_SPECIALS: Array[StringName] = [&"rocket", &"laser", &"boomerang", &"harpoon", &"freeze", &"sticky", &"gravity", &"black_hole_bomb", &"tether_mine", &"tether_rope"]
const POINT_BLANK_UNSAFE: Array[StringName] = [&"rocket", &"sticky", &"black_hole_bomb", &"gravity"]
## Rope-duel taps per second per point of fire_rate.
const DUEL_TAPS_PER_FIRE: float = 2.5
## A goal anchor has to bring the bot at least this much closer (px).
const GOAL_PROGRESS: float = 150.0
## A grapple that ends clinging closer than this to where it started got stuck on a corner (px);
## that anchor is skipped for BLOCK_TIME seconds.
const STUCK_DISTANCE: float = 60.0
const BLOCK_TIME: float = 5.0
## Directions a bot looks in for a spot to rope toward its goal.
const GOAL_RAYS: int = 16
## Far from its goal, a bot leaves a wall after this long (s).
const GOAL_CLING_TIME: float = 0.3

var fighter: Fighter
var sim: MatchSim
var profile: BotProfile
var anchors: Array[Vector2] = []

## What the bot decided last and where, for the world debug view.
var intent: StringName = &"idle"
var intent_point: Vector2 = Vector2.INF

var _melee_tick: int = -1
var _body_shape: CircleShape2D
var _last_goal_anchor: Vector2 = Vector2.INF
## Stuck memory: where the last grapple started and to which anchor; anchor -> tick it may be used again.
var _grapple_from: Vector2 = Vector2.INF
var _grapple_to: Vector2 = Vector2.INF
var _blocked: Dictionary = {}
var _escape_rolled: bool = false


func _init(bot_fighter: Fighter, match_sim: MatchSim, bot_profile: BotProfile, bot_anchors: Array[Vector2]) -> void:
	fighter = bot_fighter
	sim = match_sim
	profile = bot_profile
	anchors = bot_anchors


func build_command(tick: int) -> InputCommand:
	var cmd := InputCommand.new()
	# Rule 1.
	if fighter.is_ko() or fighter.state == SimIds.FighterState.HITSTUN:
		_melee_tick = -1
		intent = &"idle"
		return cmd
	if _melee_tick >= 0 and tick >= _melee_tick:
		cmd.melee = true
		_melee_tick = -1
	if fighter.pulled_by_id < 0:
		_escape_rolled = false
	if fighter.rope.mode == SimIds.RopeMode.DUEL:
		# ROPE-07: tap as fast as this bot can.
		cmd.rope_fire = sim.rng.randf() < profile.fire_rate * DUEL_TAPS_PER_FIRE / SimIds.TICK_RATE
		return cmd
	if sim.special_weapons.is_thrusting(fighter, tick):
		var chase := _nearest_enemy()
		if chase != null:
			cmd.steer = (chase.global_position - fighter.global_position).normalized()
	if (tick + fighter.fighter_id) % profile.perception_interval_ticks == 0:
		_think(tick, cmd)
	return cmd


func _think(tick: int, cmd: InputCommand) -> void:
	var t := TuningDB.t
	var target := _nearest_enemy()
	if _grapple_from != Vector2.INF and fighter.is_clinging() and not fighter.rope.is_out():
		if fighter.global_position.distance_to(_grapple_from) < STUCK_DISTANCE:
			_blocked[_grapple_to] = tick + SimIds.ticks(BLOCK_TIME)
		_grapple_from = Vector2.INF

	# Rule 1b.
	if fighter.can_fire_rope(tick) and not fighter.rope.is_out():
		var away := _hazard_escape(tick)
		if away != Vector2.ZERO:
			var anchor := _anchor_toward(away)
			if anchor != Vector2.INF:
				_fire(cmd, anchor, &"escape_hazard")
				return

	# Rule 2. A failed escape roll falls through, so a pulled bot can still swing back.
	if fighter.pulled_by_id >= 0 and not _escape_rolled:
		_escape_rolled = true
		if sim.rng.randf() < profile.escape_chance and fighter.can_fire_rope(tick):
			var puller := sim.get_fighter(fighter.pulled_by_id)
			var away := _escape_anchor(puller)
			if away != Vector2.INF:
				_fire(cmd, away, &"escape")
				return

	# Rule 3.
	if target != null:
		if fighter.rope.pull_target == target:
			# Arriving from our own pull: time the swing so its active ticks meet the target.
			if _melee_tick < 0:
				var eta := _arrival_ticks(target)
				if eta <= profile.perception_interval_ticks + t.melee_startup_ticks:
					var error := sim.rng.randi_range(-profile.melee_timing_error_ticks, profile.melee_timing_error_ticks)
					_melee_tick = tick + maxi(0, eta - t.melee_startup_ticks + error)
					_set_intent(&"melee", target.global_position)
			return
		var offset := target.global_position - fighter.global_position
		var closing := (target.velocity - fighter.velocity).dot(-offset.normalized())
		if offset.length() <= Melee.reach(fighter, t) + profile.melee_trigger_margin and closing > 0.0:
			if _melee_tick < 0 and fighter.can_melee(tick + 1):
				_melee_tick = tick + maxi(1, SimIds.ticks(profile.reaction_time))
				_set_intent(&"melee", target.global_position)
			return

	# Rule 3b.
	var held := sim.weapons.held_by(fighter)
	if target != null and held != null and _use_special(held, target, tick, cmd):
		return
	if target != null and held != null and _aimable(held.def) and tick >= fighter.fire_ready_tick:
		var dist := fighter.global_position.distance_to(target.global_position)
		var reach := held.def.projectile_speed * maxf(held.def.projectile_lifetime, 0.6) * 0.9 if held.ammo > 0 else Melee.reach(fighter, t) * 5.0
		var too_close := held.def.projectile_kind in POINT_BLANK_UNSAFE and held.ammo > 0 and dist < maxf(held.def.effect_radius, 250.0)
		if dist <= reach and not too_close and _in_sight(target.global_position):
			var chance := profile.fire_rate * float(profile.perception_interval_ticks) / SimIds.TICK_RATE
			if sim.rng.randf() < chance:
				var speed := held.def.projectile_speed if held.ammo > 0 else t.throw_speed
				var lead := target.global_position + target.velocity * (dist / speed)
				var error := deg_to_rad(sim.rng.randf_range(-profile.aim_error_deg, profile.aim_error_deg))
				cmd.fire = true
				cmd.aim_dir = (lead - fighter.global_position).normalized().rotated(error)
				_set_intent(&"shoot", target.global_position)
				return

	# Rule 4.
	var ropeable := target != null and _ropeable(target, tick)
	if ropeable and fighter.can_fire_rope(tick):
		var chance := profile.aggression * float(profile.perception_interval_ticks) / SimIds.TICK_RATE
		if sim.rng.randf() < chance:
			var dist := fighter.global_position.distance_to(target.global_position)
			var lead := target.global_position + target.velocity * (dist / t.hook_speed)
			var error := deg_to_rad(sim.rng.randf_range(-profile.aim_error_deg, profile.aim_error_deg))
			var aim := fighter.global_position + (lead - fighter.global_position).rotated(error)
			_fire(cmd, aim, &"rope_player")
			return

	# Rule 4b.
	if held == null and fighter.can_fire_rope(tick) and not fighter.rope.is_out():
		var item := _reachable_weapon()
		if item != null and sim.rng.randf() < profile.weapon_interest:
			var dist := fighter.global_position.distance_to(item.pos)
			_fire(cmd, item.pos + item.vel * (dist / t.hook_speed), &"grab_weapon")
			return

	# Rule 5. A clinging bot that has the player in its sights waits for its next rule 4 roll. In a
	# mode with a goal (the King of the Swing zone, away from the Hot Potato bomb) it heads there.
	var goal := sim.mode.bot_goal(fighter, tick) if sim.mode != null else Vector2.INF
	var far := goal != Vector2.INF and fighter.global_position.distance_to(goal) > GOAL_REACHED
	var clung_ticks := SimIds.ticks(t.cling_time) - fighter.cling_ticks_left
	var cling_long := fighter.is_clinging() and clung_ticks >= SimIds.ticks(profile.idle_cling_time)
	if cling_long and ropeable and profile.hold_position_when_ropeable and not far:
		_set_intent(&"aim", target.global_position)
		return
	var drifting := fighter.state == SimIds.FighterState.FREE and fighter.velocity.length() < profile.slow_speed and not fighter.rope.is_out()
	if far and not fighter.rope.is_out():
		# Away from the goal: don't wait on a wall, and re-aim when flying the wrong way.
		var to_goal := (goal - fighter.global_position).normalized()
		cling_long = cling_long or (fighter.is_clinging() and clung_ticks >= SimIds.ticks(GOAL_CLING_TIME))
		drifting = drifting or (fighter.state == SimIds.FighterState.FREE and fighter.velocity.normalized().dot(to_goal) < 0.5)
	if goal != Vector2.INF and not far:
		# At the goal (in the zone): stay and fight from here.
		_set_intent(&"hold_goal", goal)
		return
	if (cling_long or drifting) and fighter.can_fire_rope(tick):
		var anchor := _roam_anchor(target, goal if far else Vector2.INF)
		if anchor != Vector2.INF:
			_grapple_from = fighter.global_position
			_grapple_to = anchor
			_fire(cmd, anchor, &"grapple")
			return

	# Rule 6: latched ropes finish on their own.


## Guns, and Phase 6 weapons that are fired at a target.
func _aimable(def: WeaponDef) -> bool:
	return def.kind == WeaponDef.Kind.GUN or (def.kind == WeaponDef.Kind.SPECIAL and def.projectile_kind in AIMED_SPECIALS)


## Repulsor up close, magnet when there's something to pull, thruster when the fight is far away.
func _use_special(held: WeaponItem, target: Fighter, tick: int, cmd: InputCommand) -> bool:
	if held.def.kind != WeaponDef.Kind.SPECIAL or tick < fighter.fire_ready_tick or held.ammo <= 0:
		return false
	var dist := fighter.global_position.distance_to(target.global_position)
	var use := false
	match held.def.projectile_kind:
		&"repulsor":
			use = dist < held.def.effect_radius * 0.7 or fighter.pulled_by_id >= 0
		&"magnet":
			use = dist < held.def.effect_radius and (target.weapon_id >= 0 or _reachable_weapon() != null)
		&"thruster":
			use = dist > TuningDB.t.rope_range * 0.6
	if use:
		cmd.fire = true
		_set_intent(&"use_weapon", target.global_position)
	return use


func _fire(cmd: InputCommand, point: Vector2, why: StringName) -> void:
	cmd.rope_fire = true
	cmd.rope_target = point
	cmd.rope_held = false
	_set_intent(why, point)


func _set_intent(why: StringName, point: Vector2) -> void:
	intent = why
	intent_point = point


func _nearest_enemy() -> Fighter:
	var best: Fighter = null
	var best_dist := INF
	for other in sim.fighters:
		if other == fighter or other.is_ko() or not sim.are_enemies(fighter, other):
			continue
		var d := fighter.global_position.distance_to(other.global_position)
		if d < best_dist:
			best = other
			best_dist = d
	return best


## The nearest floating weapon within rope range and in sight, or null.
func _reachable_weapon() -> WeaponItem:
	var best: WeaponItem = null
	var best_dist := TuningDB.t.rope_range
	for item in sim.weapons.items:
		if item.state != WeaponItem.State.FLOATING:
			continue
		var d := fighter.global_position.distance_to(item.pos)
		if d < best_dist and _in_sight(item.pos):
			best = item
			best_dist = d
	return best


## Ticks until the pulled target is half a melee range away, at its current closing speed.
func _arrival_ticks(target: Fighter) -> int:
	var offset := fighter.global_position - target.global_position
	var closing := maxf((target.velocity - fighter.velocity).dot(offset.normalized()), 1.0)
	var gap := maxf(offset.length() - TuningDB.t.melee_range * 0.5, 0.0)
	return ceili(gap / (closing / SimIds.TICK_RATE))


## Rule 2: the reachable anchor whose direction points most away from the puller.
func _escape_anchor(puller: Fighter) -> Vector2:
	if puller == null:
		return Vector2.INF
	return _anchor_toward((fighter.global_position - puller.global_position).normalized())


## Rule 1b: the direction to flee in, or zero when the bot is safe.
func _hazard_escape(tick: int) -> Vector2:
	var pull := sim.hazards.danger_at(fighter.global_position, tick)
	if pull.length() >= HAZARD_DANGER:
		return -pull.normalized()
	var zone := sim.hazards.safe_zone(tick)
	if not zone.grow(-TuningDB.t.fighter_radius * 2.0).has_point(fighter.global_position):
		return (zone.get_center() - fighter.global_position).normalized()
	return Vector2.ZERO


func _safe_anchor(a: Vector2, tick: int) -> bool:
	return sim.hazards.danger_at(a, tick).length() < HAZARD_DANGER and sim.hazards.safe_zone(tick).has_point(a)


## The reachable anchor whose direction is closest to dir.
func _anchor_toward(away: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dot := -INF
	for a in anchors:
		if not _reachable(a):
			continue
		var d := (a - fighter.global_position).normalized().dot(away)
		if d > best_dot:
			best_dot = d
			best = a
	return best


## Rule 5: reachable anchors ranked by how well they keep the bot in the preferred distance band
## from the player, with a penalty when the player would be in range but out of sight from there.
## One of the best few in the band is picked at random; with none in the band the bot heads for the
## closest fit instead of wandering. Anchors in danger (a hazard's pull, outside the Closing Walls
## zone) are skipped. With a mode goal (§6.5) the anchor closest to the goal wins instead, if it
## gets the bot closer; when nothing does (a wall in the way) a random one gets it unstuck.
func _roam_anchor(target: Fighter, goal: Vector2 = Vector2.INF) -> Vector2:
	if goal != Vector2.INF:
		return _goal_anchor(goal)
	var scored: Array[Vector2] = []
	for i in anchors.size():
		var a := anchors[i]
		var d := fighter.global_position.distance_to(a)
		if d < profile.anchor_min_move or d > TuningDB.t.rope_range or not _reachable(a) or not _safe_anchor(a, sim.tick):
			continue
		var miss := 0.0
		if target != null:
			var to_player := a.distance_to(target.global_position)
			miss = maxf(0.0, profile.preferred_min_dist - to_player) + maxf(0.0, to_player - profile.preferred_max_dist)
			if to_player <= TuningDB.t.rope_range and not _anchor_sees(a, target.global_position):
				miss += profile.no_sight_penalty
		scored.append(Vector2(miss, i))
	if scored.is_empty():
		return Vector2.INF
	scored.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x or (x.x == y.x and x.y < y.y))
	if scored[0].x > 0.0:
		# Nothing in the band: head for the best one, no wandering.
		return anchors[int(scored[0].y)]
	var in_band := scored.filter(func(x: Vector2) -> bool: return x.x <= 0.0).size()
	var pick := sim.rng.randi_range(0, mini(profile.anchor_pick_count, in_band) - 1)
	return anchors[int(scored[pick].y)]


## Like a player aiming at a wall near the goal: rays in GOAL_RAYS directions find hookable spots
## (plus the known anchors), and the reachable spot closest to the goal wins.
func _goal_anchor(goal: Vector2) -> Vector2:
	var here := fighter.global_position.distance_to(goal)
	var spots: Array[Vector2] = []
	var from := fighter.global_position
	for i in GOAL_RAYS:
		var dir := Vector2.from_angle(TAU * i / GOAL_RAYS)
		var hit := _ray(from, from + dir * TuningDB.t.rope_range, Layers.HOOK_MASK)
		if hit.is_empty():
			continue
		var obj := hit["collider"] as ArenaObject
		if obj == null or not obj.hookable or (fighter.is_clinging() and obj == fighter.cling_object):
			continue
		var point: Vector2 = hit["position"]
		if from.distance_to(point) >= profile.anchor_min_move and _body_fits(from, point, hit["normal"]):
			spots.append(point)
	for a in anchors:
		if from.distance_to(a) >= profile.anchor_min_move and _reachable(a):
			spots.append(a)
	var best := Vector2.INF
	var best_dist := here - GOAL_PROGRESS
	var others: Array[Vector2] = []
	for p in spots:
		if not _safe_anchor(p, sim.tick):
			continue
		var to_goal := p.distance_to(goal)
		if to_goal < best_dist:
			best = p
			best_dist = to_goal
		elif p.distance_to(_last_goal_anchor) > 100.0:
			others.append(p)
	if best == Vector2.INF and not others.is_empty():
		best = others[sim.rng.randi_range(0, others.size() - 1)]
	_last_goal_anchor = best
	return best


## In rope range with a clear line: the ray toward the anchor hits the surface right at it. An
## anchor on the object the bot is clinging to doesn't count: roping along your own surface just
## re-clings at once.
func _reachable(anchor: Vector2) -> bool:
	var from := fighter.global_position
	var dir := anchor - from
	if dir.length() > TuningDB.t.rope_range:
		return false
	var hit := _ray(from, anchor + dir.normalized() * profile.anchor_hit_tolerance)
	if hit.is_empty():
		return false
	if fighter.is_clinging() and hit["collider"] == fighter.cling_object:
		return false
	var point: Vector2 = hit["position"]
	if point.distance_to(anchor) > profile.anchor_hit_tolerance:
		return false
	return sim.tick >= int(_blocked.get(anchor, -1))


## For free spots toward a goal: the fighter's body must fit along the way, or a line that just
## grazes a corner leaves the bot re-clinging on that corner over and over. The check stops where
## a slimmer body would touch the spot's surface. (Known anchors use the stuck memory instead.)
func _body_fits(from: Vector2, anchor: Vector2, normal: Vector2) -> bool:
	var t := TuningDB.t
	var dir := anchor - from
	var radius := t.fighter_radius * 0.6
	var facing := maxf(absf(dir.normalized().dot(normal)), 0.2)
	var travel := dir.length() - (radius + 6.0) / facing
	if travel <= 0.0:
		return true
	if _body_shape == null:
		_body_shape = CircleShape2D.new()
		_body_shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _body_shape
	params.transform = Transform2D(0.0, from)
	params.motion = dir.normalized() * travel
	params.collision_mask = Layers.FIGHTER_BODY_MASK
	params.exclude = [fighter.get_rid()]
	var safe := fighter.get_world_2d().direct_space_state.cast_motion(params)
	return safe.is_empty() or safe[0] >= 0.999


## Rule 4's conditions: in rope range, in sight and pullable.
func _ropeable(target: Fighter, tick: int) -> bool:
	if not target.can_be_pulled(tick):
		return false
	if fighter.global_position.distance_to(target.global_position) > TuningDB.t.rope_range:
		return false
	return _in_sight(target.global_position)


## Would a bot clinging at this anchor see the player? Starts just off the surface, where it would
## actually cling.
func _anchor_sees(anchor: Vector2, point: Vector2) -> bool:
	var dir := (point - anchor).normalized()
	return _ray(anchor + dir * (TuningDB.t.fighter_radius + 2.0), point).is_empty()


func _in_sight(point: Vector2) -> bool:
	return _ray(fighter.global_position, point).is_empty()


func _ray(from: Vector2, to: Vector2, mask: int = Layers.WORLD_HOOKABLE) -> Dictionary:
	var exclude: Array[RID] = [fighter.get_rid()]
	var query := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
	return fighter.get_world_2d().direct_space_state.intersect_ray(query)
