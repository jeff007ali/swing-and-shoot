extends GutTest
## Phase 6 (§6.6): the 14 new weapons, legendary spawns (WPN-04), projectile catch (ROPE-06), rope
## tug-of-war (ROPE-07), mutual clash (ROPE-15), thruster steering, special state round trips, and
## Co-op Survival (waves, benched enemies, the boss and its weak points, shared lives).

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
## A clear lane along the bottom of the Hangar.
const LANE_Y: float = 930.0

var h: MatchHarness
var events: Array = []
var _connected: Array = []
const RECORDED: Array[StringName] = [
	&"blast", &"laser_bounced", &"frozen", &"tethered", &"tether_smash", &"grenade_stuck", &"well_opened",
	&"mine_placed", &"mine_triggered", &"repulsed", &"boomerang_caught", &"wrecking_ball", &"rope_clash",
	&"rope_duel_started", &"rope_duel_ended", &"projectile_caught", &"projectile_whipped", &"shield_ripped",
	&"projectile_blocked", &"legendary_incoming", &"weapon_spawned", &"rope_cut", &"fighter_ko", &"wave_started",
	&"boss_hit", &"match_ended",
]


func before_each() -> void:
	TuningDB.reset_to_default()
	events = []
	_connected.clear()
	for sig in RECORDED:
		var recorder := _recorder(sig)
		GameEvents.connect(sig, recorder)
		_connected.append([sig, recorder])
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	h.player.teleport(Vector2(300, LANE_Y))
	h.player.facing = Vector2.RIGHT


func after_each() -> void:
	for pair in _connected:
		GameEvents.disconnect(pair[0], pair[1])
	if h != null:
		h.destroy()
	h = null


func _recorder(sig: StringName) -> Callable:
	return func(...args: Array) -> void: events.append([sig, args])


func _of(name: StringName) -> Array:
	return events.filter(func(ev: Array) -> bool: return ev[0] == name)


func _give(f: Fighter, id: StringName) -> WeaponItem:
	var item := h.sim.weapons.spawn(WeaponDef.load_by_id(id), f.global_position)
	h.sim.weapons.equip(f, item)
	return item


## An enemy whose rope holds a fighter clinging to the bottom wall below it: a rope line across the
## lane at x that stays put (the clinging target resists the pull, CNT-01).
func _rope_across_lane(x: float, top_y: float) -> Fighter:
	var anchor := h.add_enemy(Vector2(x, 1000))
	anchor.velocity = Vector2(0, 400)
	h.step_until(func() -> bool: return anchor.is_clinging(), 30)
	anchor.cling_ticks_left = 100000
	var puller := h.add_enemy(Vector2(x, top_y))
	puller.rope.pull_fighter(anchor, h.sim.tick)
	return puller


## Fires f's weapon now, aimed along dir.
func _shoot(f: Fighter, dir: Vector2) -> void:
	var cmd := InputCommand.new()
	cmd.fire = true
	cmd.aim_dir = dir
	f.fire_ready_tick = 0
	h.sim.weapons.fire(f, cmd, h.sim.tick)


func test_every_weapon_loads() -> void:
	var ids := WeaponDef.all().map(func(d: WeaponDef) -> StringName: return d.id)
	for id in [&"rocket", &"laser", &"boomerang", &"harpoon", &"freeze", &"magnet", &"sticky", &"gravity", &"black_hole_bomb", &"repulsor", &"tether_mine", &"tether_rope", &"shield", &"thruster"]:
		assert_has(ids, id)
		assert_eq(WeaponDef.load_by_id(id).kind, WeaponDef.Kind.SPECIAL, String(id))
	assert_eq(WeaponDef.all().filter(func(d: WeaponDef) -> bool: return d.legendary).size(), 1)
	assert_lt(WeaponDef.load_by_id(&"tether_rope").spawn_weight, 1.0, "tether rope is rare")


func test_rocket_explodes_with_splash_and_recoil() -> void:
	var enemy := h.add_enemy(Vector2(1000, LANE_Y))
	_give(h.player, &"rocket")
	_shoot(h.player, Vector2.RIGHT)
	assert_lt(h.player.velocity.x, -500.0, "big recoil")
	h.step_until(func() -> bool: return not _of(&"blast").is_empty(), 90)
	assert_eq(_of(&"blast").size(), 1)
	assert_lt(enemy.hp, TuningDB.t.max_hp)


func test_laser_ricochets() -> void:
	h.player.teleport(Vector2(300, 700))
	_give(h.player, &"laser")
	_shoot(h.player, Vector2(-1, 1).normalized())
	h.step(30)
	assert_gt(_of(&"laser_bounced").size(), 0)


func test_boomerang_goes_out_cuts_a_rope_and_comes_back() -> void:
	_rope_across_lane(800.0, 700.0)
	var item := _give(h.player, &"boomerang")
	_shoot(h.player, Vector2.RIGHT)
	assert_true(item.extra.get("out", false))
	var back := h.step_until(func() -> bool: return not _of(&"boomerang_caught").is_empty(), 240)
	assert_true(back, "returns to the thrower")
	assert_false(item.extra.get("out", false))
	assert_gt(_of(&"rope_cut").size(), 0, "cut the rope it crossed")


func test_harpoon_hauls_an_enemy_while_your_rope_holds() -> void:
	var enemy := h.add_enemy(Vector2(900, LANE_Y))
	h.player.rope.fire(h.sim.tick, Vector2(300, 1040))
	h.step(3)
	_give(h.player, &"harpoon")
	_shoot(h.player, Vector2.RIGHT)
	h.step_until(func() -> bool: return not _of(&"tethered").is_empty(), 30)
	var start := enemy.global_position.distance_to(h.player.global_position)
	h.step(20)
	assert_lt(enemy.global_position.distance_to(h.player.global_position), start - 100.0)


func test_freeze_makes_a_ropeable_wrecking_ball() -> void:
	var enemy := h.add_enemy(Vector2(900, LANE_Y))
	var third := h.add_enemy(Vector2(1500, LANE_Y))
	_give(h.player, &"freeze")
	_shoot(h.player, Vector2.RIGHT)
	h.step_until(func() -> bool: return not _of(&"frozen").is_empty(), 40)
	assert_true(enemy.is_frozen(h.sim.tick))
	enemy.pull_immune_until_tick = h.sim.tick + 600
	assert_true(enemy.can_be_pulled(h.sim.tick), "frozen fighters can always be roped")
	enemy.velocity = Vector2(1200, 0)
	h.step_until(func() -> bool: return not _of(&"wrecking_ball").is_empty(), 60)
	assert_lt(third.hp, TuningDB.t.max_hp, "the ball smashed into someone")


func test_magnet_drags_loose_weapons_in() -> void:
	var loose := h.sim.weapons.spawn(WeaponDef.load_by_id(&"pistol"), Vector2(800, LANE_Y))
	_give(h.player, &"magnet")
	_shoot(h.player, Vector2.RIGHT)
	var before := loose.pos.distance_to(h.player.global_position)
	h.step(20)
	assert_lt(loose.pos.distance_to(h.player.global_position), before - 50.0)


func test_sticky_grenade_sticks_and_blows() -> void:
	var enemy := h.add_enemy(Vector2(700, LANE_Y))
	_give(h.player, &"sticky")
	_shoot(h.player, Vector2.RIGHT)
	h.step_until(func() -> bool: return not _of(&"grenade_stuck").is_empty(), 60)
	assert_eq(_of(&"grenade_stuck").size(), 1)
	h.step_until(func() -> bool: return not _of(&"blast").is_empty(), 180)
	assert_lt(enemy.hp, TuningDB.t.max_hp)


func test_black_hole_bomb_swallows_whoever_reaches_its_core() -> void:
	var enemy := h.add_enemy(Vector2(1000, LANE_Y))
	_give(h.player, &"black_hole_bomb")
	_shoot(h.player, Vector2.RIGHT)
	h.step_until(func() -> bool: return not _of(&"well_opened").is_empty(), 90)
	var well: Dictionary = h.sim.special_weapons.wells[0]
	enemy.teleport(well["pos"] + Vector2(40, 0))
	h.step(2)
	assert_true(enemy.is_ko())
	var ko: Array = _of(&"fighter_ko").back()[1]
	assert_eq(ko[1], h.player.fighter_id, "credited to the bomber")
	assert_eq(ko[2], &"black_hole_bomb")


func test_gravity_well_pulls_without_killing() -> void:
	var enemy := h.add_enemy(Vector2(900, LANE_Y))
	_give(h.player, &"gravity")
	_shoot(h.player, Vector2.RIGHT)
	h.step_until(func() -> bool: return not _of(&"well_opened").is_empty(), 90)
	var at: Vector2 = h.sim.special_weapons.wells[0]["pos"]
	enemy.teleport(at + Vector2(250, 0))
	h.step(20)
	assert_lt(enemy.global_position.distance_to(at), 240.0)
	assert_false(enemy.is_ko())


func test_repulsor_pushes_away_and_breaks_a_pull() -> void:
	var enemy := h.add_enemy(Vector2(500, LANE_Y))
	enemy.rope.pull_fighter(h.player, h.sim.tick)
	assert_eq(h.player.pulled_by_id, enemy.fighter_id)
	_give(h.player, &"repulsor")
	_shoot(h.player, Vector2.RIGHT)
	h.step(1)
	assert_eq(_of(&"repulsed").size(), 1)
	assert_eq(h.player.pulled_by_id, -1, "the pull is broken")
	assert_gt(enemy.velocity.x, 500.0)


func test_tether_mine_ropes_an_enemy_that_drifts_close() -> void:
	_give(h.player, &"tether_mine")
	_shoot(h.player, Vector2.DOWN)
	h.step_until(func() -> bool: return not _of(&"mine_placed").is_empty(), 60)
	var mine: Dictionary = h.sim.special_weapons.mines[0]
	h.step(SimIds.ticks(SpecialWeapons.MINE_ARM) + 1)
	var enemy := h.add_enemy(mine["pos"] + Vector2(150, -100))
	h.step(3)
	assert_eq(_of(&"mine_triggered").size(), 1)
	h.step(40)
	assert_lt(enemy.global_position.distance_to(mine["pos"]), 100.0)


func test_tether_rope_smashes_two_enemies_together() -> void:
	var a := h.add_enemy(Vector2(800, LANE_Y))
	var b := h.add_enemy(Vector2(1300, LANE_Y - 200))
	_give(h.player, &"tether_rope")
	_shoot(h.player, Vector2.RIGHT)
	var smashed := h.step_until(func() -> bool: return not _of(&"tether_smash").is_empty(), 180)
	assert_true(smashed)
	assert_lt(a.hp, TuningDB.t.max_hp)
	assert_lt(b.hp, TuningDB.t.max_hp)


func test_shield_blocks_from_the_front_and_a_rope_rips_it_off() -> void:
	var enemy := h.add_enemy(Vector2(900, LANE_Y))
	enemy.facing = Vector2.LEFT
	_give(enemy, &"shield")
	_give(h.player, &"pistol")
	_shoot(h.player, Vector2.RIGHT)
	h.step(30)
	assert_eq(enemy.hp, TuningDB.t.max_hp, "blocked")
	assert_gt(_of(&"projectile_blocked").size(), 0)
	h.player.rope.fire(h.sim.tick, enemy.global_position)
	h.step_until(func() -> bool: return not _of(&"shield_ripped").is_empty(), 30)
	assert_eq(_of(&"shield_ripped").size(), 1)
	assert_eq(enemy.weapon_id, -1)
	assert_eq(h.player.rope.mode, SimIds.RopeMode.FETCH)


func test_thruster_steers_while_held_and_a_tap_still_ropes() -> void:
	_give(h.player, &"thruster")
	_shoot(h.player, Vector2.RIGHT)
	assert_true(h.sim.special_weapons.is_thrusting(h.player, h.sim.tick))
	h.player.velocity = Vector2.ZERO
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.steer = Vector2.UP
	h.step(1)
	assert_lt(h.player.velocity.y, -20.0)
	# The router: a long hold steers, a quick tap fires a rope on release.
	var router := TouchRouter.new()
	router.fighter = h.player
	add_child_autofree(router)
	router.build_command(h.sim.tick)
	router.touch_down(0, Vector2(800, 200))
	var held := InputCommand.new()
	for i in SimIds.ticks(TuningDB.t.hold_threshold) + 2:
		held = router.build_command(h.sim.tick + 1 + i)
	assert_ne(held.steer, Vector2.ZERO)
	assert_false(held.rope_fire)
	router.touch_up(0, Vector2(800, 200))
	router.touch_down(1, Vector2(800, 200))
	router.touch_up(1, Vector2(800, 200))
	h.player.rope_cooldown_until_tick = 0
	assert_true(router.build_command(h.sim.tick + 40).rope_fire, "a tap still ropes")


func test_legendary_is_announced_then_spawns_in_the_open() -> void:
	TuningDB.t.legendary_first_delay = 1.0
	TuningDB.t.legendary_countdown = 1.0
	h.sim.weapons.spawning = true
	h.sim.weapons.next_legendary_tick = h.sim.tick + 60
	h.sim.weapons.next_spawn_tick = 100000
	h.step(62)
	assert_eq(_of(&"legendary_incoming").size(), 1)
	var at: Vector2 = _of(&"legendary_incoming")[0][1][1]
	h.step(62)
	var spawned := _of(&"weapon_spawned").filter(func(e: Array) -> bool: return e[1][1] == &"black_hole_bomb")
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0][1][2], at)
	assert_gt(at.distance_to(Vector2(960, 600)), 150.0, "not inside the turbine")


func test_a_rope_catches_a_thrown_grenade_and_whips_it_back() -> void:
	var enemy := h.add_enemy(Vector2(1000, LANE_Y))
	_give(enemy, &"gravity")
	_shoot(enemy, Vector2.LEFT)
	h.step(5)
	var nade: Projectile = h.sim.weapons.projectiles[0]
	h.player.rope.fire(h.sim.tick, nade.pos)
	var caught := h.step_until(func() -> bool: return not _of(&"projectile_caught").is_empty(), 20)
	assert_true(caught)
	h.step_until(func() -> bool: return not _of(&"projectile_whipped").is_empty(), 60)
	assert_eq(nade.owner_id, h.player.fighter_id, "now the catcher's")
	assert_gt(nade.vel.x, 0.0, "flies back toward the thrower")


func test_crossing_an_enemy_rope_starts_a_tug_of_war() -> void:
	var enemy := _rope_across_lane(700.0, 600.0)
	assert_true(enemy.rope.is_attached())
	h.player.teleport(Vector2(300, 680))
	h.player.rope.fire(h.sim.tick, Vector2(1100, 680))
	var started := h.step_until(func() -> bool: return not _of(&"rope_duel_started").is_empty(), 20)
	assert_true(started)
	assert_eq(h.player.rope.mode, SimIds.RopeMode.DUEL)
	for i in 6:
		h.input.at(h.sim.tick + 1 + i * 3).rope_fire = true
	h.step(SimIds.ticks(SpecialWeapons.DUEL_TIME) + 2)
	var ended: Array = _of(&"rope_duel_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0][1][0], h.player.fighter_id, "more taps wins")
	assert_eq(h.player.rope.pull_target, enemy)


func test_two_fighters_roping_each_other_clash_in_the_middle() -> void:
	var enemy := h.add_enemy(Vector2(900, LANE_Y))
	h.player.rope.pull_fighter(enemy, h.sim.tick)
	enemy.rope.pull_fighter(h.player, h.sim.tick)
	var clashed := h.step_until(func() -> bool: return not _of(&"rope_clash").is_empty(), 60)
	assert_true(clashed)
	assert_false(h.player.rope.is_attached())
	assert_lt(h.player.velocity.x, 0.0)
	assert_gt(enemy.velocity.x, 0.0)


func test_special_state_round_trips() -> void:
	var enemy := h.add_enemy(Vector2(900, LANE_Y))
	_give(h.player, &"gravity")
	_shoot(h.player, Vector2.RIGHT)
	h.step_until(func() -> bool: return not _of(&"well_opened").is_empty(), 90)
	enemy.frozen_until = h.sim.tick + 100
	var saved := h.sim.get_state()
	h.step(400)
	assert_eq(h.sim.special_weapons.wells.size(), 0)
	h.sim.set_state(saved)
	assert_eq(h.sim.special_weapons.wells.size(), 1)
	assert_true(enemy.is_frozen(h.sim.tick))


# --- Co-op Survival --------------------------------------------------------------------------------

func _survival() -> SurvivalMode:
	h.destroy()
	h = MatchHarness.new()
	h.create(self, 1234, &"station", &"survival")
	await wait_physics_frames(2)
	return h.sim.mode as SurvivalMode


func test_survival_waves_bench_enemies_and_count_clears() -> void:
	var mode := await _survival()
	assert_eq(h.sim.fighters.size(), 2 + mode.def.enemy_slots)
	assert_true(mode.enemies().all(func(f: Fighter) -> bool: return f.is_ko()), "benched at the start")
	h.step(SimIds.ticks(SurvivalMode.FIRST_WAVE) + 1)
	assert_eq(mode.wave, 1)
	var alive := mode.enemies().filter(func(f: Fighter) -> bool: return not f.is_ko())
	assert_eq(alive.size(), 2)
	for f: Fighter in alive:
		f.take_hit(h.sim.tick, h.player.fighter_id, 999.0, Vector2.ZERO, 0)
	h.step(SimIds.ticks(TuningDB.t.respawn_time) + 5)
	assert_true(mode.enemies().all(func(f: Fighter) -> bool: return f.is_ko()), "KO'd enemies stay down")
	assert_eq(int(mode.scores[0]), 1)
	assert_eq(mode.score_text(0), "WAVE 1")


func test_survival_boss_only_hurts_at_weak_points() -> void:
	var mode := await _survival()
	mode.wave = SurvivalMode.BOSS_EVERY - 1
	mode.next_wave = h.sim.tick + 1
	h.step(2)
	assert_true(mode.boss_active)
	assert_true(mode.boss.active)
	assert_eq(_of(&"wave_started").back()[1], [SurvivalMode.BOSS_EVERY, true])
	var full := mode.boss_hp
	var center := mode.boss_pos
	var weak := mode.weak_points(h.sim.tick)[0]
	var armored := center + (weak - center).normalized().rotated(PI / 3.0) * BossBody.RADIUS
	assert_true(mode.on_object_hit(mode.boss, armored, 20.0, 0, h.sim.tick))
	assert_eq(mode.boss_hp, full, "armor")
	mode.on_object_hit(mode.boss, weak, 20.0, 0, h.sim.tick)
	assert_eq(mode.boss_hp, full - 20.0)
	mode.damage_boss(9999.0, weak)
	assert_false(mode.boss_active)


func test_survival_ends_when_the_lives_run_out() -> void:
	var mode := await _survival()
	mode.lives = 1
	h.player.take_hit(h.sim.tick, -1, 999.0, Vector2.ZERO, 0)
	h.step(1)
	assert_true(mode.ended)
	assert_eq(mode.winner, 1)


func test_bots_fight_with_the_whole_arsenal() -> void:
	h.destroy()
	h = MatchHarness.new()
	h.create(self, 99, &"station", &"ffa")
	await wait_physics_frames(2)
	h.make_bot(h.player, &"hard")
	h.sim.weapons.spawning = true
	TuningDB.t.weapon_spawn_interval = 1.0
	h.step(2400)
	assert_eq(h.sim.tick, 2400)
