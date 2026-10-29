class_name FighterView
extends Node2D
## Draws one fighter (§4.11): the skin's sprite posed for the current state, a speed trail, the rope
## range circle for the local player, and an overlay with the knife slash (wind-up, sweep, recover),
## the pull-immunity ring, pickup auras (armor, haste, power), the local player's dash charges and
## (for enemies) a small HP bar with chip damage. Taking damage (any source: it watches HP and armor)
## plays a hit reaction: squash and stretch along the hit, a white then red flash, a floating damage
## number, dazed stars while stunned and a smoke trail behind a hard knockback.
## Visual only: it reads the fighter and never changes it.

## Frozen fighters (§6.6) look icy.
const ICE_TINT: Color = Color(0.6, 0.85, 1.4)
const TRAIL_MIN_SPEED: float = 900.0
const TRAIL_POINTS: int = 12
const TRAIL_WIDTH: float = 26.0
const KICK_POSE_SPEED: float = 300.0
const TURN_RATE: float = 14.0
const BOB_SPEED: float = 1.6
const BOB_ANGLE: float = 0.15
## Hitstun tumble (D12): spin in rad/s per px/s of knockback.
const SPIN_PER_KNOCKBACK: float = 0.008
const BLINK_RATE: float = 12.0
const HIT_FLASH: Color = Color(2.4, 2.4, 2.4)
const IMMUNE_COLOR: Color = Color(0.45, 0.75, 1.0, 0.45)
const HP_BAR_SIZE: Vector2 = Vector2(64, 7)
const HP_BAR_OFFSET: float = -52.0
const SLASH_COLOR: Color = Color(1.0, 0.95, 0.8)
## The knife: hand distance from the center, handle and blade length (px), and how far the wind-up
## pulls it back past the start of the arc (rad).
const KNIFE_HAND: float = 22.0
const KNIFE_HANDLE: float = 16.0
const KNIFE_BLADE: float = 46.0
const KNIFE_WINDUP: float = 0.5
## The body leans this far into an active swing (px).
const LUNGE_OFFSET: float = 10.0
## Hit reaction: squash-and-stretch length and depth, how long the red tint fades, and the knockback
## speed that leaves a smoke trail.
const SQUASH_TIME: float = 0.4
const SQUASH_DEPTH: float = 0.38
const HURT_RED: Color = Color(1.6, 0.25, 0.2)
const HURT_TIME: float = 0.35
const SMOKE_SPEED: float = 900.0
const SMOKE_TIME: float = 0.45
const SMOKE_EVERY: float = 0.035
const SMOKE_LIFE: float = 0.5
## Damage numbers: how long they float and how far they rise.
const NUMBER_TIME: float = 0.85
const NUMBER_RISE: float = 70.0
const SNAP_NUMBER: Color = Color(1.0, 0.85, 0.3)
## Chip damage: the lost part of the HP bar waits this long, then drains at this share of max HP/s.
const CHIP_HOLD: float = 0.4
const CHIP_RATE: float = 1.5
const ARMOR_COLOR: Color = Color(0.35, 0.7, 1.0)
const HASTE_COLOR: Color = Color(1.0, 0.9, 0.25)
const POWER_COLOR: Color = Color(1.0, 0.35, 0.6)
## LAN corrections (§6.2) are blended out over ~100 ms (1/s, exponential).
const CORRECTION_RATE: float = 30.0

var fighter: Fighter
var skin: SkinDef
var range_indicator: RangeIndicator

var _sprite: AnimatedSprite2D
var _trail: Line2D
var _overlay: Node2D
var _bob_time: float = 0.0
var _blink_time: float = 0.0
var _correction: Vector2 = Vector2.ZERO
## The sprite's pose, composed with the squash each frame.
var _rot: float = 0.0
var _sprite_pos: Vector2 = Vector2.ZERO
var _sprite_scale: float = 1.0
## Hit reaction state (seconds since the last hit, how hard, which way it sent us).
var _last_hp: float = 0.0
var _last_armor: float = 0.0
var _hit_age: float = INF
var _hit_power: float = 0.0
var _hit_dir: Vector2 = Vector2.RIGHT
var _combo_hit_ms: int = -1000
var _chip_hp: float = 0.0
var _chip_hold: float = 0.0
var _smoke_left: float = 0.0
var _smoke_clock: float = 0.0
## World-space effects that stay where they were made: [{pos, age}] puffs and
## [{pos, age, text, color, size}] numbers.
var _fx: Node2D
var _puffs: Array[Dictionary] = []
var _numbers: Array[Dictionary] = []


func _ready() -> void:
	fighter = get_parent() as Fighter
	skin = SkinDef.load_by_id(fighter.skin_id)
	var trail_color := skin.trail_color if skin != null else Color(1, 1, 1, 0.5)

	_trail = Line2D.new()
	_trail.top_level = true
	_trail.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_trail.width = TRAIL_WIDTH
	var width_curve := Curve.new()
	width_curve.add_point(Vector2(0.0, 0.0))
	width_curve.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = width_curve
	var gradient := Gradient.new()
	gradient.set_color(0, Color(trail_color, 0.0))
	gradient.set_color(1, trail_color)
	_trail.gradient = gradient
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_trail)

	if fighter.is_local_player:
		range_indicator = RangeIndicator.new()
		range_indicator.fighter = fighter
		add_child(range_indicator)

	_sprite = AnimatedSprite2D.new()
	if skin != null:
		_sprite.sprite_frames = skin.sprite_frames
		_sprite_scale = skin.sprite_scale
		_sprite.modulate = skin.tint
	_sprite.scale = Vector2.ONE * _sprite_scale
	add_child(_sprite)
	_play(&"float")

	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_fx = Node2D.new()
	_fx.top_level = true
	_fx.z_index = 10
	_fx.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_last_hp = fighter.hp
	_last_armor = fighter.armor
	_chip_hp = fighter.hp
	GameEvents.hit_landed.connect(_on_hit_landed)


func _on_hit_landed(_attacker_id: int, victim_id: int, _damage: float, _knockback: float, is_combo: bool) -> void:
	if victim_id == fighter.fighter_id and is_combo:
		_combo_hit_ms = Time.get_ticks_msec()


## A LAN snapshot moved the fighter by -delta: draw it where it was and slide it into place.
func add_correction(delta: Vector2) -> void:
	_correction += delta


func _process(delta: float) -> void:
	_correction = _correction.lerp(Vector2.ZERO, 1.0 - exp(-CORRECTION_RATE * delta))
	position = _correction
	var ko := fighter.is_ko()
	_watch_damage(delta)
	_sprite.visible = not ko
	_overlay.visible = not ko
	if not ko:
		_update_pose(delta)
		_update_flash(delta)
		_apply_sprite_transform()
	_update_trail()
	_update_fx(delta)
	_overlay.queue_redraw()


## Notices HP or armor going down, from any source, and starts the hit reaction.
func _watch_damage(delta: float) -> void:
	var t := TuningDB.t
	var lost := maxf(0.0, _last_hp - fighter.hp) + maxf(0.0, _last_armor - fighter.armor)
	var respawned := _last_hp <= 0.0 and fighter.hp > 0.0
	if lost > 0.5 and not respawned:
		_hit_age = 0.0
		_hit_power = clampf(lost / 30.0, 0.35, 1.0)
		_hit_dir = fighter.velocity.normalized() if fighter.velocity.length() > 1.0 else _hit_dir
		if fighter.velocity.length() >= SMOKE_SPEED:
			_smoke_left = SMOKE_TIME
		var combo := Time.get_ticks_msec() - _combo_hit_ms < 200
		var color := SNAP_NUMBER if combo else (ARMOR_COLOR if fighter.hp >= _last_hp else Color.WHITE)
		# A SNAP's number sits above the "SNAP!" pop (ImpactFx).
		_numbers.append({"pos": interpolated_position() + Vector2(randf_range(-14.0, 14.0), -130.0 if combo else -48.0), "age": 0.0,
			"text": "-%d" % roundi(lost), "color": color, "size": 40 if combo else (34 if lost >= 20.0 else 28)})
		_chip_hold = CHIP_HOLD
	if fighter.hp > _chip_hp or respawned:
		_chip_hp = fighter.hp
	elif _chip_hold > 0.0:
		_chip_hold -= delta
	else:
		_chip_hp = move_toward(_chip_hp, fighter.hp, t.max_hp * CHIP_RATE * delta)
	_last_hp = fighter.hp
	_last_armor = fighter.armor
	_hit_age += delta


## Sprite = its position, the squash along the last hit, its rotation and its scale. The squash
## starts flattened along the hit, then wobbles back through a stretch.
func _apply_sprite_transform() -> void:
	var xf := Transform2D(_rot, Vector2.ONE * _sprite_scale, 0.0, Vector2.ZERO)
	if _hit_age < SQUASH_TIME:
		var k := _hit_age / SQUASH_TIME
		var amount := SQUASH_DEPTH * _hit_power * cos(k * TAU * 1.25) * (1.0 - k) * (1.0 - k)
		var turn := Transform2D(_hit_dir.angle(), Vector2.ZERO)
		var squash := Transform2D(Vector2(1.0 - amount, 0.0), Vector2(0.0, 1.0 + amount * 0.6), Vector2.ZERO)
		xf = turn * squash * turn.affine_inverse() * xf
	xf.origin = _sprite_pos
	_sprite.transform = xf


func _tick() -> int:
	return fighter.sim.tick if fighter.sim != null else 0


func _update_pose(delta: float) -> void:
	var anim := &"float"
	var target_rot := 0.0
	var free_pose := false
	match fighter.state:
		SimIds.FighterState.CLINGING:
			# Feet on the surface: sprite "up" points along the surface normal.
			anim = &"cling"
			target_rot = fighter.cling_normal.angle() + PI * 0.5
		SimIds.FighterState.REELING, SimIds.FighterState.ORBITING, SimIds.FighterState.SWINGING:
			# Reaching for the hook.
			anim = &"reel"
			target_rot = (fighter.rope.hook_pos - fighter.global_position).angle() + PI * 0.5
		SimIds.FighterState.HITSTUN:
			# Ragdoll-style tumble (D12), spinning with the knockback.
			_play(&"hurt")
			if fighter.freeze_ticks <= 0:
				_rot += fighter.hit_spin_dir * fighter.hit_spin * SPIN_PER_KNOCKBACK * delta
			_sprite_pos = _sprite_pos.lerp(Vector2.ZERO, 1.0 - exp(-TURN_RATE * 2.0 * delta))
			return
		SimIds.FighterState.BEING_PULLED:
			anim = &"hurt"
			target_rot = fighter.velocity.angle() + PI * 0.5 if fighter.velocity.length() > KICK_POSE_SPEED else 0.0
		_:
			if fighter.velocity.length() > KICK_POSE_SPEED:
				# Flying head first.
				anim = &"kick"
				target_rot = fighter.velocity.angle() + PI * 0.5
			else:
				_bob_time += delta
				target_rot = sin(_bob_time * BOB_SPEED) * BOB_ANGLE
				free_pose = true
	var lunge := Vector2.ZERO
	var phase := fighter.melee_phase(_tick())
	if phase != SimIds.MeleePhase.NONE:
		# Slashing: lean into the swing, and lunge with the active frames.
		anim = &"kick"
		target_rot = fighter.melee_dir.angle() + PI * 0.5
		free_pose = false
		if phase == SimIds.MeleePhase.ACTIVE:
			lunge = fighter.melee_dir * LUNGE_OFFSET
	_sprite_pos = _sprite_pos.lerp(lunge, 1.0 - exp(-TURN_RATE * 2.0 * delta))
	_play(anim)
	_rot = lerp_angle(_rot, target_rot, 1.0 - exp(-TURN_RATE * delta))
	_sprite.flip_h = free_pose and fighter.facing.x < 0.0


## Hitstop flash on both fighters of a hit, and a blink while spawn-invulnerable.
func _update_flash(delta: float) -> void:
	var base := skin.tint if skin != null else Color.WHITE
	_sprite.modulate = HIT_FLASH if fighter.freeze_ticks > 0 else base
	if fighter.freeze_ticks <= 0 and _hit_age < HURT_TIME:
		# After the white hitstop flash, a red flush that fades.
		_sprite.modulate = base.lerp(HURT_RED, 0.85 * (1.0 - _hit_age / HURT_TIME))
	var frozen := fighter.is_frozen(_tick())
	_sprite.speed_scale = 0.0 if frozen else 1.0
	if frozen:
		_sprite.modulate = base * ICE_TINT
	if fighter.is_invulnerable(_tick()):
		_blink_time += delta
		_sprite.visible = int(_blink_time * BLINK_RATE) % 2 == 0
	else:
		_blink_time = 0.0


func _update_trail() -> void:
	var min_speed := TRAIL_MIN_SPEED * (0.4 if fighter.is_hasted(_tick()) else 1.0)
	var fast := fighter.velocity.length() >= min_speed and not fighter.is_ko()
	if fast:
		_trail.add_point(interpolated_position())
		while _trail.get_point_count() > TRAIL_POINTS:
			_trail.remove_point(0)
	elif _trail.get_point_count() > 0:
		_trail.remove_point(0)


func _draw_overlay() -> void:
	var tick := _tick()
	var t := TuningDB.t
	if fighter.is_pull_immune(tick):
		_overlay.draw_arc(Vector2.ZERO, t.fighter_radius + 6.0, 0.0, TAU, 40, IMMUNE_COLOR, 3.0, true)
	_draw_pickup_auras(tick)
	_draw_dazed(tick)
	if fighter.is_local_player:
		_draw_dash_charges(tick)
	var phase := fighter.melee_phase(tick)
	if phase == SimIds.MeleePhase.ACTIVE or phase == SimIds.MeleePhase.RECOVERY:
		var elapsed := tick - fighter.melee_start_tick - t.melee_startup_ticks
		var fade := 1.0 - clampf(float(elapsed) / float(t.melee_active_ticks + 4), 0.0, 1.0)
		if fade > 0.0:
			var half := deg_to_rad(t.melee_arc_deg) * 0.5
			var mid := fighter.melee_dir.angle()
			for i in 3:
				var r := t.melee_range * (0.6 + 0.15 * i)
				_overlay.draw_arc(Vector2.ZERO, r, mid - half, mid + half, 24, Color(SLASH_COLOR, fade * (0.9 - 0.25 * i)), 8.0 - 2.0 * i, true)
	if phase != SimIds.MeleePhase.NONE and not _holds_blade():
		_draw_knife(tick)
	_draw_specials(tick)
	if not fighter.is_local_player:
		var frac := clampf(fighter.hp / t.max_hp, 0.0, 1.0)
		var chip := clampf(_chip_hp / t.max_hp, 0.0, 1.0)
		var origin := Vector2(-HP_BAR_SIZE.x * 0.5, HP_BAR_OFFSET)
		_overlay.draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0, 0, 0, 0.55))
		if chip > frac:
			_overlay.draw_rect(Rect2(origin + Vector2(HP_BAR_SIZE.x * frac, 0), Vector2(HP_BAR_SIZE.x * (chip - frac), HP_BAR_SIZE.y)), Color(1, 1, 1, 0.85))
		_overlay.draw_rect(Rect2(origin, Vector2(HP_BAR_SIZE.x * frac, HP_BAR_SIZE.y)), Color(1, 0.35, 0.3).lerp(Color(0.5, 1.0, 0.6), frac))


## Stars circling the head while stunned for more than a moment.
func _draw_dazed(tick: int) -> void:
	if fighter.state != SimIds.FighterState.HITSTUN or fighter.hitstun_until_tick - tick < 3:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var head := Vector2(0, -TuningDB.t.fighter_radius - 10.0)
	for i in 3:
		var a := now * 7.0 + TAU * i / 3.0
		var at := head + Vector2(cos(a) * 24.0, sin(a) * 7.0)
		var star := PackedVector2Array()
		for j in 8:
			star.append(at + Vector2.from_angle(TAU * j / 8.0 + now * 4.0) * (7.0 if j % 2 == 0 else 3.0))
		_overlay.draw_colored_polygon(star, Color(1.0, 0.92, 0.4, 0.95))


## The local player's air dash charges: a dot each under the fighter, refilling as a ring.
func _draw_dash_charges(tick: int) -> void:
	var t := TuningDB.t
	var count := t.dash_charges
	for i in count:
		var at := Vector2((i - (count - 1) * 0.5) * 16.0, t.fighter_radius + 16.0)
		if i < fighter.dash_charges:
			_overlay.draw_circle(at, 5.0, Color(0.6, 0.95, 1.0, 0.9))
		else:
			_overlay.draw_arc(at, 5.0, 0.0, TAU, 16, Color(1, 1, 1, 0.3), 1.5, true)
			if i == fighter.dash_charges and fighter.dash_recharge_tick != SimIds.NO_TICK:
				var left := float(fighter.dash_recharge_tick - tick) / SimIds.ticks(t.dash_recharge)
				var k := clampf(1.0 - left, 0.0, 1.0)
				_overlay.draw_arc(at, 5.0, -PI * 0.5, -PI * 0.5 + TAU * k, 16, Color(0.6, 0.95, 1.0, 0.8), 2.0, true)


## Smoke puffs behind a hard knockback, and the floating damage numbers.
func _update_fx(delta: float) -> void:
	if _smoke_left > 0.0 and not fighter.is_ko():
		_smoke_left -= delta
		_smoke_clock += delta
		while _smoke_clock >= SMOKE_EVERY:
			_smoke_clock -= SMOKE_EVERY
			_puffs.append({"pos": interpolated_position() + _correction, "age": 0.0})
	for p in _puffs:
		p["age"] += delta
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return p["age"] < SMOKE_LIFE)
	for n in _numbers:
		n["age"] += delta
	_numbers = _numbers.filter(func(n: Dictionary) -> bool: return n["age"] < NUMBER_TIME)
	_fx.queue_redraw()


func _draw_fx() -> void:
	for p in _puffs:
		var k: float = p["age"] / SMOKE_LIFE
		_fx.draw_circle(p["pos"], lerpf(8.0, 22.0, k), Color(0.85, 0.85, 0.9, 0.45 * (1.0 - k)))
	var font := UiTheme.FONT
	for n in _numbers:
		var age: float = n["age"]
		var k := age / NUMBER_TIME
		var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - age / 0.12)
		var size := int(float(n["size"]) * pop)
		var alpha := clampf((1.0 - k) / 0.35, 0.0, 1.0)
		var at: Vector2 = n["pos"] + Vector2(0, -NUMBER_RISE * (1.0 - pow(1.0 - k, 2.0)))
		var color: Color = n["color"]
		_fx.draw_string_outline(font, at - Vector2(100, 0), n["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, 8, Color(0.1, 0.02, 0.02, alpha))
		_fx.draw_string(font, at - Vector2(100, 0), n["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, size, Color(color, alpha))


func _holds_blade() -> bool:
	var item := fighter.sim.weapons.held_by(fighter) if fighter.sim != null else null
	return item != null and item.def.kind == WeaponDef.Kind.BLADE


## The knife (the default melee): pulled back during the wind-up, swept across the arc during the
## active frames with a smear behind it, then held at the end of the arc while it fades.
func _draw_knife(tick: int) -> void:
	var t := TuningDB.t
	var elapsed := float(tick - fighter.melee_start_tick) + Engine.get_physics_interpolation_fraction()
	var startup := float(t.melee_startup_ticks)
	var active := float(t.melee_active_ticks)
	var recovery := float(t.melee_recovery_ticks)
	var half := deg_to_rad(t.melee_arc_deg) * 0.5
	var mid := fighter.melee_dir.angle()
	var from := mid - half
	var angle := from
	var alpha := 1.0
	if elapsed < startup:
		angle = from - KNIFE_WINDUP * (elapsed / maxf(startup, 1.0))
	elif elapsed < startup + active:
		var k := (elapsed - startup) / active
		angle = from + half * 2.0 * (1.0 - pow(1.0 - k, 3.0))
		_draw_smear(from, angle, t.melee_range)
	else:
		var k := clampf((elapsed - startup - active) / maxf(recovery, 1.0), 0.0, 1.0)
		angle = lerp_angle(mid + half, mid, k * 0.6)
		alpha = 1.0 - k
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal()
	var hand := dir * KNIFE_HAND
	var guard := hand + dir * KNIFE_HANDLE
	var tip := guard + dir * KNIFE_BLADE
	var blade := PackedVector2Array([guard - side * 7.0, tip, guard + side * 4.0])
	_overlay.draw_polyline(blade + PackedVector2Array([blade[0]]), Color(0.1, 0.1, 0.15, alpha * 0.8), 4.0, true)
	_overlay.draw_colored_polygon(blade, Color(0.88, 0.92, 1.0, alpha))
	_overlay.draw_line(guard - side * 7.0, tip, Color(1, 1, 1, alpha), 2.0, true)
	_overlay.draw_line(hand, guard, Color(0.35, 0.24, 0.18, alpha), 9.0, true)
	_overlay.draw_line(guard - side * 9.0, guard + side * 9.0, Color(0.75, 0.75, 0.8, alpha), 5.0, true)


## The blur of the blade sweeping from `from` to `to` (rad).
func _draw_smear(from: float, to: float, reach: float) -> void:
	var steps := 10
	var pts := PackedVector2Array()
	for i in steps + 1:
		pts.append(Vector2.from_angle(lerpf(from, to, float(i) / steps)) * reach)
	for i in range(steps, -1, -1):
		pts.append(Vector2.from_angle(lerpf(from, to, float(i) / steps)) * (KNIFE_HAND + KNIFE_HANDLE))
	if pts.size() >= 3 and absf(to - from) > 0.05:
		_overlay.draw_colored_polygon(pts, Color(SLASH_COLOR, 0.25))


## Pickups: an armor bubble that thins as it is used up, a crackling haste ring, a pulsing power glow.
func _draw_pickup_auras(tick: int) -> void:
	var t := TuningDB.t
	var r := t.fighter_radius
	var now := Time.get_ticks_msec() / 1000.0
	if fighter.armor > 0.0:
		var k := clampf(fighter.armor / t.max_armor, 0.0, 1.0)
		_overlay.draw_circle(Vector2.ZERO, r + 12.0, Color(ARMOR_COLOR, 0.12))
		_overlay.draw_arc(Vector2.ZERO, r + 12.0, 0.0, TAU, 40, Color(ARMOR_COLOR, 0.8), 2.0 + 5.0 * k, true)
	if fighter.is_powered(tick):
		var pulse := 0.5 + 0.5 * sin(now * 10.0)
		_overlay.draw_arc(Vector2.ZERO, r + 18.0 + 4.0 * pulse, 0.0, TAU, 40, Color(POWER_COLOR, 0.35 + 0.4 * pulse), 4.0, true)
	if fighter.is_hasted(tick):
		for i in 6:
			var a := now * 9.0 + TAU * i / 6.0
			_overlay.draw_arc(Vector2.ZERO, r + 8.0, a, a + 0.5, 6, Color(HASTE_COLOR, 0.85), 3.0, true)


## Phase 6 states (§6.6): an ice block when frozen, the thruster flame, the magnet's field.
func _draw_specials(tick: int) -> void:
	var t := TuningDB.t
	var r := t.fighter_radius
	if fighter.is_frozen(tick):
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(Vector2.from_angle(TAU * i / 6.0 + 0.3) * (r + 14.0))
		_overlay.draw_colored_polygon(pts, Color(0.6, 0.9, 1.0, 0.35))
		_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.85, 0.97, 1.0, 0.9), 3.0, true)
	var sim := fighter.sim
	if sim == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if sim.special_weapons.is_thrusting(fighter, tick) and fighter.velocity.length() > 30.0:
		var back := -fighter.velocity.normalized()
		var flicker := 0.8 + 0.2 * sin(now * 40.0)
		var flame := PackedVector2Array([back.orthogonal() * 10.0 + back * r, -back.orthogonal() * 10.0 + back * r, back * (r + 46.0 * flicker)])
		_overlay.draw_colored_polygon(flame, Color(0.4, 0.85, 1.0, 0.85))
	if sim.special_weapons.is_magnetized(fighter, tick):
		for i in 3:
			var k := fposmod(now * 1.2 + i / 3.0, 1.0)
			_overlay.draw_arc(Vector2.ZERO, lerpf(400.0, r, k), 0.0, TAU, 48, Color(0.9, 0.9, 1.0, 0.35 * k), 3.0, true)


## Where the fighter is drawn this frame (between the last two sim ticks).
func interpolated_position() -> Vector2:
	return fighter.prev_position.lerp(fighter.global_position, Engine.get_physics_interpolation_fraction())


func _play(anim: StringName) -> void:
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(anim):
		return
	if _sprite.animation != anim or not _sprite.is_playing():
		_sprite.play(anim)
