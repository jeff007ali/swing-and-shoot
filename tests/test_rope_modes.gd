extends GutTest
## §4.14 / M3: mode selection (reel, orbit, swing), orbit tightening keeps angular momentum, release
## keeps velocity plus the fling bonus, latched orbits auto-release, the turbine swing flings you.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")

## Asteroid1 (420, 800) r55. A fighter at (420, 600) flying right passes above it.
const PASS_START := Vector2(420, 600)
const ASTEROID_TOP := Vector2(420, 745)
const ASTEROID_CENTER := Vector2(420, 800)

var h: MatchHarness


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)


func after_each() -> void:
	h.destroy()


func _object(object_name: StringName) -> ArenaObject:
	for obj in h.sim.arena_objects:
		if obj.name == object_name:
			return obj
	return null


func _fire(on_tick: int, target: Vector2, held: bool) -> void:
	var cmd := h.input.at(on_tick)
	cmd.rope_fire = true
	cmd.rope_target = target
	cmd.rope_held = held


func _hold(from_tick: int, to_tick: int) -> void:
	for t in range(from_tick, to_tick + 1):
		h.input.at(t).rope_held = true


## Angular momentum about the pivot: |tangential speed| × distance.
func _angular_momentum(pivot: Vector2) -> float:
	var offset := h.player.global_position - pivot
	return absf(h.player.velocity.cross(offset.normalized())) * offset.length()


func _start_orbit(speed: float, held: bool) -> void:
	h.player.teleport(PASS_START)
	h.player.velocity = Vector2(speed, 0)
	_fire(1, ASTEROID_TOP, held)
	if held:
		_hold(2, 400)
	h.step_until(func() -> bool: return h.player.rope.is_attached(), 10)


# --- Mode selection ---------------------------------------------------------------------------

func test_still_fighter_reels() -> void:
	h.player.teleport(PASS_START)
	assert_eq(h.player.rope.pick_surface_mode(_object(&"Asteroid1"), ASTEROID_TOP), SimIds.RopeMode.REEL)


func test_fast_sideways_pass_orbits() -> void:
	h.player.teleport(PASS_START)
	h.player.velocity = Vector2(600, 0)
	assert_eq(h.player.rope.pick_surface_mode(_object(&"Asteroid1"), ASTEROID_TOP), SimIds.RopeMode.ORBIT)


func test_slow_sideways_pass_reels() -> void:
	h.player.teleport(PASS_START)
	h.player.velocity = Vector2(TuningDB.t.orbit_min_tangent_speed - 20.0, 0)
	assert_eq(h.player.rope.pick_surface_mode(_object(&"Asteroid1"), ASTEROID_TOP), SimIds.RopeMode.REEL)


func test_fast_but_mostly_toward_the_anchor_reels() -> void:
	h.player.teleport(PASS_START)
	# 40 degrees off the rope direction: plenty of sideways speed, but the angle is under ORBIT_MIN_ANGLE.
	h.player.velocity = Vector2.DOWN.rotated(deg_to_rad(40.0)) * 1000.0
	assert_eq(h.player.rope.pick_surface_mode(_object(&"Asteroid1"), ASTEROID_TOP), SimIds.RopeMode.REEL)


func test_moving_object_swings() -> void:
	h.player.teleport(Vector2(960, 950))
	assert_eq(h.player.rope.pick_surface_mode(_object(&"Turbine"), Vector2(960, 645)), SimIds.RopeMode.SWING)


# --- Orbit ------------------------------------------------------------------------------------

func test_sideways_pass_by_an_asteroid_orbits_its_center() -> void:
	_start_orbit(600.0, true)
	assert_eq(h.player.rope.mode, SimIds.RopeMode.ORBIT)
	assert_eq(h.player.state, SimIds.FighterState.ORBITING)
	assert_eq(h.player.rope.pivot_world(), ASTEROID_CENTER, "round objects pivot on their center")
	assert_almost_eq(h.player.rope.hook_pos.distance_to(ASTEROID_CENTER), 55.0, 0.5, "rope drawn to the surface")
	h.step(30)
	assert_eq(h.player.state, SimIds.FighterState.ORBITING, "still orbiting")
	assert_almost_eq(h.player.global_position.distance_to(ASTEROID_CENTER), h.player.rope.length, 0.5, "on the circle")


func test_orbit_tightens_down_to_the_minimum_length() -> void:
	_start_orbit(600.0, true)
	var start_len := h.player.rope.length
	h.step(10)
	assert_almost_eq(h.player.rope.length, start_len - 10.0 * TuningDB.t.orbit_reel_speed / 60.0, 0.5)
	h.step(120)
	assert_almost_eq(h.player.rope.length, TuningDB.t.orbit_min_length + 55.0, 0.01)


func test_orbit_tightening_keeps_angular_momentum() -> void:
	_start_orbit(600.0, true)
	h.step(2)
	var before := _angular_momentum(ASTEROID_CENTER)
	var ticks := 30
	h.step(ticks)
	var after := _angular_momentum(ASTEROID_CENTER)
	var drag_only := exp(-TuningDB.t.drag * ticks / 60.0)
	assert_almost_eq(after / before, drag_only, 0.02, "only drag removes angular momentum")


func test_slingshot_release_is_faster_than_the_entry() -> void:
	_start_orbit(600.0, true)
	var release_tick := h.sim.tick + 55
	h.step(54)
	var before := h.player.velocity
	h.input.at(release_tick).rope_release = true
	watch_signals(GameEvents)
	h.step()
	var bonus := TuningDB.t.slingshot_release_bonus * exp(-TuningDB.t.drag / 60.0)
	assert_eq(h.player.state, SimIds.FighterState.FREE)
	assert_almost_eq(h.player.velocity.length(), before.length() * bonus, 1.0, "bonus, then one tick of drag")
	assert_almost_eq(h.player.velocity.normalized().dot(before.normalized()), 1.0, 0.001, "same direction")
	assert_gt(h.player.velocity.length(), 600.0, "flung out faster than it came in")
	assert_signal_emitted_with_parameters(GameEvents, "rope_released", [h.player.fighter_id, SimIds.RopeMode.ORBIT])


func test_latched_orbit_auto_releases() -> void:
	_start_orbit(600.0, false)
	assert_eq(h.player.rope.mode, SimIds.RopeMode.ORBIT)
	assert_true(h.player.rope.latched)
	var limit := SimIds.ticks(TuningDB.t.latched_orbit_max_time)
	h.step(limit - 2)
	assert_eq(h.player.state, SimIds.FighterState.ORBITING, "still orbiting just before the limit")
	h.step(2)
	assert_eq(h.player.state, SimIds.FighterState.FREE, "released at LATCHED_ORBIT_MAX_TIME")


# --- Swing ------------------------------------------------------------------------------------

## Hooks the end cap of the turbine's first arm from straight outside it. The arm points right at
## tick 0 and the hook needs 3 ticks to cover the 170 px gap, so aim along the arm's angle at tick 3.
func _start_swing() -> void:
	var center := Vector2(960, 600)
	var arm_dir := Vector2.from_angle(TuningDB.t.turbine_omega * 3.0 / 60.0)
	h.player.teleport(center + arm_dir * 340.0)
	_fire(1, center, true)
	_hold(2, 400)
	assert_true(h.step_until(func() -> bool: return h.player.rope.is_attached(), 10), "hooks the turbine")


func test_turbine_swing_reels_in_and_rides_the_turbine() -> void:
	_start_swing()
	assert_eq(h.player.rope.mode, SimIds.RopeMode.SWING)
	assert_eq(h.player.state, SimIds.FighterState.SWINGING)
	h.step(20)
	assert_eq(h.player.state, SimIds.FighterState.SWINGING)
	assert_almost_eq(h.player.rope.length, TuningDB.t.swing_min_length, 0.01, "reeled in to SWING_MIN_LENGTH")
	var anchor := h.player.rope.anchor_world()
	assert_almost_eq(h.player.global_position.distance_to(anchor), TuningDB.t.swing_min_length, 0.5, "held at that length")
	var angle_before := (h.player.global_position - Vector2(960, 600)).angle()
	h.step(20)
	var angle_after := (h.player.global_position - Vector2(960, 600)).angle()
	assert_gt(angle_difference(angle_before, angle_after), 0.3, "carried clockwise with the turbine")


func test_turbine_swing_flings_on_release() -> void:
	_start_swing()
	h.step(40)
	assert_eq(h.player.state, SimIds.FighterState.SWINGING)
	var before := h.player.velocity
	h.input.at(h.sim.tick + 1).rope_release = true
	h.step()
	var bonus := TuningDB.t.swing_release_bonus * exp(-TuningDB.t.drag / 60.0)
	assert_eq(h.player.state, SimIds.FighterState.FREE)
	assert_almost_eq(h.player.velocity.length(), before.length() * bonus, 1.0)
	assert_gt(h.player.velocity.length(), 400.0, "flung off at speed")
