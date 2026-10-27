class_name FighterView
extends Node2D
## Draws one fighter (§4.11): the skin's sprite posed for the current state, a speed trail, the rope
## range circle for the local player, and an overlay with the melee slash, the pull-immunity ring and
## (for enemies) a small HP bar. Visual only: it reads the fighter and never changes it.

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
		_sprite.scale = Vector2.ONE * skin.sprite_scale
		_sprite.modulate = skin.tint
	add_child(_sprite)
	_play(&"float")

	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## A LAN snapshot moved the fighter by -delta: draw it where it was and slide it into place.
func add_correction(delta: Vector2) -> void:
	_correction += delta


func _process(delta: float) -> void:
	_correction = _correction.lerp(Vector2.ZERO, 1.0 - exp(-CORRECTION_RATE * delta))
	position = _correction
	var ko := fighter.is_ko()
	_sprite.visible = not ko
	_overlay.visible = not ko
	if not ko:
		_update_pose(delta)
		_update_flash(delta)
	_update_trail()
	_overlay.queue_redraw()


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
				_sprite.rotation += fighter.hit_spin_dir * fighter.hit_spin * SPIN_PER_KNOCKBACK * delta
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
	if fighter.melee_phase(_tick()) != SimIds.MeleePhase.NONE:
		# Punching: lean into the swing.
		anim = &"kick"
		target_rot = fighter.melee_dir.angle() + PI * 0.5
		free_pose = false
	_play(anim)
	_sprite.rotation = lerp_angle(_sprite.rotation, target_rot, 1.0 - exp(-TURN_RATE * delta))
	_sprite.flip_h = free_pose and fighter.facing.x < 0.0


## Hitstop flash on both fighters of a hit, and a blink while spawn-invulnerable.
func _update_flash(delta: float) -> void:
	var base := skin.tint if skin != null else Color.WHITE
	_sprite.modulate = HIT_FLASH if fighter.freeze_ticks > 0 else base
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
	var fast := fighter.velocity.length() >= TRAIL_MIN_SPEED and not fighter.is_ko()
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
	_draw_specials(tick)
	if not fighter.is_local_player:
		var frac := clampf(fighter.hp / t.max_hp, 0.0, 1.0)
		var origin := Vector2(-HP_BAR_SIZE.x * 0.5, HP_BAR_OFFSET)
		_overlay.draw_rect(Rect2(origin, HP_BAR_SIZE), Color(0, 0, 0, 0.55))
		_overlay.draw_rect(Rect2(origin, Vector2(HP_BAR_SIZE.x * frac, HP_BAR_SIZE.y)), Color(1, 0.35, 0.3).lerp(Color(0.5, 1.0, 0.6), frac))


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
