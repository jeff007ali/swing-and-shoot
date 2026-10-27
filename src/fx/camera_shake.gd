class_name CameraShake
extends Camera2D
## Arena camera (§3.4) with trauma-based screen shake (§4.8): offset = trauma² × SHAKE_MAX_OFFSET in a
## random direction each frame; trauma decays over time.
## In arenas bigger than the screen it follows the local fighter, leading a little in the direction
## of travel and staying inside the arena (D28). On an axis where the arena fits, it stays centered.

const TRAUMA_DECAY: float = 1.5
## How quickly the camera catches up (1/s, exponential).
const FOLLOW_SHARPNESS: float = 6.0
## Look this far ahead along the velocity (s), at most LOOKAHEAD_MAX px.
const LOOKAHEAD_TIME: float = 0.25
const LOOKAHEAD_MAX: float = 260.0
## A target that moved further than this in one tick went through a wrap edge (ARN-06): snap.
const JUMP_DISTANCE: float = 600.0

var trauma: float = 0.0
var target: Fighter
var bounds: Rect2 = Rect2()

var _last_target_pos: Vector2 = Vector2.INF


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


## Starts following target inside arena_bounds and jumps there at once.
func follow(new_target: Fighter, arena_bounds: Rect2) -> void:
	target = new_target
	bounds = arena_bounds
	snap()


func snap() -> void:
	if bounds.has_area():
		global_position = desired_position()
		reset_physics_interpolation()


## Where the camera wants to be this tick.
func desired_position() -> Vector2:
	var view := get_viewport_rect().size / zoom
	var aim := bounds.get_center()
	if target != null and not target.is_ko():
		aim = target.global_position + (target.velocity * LOOKAHEAD_TIME).limit_length(LOOKAHEAD_MAX)
	return Vector2(
		_axis(aim.x, bounds.position.x, bounds.end.x, view.x),
		_axis(aim.y, bounds.position.y, bounds.end.y, view.y))


## True when the arena is bigger than the screen on either axis.
func is_scrolling() -> bool:
	var view := get_viewport_rect().size / zoom
	return bounds.size.x > view.x + 1.0 or bounds.size.y > view.y + 1.0


func _physics_process(delta: float) -> void:
	if not bounds.has_area():
		return
	if target != null:
		var jumped := _last_target_pos != Vector2.INF and target.global_position.distance_to(_last_target_pos) > JUMP_DISTANCE
		_last_target_pos = target.global_position
		if jumped:
			snap()
			return
	global_position = global_position.lerp(desired_position(), 1.0 - exp(-FOLLOW_SHARPNESS * delta))


func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	if trauma <= 0.0:
		offset = Vector2.ZERO
		return
	offset = Vector2.from_angle(randf() * TAU) * trauma * trauma * TuningDB.t.shake_max_offset


static func _axis(value: float, low: float, high: float, view: float) -> float:
	if high - low <= view:
		return (low + high) * 0.5
	return clampf(value, low + view * 0.5, high - view * 0.5)
