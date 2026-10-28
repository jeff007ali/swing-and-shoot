extends GutTest
## Clinging to a spinning turbine (§4.3): the fighter rides the arm and can always get off it again,
## by timing out or kicking, even from the arm's leading face that sweeps after it.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const TRIALS: int = 24

var h: MatchHarness
var turbine: ArenaObject


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	turbine = h.object_named("Turbine")


func after_each() -> void:
	h.destroy()


## Throws the player at the turbine from angle a; true once it clings to it.
func _cling_from(a: float) -> bool:
	var dir := Vector2.from_angle(a)
	h.player.teleport(turbine.global_position + dir * 330.0)
	h.player.velocity = -dir * 700.0
	return h.step_until(func() -> bool: return h.player.is_clinging() and h.player.cling_object == turbine, 90)


## Ticks after leaving the turbine that the player spends clinging to it again.
func _ticks_stuck_after(leave_tick: int, window: int) -> int:
	var stuck := 0
	h.step(maxi(0, leave_tick - h.sim.tick))
	for i in window:
		h.step()
		if h.player.is_clinging() and h.player.cling_object == turbine:
			stuck += 1
	return stuck


func test_cling_timeout_lets_go_of_a_turbine() -> void:
	var clung := 0
	for i in TRIALS:
		if not _cling_from(TAU * float(i) / TRIALS):
			continue
		clung += 1
		var leave := h.sim.tick + SimIds.ticks(TuningDB.t.cling_time) + 1
		assert_eq(_ticks_stuck_after(leave, 42), 0, "free of the turbine after the cling ends (trial %d)" % i)
	assert_gt(clung, TRIALS / 2, "most throws reach the turbine")


func test_a_sideways_kick_gets_off_a_turbine() -> void:
	for side: float in [1.0, -1.0]:
		for i in TRIALS:
			if not _cling_from(TAU * float(i) / TRIALS):
				continue
			var n := h.player.cling_normal
			var cmd := h.input.at(h.sim.tick + 1)
			cmd.kick = true
			cmd.kick_dir = n.orthogonal() * side
			assert_eq(_ticks_stuck_after(h.sim.tick, 42), 0, "kick gets clear (trial %d, side %d)" % [i, side])


func test_leaving_a_turbine_keeps_its_surface_speed() -> void:
	assert_true(_cling_from(0.0), "clings")
	var point := h.player.global_position
	var expected := turbine.surface_velocity(point)
	assert_gt(expected.length(), 1.0, "the arm is moving")
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.kick = true
	cmd.kick_dir = h.player.cling_normal
	h.step()
	var kick := h.player.velocity - expected
	assert_almost_eq(kick.length(), TuningDB.t.kick_speed, TuningDB.t.kick_speed * 0.05, "kick speed on top of the arm's speed")
