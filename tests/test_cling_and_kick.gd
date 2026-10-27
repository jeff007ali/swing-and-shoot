extends GutTest
## M1 behavior (§4.3, §4.4): cling on arrival, drift off on timeout, kick direction correction.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")

var h: MatchHarness


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)


func after_each() -> void:
	h.destroy()


## Drifts the player into the left wall (inner face at x = 40).
func _cling_to_left_wall() -> void:
	h.player.teleport(Vector2(200, 540))
	h.player.velocity = Vector2(-600, 0)
	assert_true(h.step_until(h.player.is_clinging, 60), "reaches the wall")


func test_drifting_into_a_wall_clings() -> void:
	_cling_to_left_wall()
	assert_eq(h.player.velocity, Vector2.ZERO)
	assert_almost_eq(h.player.cling_normal.x, 1.0, 0.01)
	assert_almost_eq(h.player.global_position.x, 40.0 + TuningDB.t.fighter_radius + Fighter.CLING_SKIN, 0.5)


func test_drag_slows_a_free_fighter() -> void:
	h.player.teleport(Vector2(700, 900))
	h.player.velocity = Vector2(400, 0)
	h.step(60)
	assert_almost_eq(h.player.velocity.x, 400.0 * exp(-TuningDB.t.drag), 1.0)


func test_cling_timeout_drifts_off_along_the_normal() -> void:
	_cling_to_left_wall()
	var cling_ticks := SimIds.ticks(TuningDB.t.cling_time)
	h.step(cling_ticks - 2)
	assert_true(h.player.is_clinging(), "still clinging just before the timeout")
	h.step(2)
	assert_eq(h.player.state, SimIds.FighterState.FREE)
	assert_almost_eq(h.player.velocity.x, TuningDB.t.cling_drift_speed * exp(-TuningDB.t.drag / 60.0), 1.0)
	assert_almost_eq(h.player.velocity.y, 0.0, 0.01)


func test_kick_off_uses_the_swipe_direction() -> void:
	_cling_to_left_wall()
	var dir := Vector2(1, -1).normalized()
	h.input.at(h.sim.tick + 1).kick = true
	h.input.at(h.sim.tick + 1).kick_dir = dir
	h.step()
	assert_eq(h.player.state, SimIds.FighterState.FREE)
	assert_almost_eq(h.player.velocity.normalized().dot(dir), 1.0, 0.001)
	assert_almost_eq(h.player.velocity.length(), TuningDB.t.kick_speed * exp(-TuningDB.t.drag / 60.0), 0.5, "kick speed, then one tick of drag")


func test_kick_into_the_surface_is_corrected() -> void:
	_cling_to_left_wall()
	h.input.at(h.sim.tick + 1).kick = true
	h.input.at(h.sim.tick + 1).kick_dir = Vector2(-1, -0.2).normalized()
	h.step()
	var v := h.player.velocity.normalized()
	assert_almost_eq(v.dot(Vector2.RIGHT), TuningDB.t.kick_min_normal_dot, 0.001, "pushed out to the minimum angle")
	assert_lt(v.y, 0.0, "keeps the along-surface part (up)")


func test_kick_is_ignored_when_not_clinging() -> void:
	h.player.teleport(Vector2(700, 900))
	h.input.at(1).kick = true
	h.input.at(1).kick_dir = Vector2.RIGHT
	h.step()
	assert_eq(h.player.velocity, Vector2.ZERO)
