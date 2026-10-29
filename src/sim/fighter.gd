class_name Fighter
extends CharacterBody2D
## A player or bot body (§3.6, §4.3). It never reads touch, keys or AI: each tick MatchSim hands it
## one InputCommand and calls step(). Velocity is integrated by hand and moved with move_and_collide().

## Physics skin so a clinging fighter never starts its next move touching the surface.
const CLING_SKIN: float = 1.0
## respawn_tick of a fighter that stays down until something calls it in (Co-op Survival enemies).
const BENCHED: int = 1 << 30

var fighter_id: int = 0
var skin_id: StringName = &"alien_green"
var is_local_player: bool = false
## Shown on the HUD scoreboard ("You", a player's name, "Bot").
var display_name: String = ""
var sim: MatchSim

var state: SimIds.FighterState = SimIds.FighterState.FREE
var hp: float = 0.0
## Hitstop (§3.1 rule 7): while above zero this fighter skips its step. Only attacker and victim.
var freeze_ticks: int = 0
var rope_cooldown_until_tick: int = 0
var cling_ticks_left: int = 0
var cling_normal: Vector2 = Vector2.UP
var cling_object: ArenaObject = null
var facing: Vector2 = Vector2.RIGHT
## Position at the start of the current tick, for views that interpolate between ticks.
var prev_position: Vector2 = Vector2.ZERO

var hitstun_until_tick: int = 0
var invulnerable_until_tick: int = 0
## CNT-03: no enemy rope can pull this fighter before this tick.
var pull_immune_until_tick: int = 0
## Enemy whose rope is pulling this fighter right now, or -1.
var pulled_by_id: int = -1
## Who pulled this fighter last and when: the signature combo (MEL-03) and kill credit (§7).
var last_pulled_by_id: int = -1
var last_pulled_tick: int = SimIds.NO_TICK
var respawn_tick: int = 0
## The last enemy to hit this fighter and when: kill credit for hazard KOs (§6.4).
var last_hit_by_id: int = -1
var last_hit_tick: int = SimIds.NO_TICK

## Held weapon (WeaponItem id) or -1, and when the fire button works again.
var weapon_id: int = -1
var fire_ready_tick: int = 0
var melee_start_tick: int = SimIds.NO_TICK
var melee_ready_tick: int = 0
var melee_dir: Vector2 = Vector2.RIGHT
## Victims already hit by the current swing (one hit each).
var melee_hit_ids: Array[int] = []
## Knockback speed of the last hit taken and its spin direction. View only: the tumble (D12).
var hit_spin: float = 0.0
var hit_spin_dir: float = 1.0
## Freeze ray (§6.6): until this tick the fighter can't act, keeps its speed and can always be roped.
var frozen_until: int = SimIds.NO_TICK
## Pickups (consumables): armor soaks damage before HP; haste and power last until their tick.
var armor: float = 0.0
## Air dash charges left, and when the next one comes back (NO_TICK: all full).
var dash_charges: int = 0
var dash_recharge_tick: int = SimIds.NO_TICK
var haste_until: int = SimIds.NO_TICK
var power_until: int = SimIds.NO_TICK

var _cling_local_pos: Vector2 = Vector2.ZERO
var _cling_local_normal: Vector2 = Vector2.UP
## A moving surface (turbine) this fighter just let go of: until _released_until it can't cling to it
## again and is pushed off it instead, so the sweeping arm can't pin it.
var _released_object: ArenaObject = null
var _released_until: int = SimIds.NO_TICK

@onready var rope: Rope = $Rope
@onready var view: FighterView = $View
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	set_physics_process(false)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = Layers.FIGHTERS
	collision_mask = Layers.FIGHTER_BODY_MASK
	var circle := CircleShape2D.new()
	circle.radius = TuningDB.t.fighter_radius
	_shape.shape = circle
	hp = TuningDB.t.max_hp
	dash_charges = TuningDB.t.dash_charges
	rope.fighter = self
	prev_position = global_position


## §3.3 step 3: freeze, command, rope, integrate, move.
func step(tick: int, cmd: InputCommand) -> void:
	prev_position = global_position
	if state == SimIds.FighterState.KO:
		return
	if freeze_ticks > 0:
		freeze_ticks -= 1
		return
	_follow_cling_surface()
	_apply_command(tick, cmd)
	rope.step(tick)
	_integrate()
	_move()
	rope.post_move()


## §3.3 step 6: status timers.
func step_timers(tick: int) -> void:
	if state == SimIds.FighterState.KO:
		if tick >= respawn_tick and sim != null:
			sim.respawn(self)
		return
	if freeze_ticks > 0:
		return
	if state == SimIds.FighterState.HITSTUN and tick >= hitstun_until_tick:
		state = _idle_state()
	if dash_recharge_tick != SimIds.NO_TICK and tick >= dash_recharge_tick:
		dash_charges += 1
		dash_recharge_tick = tick + SimIds.ticks(TuningDB.t.dash_recharge) if dash_charges < TuningDB.t.dash_charges else SimIds.NO_TICK
	if state == SimIds.FighterState.CLINGING:
		cling_ticks_left -= 1
		if cling_ticks_left <= 0:
			var normal := cling_normal
			var carry := _surface_velocity()
			_leave_cling()
			state = _idle_state()
			velocity = normal * TuningDB.t.cling_drift_speed + carry


func teleport(pos: Vector2) -> void:
	if rope.is_out():
		rope.release(false)
	if weapon_id >= 0 and sim != null:
		sim.weapons.drop(self, Vector2.ZERO)
	rope.reset()
	_break_pull()
	_leave_cling()
	_released_object = null
	state = SimIds.FighterState.FREE
	velocity = Vector2.ZERO
	freeze_ticks = 0
	melee_start_tick = SimIds.NO_TICK
	global_position = pos
	prev_position = pos
	reset_physics_interpolation()


## Back in the arena after a KO (§4.8): full HP and a short invulnerability.
func respawn_at(pos: Vector2, tick: int) -> void:
	teleport(pos)
	hp = TuningDB.t.max_hp
	armor = 0.0
	dash_charges = TuningDB.t.dash_charges
	dash_recharge_tick = SimIds.NO_TICK
	haste_until = SimIds.NO_TICK
	power_until = SimIds.NO_TICK
	invulnerable_until_tick = tick + SimIds.ticks(TuningDB.t.spawn_invuln)
	pull_immune_until_tick = 0
	hitstun_until_tick = 0
	emit_event(&"fighter_respawned", [fighter_id])


func is_clinging() -> bool:
	return state == SimIds.FighterState.CLINGING


func is_ko() -> bool:
	return state == SimIds.FighterState.KO


func has_rope_out() -> bool:
	return rope.is_out()


func rope_ready(tick: int) -> bool:
	return tick >= rope_cooldown_until_tick


func can_fire_rope(tick: int) -> bool:
	return _can_act() and rope_ready(tick)


func can_melee(tick: int) -> bool:
	return _can_act() and tick >= melee_ready_tick


func can_be_targeted() -> bool:
	return state != SimIds.FighterState.KO


func is_invulnerable(tick: int) -> bool:
	return tick < invulnerable_until_tick


func is_pull_immune(tick: int) -> bool:
	return tick < pull_immune_until_tick


func can_be_hit(tick: int) -> bool:
	return state != SimIds.FighterState.KO and not is_invulnerable(tick)


func can_be_pulled(tick: int) -> bool:
	if is_frozen(tick):
		return not is_ko()
	return can_be_hit(tick) and not is_pull_immune(tick)


func is_frozen(tick: int) -> bool:
	return tick < frozen_until and not is_ko()


func is_hasted(tick: int) -> bool:
	return tick < haste_until and not is_ko()


func is_powered(tick: int) -> bool:
	return tick < power_until and not is_ko()


## Movement multiplier from the haste pickup: reel, kick, top speed and rope cooldown.
func speed_mult(tick: int) -> float:
	return TuningDB.t.haste_mult if is_hasted(tick) else 1.0


## A consumable pickup reached this fighter (WeaponSystem.consume).
func apply_consumable(def: WeaponDef, tick: int) -> void:
	var t := TuningDB.t
	match def.projectile_kind:
		&"health":
			hp = minf(t.max_hp, hp + def.effect_strength)
		&"armor":
			armor = minf(t.max_armor, armor + def.effect_strength)
		&"haste":
			haste_until = tick + SimIds.ticks(def.effect_time)
		&"power":
			power_until = tick + SimIds.ticks(def.effect_time)


## MEL-04: a melee swing parries things coming at its front during its active frames, plus
## PARRY_WINDOW either side. incoming_velocity is the velocity of the bullet or hook.
func is_parrying(tick: int, incoming_velocity: Vector2) -> bool:
	var t := TuningDB.t
	var elapsed := tick - melee_start_tick
	var window := SimIds.ticks(t.parry_window)
	if elapsed < t.melee_startup_ticks - window or elapsed > t.melee_startup_ticks + t.melee_active_ticks + window:
		return false
	if incoming_velocity.length_squared() < 0.0001:
		return true
	return melee_dir.dot(-incoming_velocity.normalized()) >= cos(deg_to_rad(t.melee_arc_deg) * 0.5)


## Recoil or a push knocks a clinging fighter off its surface.
func leave_surface() -> void:
	if state == SimIds.FighterState.CLINGING:
		velocity = _surface_velocity()
		_leave_cling()
		state = _idle_state()


func melee_phase(tick: int) -> SimIds.MeleePhase:
	var t := TuningDB.t
	var elapsed := tick - melee_start_tick
	if elapsed < 0:
		return SimIds.MeleePhase.NONE
	if elapsed < t.melee_startup_ticks:
		return SimIds.MeleePhase.STARTUP
	if elapsed < t.melee_startup_ticks + t.melee_active_ticks:
		return SimIds.MeleePhase.ACTIVE
	if elapsed < t.melee_startup_ticks + t.melee_active_ticks + t.melee_recovery_ticks:
		return SimIds.MeleePhase.RECOVERY
	return SimIds.MeleePhase.NONE


## Called by the rope when it attaches to a surface.
func enter_rope_state(new_state: SimIds.FighterState) -> void:
	if state == SimIds.FighterState.CLINGING:
		velocity = _surface_velocity()
	_leave_cling()
	state = new_state


## Called by the rope when it lets go. Velocity is kept (PHY-04).
func on_rope_released() -> void:
	match state:
		SimIds.FighterState.REELING, SimIds.FighterState.ORBITING, SimIds.FighterState.SWINGING:
			state = _idle_state()


## An enemy rope caught this fighter (ROPE-03). Its own rope, if any, keeps working: forces add up.
func begin_pulled(puller_id: int, tick: int) -> void:
	pulled_by_id = puller_id
	last_pulled_by_id = puller_id
	last_pulled_tick = tick
	# CNT-01: a clinging target holds on and resists (Rope._step_pull); it is pulled once it lets go.
	if state == SimIds.FighterState.FREE:
		state = SimIds.FighterState.BEING_PULLED


## Called by the puller's rope when the pull ends for any reason. Velocity is kept (ROPE-13).
func end_pulled(tick: int) -> void:
	pulled_by_id = -1
	pull_immune_until_tick = tick + SimIds.ticks(TuningDB.t.pull_immunity)
	if state == SimIds.FighterState.BEING_PULLED:
		state = SimIds.FighterState.FREE


## A hit landed on this fighter (§4.8): melee, a shot, a ram or a hazard (attacker_id -1).
## hitstop delays the hitstun timer so the freeze doesn't eat it.
func take_hit(tick: int, attacker_id: int, damage: float, knockback: Vector2, hitstop: int, cause: StringName = &"melee") -> void:
	if attacker_id >= 0 and attacker_id != fighter_id:
		last_hit_by_id = attacker_id
		last_hit_tick = tick
	if rope.is_out():
		rope.release(false)
	_break_pull()
	_leave_cling()
	melee_start_tick = SimIds.NO_TICK
	if weapon_id >= 0 and sim != null and knockback.length() >= TuningDB.t.disarm_knockback:
		# HP-03: a hard hit knocks the weapon loose in a random direction.
		sim.weapons.drop(self, Vector2.from_angle(sim.rng.randf() * TAU))
	var attacker := sim.get_fighter(attacker_id) if sim != null and attacker_id >= 0 and attacker_id != fighter_id else null
	if attacker != null and attacker.is_powered(tick):
		damage *= TuningDB.t.power_mult
	var soaked := minf(armor, damage)
	armor -= soaked
	hp -= damage - soaked
	velocity = knockback
	hit_spin = knockback.length()
	hit_spin_dir = -1.0 if knockback.x < 0.0 else 1.0
	if hp <= 0.0:
		knock_out(tick, attacker_id if attacker_id >= 0 else credited_killer(tick), cause)
		return
	state = SimIds.FighterState.HITSTUN
	var t := TuningDB.t
	hitstun_until_tick = tick + hitstop + SimIds.ticks(t.hitstun_base + knockback.length() / t.hitstun_kb_divisor)


## Lost to a hazard: falling out through a vent, into a black hole (§6.4).
func hazard_ko(tick: int, cause: StringName) -> void:
	knock_out(tick, credited_killer(tick), cause)


## §6.4 kill credit: whoever hit or pulled this fighter within KILL_CREDIT_TIME, the more recent one.
func credited_killer(tick: int) -> int:
	var window := SimIds.ticks(TuningDB.t.kill_credit_time)
	var hit_ok := last_hit_by_id >= 0 and tick - last_hit_tick <= window
	var pull_ok := last_pulled_by_id >= 0 and tick - last_pulled_tick <= window
	if hit_ok and pull_ok:
		return last_hit_by_id if last_hit_tick >= last_pulled_tick else last_pulled_by_id
	if hit_ok:
		return last_hit_by_id
	if pull_ok:
		return last_pulled_by_id
	return -1


## HP-01: out until RESPAWN_TIME has passed.
func knock_out(tick: int, killer_id: int, cause: StringName) -> void:
	if rope.is_out():
		rope.release(false)
	_break_pull()
	_leave_cling()
	if weapon_id >= 0 and sim != null:
		sim.weapons.drop(self, Vector2.ZERO)
	state = SimIds.FighterState.KO
	hp = 0.0
	velocity = Vector2.ZERO
	freeze_ticks = 0
	melee_start_tick = SimIds.NO_TICK
	respawn_tick = tick + SimIds.ticks(TuningDB.t.respawn_time)
	if sim != null:
		sim.on_fighter_ko(self, killer_id, cause)
	emit_event(&"fighter_ko", [fighter_id, killer_id, cause, last_pulled_by_id])


func emit_event(signal_name: StringName, args: Array) -> void:
	if sim != null:
		sim.queue_event(signal_name, args)


func get_state() -> Dictionary:
	return {
		"id": fighter_id,
		"pos": global_position,
		"vel": velocity,
		"state": state,
		"hp": hp,
		"freeze": freeze_ticks,
		"rope_cd": rope_cooldown_until_tick,
		"cling_left": cling_ticks_left,
		"cling_normal": cling_normal,
		"cling_obj": cling_object.object_id if cling_object != null else -1,
		"cling_local_pos": _cling_local_pos,
		"cling_local_normal": _cling_local_normal,
		"facing": facing,
		"hitstun_until": hitstun_until_tick,
		"invuln_until": invulnerable_until_tick,
		"pull_immune_until": pull_immune_until_tick,
		"pulled_by": pulled_by_id,
		"last_pulled_by": last_pulled_by_id,
		"last_pulled_tick": last_pulled_tick,
		"respawn_tick": respawn_tick,
		"melee_start": melee_start_tick,
		"melee_ready": melee_ready_tick,
		"melee_dir": melee_dir,
		"melee_hits": melee_hit_ids.duplicate(),
		"weapon": weapon_id,
		"last_hit_by": last_hit_by_id,
		"last_hit_tick": last_hit_tick,
		"fire_ready": fire_ready_tick,
		"frozen": frozen_until,
		"armor": armor,
		"dash": dash_charges,
		"dash_at": dash_recharge_tick,
		"haste": haste_until,
		"power": power_until,
		"released_obj": _released_object.object_id if _released_object != null else -1,
		"released_until": _released_until,
		"rope": rope.get_state(),
	}


func set_state(s: Dictionary) -> void:
	global_position = s["pos"]
	velocity = s["vel"]
	state = s["state"]
	hp = s["hp"]
	freeze_ticks = s["freeze"]
	rope_cooldown_until_tick = s["rope_cd"]
	cling_ticks_left = s["cling_left"]
	cling_normal = s["cling_normal"]
	cling_object = sim.get_object(s["cling_obj"]) if sim != null else null
	_cling_local_pos = s["cling_local_pos"]
	_cling_local_normal = s["cling_local_normal"]
	facing = s["facing"]
	hitstun_until_tick = s["hitstun_until"]
	invulnerable_until_tick = s["invuln_until"]
	pull_immune_until_tick = s["pull_immune_until"]
	pulled_by_id = s["pulled_by"]
	last_pulled_by_id = s["last_pulled_by"]
	last_pulled_tick = s["last_pulled_tick"]
	respawn_tick = s["respawn_tick"]
	melee_start_tick = s["melee_start"]
	melee_ready_tick = s["melee_ready"]
	melee_dir = s["melee_dir"]
	melee_hit_ids.assign(s["melee_hits"])
	weapon_id = s["weapon"]
	last_hit_by_id = s["last_hit_by"]
	last_hit_tick = s["last_hit_tick"]
	fire_ready_tick = s["fire_ready"]
	frozen_until = s.get("frozen", SimIds.NO_TICK)
	armor = s.get("armor", 0.0)
	dash_charges = s.get("dash", TuningDB.t.dash_charges)
	dash_recharge_tick = s.get("dash_at", SimIds.NO_TICK)
	haste_until = s.get("haste", SimIds.NO_TICK)
	power_until = s.get("power", SimIds.NO_TICK)
	_released_object = sim.get_object(s.get("released_obj", -1)) if sim != null else null
	_released_until = s.get("released_until", SimIds.NO_TICK)
	rope.set_state(s["rope"])


## What each state allows (§4.3): HITSTUN and KO can't fire or melee.
func _can_act() -> bool:
	match state:
		SimIds.FighterState.HITSTUN, SimIds.FighterState.KO:
			return false
	return true


func _idle_state() -> SimIds.FighterState:
	return SimIds.FighterState.BEING_PULLED if pulled_by_id >= 0 else SimIds.FighterState.FREE


## Ends a pull on this fighter by releasing the puller's rope (which calls end_pulled()).
func _break_pull() -> void:
	if pulled_by_id < 0:
		return
	var puller := sim.get_fighter(pulled_by_id) if sim != null else null
	if puller != null and puller.rope.pull_target == self:
		puller.rope.release(false)
	else:
		end_pulled(sim.tick if sim != null else 0)


func _apply_command(tick: int, cmd: InputCommand) -> void:
	if is_frozen(tick):
		return
	if rope.mode == SimIds.RopeMode.DUEL:
		# ROPE-07: every tap counts in the tug-of-war; nothing else happens meanwhile.
		if (cmd.rope_fire or cmd.melee or cmd.fire) and sim != null:
			sim.special_weapons.duel_tap(self)
		return
	if cmd.steer.length_squared() > 0.0001 and sim != null and sim.special_weapons.is_thrusting(self, tick):
		leave_surface()
		var thruster := WeaponDef.load_by_id(&"thruster")
		velocity += cmd.steer.normalized() * (thruster.effect_strength if thruster != null else 2600.0) * SimIds.DT
	if cmd.rope_release and rope.is_out():
		rope.release()
	if cmd.rope_fire and can_fire_rope(tick):
		if rope.is_out():
			rope.release()
		rope.fire(tick, cmd.rope_target)
	if cmd.kick:
		if state == SimIds.FighterState.CLINGING:
			_kick(cmd.kick_dir)
		else:
			dash(tick, cmd.kick_dir)
	if cmd.melee and can_melee(tick):
		start_melee(tick, cmd.aim_dir)
	if cmd.fire and _can_act() and sim != null:
		sim.weapons.fire(self, cmd, tick)
	if rope.is_out() and not cmd.rope_held:
		rope.latched = true


## Air dash (a swipe away from walls): turn toward dir at DASH_SPEED, or DASH_KEEP of the current
## speed if that is more. Uses a charge. A rope on a surface or a hook still flying lets go; pulling
## an enemy or fetching a weapon goes on.
func can_dash(tick: int) -> bool:
	return dash_charges > 0 and _can_act() and not is_frozen(tick) and state != SimIds.FighterState.CLINGING


func dash(tick: int, dir: Vector2) -> void:
	if dir.length_squared() < 0.0001 or not can_dash(tick):
		return
	var t := TuningDB.t
	match rope.mode:
		SimIds.RopeMode.PULL, SimIds.RopeMode.FETCH, SimIds.RopeMode.CATCH:
			pass
		_:
			if rope.is_out():
				rope.release(false)
	var d := dir.normalized()
	velocity = d * maxf(t.dash_speed * speed_mult(tick), velocity.length() * t.dash_keep)
	facing = d
	if dash_charges == t.dash_charges:
		dash_recharge_tick = tick + SimIds.ticks(t.dash_recharge)
	dash_charges -= 1
	emit_event(&"dashed", [fighter_id, d])


## Kick off the surface toward dir (a missed rope from a wall, D38). Does nothing unless clinging.
func kick_toward(dir: Vector2) -> void:
	if state == SimIds.FighterState.CLINGING:
		_kick(dir)


func _kick(dir: Vector2) -> void:
	var t := TuningDB.t
	var raw := dir if dir.length_squared() > 0.0001 else cling_normal
	var kick_dir := MathUtil.correct_kick_dir(raw, cling_normal, t.kick_min_normal_dot)
	var carry := _surface_velocity()
	_leave_cling()
	state = _idle_state()
	velocity = kick_dir * t.kick_speed * speed_mult(sim.tick if sim != null else 0) + carry
	facing = kick_dir
	emit_event(&"kicked_off", [fighter_id, kick_dir])


## MEL-01: wind-up, active, recovery. Swings along aim if the player aimed (KNIFE dragged), else at
## the nearest enemy in reach (§4.8 auto-aim), and lunges that way.
func start_melee(tick: int, aim: Vector2 = Vector2.ZERO) -> void:
	var t := TuningDB.t
	melee_start_tick = tick
	melee_ready_tick = tick + SimIds.ticks(t.melee_cooldown)
	melee_hit_ids.clear()
	melee_dir = aim.normalized() if aim.length_squared() > 0.0001 else _melee_aim()
	facing = melee_dir
	if state != SimIds.FighterState.CLINGING:
		velocity += melee_dir * t.melee_lunge_speed
	emit_event(&"melee_started", [fighter_id, melee_dir])


## §4.8 aim: nearest living enemy within MELEE_AUTOAIM_RANGE, else movement direction, else facing.
func _melee_aim() -> Vector2:
	var best_dist := TuningDB.t.melee_autoaim_range
	var best_dir := Vector2.ZERO
	if sim != null:
		for other in sim.fighters:
			if other == self or other.is_ko() or not sim.are_enemies(self, other):
				continue
			var offset := other.global_position - global_position
			var dist := offset.length()
			if dist <= best_dist and dist > 0.001:
				best_dist = dist
				best_dir = offset / dist
	if best_dir != Vector2.ZERO:
		return best_dir
	if velocity.length_squared() > 1.0:
		return velocity.normalized()
	return facing


## A fighter clinging to a moving surface (turbine) rides along with it (§4.3).
func _follow_cling_surface() -> void:
	if state != SimIds.FighterState.CLINGING or cling_object == null or not cling_object.is_moving:
		return
	global_position = cling_object.to_global(_cling_local_pos)
	cling_normal = cling_object.global_transform.basis_xform(_cling_local_normal).normalized()


## How fast the surface this fighter clings to is moving under it (a turbine arm). Letting go keeps
## it, so a sweeping arm doesn't catch the fighter again right away.
func _surface_velocity() -> Vector2:
	if state != SimIds.FighterState.CLINGING or cling_object == null:
		return Vector2.ZERO
	return cling_object.surface_velocity(global_position)


func _integrate() -> void:
	if state == SimIds.FighterState.CLINGING:
		velocity = Vector2.ZERO
		return
	var t := TuningDB.t
	if not is_frozen(sim.tick if sim != null else 0):
		velocity *= MathUtil.drag_factor(t.drag, SimIds.DT)
	velocity = velocity.limit_length(t.max_speed * speed_mult(sim.tick if sim != null else 0))
	if velocity.length_squared() > 1.0 and melee_phase(sim.tick if sim != null else 0) == SimIds.MeleePhase.NONE:
		facing = velocity.normalized()


func _move() -> void:
	if state == SimIds.FighterState.CLINGING:
		return
	var start := global_position
	var motion := velocity * SimIds.DT
	var swinging := rope.is_swinging()
	if swinging:
		# Swing (§4.6): the turbine carries the fighter; velocity follows the move.
		motion = rope.swing_target() - start
	var collision := move_and_collide(motion)
	if swinging:
		velocity = ((global_position - start) / SimIds.DT).limit_length(TuningDB.t.max_speed)
	if collision == null:
		return
	var obj := collision.get_collider() as ArenaObject
	if obj == null:
		velocity = velocity.slide(collision.get_normal())
		return
	if obj == _released_object and (sim.tick if sim != null else 0) < _released_until:
		_push_off(collision, obj)
		return
	match obj.surface_type:
		&"smooth":
			# ARN-07: nothing to grab; bounce off.
			velocity = velocity.bounce(collision.get_normal()) * TuningDB.t.smooth_restitution
		&"electric":
			_shock(collision)
		_:
			if not _glance(collision, obj):
				_cling(collision, obj)


## Touching a moving surface just let go of: keep at least KICK_MIN_NORMAL_DOT x KICK_SPEED away
## from it, relative to its own motion. Each push starts the grace again.
func _push_off(collision: KinematicCollision2D, obj: ArenaObject) -> void:
	var t := TuningDB.t
	var n := collision.get_normal()
	var carry := obj.surface_velocity(collision.get_position())
	var rel := velocity - carry
	rel += n * maxf(0.0, t.kick_speed * t.kick_min_normal_dot - rel.dot(n))
	velocity = rel + carry
	_released_until = sim.tick + SimIds.ticks(t.moving_release_grace) if sim != null else _released_until


## A fast, shallow hit on a still surface slides along it and keeps most of the speed instead of
## clinging; the steeper the hit, the more speed it costs. True when it glanced.
func _glance(collision: KinematicCollision2D, obj: ArenaObject) -> bool:
	var t := TuningDB.t
	var speed := velocity.length()
	if obj.is_moving or speed < t.glance_min_speed:
		return false
	var n := collision.get_normal()
	var steep := absf(velocity.dot(n)) / speed
	var limit := sin(deg_to_rad(t.glance_max_angle))
	if steep > limit:
		return false
	velocity = velocity.slide(n) * lerpf(1.0, t.glance_keep, steep / maxf(limit, 0.001))
	if rope.is_attached() and rope.anchor_object == obj and rope.mode in [SimIds.RopeMode.REEL, SimIds.RopeMode.ORBIT]:
		# Skimming the wall the rope hangs on: the rope would only drag the fighter into it.
		rope.release(false)
	if steep > 0.05:
		emit_event(&"glanced", [fighter_id, collision.get_position(), n])
	return true


## ARN-05: bounce off hard and take damage (at most every ELECTRIC_COOLDOWN).
func _shock(collision: KinematicCollision2D) -> void:
	var t := TuningDB.t
	var n := collision.get_normal()
	var v := velocity.bounce(n)
	v += n * maxf(0.0, t.electric_bounce_speed - v.dot(n))
	var tick := sim.tick if sim != null else 0
	var key := fighter_id
	if sim == null or not sim.authoritative or tick < int(sim.hazards.shock_until.get(key, -1)) or not can_be_hit(tick):
		velocity = v
		return
	sim.hazards.shock_until[key] = tick + SimIds.ticks(t.electric_cooldown)
	emit_event(&"shocked", [fighter_id, collision.get_position()])
	take_hit(tick, -1, t.electric_damage, v, 0, &"electric")


## PHY-03: stop, snap to the surface and hold for CLING_TIME. Being pulled into a surface ends the pull.
func _cling(collision: KinematicCollision2D, obj: ArenaObject) -> void:
	if rope.is_attached() and rope.mode != SimIds.RopeMode.PULL:
		rope.release(false)
	_break_pull()
	state = SimIds.FighterState.CLINGING
	velocity = Vector2.ZERO
	cling_normal = collision.get_normal()
	facing = cling_normal
	global_position = collision.get_position() + cling_normal * (TuningDB.t.fighter_radius + CLING_SKIN)
	cling_object = obj
	_cling_local_pos = obj.to_local(global_position)
	_cling_local_normal = obj.global_transform.basis_xform_inv(cling_normal)
	cling_ticks_left = SimIds.ticks(TuningDB.t.cling_time)
	emit_event(&"clung", [fighter_id, collision.get_position(), cling_normal])


func _leave_cling() -> void:
	if cling_object != null and cling_object.is_moving and state == SimIds.FighterState.CLINGING:
		_released_object = cling_object
		_released_until = (sim.tick if sim != null else 0) + SimIds.ticks(TuningDB.t.moving_release_grace)
	cling_object = null
