extends GutTest
## §4.14 / M4: damage and knockback formulas at closing speeds 0, 750 and 1500; the combo multiplier
## only within COMBO_WINDOW; one hit per victim per swing; hit arc; hitstop; hitstun; KO and respawn.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
## Open space along the bottom of the Hangar: no obstacles between x 100 and 1800 at this height.
const PLAYER_POS := Vector2(600, 930)

var h: MatchHarness
var enemy: Fighter


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	h.player.teleport(PLAYER_POS)
	enemy = h.add_enemy(PLAYER_POS + Vector2(80, 0))
	watch_signals(GameEvents)


func after_each() -> void:
	h.destroy()


func _press_melee(on_tick: int) -> void:
	h.input.at(on_tick).melee = true


func _last_hit() -> Array:
	return get_signal_parameters(GameEvents, "hit_landed")


# --- Formulas ---------------------------------------------------------------------------------

func test_damage_at_closing_speeds_0_750_1500() -> void:
	var t := TuningDB.t
	assert_almost_eq(Melee.damage(0.0, false, t), 8.0, 0.001, "still")
	assert_almost_eq(Melee.damage(750.0, false, t), 26.75, 0.001)
	assert_almost_eq(Melee.damage(1500.0, false, t), 45.0, 0.001, "capped at MELEE_MAX_DAMAGE")
	assert_almost_eq(Melee.damage(1500.0, true, t), 56.25, 0.001, "combo bonus after the cap")


func test_knockback_at_closing_speeds_0_750_1500() -> void:
	var t := TuningDB.t
	assert_almost_eq(Melee.knockback(0.0, t), 350.0, 0.001)
	assert_almost_eq(Melee.knockback(750.0, t), 1175.0, 0.001)
	assert_almost_eq(Melee.knockback(1500.0, t), 1700.0, 0.001, "capped at MELEE_KB_MAX")


func test_hitstop_table() -> void:
	var t := TuningDB.t
	assert_eq(Melee.hitstop_ticks(8.0, false, t), 4)
	assert_eq(Melee.hitstop_ticks(26.75, false, t), 6)
	assert_eq(Melee.hitstop_ticks(45.0, false, t), 8)
	assert_eq(Melee.hitstop_ticks(200.0, false, t), 9, "capped")
	assert_eq(Melee.hitstop_ticks(45.0, true, t), 11, "+3 for the combo")


# --- Hits in the sim --------------------------------------------------------------------------

func test_melee_hits_after_startup_with_lunge_closing_speed() -> void:
	_press_melee(1)
	h.step(1 + TuningDB.t.melee_startup_ticks - 1)
	assert_signal_not_emitted(GameEvents, "hit_landed", "nothing during startup")
	h.step()
	assert_signal_emit_count(GameEvents, "hit_landed", 1)
	var hit := _last_hit()
	assert_eq(hit[0], h.player.fighter_id)
	assert_eq(hit[1], enemy.fighter_id)
	# The attacker is frozen by hitstop, so its velocity is still the closing speed (the lunge).
	var closing := h.player.velocity.x
	assert_gt(closing, 100.0, "the lunge adds closing speed")
	assert_almost_eq(hit[2], Melee.damage(closing, false, TuningDB.t), 0.01)
	assert_false(hit[4], "no combo without a pull")
	assert_almost_eq(enemy.hp, TuningDB.t.max_hp - hit[2], 0.01)
	assert_eq(enemy.state, SimIds.FighterState.HITSTUN)
	assert_almost_eq(enemy.velocity.x, Melee.knockback(closing, TuningDB.t), 0.01, "knocked straight away")


func test_victim_flying_in_hits_harder() -> void:
	enemy.teleport(PLAYER_POS + Vector2(150, 0))
	enemy.velocity = Vector2(-1000, 0)
	_press_melee(1)
	h.step(6)
	assert_signal_emit_count(GameEvents, "hit_landed", 1)
	assert_gt(_last_hit()[2], 30.0, "closing speed counts the victim's speed too")


func test_one_hit_per_victim_per_swing() -> void:
	_press_melee(1)
	h.step(40)
	assert_signal_emit_count(GameEvents, "hit_landed", 1)


func test_victim_behind_the_swing_is_not_hit() -> void:
	# Out of autoaim range at the press, so the swing aims along the player's movement (right),
	# then the enemy flies in from behind during the active ticks.
	h.player.velocity = Vector2(300, 0)
	enemy.teleport(PLAYER_POS + Vector2(-190, 0))
	# Slow enough not to count as a ram (MEL-05), fast enough to arrive during the active ticks.
	enemy.velocity = Vector2(1100, 0)
	_press_melee(1)
	h.step(12)
	assert_signal_not_emitted(GameEvents, "hit_landed")


func test_hitstop_freezes_attacker_and_victim_only() -> void:
	_press_melee(1)
	h.step(1 + TuningDB.t.melee_startup_ticks)
	var stop := Melee.hitstop_ticks(_last_hit()[2], false, TuningDB.t)
	assert_eq(h.player.freeze_ticks, stop)
	assert_eq(enemy.freeze_ticks, stop)
	var enemy_pos := enemy.global_position
	h.step(stop - 1)
	assert_eq(enemy.global_position, enemy_pos, "frozen victim does not move")
	h.step(2)
	assert_ne(enemy.global_position, enemy_pos, "moves once the freeze is over")


func test_hitstun_ends_after_its_time() -> void:
	_press_melee(1)
	h.step(1 + TuningDB.t.melee_startup_ticks)
	assert_eq(enemy.state, SimIds.FighterState.HITSTUN)
	assert_true(h.step_until(func() -> bool: return enemy.state != SimIds.FighterState.HITSTUN, 60))
	assert_eq(enemy.state, SimIds.FighterState.FREE)


func test_combo_multiplier_within_the_window() -> void:
	enemy.last_pulled_by_id = h.player.fighter_id
	enemy.last_pulled_tick = 0
	_press_melee(1)
	h.step(1 + TuningDB.t.melee_startup_ticks)
	assert_true(_last_hit()[4], "pulled 3 ticks ago: combo")
	var closing := h.player.velocity.x
	assert_almost_eq(_last_hit()[2], Melee.damage(closing, true, TuningDB.t), 0.01)


func test_no_combo_outside_the_window() -> void:
	enemy.last_pulled_by_id = h.player.fighter_id
	enemy.last_pulled_tick = -SimIds.ticks(TuningDB.t.combo_window)
	_press_melee(1)
	h.step(1 + TuningDB.t.melee_startup_ticks)
	assert_false(_last_hit()[4], "pulled longer ago than COMBO_WINDOW")


func test_no_combo_when_someone_else_pulled() -> void:
	enemy.last_pulled_by_id = 7
	enemy.last_pulled_tick = 0
	_press_melee(1)
	h.step(1 + TuningDB.t.melee_startup_ticks)
	assert_false(_last_hit()[4])


func test_melee_cooldown() -> void:
	_press_melee(1)
	_press_melee(5)
	h.step(5)
	assert_eq(h.player.melee_start_tick, 1, "second press inside MELEE_COOLDOWN is ignored")
	var ready := 1 + SimIds.ticks(TuningDB.t.melee_cooldown)
	_press_melee(ready)
	h.step(ready - 5)
	assert_eq(h.player.melee_start_tick, ready)


# --- KO and respawn ---------------------------------------------------------------------------

func test_ko_then_respawn_far_from_the_enemy_with_invulnerability() -> void:
	enemy.hp = 5.0
	_press_melee(1)
	h.step(1 + TuningDB.t.melee_startup_ticks)
	assert_eq(enemy.state, SimIds.FighterState.KO)
	assert_signal_emitted_with_parameters(GameEvents, "fighter_ko", [enemy.fighter_id, h.player.fighter_id, &"melee", -1])
	h.step(SimIds.ticks(TuningDB.t.respawn_time) - 1)
	assert_eq(enemy.state, SimIds.FighterState.KO, "still out")
	h.step()
	assert_eq(enemy.state, SimIds.FighterState.FREE)
	assert_signal_emitted(GameEvents, "fighter_respawned")
	assert_eq(enemy.hp, TuningDB.t.max_hp)
	assert_eq(enemy.global_position, Vector2(1770, 150), "the spawn point farthest from the player")
	assert_true(enemy.is_invulnerable(h.sim.tick))


func test_invulnerable_fighters_cannot_be_hit() -> void:
	enemy.invulnerable_until_tick = 100
	_press_melee(1)
	h.step(10)
	assert_signal_not_emitted(GameEvents, "hit_landed")
