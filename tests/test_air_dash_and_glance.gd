extends GutTest
## Movement feel pass: the air dash (a swipe away from walls), glancing off surfaces at speed, and a
## latched reel that lets go short of its hook.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")

var h: MatchHarness


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)


func after_each() -> void:
	h.destroy()


func _dash_cmd(dir: Vector2) -> void:
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.kick = true
	cmd.kick_dir = dir


# --- Air dash -----------------------------------------------------------------------------------

func test_dash_from_rest_flies_along_the_swipe() -> void:
	var t := TuningDB.t
	h.player.teleport(Vector2(700, 540))
	_dash_cmd(Vector2.UP)
	h.step()
	assert_almost_eq(h.player.velocity.normalized().dot(Vector2.UP), 1.0, 0.001)
	assert_almost_eq(h.player.velocity.length(), t.dash_speed * exp(-t.drag / 60.0), 1.0)
	assert_eq(h.player.dash_charges, t.dash_charges - 1, "uses a charge")


func test_dash_while_fast_turns_most_of_the_speed() -> void:
	var t := TuningDB.t
	h.player.teleport(Vector2(400, 540))
	h.player.velocity = Vector2(1600, 0)
	_dash_cmd(Vector2.UP)
	h.step()
	assert_lt(absf(h.player.velocity.x), 1.0, "now going up")
	assert_almost_eq(-h.player.velocity.y, 1600.0 * t.dash_keep * exp(-t.drag / 60.0), 2.0)


func test_charges_run_out_and_come_back() -> void:
	var t := TuningDB.t
	h.player.teleport(Vector2(700, 540))
	for i in t.dash_charges:
		h.player.velocity = Vector2.ZERO
		_dash_cmd(Vector2.UP)
		h.step()
	assert_eq(h.player.dash_charges, 0)
	h.player.velocity = Vector2.ZERO
	_dash_cmd(Vector2.UP)
	h.step()
	assert_eq(h.player.velocity, Vector2.ZERO, "no charges: no dash")
	h.step(SimIds.ticks(t.dash_recharge))
	assert_eq(h.player.dash_charges, 1, "one back after DASH_RECHARGE")
	h.step(SimIds.ticks(t.dash_recharge))
	assert_eq(h.player.dash_charges, t.dash_charges, "all back")
	assert_eq(h.player.dash_recharge_tick, SimIds.NO_TICK)


func test_no_dash_in_hitstun() -> void:
	h.player.teleport(Vector2(700, 540))
	h.player.take_hit(h.sim.tick, -1, 5.0, Vector2(300, 0), 0)
	_dash_cmd(Vector2.UP)
	h.step()
	assert_eq(h.player.dash_charges, TuningDB.t.dash_charges)
	assert_almost_eq(h.player.velocity.y, 0.0, 0.01)


func test_dash_lets_go_of_a_reel_but_keeps_pulling_an_enemy() -> void:
	h.player.teleport(Vector2(600, 200))
	h.player.rope.fire(h.sim.tick, Vector2(40, 200))
	assert_true(h.step_until(func() -> bool: return h.player.rope.is_attached(), 20), "hooks the wall")
	_dash_cmd(Vector2.DOWN)
	h.step()
	assert_false(h.player.rope.is_out(), "the reel lets go")
	var enemy := h.add_enemy(Vector2(800, 930))
	h.player.teleport(Vector2(300, 930))
	h.player.rope.pull_fighter(enemy, h.sim.tick)
	_dash_cmd(Vector2.RIGHT)
	h.step()
	assert_eq(h.player.rope.pull_target, enemy, "still pulling")


func test_dash_charges_survive_a_state_round_trip() -> void:
	h.player.dash_charges = 1
	h.player.dash_recharge_tick = 345
	var s := h.player.get_state()
	h.player.dash_charges = 2
	h.player.dash_recharge_tick = SimIds.NO_TICK
	h.player.set_state(s)
	assert_eq(h.player.dash_charges, 1)
	assert_eq(h.player.dash_recharge_tick, 345)


# --- Glancing -----------------------------------------------------------------------------------

func test_fast_shallow_hit_slides_along_the_wall() -> void:
	h.player.teleport(Vector2(120, 800))
	h.player.velocity = Vector2(-400, -1500)
	h.step(15)
	assert_false(h.player.is_clinging(), "slid instead of clinging")
	assert_lt(absf(h.player.velocity.x), 50.0, "along the wall")
	assert_gt(-h.player.velocity.y, 1300.0, "kept most of its speed")


func test_head_on_hit_still_clings() -> void:
	h.player.teleport(Vector2(200, 600))
	h.player.velocity = Vector2(-1500, -100)
	assert_true(h.step_until(h.player.is_clinging, 20))


func test_slow_shallow_hit_still_clings() -> void:
	h.player.teleport(Vector2(90, 800))
	h.player.velocity = Vector2(-150, -500)
	assert_true(h.step_until(h.player.is_clinging, 30))


# --- Reel lets go short -------------------------------------------------------------------------

func test_latched_reel_lets_go_short_of_the_wall_and_coasts_in() -> void:
	var t := TuningDB.t
	h.player.teleport(Vector2(650, 200))
	h.player.rope.fire(h.sim.tick, Vector2(40, 200))
	h.player.rope.latched = true
	var released_at := -1.0
	for i in 90:
		h.step()
		if released_at < 0.0 and not h.player.rope.is_out() and not h.player.is_clinging():
			released_at = h.player.global_position.x
		if h.player.is_clinging():
			break
	assert_gt(released_at, 40.0 + t.fighter_radius + 20.0, "let go before reaching the wall")
	assert_lt(released_at, 40.0 + t.reel_release_dist + 40.0, "but only near the end")
	assert_true(h.player.is_clinging(), "and coasted in")


# --- Wall swing ---------------------------------------------------------------------------------

## The Hangar's ceiling: its inner face is at y = 40, facing down.
const CEILING_HOOK := Vector2(600, 40)


func _ceiling() -> ArenaObject:
	var hit := h.sim.weapons.cast(Vector2(600, 300), Vector2(600, -100))
	return hit["collider"] as ArenaObject


func test_fast_sideways_hook_on_a_wall_swings() -> void:
	h.player.teleport(Vector2(400, 400))
	h.player.velocity = Vector2(1200, 0)
	assert_eq(h.player.rope.pick_surface_mode(_ceiling(), CEILING_HOOK, Vector2.DOWN), SimIds.RopeMode.ORBIT)


func test_wall_hook_while_flying_into_that_wall_reels() -> void:
	h.player.teleport(Vector2(400, 400))
	h.player.velocity = Vector2(1, -1).normalized() * 1200.0
	assert_eq(h.player.rope.pick_surface_mode(_ceiling(), Vector2(900, 40), Vector2.DOWN), SimIds.RopeMode.REEL)


func test_slow_wall_hook_reels() -> void:
	h.player.teleport(Vector2(400, 400))
	h.player.velocity = Vector2(TuningDB.t.wall_swing_min_tangent_speed - 50.0, 0)
	assert_eq(h.player.rope.pick_surface_mode(_ceiling(), CEILING_HOOK, Vector2.DOWN), SimIds.RopeMode.REEL)


func test_quick_tap_wall_swing_flings_out_and_skims_the_wall() -> void:
	h.player.teleport(Vector2(400, 400))
	h.player.velocity = Vector2(1200, 0)
	h.player.rope.fire(h.sim.tick, CEILING_HOOK)
	h.player.rope.latched = true
	assert_true(h.step_until(func() -> bool: return h.player.rope.is_attached(), 10), "hooks the ceiling")
	assert_eq(h.player.rope.mode, SimIds.RopeMode.ORBIT, "swings")
	assert_true(h.step_until(func() -> bool: return not h.player.rope.is_out(), 60), "lets go on its own")
	assert_lt(h.player.velocity.y, 0.0, "flung up and on")
	assert_gt(h.player.velocity.x, 0.0)
	var clung := false
	for i in 50:
		h.step()
		clung = clung or h.player.is_clinging()
	assert_false(clung, "skims along the ceiling instead of sticking")
	assert_gt(h.player.global_position.x, 1000.0, "and keeps going")


func test_held_wall_swing_keeps_circling() -> void:
	var hook := Vector2(800, 40)
	h.player.teleport(Vector2(600, 420))
	h.player.velocity = Vector2(1200, 0)
	h.player.rope.fire(h.sim.tick, hook)
	for i in 40:
		h.input.at(h.sim.tick + 1 + i).rope_held = true
	h.step(12)
	assert_eq(h.player.rope.mode, SimIds.RopeMode.ORBIT)
	var r := h.player.global_position.distance_to(hook)
	h.step(16)
	assert_true(h.player.rope.is_attached(), "held: no auto release")
	assert_lt(h.player.velocity.y, -300.0, "swung round past where a quick tap lets go")
	assert_almost_eq(h.player.global_position.distance_to(hook), r, 20.0, "on the rope's circle")
