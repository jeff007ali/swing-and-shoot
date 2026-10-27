extends GutTest
## Phase 3 (§6.3): weapon spawning, drift, despawn, rope pickup, firing with auto-aim and recoil,
## shotgun spread, throwing empty guns, blades, disarm, parry, rope cutting, ramming, cling resistance,
## bots using weapons, and weapons surviving a state round trip.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const PLAYER_POS := Vector2(600, 930)

var h: MatchHarness
var enemy: Fighter
var events: Array = []
var _connected: Array = []
const RECORDED: Array[StringName] = [&"weapon_spawned", &"weapon_despawned", &"weapon_picked", &"weapon_dropped", &"weapon_fired", &"weapon_thrown", &"parried", &"rope_cut", &"rammed", &"hit_landed"]


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	h.player.teleport(PLAYER_POS)
	h.player.facing = Vector2.RIGHT
	events = []
	_connected.clear()
	for sig in RECORDED:
		var recorder := _recorder(sig)
		GameEvents.connect(sig, recorder)
		_connected.append([sig, recorder])


func after_each() -> void:
	for pair in _connected:
		GameEvents.disconnect(pair[0], pair[1])
	h.destroy()


## A listener that records this signal's name and arguments, whatever their count.
func _recorder(sig: StringName) -> Callable:
	return func(...args: Array) -> void: events.append([sig, args])


func _of(name: StringName) -> Array:
	return events.filter(func(ev: Array) -> bool: return ev[0] == name)


func _weapon(id: StringName) -> WeaponDef:
	return WeaponDef.load_by_id(id)


func _give(f: Fighter, id: StringName) -> WeaponItem:
	var item := h.sim.weapons.spawn(_weapon(id), f.global_position)
	h.sim.weapons.equip(f, item)
	return item


func _press(on_tick: int, what: String, aim: Vector2 = Vector2.ZERO) -> void:
	var cmd := h.input.at(on_tick)
	cmd.set(what, true)
	cmd.aim_dir = aim


# --- Spawning, drift, despawn -----------------------------------------------------------------

func test_spawner_fills_spawn_points_with_drifting_weapons() -> void:
	h.sim.weapons.spawning = true
	h.step(SimIds.ticks(TuningDB.t.weapon_spawn_interval) * 2)
	assert_gt(h.sim.weapons.items.size(), 0)
	assert_gt(_of(&"weapon_spawned").size(), 0)
	var item := h.sim.weapons.items[0]
	var speed := item.vel.length()
	assert_between(speed, TuningDB.t.weapon_drift_min - 0.01, TuningDB.t.weapon_drift_max + 0.01, "WPN-01 drift speed")
	assert_ne(item.spin, 0.0, "WPN-06 spins")


func test_unclaimed_weapon_despawns() -> void:
	var item := h.sim.weapons.spawn(_weapon(&"pistol"), Vector2(700, 520))
	h.step(SimIds.ticks(TuningDB.t.weapon_lifetime) - 2)
	assert_has(h.sim.weapons.items, item, "still there just before")
	h.step(3)
	assert_does_not_have(h.sim.weapons.items, item)
	assert_eq(_of(&"weapon_despawned").size(), 1, "WPN-03")


func test_drifting_weapon_bounces_off_walls() -> void:
	var item := h.sim.weapons.spawn(_weapon(&"pistol"), Vector2(1840, 600), Vector2(300, 0))
	h.step(30)
	assert_lt(item.vel.x, 0.0, "bounced back off the right wall")
	assert_lt(item.pos.x, 1880.0)


# --- Pickup ------------------------------------------------------------------------------------

func test_rope_fetches_and_equips_a_weapon() -> void:
	var item := h.sim.weapons.spawn(_weapon(&"pistol"), Vector2(900, 930))
	var cmd := h.input.at(1)
	cmd.rope_fire = true
	cmd.rope_target = item.pos
	assert_true(h.step_until(func() -> bool: return h.player.weapon_id == item.id, 60), "ROPE-02: pulled in and picked up")
	assert_eq(item.state, WeaponItem.State.HELD)
	assert_false(h.player.rope.is_attached(), "rope lets go")
	assert_eq(_of(&"weapon_picked").size(), 1)


func test_grabbing_a_second_weapon_drops_the_first() -> void:
	var pistol := _give(h.player, &"pistol")
	var shotgun := h.sim.weapons.spawn(_weapon(&"shotgun"), Vector2(900, 930))
	var cmd := h.input.at(1)
	cmd.rope_fire = true
	cmd.rope_target = shotgun.pos
	assert_true(h.step_until(func() -> bool: return h.player.weapon_id == shotgun.id, 60))
	assert_eq(pistol.state, WeaponItem.State.FLOATING, "the pistol was dropped")
	assert_gt(pistol.vel.length(), 0.0, "with a small push")


# --- Firing ------------------------------------------------------------------------------------

func test_pistol_shot_recoils_and_hits_the_enemy_ahead() -> void:
	var pistol := _give(h.player, &"pistol")
	enemy = h.add_enemy(Vector2(1000, 930))
	_press(1, "fire")
	h.step()
	assert_eq(pistol.ammo, _weapon(&"pistol").ammo - 1)
	assert_eq(h.sim.weapons.projectiles.size(), 1)
	assert_almost_eq(h.player.velocity.x, -_weapon(&"pistol").recoil_impulse * exp(-TuningDB.t.drag / 60.0), 1.0, "PHY-06 recoil")
	assert_true(h.step_until(func() -> bool: return enemy.hp < TuningDB.t.max_hp, 30), "bullet lands")
	assert_almost_eq(enemy.hp, TuningDB.t.max_hp - _weapon(&"pistol").projectile_damage, 0.01)


func test_auto_aim_turns_toward_an_enemy_inside_the_cone() -> void:
	_give(h.player, &"pistol")
	# 12.7 degrees off facing: inside the 30 degree cone.
	enemy = h.add_enemy(PLAYER_POS + Vector2(400, -90))
	_press(1, "fire")
	h.step()
	var dir := h.sim.weapons.projectiles[0].vel.normalized()
	assert_almost_eq(dir.angle(), (enemy.global_position - PLAYER_POS).angle(), 0.05, "CTL-05")


func test_no_auto_aim_outside_the_cone() -> void:
	_give(h.player, &"pistol")
	enemy = h.add_enemy(PLAYER_POS + Vector2(0, -300))
	_press(1, "fire")
	h.step()
	assert_almost_eq(h.sim.weapons.projectiles[0].vel.normalized().angle(), 0.0, 0.001, "straight ahead")


func test_shotgun_fires_a_spread_and_kicks_hard() -> void:
	var def := _weapon(&"shotgun")
	_give(h.player, &"shotgun")
	_press(1, "fire")
	h.step()
	var angles: Array = h.sim.weapons.projectiles.map(func(p: Projectile) -> float: return rad_to_deg(p.vel.angle()))
	assert_eq(angles.size(), def.projectile_count)
	assert_almost_eq(angles.max() - angles.min(), def.spread_deg, 0.5)
	assert_lt(h.player.velocity.x, -600.0, "a movement burst")


func test_recoil_pushes_a_clinging_shooter_off_the_wall() -> void:
	h.player.teleport(Vector2(200, 540))
	h.player.velocity = Vector2(-600, 0)
	assert_true(h.step_until(h.player.is_clinging, 30))
	_give(h.player, &"shotgun")
	h.player.facing = Vector2.LEFT
	_press(h.sim.tick + 1, "fire", Vector2.LEFT)
	h.step()
	assert_false(h.player.is_clinging())
	assert_gt(h.player.velocity.x, 500.0, "launched away from the wall")


func test_fire_cooldown() -> void:
	var pistol := _give(h.player, &"pistol")
	_press(1, "fire")
	_press(2, "fire")
	h.step(2)
	assert_eq(pistol.ammo, _weapon(&"pistol").ammo - 1, "second press inside the cooldown does nothing")


func test_empty_gun_is_thrown_and_hurts() -> void:
	var pistol := _give(h.player, &"pistol")
	pistol.ammo = 0
	enemy = h.add_enemy(Vector2(900, 930))
	_press(1, "fire")
	h.step()
	assert_eq(h.player.weapon_id, -1, "WPN-05: no longer held")
	assert_does_not_have(h.sim.weapons.items, pistol)
	assert_eq(h.sim.weapons.projectiles[0].kind, Projectile.Kind.THROWN)
	assert_true(h.step_until(func() -> bool: return enemy.hp < TuningDB.t.max_hp, 30))
	assert_gte(TuningDB.t.max_hp - enemy.hp, TuningDB.t.throw_damage_base)


# --- Blades, disarm, parry, cutting, ramming ---------------------------------------------------

func test_sword_hits_harder_and_reaches_further() -> void:
	_give(h.player, &"sword")
	var reach := TuningDB.t.melee_range + _weapon(&"sword").melee_range_bonus
	enemy = h.add_enemy(PLAYER_POS + Vector2(reach - 10.0, 0))
	_press(1, "fire")
	h.step(1 + TuningDB.t.melee_startup_ticks)
	assert_eq(_of(&"hit_landed").size(), 1, "fire swings the sword; reaches past plain melee range")
	var closing := h.player.velocity.x
	assert_almost_eq(_of(&"hit_landed")[0][1][2], Melee.damage(closing, false, TuningDB.t) * _weapon(&"sword").melee_damage_mult, 0.01)


func test_hard_hit_disarms() -> void:
	enemy = h.add_enemy(Vector2(680, 930))
	var pistol := _give(enemy, &"pistol")
	enemy.take_hit(h.sim.tick, h.player.fighter_id, 5.0, Vector2(TuningDB.t.disarm_knockback, 0), 0)
	assert_eq(enemy.weapon_id, -1, "HP-03")
	assert_eq(pistol.state, WeaponItem.State.FLOATING)


func test_soft_hit_does_not_disarm() -> void:
	enemy = h.add_enemy(Vector2(680, 930))
	var pistol := _give(enemy, &"pistol")
	enemy.take_hit(h.sim.tick, h.player.fighter_id, 5.0, Vector2(TuningDB.t.disarm_knockback - 100.0, 0), 0)
	assert_eq(enemy.weapon_id, pistol.id)


func test_timed_melee_parries_a_bullet_back_at_the_shooter() -> void:
	enemy = h.add_enemy(Vector2(1100, 930))
	enemy.facing = Vector2.LEFT
	_give(enemy, &"pistol")
	var shot := InputCommand.new()
	shot.fire = true
	shot.aim_dir = Vector2.LEFT
	var enemy_input := preload("res://tests/helpers/scripted_input.gd").new()
	enemy_input.commands[1] = shot
	h.sim.set_input_source(enemy.fighter_id, enemy_input)
	h.player.facing = Vector2.RIGHT
	# The bullet covers ~460 px in ~12 ticks: swing so the active frames meet it.
	_press(9, "melee")
	assert_true(h.step_until(func() -> bool: return _of(&"parried").size() > 0, 40), "MEL-04")
	assert_eq(h.player.hp, TuningDB.t.max_hp, "the parrier is unhurt")
	assert_true(h.step_until(func() -> bool: return enemy.hp < TuningDB.t.max_hp, 40), "the bullet flies back into the shooter")


func test_timed_melee_knocks_away_an_incoming_hook() -> void:
	enemy = h.add_enemy(Vector2(1000, 930))
	var cmd := InputCommand.new()
	cmd.rope_fire = true
	cmd.rope_target = PLAYER_POS
	var enemy_input := preload("res://tests/helpers/scripted_input.gd").new()
	enemy_input.commands[1] = cmd
	h.sim.set_input_source(enemy.fighter_id, enemy_input)
	_press(4, "melee")
	h.step(12)
	# The swing either knocks the hook away (parry) or cuts the rope just before it arrives.
	assert_eq(_of(&"parried").size() + _of(&"rope_cut").size(), 1, "CNT-02")
	assert_eq(h.player.pulled_by_id, -1, "not pulled")


func test_melee_cuts_a_rope_passing_through_its_arc() -> void:
	# The enemy hangs on a rope to the floor, out of the swing's auto-aim range; the rope passes
	# right in front of the player.
	h.player.teleport(Vector2(540, 900))
	h.player.facing = Vector2.RIGHT
	enemy = h.add_enemy(Vector2(600, 450))
	enemy.rope.fire(h.sim.tick, Vector2(600, 1040))
	assert_true(h.step_until(func() -> bool: return enemy.rope.is_attached(), 12))
	_press(h.sim.tick + 1, "melee", Vector2.ZERO)
	h.step(1 + TuningDB.t.melee_startup_ticks + 1)
	assert_eq(_of(&"rope_cut").size(), 1, "ROPE-14")
	assert_false(enemy.rope.is_attached())


func test_fast_fighters_ram() -> void:
	enemy = h.add_enemy(PLAYER_POS + Vector2(120, 0))
	h.player.velocity = Vector2(1300, 0)
	assert_true(h.step_until(func() -> bool: return _of(&"rammed").size() > 0, 10), "MEL-05")
	assert_lt(enemy.hp, TuningDB.t.max_hp)
	assert_gt(enemy.velocity.x, 500.0, "knocked away")
	assert_lt(h.player.velocity.x, 1300.0 * 0.5, "the rammer loses most of its speed")


func test_slow_contact_is_not_a_ram() -> void:
	enemy = h.add_enemy(PLAYER_POS + Vector2(120, 0))
	h.player.velocity = Vector2(500, 0)
	h.step(20)
	assert_eq(_of(&"rammed").size(), 0)


func test_clinging_target_resists_a_pull() -> void:
	enemy = h.add_enemy(Vector2(1000, 990))
	enemy.velocity = Vector2(0, 600)
	assert_true(h.step_until(enemy.is_clinging, 10), "enemy holds the floor")
	var cling_left := enemy.cling_ticks_left
	h.player.teleport(Vector2(600, 990))
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.rope_fire = true
	cmd.rope_target = enemy.global_position
	assert_true(h.step_until(func() -> bool: return enemy.pulled_by_id == h.player.fighter_id, 15))
	var held_at := enemy.global_position
	var drained := enemy.cling_ticks_left
	h.step(10)
	assert_true(enemy.is_clinging(), "CNT-01: holds on")
	assert_eq(enemy.global_position, held_at)
	assert_almost_eq(float(drained - enemy.cling_ticks_left), 10.0 * TuningDB.t.cling_pull_drain_mult, 1.0, "grip drains faster")
	assert_gt(h.player.velocity.x, 0.0, "the puller is dragged toward the target")
	assert_lt(cling_left, 100000)


# --- Bots, state -------------------------------------------------------------------------------

func test_bot_grabs_a_weapon_and_shoots() -> void:
	enemy = h.add_enemy(Vector2(1200, 930))
	h.sim.weapons.spawn(_weapon(&"pistol"), Vector2(1300, 930))
	h.make_bot(enemy, &"hard")
	assert_true(h.step_until(func() -> bool: return enemy.weapon_id >= 0, 240), "picks the pistol up")
	assert_true(h.step_until(func() -> bool: return _of(&"weapon_fired").any(func(ev: Array) -> bool: return ev[1][0] == enemy.fighter_id), 300), "and fires")


func test_weapons_and_projectiles_survive_a_state_round_trip() -> void:
	_give(h.player, &"shotgun")
	h.sim.weapons.spawn(_weapon(&"sword"), Vector2(1300, 600), Vector2(50, 20))
	_press(1, "fire")
	h.step(3)
	var snapshot := h.sim.get_state()
	h.step(10)
	var later := h.sim.get_state()
	h.sim.set_state(snapshot)
	h.step(10)
	assert_eq(str(h.sim.get_state()), str(later), "rewind and replay match with weapons in play")
