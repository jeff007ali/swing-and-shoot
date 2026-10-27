extends GutTest
## M2 rope core (§4.5, §4.6): hook flight, attach, reel, range limit, cooldown, release keeps velocity.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")

var h: MatchHarness


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)


func after_each() -> void:
	h.destroy()


func _fire(on_tick: int, target: Vector2, held: bool = false) -> void:
	var cmd := h.input.at(on_tick)
	cmd.rope_fire = true
	cmd.rope_target = target
	cmd.rope_held = held


func test_rope_to_a_wall_reels_in_and_clings() -> void:
	h.player.teleport(Vector2(300, 540))
	_fire(1, Vector2(40, 540))
	h.step()
	assert_eq(h.player.rope.state, SimIds.RopeState.FLYING)
	assert_true(h.step_until(func() -> bool: return h.player.rope.is_attached(), 10), "hook reaches the wall")
	assert_eq(h.player.state, SimIds.FighterState.REELING)
	assert_eq(h.player.rope.mode, SimIds.RopeMode.REEL)
	assert_true(h.step_until(h.player.is_clinging, 60), "reels in and clings")
	assert_almost_eq(h.player.cling_normal.x, 1.0, 0.01)
	assert_false(h.player.rope.is_out(), "clinging detaches the rope")


func test_reel_speed_toward_anchor_is_capped() -> void:
	h.player.teleport(Vector2(660, 540))
	_fire(1, Vector2(40, 540))
	var top := 0.0
	for i in 60:
		h.step()
		if h.player.is_clinging():
			break
		top = maxf(top, -h.player.velocity.x)
	assert_gt(top, TuningDB.t.reel_max_speed * 0.9, "gets close to the cap")
	assert_lte(top, TuningDB.t.reel_max_speed + 0.01, "never above it")


func test_hook_misses_beyond_rope_range() -> void:
	h.player.teleport(Vector2(700, 980))
	watch_signals(GameEvents)
	_fire(1, Vector2(1880, 980))
	var ticks_to_range := ceili(TuningDB.t.rope_range / (TuningDB.t.hook_speed / 60.0))
	h.step(ticks_to_range)
	assert_eq(h.player.rope.state, SimIds.RopeState.RETRACTING)
	assert_signal_emitted(GameEvents, "rope_missed")
	h.step(SimIds.ticks(TuningDB.t.rope_retract_time))
	assert_eq(h.player.rope.state, SimIds.RopeState.IDLE)
	assert_eq(h.player.state, SimIds.FighterState.FREE)


func test_rope_cooldown_blocks_a_second_fire() -> void:
	h.player.teleport(Vector2(700, 980))
	_fire(1, Vector2(1880, 980))
	_fire(2, Vector2(40, 980))
	h.step(2)
	assert_eq(h.player.rope_cooldown_until_tick, 1 + SimIds.ticks(TuningDB.t.rope_cooldown))
	assert_almost_eq(h.player.rope.hook_pos.x, 700.0 + 2.0 * TuningDB.t.hook_speed / 60.0, 0.5, "still the first hook")


func test_release_keeps_velocity() -> void:
	h.player.teleport(Vector2(660, 540))
	_fire(1, Vector2(40, 540), true)
	for t in range(2, 20):
		h.input.at(t).rope_held = true
	h.step(19)
	assert_true(h.player.rope.is_attached())
	var before := h.player.velocity
	h.input.at(20).rope_release = true
	h.step()
	assert_eq(h.player.state, SimIds.FighterState.FREE)
	assert_almost_eq(h.player.velocity.x, before.x * exp(-TuningDB.t.drag / 60.0), 1.0, "only drag applies")
	assert_eq(h.player.rope.state, SimIds.RopeState.RETRACTING)


func test_rope_from_a_clinging_fighter_pulls_it_off_the_wall() -> void:
	h.player.teleport(Vector2(200, 540))
	h.player.velocity = Vector2(-600, 0)
	assert_true(h.step_until(h.player.is_clinging, 60))
	_fire(h.sim.tick + 1, Vector2(480, 255))
	assert_true(h.step_until(func() -> bool: return h.player.state == SimIds.FighterState.REELING, 10))
	assert_true(h.step_until(h.player.is_clinging, 60), "reaches Box A")
	assert_eq(h.player.cling_object.name, &"BoxA")


func test_turbine_moves_its_rope_anchor() -> void:
	h.player.teleport(Vector2(960, 950))
	_fire(1, Vector2(960, 645))
	assert_true(h.step_until(func() -> bool: return h.player.rope.is_attached(), 10), "hooks the turbine")
	var first := h.player.rope.anchor_world()
	h.step()
	if h.player.rope.is_attached():
		assert_ne(h.player.rope.anchor_world(), first, "anchor rides on the rotating turbine")


func test_aim_assist_snaps_to_a_nearby_surface() -> void:
	h.player.teleport(Vector2(700, 540))
	var near_box := Vector2(480, 300 - 45 - 40)
	var target := h.sim.aim_assist(near_box, h.player)
	assert_almost_eq(target.y, 255.0, 1.0, "snaps onto the top face of Box A")
	var empty := Vector2(700, 700)
	assert_eq(h.sim.aim_assist(empty, h.player), empty, "open space is left alone")
