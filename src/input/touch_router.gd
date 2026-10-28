class_name TouchRouter
extends Node
## Turns the local player's touches into InputCommands (§4.4, hybrid rope input D7).
## Tracks one rope touch at a time. Touches that start on a button rect are ignored here, so the
## melee thumb never fires a rope. MatchSim pulls one command per tick with build_command().
##
## Timing: events between two ticks belong to the next tick, the one whose command carries them.
## Thruster pack (§6.6): while it burns, a touch held longer than HOLD_THRESHOLD steers toward the
## finger instead of roping; a quick tap still fires a rope, sent when the finger lifts.

signal rope_blocked_by_cooldown
signal debug_toggle_requested
## A rope went out this tick: where the finger was and where aim assist sent it (the HUD shows the
## snap, D39).
signal rope_aimed(tap_world: Vector2, target_world: Vector2)
## The tap was beyond rope range: the range circle flashes (D39).
signal rope_out_of_range

const DEBUG_TOUCH_COUNT: int = 3

var fighter: Fighter
## Turns a world point into the final rope target (aim assist). Unset means no assist.
var aim_resolver: Callable
## Turns a rope-stick direction into a world target (AimAssist.resolve_direction).
var direction_resolver: Callable
## Canvas-space rects of on-screen buttons, set by the HUD.
var button_rects: Array[Rect2] = []

## For the world debug view.
var last_tap_world: Vector2 = Vector2.INF
var last_aim_target: Vector2 = Vector2.INF

var _tick: int = 0
var _pending := InputCommand.new()
var _pending_fire_world: Vector2 = Vector2.ZERO
## The pending target came from the rope stick and is already resolved.
var _pending_resolved: bool = false
var _touches: Dictionary = {}
var _rope_touch: int = -1
var _touch_start_screen: Vector2 = Vector2.ZERO
var _touch_start_world: Vector2 = Vector2.ZERO
## Tick whose command fired this touch's rope, or -1.
var _fire_tick: int = -1
var _kick_window_open: bool = false
var _kick_window_start: int = 0
var _steer_touch: int = -1
var _steer_start: int = 0
var _steer_screen: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			touch_down(touch.index, touch.position)
		else:
			touch_up(touch.index, touch.position)
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		touch_move(drag.index, drag.position)


func touch_down(index: int, screen_pos: Vector2) -> void:
	_touches[index] = true
	if _touches.size() == DEBUG_TOUCH_COUNT:
		debug_toggle_requested.emit()
	if fighter == null or _is_on_button(screen_pos):
		return
	if _thrusting():
		_steer_touch = index
		_steer_start = _event_tick()
		_steer_screen = screen_pos
		_touch_start_world = _to_world(screen_pos)
		return
	_rope_touch = index
	_touch_start_screen = screen_pos
	_touch_start_world = _to_world(screen_pos)
	_fire_tick = -1
	_kick_window_open = false
	if fighter.has_rope_out() or _pending.rope_fire:
		# Rule 4: a new touch releases, then fires again if the cooldown allows.
		_pending.rope_release = true
		_try_fire(_touch_start_world, _event_tick())
	elif fighter.is_clinging():
		# Rule 2: wait a moment to see if this is a kick swipe.
		_kick_window_open = true
		_kick_window_start = _event_tick()
	else:
		# Rule 1: fire at once.
		_try_fire(_touch_start_world, _event_tick())


func touch_move(index: int, screen_pos: Vector2) -> void:
	if index == _steer_touch:
		_steer_screen = screen_pos
		return
	if index != _rope_touch or not _kick_window_open:
		return
	var swipe := screen_pos - _touch_start_screen
	if swipe.length() < TuningDB.t.swipe_min_dist:
		return
	_kick_window_open = false
	_pending.kick = true
	_pending.kick_dir = swipe.normalized()
	# The swipe used up this touch: lifting it does nothing.
	_rope_touch = -1


func touch_up(index: int, _screen_pos: Vector2) -> void:
	_touches.erase(index)
	if index == _steer_touch:
		_steer_touch = -1
		if _event_tick() - _steer_start < SimIds.ticks(TuningDB.t.hold_threshold):
			if fighter.has_rope_out():
				_pending.rope_release = true
			_try_fire(_touch_start_world, _event_tick())
			_fire_tick = -1
		return
	if index != _rope_touch:
		return
	_rope_touch = -1
	if _kick_window_open:
		# Rule 2: a tap while clinging fires a latched rope at the original point.
		_kick_window_open = false
		_try_fire(_touch_start_world, _event_tick())
		_fire_tick = -1
		return
	# Rule 3: a long hold means "let go now"; a short one leaves the rope latched.
	if _fire_tick >= 0 and _event_tick() - _fire_tick >= SimIds.ticks(TuningDB.t.hold_threshold):
		_pending.rope_release = true
	_fire_tick = -1


## Rope stick (D39): fire along dir, letting go of any rope out. Latched, like a quick tap.
func fire_rope_toward(dir: Vector2) -> void:
	if fighter == null or dir == Vector2.ZERO:
		return
	var target: Vector2 = direction_resolver.call(dir) if direction_resolver.is_valid() else fighter.global_position + dir.normalized() * TuningDB.t.rope_range
	if fighter.has_rope_out() or _pending.rope_fire:
		_pending.rope_release = true
	if _try_fire(target, _event_tick()):
		_pending_resolved = true
		_fire_tick = -1


## Rope stick tapped without a drag: let go.
func release_rope() -> void:
	if fighter != null and fighter.has_rope_out():
		_pending.rope_release = true


## KNIFE (melee) button. aim: the direction the player dragged it, or zero for auto-aim.
func queue_melee(aim: Vector2 = Vector2.ZERO) -> void:
	_pending.melee = true
	if aim != Vector2.ZERO:
		_pending.aim_dir = aim.normalized()


## FIRE button, aimed like queue_melee.
func queue_fire(aim: Vector2 = Vector2.ZERO) -> void:
	_pending.fire = true
	if aim != Vector2.ZERO:
		_pending.aim_dir = aim.normalized()


func build_command(tick: int) -> InputCommand:
	if _kick_window_open and tick - _kick_window_start >= SimIds.ticks(TuningDB.t.kick_window):
		# Rule 2: the window ended without a swipe, so fire and keep tracking the hold.
		_kick_window_open = false
		_try_fire(_touch_start_world, tick)
	_tick = tick
	var cmd := _pending
	_pending = InputCommand.new()
	cmd.tick = tick
	if cmd.rope_fire:
		var assisted := aim_resolver.is_valid() and not _pending_resolved
		cmd.rope_target = aim_resolver.call(_pending_fire_world) if assisted else _pending_fire_world
		last_tap_world = _pending_fire_world
		last_aim_target = cmd.rope_target
		rope_aimed.emit(last_tap_world, last_aim_target)
		if fighter != null and fighter.global_position.distance_to(cmd.rope_target) > TuningDB.t.rope_range + TuningDB.t.aim_assist_range_slack:
			rope_out_of_range.emit()
	_pending_resolved = false
	cmd.rope_held = _rope_touch != -1 and _fire_tick >= 0
	if _steer_touch >= 0 and tick - _steer_start >= SimIds.ticks(TuningDB.t.hold_threshold) and fighter != null:
		cmd.steer = (_to_world(_steer_screen) - fighter.global_position).normalized()
	return cmd


func _thrusting() -> bool:
	return fighter.sim != null and fighter.sim.special_weapons.is_thrusting(fighter, _event_tick())


func _try_fire(world_point: Vector2, on_tick: int) -> bool:
	if not fighter.rope_ready(on_tick):
		# Rule 5: nothing fires; the range circle flashes.
		rope_blocked_by_cooldown.emit()
		return false
	_pending.rope_fire = true
	_pending_fire_world = world_point
	_fire_tick = on_tick
	return true


func _event_tick() -> int:
	return _tick + 1


func _is_on_button(screen_pos: Vector2) -> bool:
	for rect in button_rects:
		if rect.has_point(screen_pos):
			return true
	return false


func _to_world(screen_pos: Vector2) -> Vector2:
	if not is_inside_tree():
		return screen_pos
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
