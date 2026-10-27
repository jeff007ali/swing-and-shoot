extends GutTest
## §4.14: two runs of 600 ticks with the same seed and scripted inputs end in the same get_state().
## Protects the input-driven design that Phase 2 prediction relies on. An idle enemy is in the
## arena so pulls, hits and KOs are covered too.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const TICKS: int = 600
const TARGETS: Array[Vector2] = [
	Vector2(1000, 930), Vector2(40, 540), Vector2(480, 255), Vector2(960, 645), Vector2(1880, 300),
	Vector2(1440, 825), Vector2(420, 745), Vector2(960, 40), Vector2(1500, 335),
]


func before_each() -> void:
	TuningDB.reset_to_default()


func _script(h: MatchHarness) -> void:
	var i := 0
	for t in range(5, TICKS, 25):
		var cmd := h.input.at(t)
		cmd.rope_fire = true
		cmd.rope_target = TARGETS[i % TARGETS.size()]
		cmd.rope_held = i % 3 == 0
		i += 1
	for t in range(12, TICKS, 37):
		var kick := h.input.at(t)
		kick.kick = true
		kick.kick_dir = Vector2.from_angle(t * 0.7)
	for t in range(40, TICKS, 90):
		h.input.at(t).rope_release = true
	for t in range(20, TICKS, 17):
		h.input.at(t).melee = true


func _run() -> Dictionary:
	var h := MatchHarness.new()
	h.create(self, 777)
	await wait_physics_frames(2)
	h.add_enemy(Vector2(1000, 930))
	_script(h)
	h.step(TICKS)
	var state := h.sim.get_state()
	h.destroy()
	await wait_physics_frames(2)
	return state


func test_same_seed_and_inputs_give_the_same_state() -> void:
	var a: Dictionary = await _run()
	var b: Dictionary = await _run()
	assert_eq(a["tick"], TICKS)
	assert_eq(str(a), str(b), "identical final state")


func test_set_state_restores_a_snapshot() -> void:
	var h := MatchHarness.new()
	h.create(self, 99)
	await wait_physics_frames(2)
	h.add_enemy(Vector2(1000, 930))
	_script(h)
	h.step(200)
	var snapshot := h.sim.get_state()
	h.step(150)
	var after_once := h.sim.get_state()
	h.sim.set_state(snapshot)
	h.step(150)
	assert_eq(str(h.sim.get_state()), str(after_once), "rewind and replay match")
	h.destroy()


func _run_bots() -> Dictionary:
	var h := MatchHarness.new()
	h.create(self, 4242)
	await wait_physics_frames(2)
	var enemy := h.add_enemy(Vector2(1770, 930))
	h.make_bot(h.player, &"hard")
	h.make_bot(enemy, &"normal")
	h.step(TICKS * 2)
	var state := h.sim.get_state()
	h.destroy()
	await wait_physics_frames(2)
	return state


func test_bot_match_replays_from_its_seed() -> void:
	var a: Dictionary = await _run_bots()
	var b: Dictionary = await _run_bots()
	assert_eq(str(a), str(b), "bots take all randomness from the match seed")
