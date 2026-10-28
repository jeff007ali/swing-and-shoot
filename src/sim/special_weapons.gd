class_name SpecialWeapons
extends RefCounted
## Phase 6 (§6.6): every SPECIAL weapon's behavior, plus the advanced rope moves that need shared
## state: projectile catch (ROPE-06, together with Rope), tug-of-war duels (ROPE-07) and mutual
## rope clashes (ROPE-15). Part of the sim: stepped by MatchSim after WeaponSystem, tick-based,
## seeded randomness, full get_state/set_state. Hits and KOs come from the authoritative sim only.
##
## Weapon kinds (WeaponDef.projectile_kind):
##   rocket       slow shot that explodes on impact, huge recoil
##   laser        ricochets off surfaces (bounces)
##   boomerang    thrown blade: out to effect_radius and back, cuts ropes both ways
##   harpoon      a second rope: hooks an enemy and hauls them in while your own rope stays put
##   freeze       frozen target can't act, keeps its speed, can always be roped: a wrecking ball
##   magnet       for a while, drags loose weapons and armed enemies toward you
##   sticky       grenade that sticks to a fighter, a rope's owner or a wall, then blows
##   gravity      grenade that opens a gravity well for a few seconds
##   black_hole_bomb  a stronger well whose core KOs and swallows ropes and weapons (legendary)
##   repulsor     a cone blast ahead: slams enemies away hard enough to disarm, turns shots around,
##                breaks pulls on you and kicks you backward
##   tether_mine  sticks to a wall; ropes the first enemy that drifts close
##   prox_mine    sticks to a wall; explodes when an enemy comes close
##   tether_rope  ties the enemy it hits to the nearest other enemy; they smash together
##   shield       blocks shots from the front; an enemy rope rips it away
##   thruster     for a while, holding a touch steers instead of roping

const CATCHABLE: Array[StringName] = [&"rocket", &"sticky", &"gravity", &"black_hole_bomb", &"boomerang", &"tether_mine", &"prox_mine"]
const THROWN_KINDS: Array[StringName] = [&"sticky", &"gravity", &"black_hole_bomb", &"tether_mine", &"prox_mine"]
## Fire button labels on the HUD.
const USE_LABELS: Dictionary = {
	&"magnet": "MAGNET", &"repulsor": "BLAST", &"thruster": "BOOST", &"shield": "BASH", &"boomerang": "THROW",
}
const DUEL_TIME: float = 1.2
const DUEL_DAMP: float = 0.85
const CLASH_DISTANCE: float = 72.0
const CLASH_KNOCKBACK: float = 1000.0
const CLASH_HITSTOP: int = 6
## Shield blocks shots within this angle of its holder's facing.
const SHIELD_ARC_DEG: float = 130.0
const FREEZE_RAM_SPEED: float = 600.0
const FREEZE_RAM_DAMAGE: float = 0.022
const FREEZE_RAM_COOLDOWN: float = 0.5
const WELL_CORE: float = 70.0
const MINE_ARM: float = 0.5
## Proximity mines arm slower, so one dropped at your feet in a fight can't be used point-blank.
const PROX_MINE_ARM: float = 0.9
## Repulsor: the blast covers this cone ahead of the aim, plus everything this close all around.
const REPULSE_CONE_DEG: float = 110.0
const REPULSE_CLOSE: float = 90.0
const MINE_HOLD: float = 1.5
const TETHER_ARRIVE: float = 80.0
const WHIP_SPEED: float = 1600.0
const BOOMERANG_CATCH: float = 50.0

var sim: MatchSim

# State
## {id, pos, radius, strength, until, owner, core}
var wells: Array[Dictionary] = []
## {a, b (fighter id or -1), point, until, strength, kind, owner, held}
var tethers: Array[Dictionary] = []
## {id, pos, armed, until, owner, radius, strength}
var mines: Array[Dictionary] = []
## fighter id -> tick the effect ends
var magnets: Dictionary = {}
var thrusters: Dictionary = {}
## {a, b, point, end, taps_a, taps_b}
var duels: Array[Dictionary] = []
var _ram_until: Dictionary = {}


func setup(match_sim: MatchSim) -> void:
	sim = match_sim


# --- Queries -------------------------------------------------------------------------------------

func is_thrusting(f: Fighter, tick: int) -> bool:
	return tick < int(thrusters.get(f.fighter_id, -1))


func is_magnetized(f: Fighter, tick: int) -> bool:
	return tick < int(magnets.get(f.fighter_id, -1))


func holds(f: Fighter, kind: StringName) -> bool:
	var item := sim.weapons.held_by(f)
	return item != null and item.def.projectile_kind == kind


func duel_of(f: Fighter) -> Dictionary:
	for d in duels:
		if d["a"] == f.fighter_id or d["b"] == f.fighter_id:
			return d
	return {}


## The fire button's label for a held special weapon.
static func use_label(item: WeaponItem) -> String:
	var kind := item.def.projectile_kind
	if USE_LABELS.has(kind):
		return USE_LABELS[kind]
	return "THROW" if item.ammo <= 0 else "FIRE"


# --- Firing --------------------------------------------------------------------------------------

## Fire button with a SPECIAL weapon.
func fire(fighter: Fighter, item: WeaponItem, cmd: InputCommand, tick: int) -> void:
	var def := item.def
	var kind := def.projectile_kind
	var reach := def.projectile_speed * maxf(def.projectile_lifetime, 0.5)
	var aim := sim.weapons.aim_for(fighter, cmd, reach if reach > 0.0 else 900.0)
	if def.ammo > 0 and item.ammo <= 0 and not kind in [&"thruster"]:
		sim.weapons.throw_weapon(fighter, item, aim, tick)
		return
	fighter.fire_ready_tick = tick + SimIds.ticks(def.fire_cooldown)
	match kind:
		&"shield":
			if fighter.can_melee(tick):
				fighter.start_melee(tick, cmd.aim_dir if cmd != null else Vector2.ZERO)
			return
		&"boomerang":
			if item.extra.get("out", false):
				return
			item.extra["out"] = true
			var p := _projectile(fighter, def, aim, tick)
			p.extra["item"] = item.id
			p.extra["traveled"] = 0.0
			p.extra["back"] = false
			p.extra["hit"] = []
			p.expire_tick = tick + SimIds.ticks(6.0)
		&"magnet":
			item.ammo -= 1
			magnets[fighter.fighter_id] = tick + SimIds.ticks(def.effect_time)
		&"thruster":
			if is_thrusting(fighter, tick):
				return
			item.ammo = 0
			thrusters[fighter.fighter_id] = tick + SimIds.ticks(def.effect_time)
		&"repulsor":
			item.ammo -= 1
			_repulse(fighter, def, aim, tick)
		_:
			item.ammo -= 1
			var p := _projectile(fighter, def, aim, tick)
			if kind in THROWN_KINDS:
				p.vel += fighter.velocity * 0.5
				if kind == &"sticky":
					p.expire_tick = tick + SimIds.ticks(def.effect_time)
			if kind == &"laser":
				p.extra["bounces"] = def.bounces
	sim.weapons.apply_recoil(fighter, aim, def.recoil_impulse)
	sim.queue_event(&"weapon_fired", [fighter.fighter_id, def.id, fighter.global_position + aim * (TuningDB.t.fighter_radius + 12.0), aim])


func _projectile(fighter: Fighter, def: WeaponDef, aim: Vector2, tick: int) -> Projectile:
	var t := TuningDB.t
	var p := Projectile.new()
	p.id = sim.next_entity_id()
	p.kind = Projectile.Kind.BULLET
	p.def = def
	p.owner_id = fighter.fighter_id
	p.pos = fighter.global_position + aim * (t.fighter_radius + def.projectile_radius + 6.0)
	p.prev_pos = p.pos
	p.vel = aim * def.projectile_speed
	p.damage = def.projectile_damage
	p.knockback = def.projectile_knockback
	p.radius = def.projectile_radius
	p.expire_tick = tick + SimIds.ticks(def.projectile_lifetime)
	p.extra = {"special": true, "kind": def.projectile_kind}
	sim.weapons.projectiles.append(p)
	return p


# --- Projectiles ---------------------------------------------------------------------------------

## A projectile marked extra["special"] = true. Caught ones are moved by the catching rope.
func step_projectile(p: Projectile, tick: int) -> void:
	if p.extra.has("caught_by"):
		return
	var kind: StringName = p.extra.get("kind", &"")
	match kind:
		&"boomerang":
			_step_boomerang(p, tick)
			return
		&"sticky":
			if p.extra.has("stuck"):
				_follow_stuck(p)
				if tick >= p.expire_tick:
					_remove(p)
					_explode(p.pos, p.def.effect_radius, p.damage, p.knockback, p.owner_id, tick, &"grenade")
				return
	var hit := _advance(p, tick)
	var type: StringName = hit.get("type", &"")
	match kind:
		&"rocket":
			if type != &"" or tick >= p.expire_tick:
				_remove(p)
				_explode(hit.get("point", p.pos), p.def.effect_radius, p.damage, p.knockback, p.owner_id, tick, &"rocket")
		&"laser":
			if type == &"world":
				var left: int = p.extra.get("bounces", 0)
				if left <= 0:
					_remove(p)
					sim.queue_event(&"projectile_blocked", [hit["point"], p.def.id])
				else:
					p.extra["bounces"] = left - 1
					var n: Vector2 = hit["normal"]
					p.vel = p.vel.bounce(n)
					p.pos = hit["point"] + n * (p.radius + 1.0)
					sim.queue_event(&"laser_bounced", [hit["point"]])
			elif type == &"fighter":
				_remove(p)
				sim.weapons.hit_fighter(p, hit["fighter"], hit["point"], tick)
			elif type == &"blocked" or tick >= p.expire_tick:
				_remove(p)
		&"freeze":
			if type == &"fighter":
				_remove(p)
				var victim: Fighter = hit["fighter"]
				sim.weapons.hit_fighter(p, victim, hit["point"], tick)
				if not victim.is_ko():
					victim.frozen_until = tick + SimIds.ticks(p.def.effect_time)
					victim.leave_surface()
					sim.queue_event(&"frozen", [victim.fighter_id, p.def.effect_time])
			elif type != &"" or tick >= p.expire_tick:
				_remove(p)
		&"harpoon":
			if type == &"fighter":
				_remove(p)
				var victim: Fighter = hit["fighter"]
				victim.take_hit(tick, p.owner_id, p.damage, Vector2.ZERO, 0, &"shot")
				if not victim.is_ko():
					_tether(victim.fighter_id, p.owner_id, Vector2.ZERO, tick + SimIds.ticks(p.def.effect_time), p.def.effect_strength, &"harpoon", p.owner_id)
			elif type != &"" or tick >= p.expire_tick:
				_remove(p)
		&"tether_rope":
			if type == &"fighter":
				_remove(p)
				var a: Fighter = hit["fighter"]
				var b := _nearest_other(a, p.owner_id, p.def.effect_radius)
				if b != null:
					_tether(a.fighter_id, b.fighter_id, Vector2.ZERO, tick + SimIds.ticks(p.def.effect_time), p.def.effect_strength, &"tether_rope", p.owner_id)
			elif type != &"" or tick >= p.expire_tick:
				_remove(p)
		&"sticky":
			if type == &"fighter":
				_stick_to(p, hit["fighter"])
			elif type == &"rope":
				_stick_to(p, hit["fighter"])
			elif type == &"world" or type == &"blocked":
				p.extra["stuck"] = -1
				p.pos = hit["point"]
				p.vel = Vector2.ZERO
			elif tick >= p.expire_tick:
				_remove(p)
				_explode(p.pos, p.def.effect_radius, p.damage, p.knockback, p.owner_id, tick, &"grenade")
		&"gravity", &"black_hole_bomb":
			if type != &"" or tick >= p.expire_tick:
				_remove(p)
				var core := WELL_CORE if kind == &"black_hole_bomb" else 0.0
				wells.append({"id": p.id, "pos": hit.get("point", p.pos), "radius": p.def.effect_radius, "strength": p.def.effect_strength,
					"until": tick + SimIds.ticks(p.def.effect_time), "owner": p.owner_id, "core": core})
				sim.queue_event(&"well_opened", [hit.get("point", p.pos), p.def.effect_radius, core > 0.0])
		&"tether_mine", &"prox_mine":
			var prox := kind == &"prox_mine"
			if type == &"world" or type == &"blocked" or tick >= p.expire_tick:
				_remove(p)
				mines.append({"id": p.id, "pos": hit.get("point", p.pos), "armed": tick + SimIds.ticks(PROX_MINE_ARM if prox else MINE_ARM),
					"until": tick + SimIds.ticks(p.def.effect_time), "owner": p.owner_id, "radius": p.def.effect_radius, "strength": p.def.effect_strength,
					"kind": kind, "damage": p.damage, "knockback": p.knockback})
				sim.queue_event(&"mine_placed", [hit.get("point", p.pos)])
			elif type == &"fighter" and prox:
				_remove(p)
				_explode(hit["point"], p.def.effect_radius * 2.0, p.damage, p.knockback, p.owner_id, tick, &"mine")
			elif type == &"fighter":
				_remove(p)
				var victim: Fighter = hit["fighter"]
				_tether(victim.fighter_id, -1, victim.global_position, tick + SimIds.ticks(MINE_HOLD), p.def.effect_strength, &"mine", p.owner_id)
		_:
			_remove(p)


## Moves p one tick. Returns {} or {type: world|fighter|rope|blocked, point, normal, fighter}.
## Fighters (and, for sticky grenades, ropes) only count in the authoritative sim.
func _advance(p: Projectile, tick: int) -> Dictionary:
	p.prev_pos = p.pos
	var to := p.pos + p.vel * SimIds.DT
	var hit := sim.weapons.cast(p.pos, to)
	var seg_len := maxf(p.pos.distance_to(to), 0.001)
	var world_t: float = p.pos.distance_to(hit["position"]) / seg_len if not hit.is_empty() else 2.0
	var best := {}
	var best_t := world_t
	if sim.authoritative:
		var shooter := sim.get_fighter(p.owner_id)
		for f in sim.fighters:
			if f.fighter_id == p.owner_id or not f.can_be_hit(tick):
				continue
			if shooter != null and not sim.are_enemies(shooter, f):
				continue
			var ft := Rope._segment_circle(p.pos, to - p.pos, f.global_position, TuningDB.t.fighter_radius + p.radius)
			if ft >= 0.0 and ft < best_t:
				best_t = ft
				best = {"type": &"fighter", "fighter": f}
		if p.extra.get("kind") == &"sticky":
			for f in sim.fighters:
				if f.fighter_id == p.owner_id or not f.rope.is_out():
					continue
				var rt := _segments(p.pos, to, f.global_position, f.rope.hook_pos)
				if rt >= 0.0 and rt < best_t:
					best_t = rt
					best = {"type": &"rope", "fighter": f}
	if not best.is_empty():
		var point := p.pos.lerp(to, best_t)
		best["point"] = point
		var victim: Fighter = best["fighter"]
		if best["type"] == &"fighter":
			if victim.is_parrying(tick, p.vel):
				sim.weapons.reflect(p, victim, point)
				return {}
			if _shield_blocks(victim, p.vel):
				sim.queue_event(&"projectile_blocked", [point, p.def.id])
				p.pos = point
				return {"type": &"blocked", "point": point, "normal": -p.vel.normalized()}
		p.pos = point
		return best
	if not hit.is_empty():
		p.pos = hit["position"]
		var obj := hit["collider"] as ArenaObject
		if obj != null and sim.mode != null and sim.mode.on_object_hit(obj, hit["position"], p.damage, p.owner_id, tick):
			pass
		elif obj != null and obj.is_breakable():
			sim.hazards.damage_object(obj, p.damage, p.owner_id, tick)
		return {"type": &"world", "point": hit["position"], "normal": hit["normal"]}
	p.pos = to
	return {}


## Shield (§5.2): a held shield stops shots that come at its holder's front.
func _shield_blocks(victim: Fighter, vel: Vector2) -> bool:
	if not holds(victim, &"shield"):
		return false
	var incoming := -vel.normalized()
	return rad_to_deg(absf(victim.facing.angle_to(incoming))) <= SHIELD_ARC_DEG * 0.5


func _remove(p: Projectile) -> void:
	sim.weapons.projectiles.erase(p)


func _stick_to(p: Projectile, f: Fighter) -> void:
	p.extra["stuck"] = f.fighter_id
	p.extra["offset"] = Vector2.from_angle(sim.rng.randf() * TAU) * TuningDB.t.fighter_radius
	p.vel = Vector2.ZERO
	sim.queue_event(&"grenade_stuck", [f.fighter_id])


func _follow_stuck(p: Projectile) -> void:
	p.prev_pos = p.pos
	var id: int = p.extra["stuck"]
	if id < 0:
		return
	var f := sim.get_fighter(id)
	if f == null or f.is_ko():
		p.extra["stuck"] = -1
		return
	p.pos = f.global_position + p.extra["offset"]


## Boomerang: out until it has flown effect_radius (or hits a wall), then home back to its thrower.
## Hits each fighter once per leg and cuts every rope it crosses (§5.2).
func _step_boomerang(p: Projectile, tick: int) -> void:
	var owner := sim.get_fighter(p.owner_id)
	var item := sim.weapons.get_item(p.extra.get("item", -1))
	if owner == null or owner.is_ko() or item == null or item.holder_id != owner.fighter_id or tick >= p.expire_tick:
		if item != null:
			item.extra["out"] = false
		_remove(p)
		return
	if p.extra["back"]:
		var home := owner.global_position - p.pos
		if home.length() < BOOMERANG_CATCH:
			item.extra["out"] = false
			_remove(p)
			sim.queue_event(&"boomerang_caught", [owner.fighter_id])
			return
		p.vel = home.normalized() * p.def.projectile_speed
	var from := p.pos
	p.prev_pos = p.pos
	var to := p.pos + p.vel * SimIds.DT
	if not p.extra["back"]:
		var hit := sim.weapons.cast(from, to)
		if not hit.is_empty():
			to = hit["position"]
			p.extra["back"] = true
			p.extra["hit"] = []
		p.extra["traveled"] = float(p.extra["traveled"]) + from.distance_to(to)
		if float(p.extra["traveled"]) >= p.def.effect_radius:
			p.extra["back"] = true
			p.extra["hit"] = []
	p.pos = to
	if not sim.authoritative:
		return
	var hit_ids: Array = p.extra["hit"]
	for f in sim.fighters:
		if f == owner or f.is_ko() or hit_ids.has(f.fighter_id) or not sim.are_enemies(owner, f) or not f.can_be_hit(tick):
			continue
		if Rope._segment_circle(from, to - from, f.global_position, TuningDB.t.fighter_radius + p.radius) >= 0.0:
			hit_ids.append(f.fighter_id)
			sim.weapons.hit_fighter(p, f, f.global_position, tick)
	for f in sim.fighters:
		if f == owner or not f.rope.is_out():
			continue
		var rt := _segments(from, to, f.global_position, f.rope.hook_pos)
		if rt >= 0.0:
			var point := from.lerp(to, rt)
			f.rope.release(false)
			sim.queue_event(&"rope_cut", [owner.fighter_id, f.fighter_id, point])


func _repulse(user: Fighter, def: WeaponDef, aim: Vector2, tick: int) -> void:
	var at := user.global_position
	var radius := def.effect_radius
	if user.pulled_by_id >= 0:
		var puller := sim.get_fighter(user.pulled_by_id)
		if puller != null and puller.rope.pull_target == user:
			puller.rope.release(false)
	for f in sim.fighters:
		if f == user or f.is_ko() or not _in_repulse(at, aim, f.global_position, radius):
			continue
		var offset := f.global_position - at
		var d := offset.length()
		var dir := offset / d if d > 0.001 else aim
		var push := dir * def.effect_strength * (1.0 - d / radius * 0.4)
		if sim.authoritative and sim.are_enemies(user, f) and f.can_be_hit(tick):
			f.take_hit(tick, user.fighter_id, def.projectile_damage, push, 5, &"repulsor")
		elif not sim.are_enemies(user, f):
			f.leave_surface()
			f.velocity += push
	for item in sim.weapons.items:
		if item.state != WeaponItem.State.HELD and _in_repulse(at, aim, item.pos, radius):
			item.vel += (item.pos - at).normalized() * def.effect_strength * 0.5
	for p in sim.weapons.projectiles:
		if p.owner_id != user.fighter_id and _in_repulse(at, aim, p.pos, radius):
			p.vel = (p.pos - at).normalized() * p.vel.length()
			p.owner_id = user.fighter_id
	sim.queue_event(&"repulsed", [user.fighter_id, at, radius, aim])


## Inside the repulsor blast: in range and in the cone ahead, or right next to the user.
static func _in_repulse(at: Vector2, aim: Vector2, point: Vector2, radius: float) -> bool:
	var offset := point - at
	var d := offset.length()
	if d >= radius:
		return false
	if d <= REPULSE_CLOSE:
		return true
	return rad_to_deg(absf(aim.angle_to(offset))) <= REPULSE_CONE_DEG * 0.5


## Blast with falloff: rockets, grenades. Damages breakables and sets off tanks.
func _explode(at: Vector2, radius: float, damage: float, knockback: float, owner_id: int, tick: int, cause: StringName) -> void:
	sim.queue_event(&"blast", [at, radius])
	if not sim.authoritative:
		return
	if sim.mode != null:
		sim.mode.on_blast(at, radius, damage, owner_id, tick)
	var owner := sim.get_fighter(owner_id)
	for f in sim.fighters:
		if f.is_ko() or not f.can_be_hit(tick):
			continue
		if owner != null and f != owner and not sim.are_enemies(owner, f):
			continue
		var offset := f.global_position - at
		var d := offset.length()
		if d >= radius:
			continue
		var k := 1.0 - d / radius
		var dir := offset / d if d > 0.001 else Vector2.UP
		var dmg := damage * k * (0.5 if f == owner else 1.0)
		f.take_hit(tick, owner_id if f != owner else -1, dmg, dir * knockback * k, 4, cause)
	for item in sim.weapons.items:
		if item.state != WeaponItem.State.HELD and item.pos.distance_to(at) < radius:
			item.vel += (item.pos - at).normalized() * knockback * 0.5
	for obj in sim.hazards.breakables:
		if obj.active and obj.center().distance_to(at) < radius:
			sim.hazards.damage_object(obj, damage * (1.0 - obj.center().distance_to(at) / radius), owner_id, tick)


func _tether(a: int, b: int, point: Vector2, until: int, strength: float, kind: StringName, owner: int) -> void:
	for t in tethers.duplicate():
		if t["a"] == a:
			tethers.erase(t)
	var target := sim.get_fighter(a)
	if target != null:
		target.leave_surface()
	tethers.append({"a": a, "b": b, "point": point, "until": until, "strength": strength, "kind": kind, "owner": owner, "held": false})
	sim.queue_event(&"tethered", [a, b, kind])


func _nearest_other(a: Fighter, owner_id: int, reach: float) -> Fighter:
	var owner := sim.get_fighter(owner_id)
	var best: Fighter = null
	var best_d := reach
	for f in sim.fighters:
		if f == a or f.is_ko() or f.fighter_id == owner_id:
			continue
		if owner != null and not sim.are_enemies(owner, f):
			continue
		var d := f.global_position.distance_to(a.global_position)
		if d < best_d:
			best = f
			best_d = d
	return best


# --- Per tick ------------------------------------------------------------------------------------

func step(tick: int) -> void:
	_step_wells(tick)
	_step_tethers(tick)
	_step_mines(tick)
	_step_magnets(tick)
	for id: int in thrusters.keys():
		if tick >= int(thrusters[id]):
			thrusters.erase(id)
			var f := sim.get_fighter(id)
			var item := sim.weapons.held_by(f) if f != null else null
			if item != null and item.def.projectile_kind == &"thruster":
				sim.weapons.discard(item)
	if sim.authoritative:
		_step_wrecking_balls(tick)
		_step_clashes(tick)
	_step_duels(tick)


func _step_wells(tick: int) -> void:
	for w in wells.duplicate():
		if tick >= int(w["until"]):
			wells.erase(w)
			continue
		var at: Vector2 = w["pos"]
		var radius: float = w["radius"]
		var strength: float = w["strength"]
		var core: float = w["core"]
		for f in sim.fighters:
			if f.is_ko():
				continue
			var offset := at - f.global_position
			var d := offset.length()
			if d >= radius:
				continue
			if core > 0.0 and d < core and sim.authoritative:
				var owner := sim.get_fighter(int(w["owner"]))
				var killer := int(w["owner"]) if owner != null and owner != f and sim.are_enemies(owner, f) else f.credited_killer(tick)
				f.knock_out(tick, killer, &"black_hole_bomb")
				continue
			if f.is_clinging():
				if core <= 0.0:
					continue
				f.cling_ticks_left -= 2
				continue
			f.velocity += offset.normalized() * strength * (1.0 - d / radius * 0.6) * SimIds.DT
		for item in sim.weapons.items.duplicate():
			if item.state == WeaponItem.State.HELD:
				continue
			var d: float = item.pos.distance_to(at)
			if core > 0.0 and d < core:
				sim.weapons.discard(item)
			elif d < radius:
				item.vel += (at - item.pos).normalized() * strength * SimIds.DT
		for p in sim.weapons.projectiles:
			if p.pos.distance_to(at) < radius and not p.extra.has("stuck") and not p.extra.has("caught_by"):
				p.vel += (at - p.pos).normalized() * strength * 0.5 * SimIds.DT
		if core > 0.0:
			# Swallows ropes whose hooks come too close.
			for f in sim.fighters:
				if f.rope.is_out() and f.rope.hook_pos.distance_to(at) < core * 1.5:
					f.rope.release(false)


func _step_tethers(tick: int) -> void:
	var t := TuningDB.t
	for tether in tethers.duplicate():
		var a := sim.get_fighter(int(tether["a"]))
		var b := sim.get_fighter(int(tether["b"])) if int(tether["b"]) >= 0 else null
		if a == null or a.is_ko() or tick >= int(tether["until"]) or (int(tether["b"]) >= 0 and (b == null or b.is_ko())):
			tethers.erase(tether)
			continue
		var target: Vector2 = b.global_position if b != null else tether["point"]
		var offset := target - a.global_position
		var d := offset.length()
		var dir := offset / d if d > 0.001 else Vector2.ZERO
		var strength: float = tether["strength"]
		match tether["kind"]:
			&"harpoon":
				if d < TETHER_ARRIVE:
					tethers.erase(tether)
					continue
				a.leave_surface()
				a.velocity += dir * strength * SimIds.DT
				a.last_pulled_by_id = int(tether["b"])
				a.last_pulled_tick = tick
			&"mine":
				if d < TETHER_ARRIVE * 0.5 or tether["held"]:
					tether["held"] = true
					a.velocity = Vector2.ZERO
					a.global_position = a.global_position.lerp(target, 0.3)
				else:
					a.leave_surface()
					a.velocity += dir * strength * SimIds.DT
					a.last_pulled_by_id = int(tether["owner"])
					a.last_pulled_tick = tick
			&"tether_rope":
				if d < t.fighter_radius * 2.0 + 12.0:
					tethers.erase(tether)
					if sim.authoritative:
						var owner := int(tether["owner"])
						var closing := (a.velocity - b.velocity).length()
						var dmg := t.max_hp * 0.2 + closing * 0.01
						a.take_hit(tick, owner, dmg, -dir * 900.0, 6, &"tether_rope")
						b.take_hit(tick, owner, dmg, dir * 900.0, 6, &"tether_rope")
					sim.queue_event(&"tether_smash", [a.fighter_id, b.fighter_id, (a.global_position + b.global_position) * 0.5])
					continue
				a.leave_surface()
				b.leave_surface()
				a.velocity += dir * strength * SimIds.DT
				b.velocity -= dir * strength * SimIds.DT


func _step_mines(tick: int) -> void:
	for m in mines.duplicate():
		if tick >= int(m["until"]):
			mines.erase(m)
			continue
		if tick < int(m["armed"]) or not sim.authoritative:
			continue
		var owner := sim.get_fighter(int(m["owner"]))
		var at: Vector2 = m["pos"]
		for f in sim.fighters:
			if f.is_ko() or f == owner or (owner != null and not sim.are_enemies(owner, f)) or not f.can_be_hit(tick):
				continue
			if f.global_position.distance_to(at) < float(m["radius"]):
				mines.erase(m)
				sim.queue_event(&"mine_triggered", [f.fighter_id, at])
				if m.get("kind", &"tether_mine") == &"prox_mine":
					_explode(at, float(m["radius"]) * 2.0, m["damage"], m["knockback"], int(m["owner"]), tick, &"mine")
				else:
					_tether(f.fighter_id, -1, at, tick + SimIds.ticks(MINE_HOLD + 0.8), m["strength"], &"mine", int(m["owner"]))
				break


func _step_magnets(tick: int) -> void:
	for id: int in magnets.keys():
		if tick >= int(magnets[id]):
			magnets.erase(id)
			continue
		var user := sim.get_fighter(id)
		if user == null or user.is_ko():
			magnets.erase(id)
			continue
		var item_def := WeaponDef.load_by_id(&"magnet")
		var radius := item_def.effect_radius if item_def != null else 800.0
		var strength := item_def.effect_strength if item_def != null else 2600.0
		var at := user.global_position
		for item in sim.weapons.items:
			if item.state == WeaponItem.State.FLOATING and item.pos.distance_to(at) < radius:
				item.vel += (at - item.pos).normalized() * strength * SimIds.DT
		for f in sim.fighters:
			# "Metal-armored": anyone holding a weapon.
			if f == user or f.is_ko() or f.is_clinging() or f.weapon_id < 0 or not sim.are_enemies(user, f):
				continue
			var d := f.global_position.distance_to(at)
			if d < radius and d > TETHER_ARRIVE:
				f.velocity += (at - f.global_position).normalized() * strength * 0.6 * SimIds.DT


## A frozen fighter flying fast is a wrecking ball: whoever it touches is hit, credited to whoever
## roped it last.
func _step_wrecking_balls(tick: int) -> void:
	var t := TuningDB.t
	for ball in sim.fighters:
		if ball.is_ko() or not ball.is_frozen(tick):
			continue
		var speed := ball.velocity.length()
		if speed < FREEZE_RAM_SPEED:
			continue
		for f in sim.fighters:
			if f == ball or f.is_ko() or not f.can_be_hit(tick):
				continue
			var offset := f.global_position - ball.global_position
			if offset.length() > t.fighter_radius * 2.0 + 6.0:
				continue
			var key := "%d:%d" % [ball.fighter_id, f.fighter_id]
			if tick < int(_ram_until.get(key, -1)):
				continue
			_ram_until[key] = tick + SimIds.ticks(FREEZE_RAM_COOLDOWN)
			var credit := ball.last_pulled_by_id if tick - ball.last_pulled_tick <= SimIds.ticks(t.kill_credit_time) else -1
			if credit == f.fighter_id:
				credit = -1
			var dir := offset.normalized()
			f.take_hit(tick, credit, speed * FREEZE_RAM_DAMAGE, dir * speed * 0.8, 6, &"wrecking_ball")
			ball.velocity *= 0.5
			sim.queue_event(&"wrecking_ball", [ball.fighter_id, f.fighter_id, f.global_position])


## ROPE-15: two fighters roping each other meet in the middle and bounce off in a clash.
func _step_clashes(tick: int) -> void:
	for a in sim.fighters:
		var b := a.rope.pull_target if a.rope.mode == SimIds.RopeMode.PULL else null
		if b == null or b.fighter_id < a.fighter_id or b.rope.mode != SimIds.RopeMode.PULL or b.rope.pull_target != a:
			continue
		var offset := b.global_position - a.global_position
		# Checked before the pulls arrive and end on their own.
		var closing := maxf(0.0, (a.velocity - b.velocity).dot(offset.normalized()))
		if offset.length() > maxf(CLASH_DISTANCE, TuningDB.t.pull_arrive_dist) + closing * SimIds.DT * 2.0:
			continue
		var dir := offset.normalized() if offset.length() > 0.001 else Vector2.RIGHT
		a.rope.release(false)
		b.rope.release(false)
		a.velocity = -dir * CLASH_KNOCKBACK
		b.velocity = dir * CLASH_KNOCKBACK
		a.freeze_ticks = maxi(a.freeze_ticks, CLASH_HITSTOP)
		b.freeze_ticks = maxi(b.freeze_ticks, CLASH_HITSTOP)
		sim.queue_event(&"rope_clash", [a.fighter_id, b.fighter_id, (a.global_position + b.global_position) * 0.5])


# --- ROPE-07 tug-of-war ---------------------------------------------------------------------------

## The hook of `hooker` crossed `owner`'s rope at point: both ropes lock into a tap duel.
func start_duel(hooker: Fighter, owner: Fighter, point: Vector2, tick: int) -> void:
	hooker.rope.enter_duel(point, tick)
	owner.rope.enter_duel(point, tick)
	duels.append({"a": hooker.fighter_id, "b": owner.fighter_id, "point": point, "end": tick + SimIds.ticks(DUEL_TIME), "taps_a": 0, "taps_b": 0})
	sim.queue_event(&"rope_duel_started", [hooker.fighter_id, owner.fighter_id, point])


func duel_tap(f: Fighter) -> void:
	var d := duel_of(f)
	if d.is_empty():
		return
	var key := "taps_a" if d["a"] == f.fighter_id else "taps_b"
	d[key] = int(d[key]) + 1


func _step_duels(tick: int) -> void:
	for d in duels.duplicate():
		var a := sim.get_fighter(int(d["a"]))
		var b := sim.get_fighter(int(d["b"]))
		var a_in := a != null and not a.is_ko() and a.rope.mode == SimIds.RopeMode.DUEL
		var b_in := b != null and not b.is_ko() and b.rope.mode == SimIds.RopeMode.DUEL
		if not a_in or not b_in:
			duels.erase(d)
			if a_in:
				a.rope.release(false)
			if b_in:
				b.rope.release(false)
			continue
		if tick < int(d["end"]):
			continue
		duels.erase(d)
		var ta: int = d["taps_a"]
		var tb: int = d["taps_b"]
		var winner: Fighter = a if ta > tb else (b if tb > ta else null)
		var loser: Fighter = (b if winner == a else a) if winner != null else null
		if winner == null:
			a.rope.release(false)
			b.rope.release(false)
			sim.queue_event(&"rope_duel_ended", [-1, -1])
			continue
		loser.rope.release(false)
		winner.rope.pull_fighter(loser, tick)
		sim.queue_event(&"rope_duel_ended", [winner.fighter_id, loser.fighter_id])


# --- ROPE-06 catch --------------------------------------------------------------------------------

## The first catchable projectile on a hook's path, as {projectile, t}, or {}.
func catchable_on_segment(from: Vector2, to: Vector2, catcher: Fighter) -> Dictionary:
	var best := {}
	var best_t := INF
	for p in sim.weapons.projectiles:
		if p.owner_id == catcher.fighter_id or p.extra.has("caught_by") or p.extra.has("stuck"):
			continue
		var catchable: bool = p.kind == Projectile.Kind.THROWN or (p.extra.get("special", false) and p.extra.get("kind") in CATCHABLE)
		if not catchable:
			continue
		var ht := Rope._segment_circle(from, to - from, p.pos, p.radius + 14.0)
		if ht >= 0.0 and ht < best_t:
			best_t = ht
			best = {"projectile": p, "t": ht}
	return best


## The first enemy rope a hook's path crosses (ROPE-07), as {fighter, t}, or {}.
func rope_on_segment(from: Vector2, to: Vector2, hooker: Fighter) -> Dictionary:
	var best := {}
	var best_t := INF
	for f in sim.fighters:
		if f == hooker or f.is_ko() or not f.rope.is_attached() or not sim.are_enemies(hooker, f):
			continue
		if f.rope.mode == SimIds.RopeMode.DUEL or f.rope.pull_target == hooker:
			continue
		var rt := _segments(from, to, f.global_position, f.rope.hook_pos)
		if rt >= 0.0 and rt < best_t:
			best_t = rt
			best = {"fighter": f, "t": rt}
	return best


## t in [0, 1] along p1-p2 where it crosses q1-q2, or -1.
static func _segments(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> float:
	var r := p2 - p1
	var s := q2 - q1
	var denom := r.cross(s)
	if absf(denom) < 0.0001:
		return -1.0
	var qp := q1 - p1
	var t := qp.cross(s) / denom
	var u := qp.cross(r) / denom
	return t if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0 else -1.0


# --- State ---------------------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {
		"wells": wells.duplicate(true), "tethers": tethers.duplicate(true), "mines": mines.duplicate(true),
		"magnets": magnets.duplicate(), "thrusters": thrusters.duplicate(), "duels": duels.duplicate(true), "rams": _ram_until.duplicate(),
	}


func set_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	wells.assign(s["wells"].duplicate(true))
	tethers.assign(s["tethers"].duplicate(true))
	mines.assign(s["mines"].duplicate(true))
	magnets = s["magnets"].duplicate()
	thrusters = s["thrusters"].duplicate()
	duels.assign(s["duels"].duplicate(true))
	_ram_until = s["rams"].duplicate()
