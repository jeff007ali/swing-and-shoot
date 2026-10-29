extends GutTest
## §4.14: hybrid rope input rules (§4.4). The router is not in the tree, so screen == world and
## there is no aim assist.

const FIGHTER_SCENE: PackedScene = preload("res://src/sim/fighter.tscn")
const P := Vector2(500, 500)
const Q := Vector2(900, 300)

var router: TouchRouter
var fighter: Fighter
var tick: int = 0


func before_each() -> void:
	TuningDB.reset_to_default()
	fighter = FIGHTER_SCENE.instantiate()
	add_child_autofree(fighter)
	router = TouchRouter.new()
	router.fighter = fighter
	autofree(router)
	tick = 0
	router.build_command(tick)


func _step() -> InputCommand:
	tick += 1
	return router.build_command(tick)


func _steps(n: int) -> Array[InputCommand]:
	var out: Array[InputCommand] = []
	for i in n:
		out.append(_step())
	return out


func _tap(at: Vector2) -> void:
	router.touch_down(0, at)
	router.touch_up(0, at)


func _hold_ticks() -> int:
	return SimIds.ticks(TuningDB.t.hold_threshold)


func _cling(normal: Vector2) -> void:
	fighter.state = SimIds.FighterState.CLINGING
	fighter.cling_normal = normal


func test_tap_fires_a_latched_rope() -> void:
	_tap(P)
	var cmd := _step()
	assert_true(cmd.rope_fire, "fires")
	assert_eq(cmd.rope_target, P)
	assert_false(cmd.rope_release, "no release")
	assert_false(cmd.rope_held, "finger already up, so latched")


func test_short_hold_then_lift_stays_latched() -> void:
	router.touch_down(0, P)
	assert_true(_step().rope_held)
	fighter.rope.state = SimIds.RopeState.ATTACHED
	_steps(_hold_ticks() - 3)
	router.touch_up(0, P)
	var cmd := _step()
	assert_false(cmd.rope_release)
	assert_false(cmd.rope_held)


func test_hold_past_threshold_then_lift_releases() -> void:
	router.touch_down(0, P)
	var first := _step()
	assert_true(first.rope_fire)
	assert_true(first.rope_held)
	fighter.rope.state = SimIds.RopeState.ATTACHED
	for cmd in _steps(_hold_ticks()):
		assert_false(cmd.rope_release, "no release while held")
		assert_true(cmd.rope_held)
	router.touch_up(0, P)
	var last := _step()
	assert_true(last.rope_release, "lift after the hold threshold releases")
	assert_false(last.rope_fire)


func test_retap_releases_and_fires_again() -> void:
	_tap(P)
	_step()
	fighter.rope.state = SimIds.RopeState.ATTACHED
	fighter.rope_cooldown_until_tick = tick + SimIds.ticks(TuningDB.t.rope_cooldown)
	_steps(SimIds.ticks(TuningDB.t.rope_cooldown))
	_tap(Q)
	var cmd := _step()
	assert_true(cmd.rope_release, "releases the old rope")
	assert_true(cmd.rope_fire, "fires the new one")
	assert_eq(cmd.rope_target, Q)


func test_retap_during_cooldown_only_releases() -> void:
	_tap(P)
	_step()
	fighter.rope.state = SimIds.RopeState.ATTACHED
	fighter.rope_cooldown_until_tick = tick + 20
	watch_signals(router)
	_tap(Q)
	var cmd := _step()
	assert_true(cmd.rope_release)
	assert_false(cmd.rope_fire)
	assert_signal_emitted(router, "rope_blocked_by_cooldown")


func test_tap_on_cooldown_with_no_rope_fires_nothing() -> void:
	fighter.rope_cooldown_until_tick = 50
	watch_signals(router)
	_tap(P)
	var cmd := _step()
	assert_false(cmd.rope_fire)
	assert_false(cmd.rope_release)
	assert_signal_emitted(router, "rope_blocked_by_cooldown")


func test_swipe_while_clinging_kicks_and_fires_no_rope() -> void:
	_cling(Vector2.RIGHT)
	router.touch_down(0, P)
	router.touch_move(0, P + Vector2(40, -10))
	router.touch_up(0, P + Vector2(40, -10))
	var cmd := _step()
	assert_true(cmd.kick, "kicks")
	assert_almost_eq(cmd.kick_dir.angle(), Vector2(40, -10).angle(), 0.001)
	assert_false(cmd.rope_fire, "no rope")
	for later in _steps(SimIds.ticks(TuningDB.t.kick_window) + 2):
		assert_false(later.rope_fire, "kick window never fires later")


func test_small_move_while_clinging_is_not_a_swipe() -> void:
	_cling(Vector2.RIGHT)
	router.touch_down(0, P)
	router.touch_move(0, P + Vector2(10, 0))
	router.touch_up(0, P + Vector2(10, 0))
	var cmd := _step()
	assert_false(cmd.kick)
	assert_true(cmd.rope_fire, "a tap while clinging fires at the touch-down point")
	assert_eq(cmd.rope_target, P)
	assert_false(cmd.rope_held, "latched")


func test_hold_while_clinging_fires_when_kick_window_ends() -> void:
	_cling(Vector2.RIGHT)
	router.touch_down(0, P)
	var window := SimIds.ticks(TuningDB.t.kick_window)
	var fired_on := -1
	for cmd in _steps(window + 3):
		if cmd.rope_fire:
			assert_eq(fired_on, -1, "fires only once")
			fired_on = cmd.tick
			assert_true(cmd.rope_held, "still held")
	assert_eq(fired_on, window + 1, "fires on the tick the window ends")


func test_swipe_away_from_walls_dashes_instead_of_roping() -> void:
	router.touch_down(0, P)
	router.touch_move(0, P + Vector2(0, -TuningDB.t.dash_swipe_dist - 5.0))
	var cmd := _step()
	assert_true(cmd.kick, "a dash (a kick command away from walls)")
	assert_almost_eq(cmd.kick_dir, Vector2.UP, Vector2(0.001, 0.001))
	assert_false(cmd.rope_fire, "the rope the touch fired is called back")
	router.touch_up(0, P)
	assert_false(_step().rope_release, "lifting after a dash does nothing")


func test_swipe_after_the_rope_went_out_dashes_and_lets_go() -> void:
	router.touch_down(0, P)
	assert_true(_step().rope_fire)
	router.touch_move(0, P + Vector2(TuningDB.t.dash_swipe_dist + 5.0, 0))
	var cmd := _step()
	assert_true(cmd.kick)
	assert_true(cmd.rope_release, "the rope already out lets go")


func test_slow_drag_away_from_walls_is_not_a_dash() -> void:
	router.touch_down(0, P)
	_steps(SimIds.ticks(TuningDB.t.kick_window) + 2)
	router.touch_move(0, P + Vector2(200, 0))
	assert_false(_step().kick, "too late for a swipe")


func test_touch_starting_on_a_button_is_ignored() -> void:
	var rects: Array[Rect2] = [Rect2(1700, 860, 200, 200)]
	router.button_rects = rects
	_tap(Vector2(1800, 950))
	var cmd := _step()
	assert_false(cmd.rope_fire)
	assert_false(cmd.rope_release)


func test_button_thumb_does_not_block_rope_thumb() -> void:
	var rects: Array[Rect2] = [Rect2(1700, 860, 200, 200)]
	router.button_rects = rects
	router.touch_down(1, Vector2(1800, 950))
	router.queue_melee()
	_tap(P)
	var cmd := _step()
	assert_true(cmd.melee)
	assert_true(cmd.rope_fire)
	assert_eq(cmd.rope_target, P)


func test_three_finger_tap_requests_debug_overlay() -> void:
	watch_signals(router)
	router.touch_down(0, P)
	router.touch_down(1, Q)
	router.touch_down(2, Q + Vector2(50, 0))
	assert_signal_emit_count(router, "debug_toggle_requested", 1)
