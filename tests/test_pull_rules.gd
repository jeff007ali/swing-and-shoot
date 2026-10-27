extends GutTest
## §4.14 / M4: enemy pull (ROPE-03, ROPE-13), pull immunity (CNT-03), the ways a pull ends, and the
## M4 gate: pull-then-melee on a moving target hits for 40+ with the combo, and chain-pulling the same
## target within 1 s is impossible.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const PLAYER_POS := Vector2(600, 930)
const ENEMY_POS := Vector2(1000, 930)

var h: MatchHarness
var enemy: Fighter


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	h.player.teleport(PLAYER_POS)
	enemy = h.add_enemy(ENEMY_POS)
	watch_signals(GameEvents)


func after_each() -> void:
	h.destroy()


func _fire_at(target: Vector2, on_tick: int = -1) -> void:
	var cmd := h.input.at(on_tick if on_tick >= 0 else h.sim.tick + 1)
	cmd.rope_fire = true
	cmd.rope_target = target


func _pulling() -> bool:
	return enemy.pulled_by_id == h.player.fighter_id


func _start_pull() -> void:
	_fire_at(enemy.global_position)
	assert_true(h.step_until(_pulling, 15), "hook reaches the enemy")


func test_hooking_an_enemy_pulls_it() -> void:
	_start_pull()
	assert_eq(h.player.rope.mode, SimIds.RopeMode.PULL)
	assert_eq(h.player.rope.pull_target, enemy)
	assert_eq(enemy.state, SimIds.FighterState.BEING_PULLED)
	h.step(5)
	assert_lt(enemy.velocity.x, -100.0, "accelerating toward the puller")
	assert_gt(h.player.velocity.x, 0.0, "the puller lurches toward the target")


func test_pull_speed_toward_the_puller_is_capped() -> void:
	_start_pull()
	var top := 0.0
	while _pulling():
		h.step()
		top = maxf(top, -enemy.velocity.x)
	assert_lte(top, TuningDB.t.pull_max_speed + 0.01)


func test_pull_ends_on_arrival_and_the_target_flies_past() -> void:
	_start_pull()
	assert_true(h.step_until(func() -> bool: return not _pulling(), 60), "pull ends")
	assert_lte(enemy.global_position.distance_to(h.player.global_position), TuningDB.t.pull_arrive_dist + 30.0, "ended by arrival")
	assert_eq(enemy.state, SimIds.FighterState.FREE)
	assert_lt(enemy.velocity.x, -1000.0, "keeps its speed")
	assert_true(enemy.is_pull_immune(h.sim.tick), "CNT-03 immunity")
	assert_eq(h.player.rope.state, SimIds.RopeState.RETRACTING)
	h.step(10)
	assert_lt(enemy.global_position.x, h.player.global_position.x, "ROPE-13: flew past the puller")


func test_pull_ends_on_timeout() -> void:
	TuningDB.t.pull_accel = 60.0
	_start_pull()
	var started := h.sim.tick
	assert_true(h.step_until(func() -> bool: return not _pulling(), 120))
	assert_eq(h.sim.tick - started, SimIds.ticks(TuningDB.t.pull_max_time))
	assert_true(enemy.is_pull_immune(h.sim.tick))


func test_pull_ends_when_the_target_clings() -> void:
	_start_pull()
	enemy.velocity = Vector2(0, 1800)
	assert_true(h.step_until(enemy.is_clinging, 10), "target hits the bottom wall")
	assert_false(_pulling())
	assert_false(h.player.rope.is_out(), "the puller's rope lets go")
	assert_true(enemy.is_pull_immune(h.sim.tick))


func test_pull_ends_when_the_target_is_hit() -> void:
	_start_pull()
	h.input.at(h.sim.tick + 1).melee = true
	h.step_until(func() -> bool: return enemy.state == SimIds.FighterState.HITSTUN, 40)
	assert_false(_pulling())
	assert_false(h.player.rope.is_out())


func test_puller_release_ends_the_pull_and_keeps_target_velocity() -> void:
	_start_pull()
	h.step(10)
	var v := enemy.velocity
	h.input.at(h.sim.tick + 1).rope_release = true
	h.step()
	assert_false(_pulling())
	assert_almost_eq(enemy.velocity.x, v.x * exp(-TuningDB.t.drag / 60.0), 1.0)


func test_immune_target_bounces_the_hook() -> void:
	enemy.pull_immune_until_tick = 1000
	_fire_at(enemy.global_position)
	h.step(10)
	assert_signal_emitted(GameEvents, "rope_bounced")
	assert_false(_pulling())
	assert_eq(enemy.state, SimIds.FighterState.FREE)


func test_invulnerable_target_bounces_the_hook() -> void:
	enemy.invulnerable_until_tick = 1000
	_fire_at(enemy.global_position)
	h.step(10)
	assert_signal_emitted(GameEvents, "rope_bounced")
	assert_false(_pulling())


func test_wall_behind_the_enemy_does_not_steal_the_hook() -> void:
	h.player.teleport(Vector2(1400, 930))
	enemy.teleport(Vector2(1840, 930))
	_fire_at(Vector2(1880, 930))
	assert_true(h.step_until(_pulling, 30), "the enemy in front of the wall is hit first")


func test_chain_pulling_within_one_second_is_impossible() -> void:
	_start_pull()
	assert_true(h.step_until(func() -> bool: return not _pulling(), 60))
	var ended := h.sim.tick
	# Pull again as soon as the rope cooldown allows, while the target is still immune.
	var retry := maxi(ended + 1, h.player.rope_cooldown_until_tick)
	h.step(retry - h.sim.tick - 1)
	_fire_at(enemy.global_position)
	h.step(15)
	assert_false(_pulling(), "no second pull")
	assert_signal_emitted(GameEvents, "rope_bounced")
	assert_lt(h.sim.tick - ended, SimIds.TICK_RATE, "all within 1 s")


func test_pull_then_melee_combo_on_a_moving_target() -> void:
	# A moving target: the enemy drifts sideways when the hook lands.
	enemy.velocity = Vector2(0, -300)
	_fire_at(enemy.global_position + Vector2(0, -40))
	assert_true(h.step_until(_pulling, 15))
	var pressed := false
	for i in 90:
		var dist := enemy.global_position.distance_to(h.player.global_position)
		if not pressed and dist < 150.0:
			h.input.at(h.sim.tick + 1).melee = true
			pressed = true
		h.step()
		if get_signal_emit_count(GameEvents, "hit_landed") > 0:
			break
	assert_signal_emit_count(GameEvents, "hit_landed", 1)
	var hit: Array = get_signal_parameters(GameEvents, "hit_landed")
	assert_true(hit[4], "signature combo")
	assert_gte(hit[2], 40.0, "combo damage")
	assert_gte(h.player.freeze_ticks, Melee.hitstop_ticks(hit[2], true, TuningDB.t) - 1, "combo hitstop")
