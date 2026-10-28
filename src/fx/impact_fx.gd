class_name ImpactFx
extends Node2D
## Listens to GameEvents and plays the feedback for them (§3.1 rule 6, §4.8, §4.11): particles,
## sounds, screen shake and, for events involving the local player, haptics. The sim never calls any
## of this directly. Hitstop itself is in the sim (per fighter); this is everything else.

const SPARK: Texture2D = preload("res://assets/art/fx/spark_04.png")
const PUFF: Texture2D = preload("res://assets/art/fx/smoke_01.png")
const FLARE: Texture2D = preload("res://assets/art/fx/star_06.png")

## §4.8 game-feel table.
const HEAVY_HIT_DAMAGE: float = 20.0
const SHAKE_BASE: float = 0.2
const SHAKE_PER_DAMAGE: float = 0.01
const SHAKE_COMBO: float = 0.75
const SHAKE_KO: float = 0.5
const COMBO_TEXT: String = "SNAP!"
const COMBO_COLOR: Color = Color(1.0, 0.85, 0.3)
## Pop text for each consumable pickup.
const PICKUP_TEXT: Dictionary = {&"health": "+HP", &"armor": "+ARMOR", &"haste": "HASTE!", &"power": "POWER!"}
## The sniper's tracer: drawn this far along the shot and faded over this long.
const TRACER_LENGTH: float = 3300.0
const TRACER_TIME: float = 0.25

var local_fighter_id: int = -1
var sim: MatchSim
var camera: CameraShake

## Performance pass (§6.7): particle bursts reuse a fixed pool of emitters instead of creating
## and freeing a node per effect.
const POOL_SIZE: int = 40

var _additive := CanvasItemMaterial.new()
var _pool: Array[CPUParticles2D] = []
var _next: int = 0


func _ready() -> void:
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for i in POOL_SIZE:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.emitting = false
		p.lifetime = 0.35
		p.explosiveness = 1.0
		p.gravity = Vector2.ZERO
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.color_ramp = Gradient.new()
		add_child(p)
		_pool.append(p)
	GameEvents.rope_fired.connect(_on_rope_fired)
	GameEvents.rope_attached.connect(_on_rope_attached)
	GameEvents.rope_missed.connect(_on_rope_missed)
	GameEvents.rope_bounced.connect(_on_rope_bounced)
	GameEvents.rope_released.connect(_on_rope_released)
	GameEvents.clung.connect(_on_clung)
	GameEvents.kicked_off.connect(_on_kicked_off)
	GameEvents.melee_started.connect(_on_melee_started)
	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.fighter_ko.connect(_on_fighter_ko)
	GameEvents.fighter_respawned.connect(_on_fighter_respawned)
	GameEvents.weapon_spawned.connect(_on_weapon_spawned)
	GameEvents.weapon_despawned.connect(_on_weapon_despawned)
	GameEvents.weapon_picked.connect(_on_weapon_picked)
	GameEvents.weapon_dropped.connect(_on_weapon_dropped)
	GameEvents.weapon_fired.connect(_on_weapon_fired)
	GameEvents.weapon_thrown.connect(_on_weapon_thrown)
	GameEvents.projectile_blocked.connect(_on_projectile_blocked)
	GameEvents.parried.connect(_on_parried)
	GameEvents.rope_cut.connect(_on_rope_cut)
	GameEvents.rammed.connect(_on_rammed)
	GameEvents.shocked.connect(_on_shocked)
	GameEvents.tank_exploded.connect(_on_tank_exploded)
	GameEvents.object_broken.connect(_on_object_broken)
	GameEvents.object_restored.connect(_on_object_restored)
	GameEvents.vent_changed.connect(_on_vent_changed)
	GameEvents.bomb_passed.connect(_on_bomb_passed)
	GameEvents.bomb_exploded.connect(_on_bomb_exploded)
	GameEvents.level_up.connect(_on_level_up)
	GameEvents.teammate_thrown.connect(_on_teammate_thrown)
	GameEvents.blast.connect(func(at: Vector2, radius: float) -> void: _on_tank_exploded(-1, at, radius))
	GameEvents.laser_bounced.connect(func(at: Vector2) -> void:
		_burst(SPARK, at, Vector2.UP, Color(1, 0.5, 1), 6, 300.0, 180.0, 0.04, true)
		Sfx.play(&"bullet_wall", at, -14.0, 1.8))
	GameEvents.frozen.connect(func(id: int, _s: float) -> void:
		_burst(SPARK, _fighter_pos(id), Vector2.UP, Color(0.6, 0.95, 1.0), 24, 400.0, 180.0, 0.06, true)
		Sfx.play(&"shock", _fighter_pos(id), -4.0, 0.6))
	GameEvents.tethered.connect(func(id: int, _o: int, _k: StringName) -> void: Sfx.play(&"hook_fighter", _fighter_pos(id), -2.0, 0.8))
	GameEvents.tether_smash.connect(func(_a: int, _b: int, at: Vector2) -> void:
		_shockwave(at)
		_burst(SPARK, at, Vector2.UP, Color(1, 0.9, 0.4), 30, 700.0, 180.0, 0.08, true)
		Sfx.play(&"hit_heavy", at, 2.0, 0.8)
		_shake(0.6))
	GameEvents.well_opened.connect(func(at: Vector2, radius: float, hole: bool) -> void:
		_shockwave(at, radius * 0.5)
		Sfx.play(&"slingshot" if not hole else &"explosion", at, 0.0, 0.5))
	GameEvents.mine_triggered.connect(func(_id: int, at: Vector2) -> void: Sfx.play(&"alarm", at, -2.0, 1.4))
	GameEvents.repulsed.connect(func(_id: int, at: Vector2, radius: float, dir: Vector2) -> void:
		_shockwave(at, SpecialWeapons.REPULSE_CLOSE * 1.5)
		_burst(SPARK, at, dir, Color(0.4, 1.0, 0.8), 40, radius * 2.2, SpecialWeapons.REPULSE_CONE_DEG * 0.5, 0.08, true)
		_burst(PUFF, at, dir, Color(0.6, 1.0, 0.9, 0.5), 16, radius * 1.4, SpecialWeapons.REPULSE_CONE_DEG * 0.5, 0.16, false)
		Sfx.play(&"parry", at, 2.0, 0.6)
		Sfx.play(&"kick", at, 0.0, 0.7)
		_shake(0.4))
	GameEvents.consumable_used.connect(_on_consumable_used)
	GameEvents.wrecking_ball.connect(func(_b: int, _v: int, at: Vector2) -> void:
		_burst(SPARK, at, Vector2.UP, Color(0.7, 0.95, 1.0), 26, 650.0, 180.0, 0.07, true)
		Sfx.play(&"hit_heavy", at, 2.0, 0.7)
		_shake(0.5))
	GameEvents.rope_clash.connect(func(_a: int, _b: int, at: Vector2) -> void:
		_shockwave(at)
		_pop_text(at + Vector2(0, -60), "CLASH!")
		Sfx.play(&"parry", at, 2.0, 0.8)
		_shake(0.5))
	GameEvents.rope_duel_started.connect(func(_a: int, _b: int, at: Vector2) -> void:
		_pop_text(at + Vector2(0, -90), "TUG OF WAR!")
		Sfx.play(&"rope_cut", at, -2.0, 1.4))
	GameEvents.rope_duel_ended.connect(func(winner: int, _l: int) -> void:
		if winner >= 0:
			Sfx.play(&"slingshot", _fighter_pos(winner), 0.0, 1.2))
	GameEvents.projectile_caught.connect(func(_id: int, at: Vector2) -> void:
		_pop_text(at + Vector2(0, -50), "CAUGHT!")
		Sfx.play(&"hook_attach", at, 0.0, 1.3))
	GameEvents.projectile_whipped.connect(func(_id: int, at: Vector2) -> void: Sfx.play(&"throw", at, 0.0, 1.0))
	GameEvents.shield_ripped.connect(func(_id: int, at: Vector2) -> void:
		_pop_text(at + Vector2(0, -60), "RIPPED!")
		Sfx.play(&"rope_cut", at, 0.0, 0.9))
	GameEvents.grenade_stuck.connect(func(id: int) -> void: Sfx.play(&"cling", _fighter_pos(id), 0.0, 1.5))
	GameEvents.boss_hit.connect(func(at: Vector2, dmg: float) -> void:
		_burst(SPARK, at, Vector2.UP, Color(1, 0.4, 0.8), 18, 500.0, 180.0, 0.06, true)
		Sfx.play(&"hit_heavy" if dmg >= 15.0 else &"hit_light", at, 0.0, 0.7))


func _fighter(fighter_id: int) -> Fighter:
	return sim.get_fighter(fighter_id) if sim != null else null


func _fighter_pos(fighter_id: int) -> Vector2:
	var f := _fighter(fighter_id)
	return f.global_position if f != null else Vector2.ZERO


func _shake(amount: float) -> void:
	if camera != null:
		camera.add_trauma(amount)


func _on_rope_fired(fighter_id: int, _target: Vector2) -> void:
	Sfx.play(&"rope_fire", _fighter_pos(fighter_id), -8.0, 1.2)


func _on_rope_attached(fighter_id: int, mode: int, point: Vector2) -> void:
	var away := (_fighter_pos(fighter_id) - point).normalized()
	_burst(SPARK, point, away, Color(1.0, 0.85, 0.5), 10, 380.0, 70.0, 0.06, true)
	Sfx.play(&"hook_attach", point, -4.0)
	if mode == SimIds.RopeMode.PULL:
		Sfx.play(&"hook_fighter", point, -2.0)
	if fighter_id == local_fighter_id:
		Haptics.pulse(15, 0.3)


func _on_rope_missed(fighter_id: int) -> void:
	Sfx.play(&"hook_miss", _fighter_pos(fighter_id), -14.0, 1.4)


func _on_rope_bounced(_fighter_id: int, point: Vector2) -> void:
	_burst(SPARK, point, Vector2.UP, Color(0.6, 0.8, 1.0), 6, 300.0, 180.0, 0.05, true)
	Sfx.play(&"hook_bounce", point, -6.0, 1.5)


func _on_rope_released(fighter_id: int, fling_mode: int) -> void:
	if fling_mode == SimIds.RopeMode.NONE:
		return
	var f := _fighter(fighter_id)
	if f == null:
		return
	var back := -f.velocity.normalized()
	_burst(SPARK, f.global_position + back * 20.0, back, Color(0.6, 0.9, 1.0), 12, 420.0, 25.0, 0.05, true)
	Sfx.play(&"slingshot", f.global_position, -6.0, 1.0 + f.velocity.length() / TuningDB.t.max_speed * 0.4)
	if fighter_id == local_fighter_id:
		Haptics.pulse(20, 0.4)


func _on_clung(fighter_id: int, point: Vector2, normal: Vector2) -> void:
	_burst(PUFF, point, normal, Color(0.8, 0.85, 1.0, 0.5), 6, 120.0, 80.0, 0.08, false)
	Sfx.play(&"cling", point, -6.0)
	if fighter_id == local_fighter_id:
		Haptics.pulse(10, 0.2)


func _on_kicked_off(fighter_id: int, direction: Vector2) -> void:
	var pos := _fighter_pos(fighter_id)
	_burst(PUFF, pos - direction * 24.0, -direction, Color(0.7, 0.9, 1.0, 0.6), 8, 260.0, 30.0, 0.07, false)
	Sfx.play(&"kick", pos, -6.0, 1.3)


func _on_melee_started(fighter_id: int, _direction: Vector2) -> void:
	var f := _fighter(fighter_id)
	var held := sim.weapons.held_by(f) if sim != null and f != null else null
	if held != null and held.def.kind == WeaponDef.Kind.BLADE:
		Sfx.play(&"melee_swing", _fighter_pos(fighter_id), -10.0, 1.8)
	else:
		Sfx.play(&"knife", _fighter_pos(fighter_id), -6.0, 1.0)


func _on_hit_landed(attacker_id: int, victim_id: int, damage: float, _knockback: float, is_combo: bool) -> void:
	var attacker_pos := _fighter_pos(attacker_id)
	var victim_pos := _fighter_pos(victim_id)
	var dir := (victim_pos - attacker_pos).normalized()
	var at := victim_pos - dir * TuningDB.t.fighter_radius
	if is_combo:
		_burst(SPARK, at, dir, Color(1.0, 0.9, 0.5), 32, 950.0, 70.0, 0.09, true)
		_burst(FLARE, at, dir, Color(1.0, 0.7, 0.3), 1, 0.0, 0.0, 0.35, true)
		_shockwave(at)
		_pop_text(at + Vector2(0, -60), COMBO_TEXT)
		Sfx.play(&"hit_heavy", at, 2.0)
		Sfx.play(&"slingshot", at, -2.0, 0.7)
		_shake(SHAKE_COMBO)
	else:
		_burst(SPARK, at, dir, Color(1.0, 0.95, 0.75), 12, 520.0, 60.0, 0.06, true)
		Sfx.play(&"hit_heavy" if damage >= HEAVY_HIT_DAMAGE else &"hit_light", at, 0.0)
		_shake(SHAKE_BASE + damage * SHAKE_PER_DAMAGE)
	if attacker_id == local_fighter_id or victim_id == local_fighter_id:
		if is_combo:
			Haptics.pulse(70, 1.0)
		else:
			Haptics.pulse(30, 0.5)


func _on_fighter_ko(fighter_id: int, killer_id: int, _cause: StringName, _last_puller_id: int) -> void:
	var pos := _fighter_pos(fighter_id)
	_burst(SPARK, pos, Vector2.UP, Color(1.0, 0.6, 0.4), 40, 700.0, 180.0, 0.08, true)
	_burst(PUFF, pos, Vector2.UP, Color(0.9, 0.9, 1.0, 0.6), 14, 300.0, 180.0, 0.14, false)
	_shockwave(pos)
	Sfx.play(&"ko", pos, 0.0)
	_shake(SHAKE_KO)
	if fighter_id == local_fighter_id or killer_id == local_fighter_id:
		Haptics.pulse(90, 1.0)


func _on_fighter_respawned(fighter_id: int) -> void:
	var pos := _fighter_pos(fighter_id)
	_burst(FLARE, pos, Vector2.UP, Color(0.6, 0.9, 1.0), 1, 0.0, 0.0, 0.3, true)
	Sfx.play(&"respawn", pos, -8.0)


func _on_weapon_spawned(_weapon_id: int, def_id: StringName, position: Vector2) -> void:
	var def := WeaponDef.load_by_id(def_id)
	_burst(FLARE, position, Vector2.UP, def.glow_color if def != null else Color.WHITE, 1, 0.0, 0.0, 0.3, true)
	_burst(SPARK, position, Vector2.UP, def.glow_color if def != null else Color.WHITE, 14, 260.0, 180.0, 0.05, true)
	Sfx.play(&"weapon_spawn", position, -12.0)


func _on_weapon_despawned(_weapon_id: int, position: Vector2) -> void:
	_burst(PUFF, position, Vector2.UP, Color(0.8, 0.8, 0.9, 0.5), 8, 120.0, 180.0, 0.08, false)
	Sfx.play(&"weapon_gone", position, -16.0, 1.4)


func _on_weapon_picked(fighter_id: int, _weapon_id: int, def_id: StringName) -> void:
	Sfx.play(&"weapon_pick", _fighter_pos(fighter_id), -8.0)
	if def_id == &"sniper":
		# Loud on purpose: everyone should know a sniper is in play.
		Sfx.play(&"sniper_bolt", _fighter_pos(fighter_id), 4.0)
	if fighter_id == local_fighter_id:
		Haptics.pulse(20, 0.4)


func _on_weapon_dropped(_fighter_id: int, _weapon_id: int, position: Vector2) -> void:
	Sfx.play(&"weapon_drop", position, -10.0)


func _on_weapon_fired(fighter_id: int, def_id: StringName, muzzle: Vector2, direction: Vector2) -> void:
	var def := WeaponDef.load_by_id(def_id)
	var color := def.projectile_color if def != null else Color.WHITE
	_burst(SPARK, muzzle, direction, color, 8, 500.0, 25.0, 0.05, true)
	var sound := &"shot_pistol"
	if def_id == &"sniper":
		sound = &"shot_sniper"
		_tracer(muzzle, direction, color)
		_shake(0.5)
		Sfx.play(sound, muzzle, 4.0)
	else:
		if def != null and def.recoil_impulse >= 500.0:
			sound = &"shot_shotgun"
			_shake(0.25)
		Sfx.play(sound, muzzle, -6.0)
	if fighter_id == local_fighter_id:
		Haptics.pulse(15 if sound == &"shot_pistol" else 40, 0.3 if sound == &"shot_pistol" else 0.7)


func _on_weapon_thrown(_fighter_id: int, _def_id: StringName, position: Vector2) -> void:
	Sfx.play(&"throw", position, -6.0, 1.5)


func _on_projectile_blocked(position: Vector2, def_id: StringName) -> void:
	var def := WeaponDef.load_by_id(def_id) if not def_id.is_empty() else null
	_burst(SPARK, position, Vector2.UP, def.projectile_color if def != null else Color.WHITE, 5, 260.0, 180.0, 0.04, true)
	Sfx.play(&"bullet_wall", position, -18.0, 1.6)


func _on_parried(fighter_id: int, point: Vector2) -> void:
	_shockwave(point)
	_burst(SPARK, point, Vector2.UP, Color(0.6, 0.9, 1.0), 16, 600.0, 180.0, 0.05, true)
	_pop_text(point + Vector2(0, -50), "PARRY!")
	Sfx.play(&"parry", point, -2.0)
	if fighter_id == local_fighter_id:
		Haptics.pulse(40, 0.8)


func _on_rope_cut(cutter_id: int, owner_id: int, point: Vector2) -> void:
	_burst(SPARK, point, Vector2.UP, Color(1.0, 0.9, 0.6), 14, 450.0, 180.0, 0.05, true)
	Sfx.play(&"rope_cut", point, -4.0)
	if cutter_id == local_fighter_id or owner_id == local_fighter_id:
		Haptics.pulse(25, 0.5)


func _on_rammed(_rammer_id: int, victim_id: int, closing_speed: float) -> void:
	_shake(0.3 + closing_speed / 4000.0)
	Sfx.play(&"hit_heavy", _fighter_pos(victim_id), 0.0, 0.8)


func _on_shocked(fighter_id: int, point: Vector2) -> void:
	_burst(SPARK, point, Vector2.UP, Color(0.5, 0.8, 1.0), 20, 650.0, 180.0, 0.05, true)
	Sfx.play(&"shock", point, -2.0)
	if fighter_id == local_fighter_id:
		Haptics.pulse(50, 0.8)
		_shake(0.3)


func _on_tank_exploded(_object_id: int, position: Vector2, radius: float) -> void:
	_burst(FLARE, position, Vector2.UP, Color(1.0, 0.6, 0.2), 1, 0.0, 0.0, 0.8, true)
	_burst(SPARK, position, Vector2.UP, Color(1.0, 0.7, 0.3), 48, radius * 3.0, 180.0, 0.1, true)
	_burst(PUFF, position, Vector2.UP, Color(0.4, 0.35, 0.3, 0.7), 18, radius * 1.2, 180.0, 0.25, false)
	_shockwave(position, radius)
	Sfx.play(&"explosion", position, 3.0)
	_shake(0.7)
	var me := _fighter(local_fighter_id)
	if me != null and me.global_position.distance_to(position) < radius * 1.5:
		Haptics.pulse(80, 1.0)


func _on_object_broken(_object_id: int, position: Vector2) -> void:
	_burst(PUFF, position, Vector2.UP, Color(0.7, 0.7, 0.75, 0.7), 14, 300.0, 180.0, 0.14, false)
	_burst(SPARK, position, Vector2.UP, Color(1.0, 0.85, 0.6), 18, 500.0, 180.0, 0.05, true)
	Sfx.play(&"break", position, 0.0, 0.8)
	_shake(0.25)


func _on_object_restored(_object_id: int, position: Vector2) -> void:
	_burst(FLARE, position, Vector2.UP, Color(0.6, 0.9, 1.0), 1, 0.0, 0.0, 0.4, true)


func _on_vent_changed(vent_index: int, state: int) -> void:
	if sim == null or vent_index >= sim.hazards.vents.size():
		return
	var at: Vector2 = sim.hazards.vents[vent_index]["pos"]
	match state:
		HazardSystem.VentState.WARNING:
			Sfx.play(&"alarm", at, -4.0)
		HazardSystem.VentState.OPEN:
			Sfx.play(&"vent_open", at, 0.0, 0.7)
			_shake(0.2)


func _on_bomb_passed(from_id: int, to_id: int) -> void:
	var at := _fighter_pos(to_id)
	_burst(SPARK, at + Vector2(0, -78), Vector2.UP, Color(1.0, 0.5, 0.2), 14, 400.0, 180.0, 0.05, true)
	Sfx.play(&"alarm", at, -6.0, 1.3)
	if from_id >= 0:
		_pop_text(at + Vector2(0, -120), "PASS!")
	if to_id == local_fighter_id:
		Haptics.pulse(60, 0.9)


func _on_bomb_exploded(fighter_id: int, position: Vector2) -> void:
	_on_tank_exploded(-1, position, HotPotato.BLAST_RADIUS)
	if fighter_id == local_fighter_id:
		Haptics.pulse(120, 1.0)


func _on_level_up(fighter_id: int, _level: int) -> void:
	var at := _fighter_pos(fighter_id)
	_burst(FLARE, at, Vector2.UP, Color(0.6, 1.0, 0.7), 1, 0.0, 0.0, 0.4, true)
	Sfx.play(&"announce", at, -6.0, 1.3)


func _on_teammate_thrown(thrower_id: int, fighter_id: int) -> void:
	var pos := _fighter_pos(fighter_id)
	_burst(PUFF, pos, (pos - _fighter_pos(thrower_id)).normalized(), Color(0.7, 0.9, 1.0, 0.6), 10, 320.0, 40.0, 0.08, false)
	Sfx.play(&"slingshot", pos, -4.0, 1.2)


func _on_consumable_used(fighter_id: int, def_id: StringName, position: Vector2) -> void:
	var def := WeaponDef.load_by_id(def_id)
	var color := def.glow_color if def != null else Color.WHITE
	_burst(FLARE, position, Vector2.UP, color, 1, 0.0, 0.0, 0.35, true)
	_burst(SPARK, position, Vector2.UP, color, 18, 380.0, 180.0, 0.05, true)
	_pop_text(position + Vector2(0, -60), PICKUP_TEXT.get(def_id, "+"), color)
	Sfx.play(&"pickup", position, -4.0, 1.2)
	if fighter_id == local_fighter_id:
		Haptics.pulse(25, 0.5)


## A sniper shot's tracer, so everyone sees where it came from.
func _tracer(from: Vector2, dir: Vector2, color: Color) -> void:
	var to := from + dir * TRACER_LENGTH
	if sim != null:
		var hit := sim.weapons.cast(from, to)
		if not hit.is_empty():
			to = hit["position"]
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 5.0
	line.default_color = Color(color, 0.9)
	line.material = _additive
	add_child(line)
	var tween := line.create_tween().set_parallel()
	tween.tween_property(line, "width", 1.0, TRACER_TIME)
	tween.tween_property(line, "modulate:a", 0.0, TRACER_TIME)
	tween.chain().tween_callback(line.queue_free)


## Expanding ring for combos, KOs and blasts.
func _shockwave(pos: Vector2, size: float = 160.0) -> void:
	var ring := Node2D.new()
	ring.position = pos
	ring.set_meta("radius", 10.0)
	ring.draw.connect(func() -> void:
		var r: float = ring.get_meta("radius")
		ring.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, 0.8), 6.0, true))
	add_child(ring)
	var tween := ring.create_tween().set_parallel()
	tween.tween_method(func(r: float) -> void:
		ring.set_meta("radius", r)
		ring.queue_redraw(), 10.0, size, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ring, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(ring.queue_free)


## The "SNAP!" pop for the signature combo (MEL-03).
func _pop_text(pos: Vector2, text: String, color: Color = COMBO_COLOR) -> void:
	var label := Node2D.new()
	label.position = pos
	label.scale = Vector2(0.5, 0.5)
	label.draw.connect(func() -> void:
		var font := ThemeDB.fallback_font
		label.draw_string_outline(font, Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, 64, 12, Color(0.2, 0.05, 0.0))
		label.draw_string(font, Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, 64, color))
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.25)
	tween.set_parallel()
	tween.tween_property(label, "position:y", pos.y - 40.0, 0.35)
	tween.tween_property(label, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(label.queue_free)


func _burst(texture: Texture2D, pos: Vector2, dir: Vector2, color: Color, amount: int, speed: float, spread_deg: float, size: float, additive: bool) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.emitting = false
	p.texture = texture
	p.amount = amount
	p.direction = dir if dir.length_squared() > 0.0001 else Vector2.UP
	p.spread = spread_deg
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 1.5
	p.damping_max = speed * 2.5
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.2
	p.color_ramp.set_color(0, color)
	p.color_ramp.set_color(1, Color(color, 0.0))
	p.material = _additive if additive else null
	p.position = pos
	p.restart()
