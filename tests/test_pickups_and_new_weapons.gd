extends GutTest
## Consumable pickups (health, armor, haste, power), the sniper, the proximity mine, the cone
## repulsor and the 2v2 teammate rope.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
## A clear lane along the bottom of the Hangar.
const LANE_Y: float = 930.0

var h: MatchHarness
var events: Array = []


func before_each() -> void:
	TuningDB.reset_to_default()
	events = []
	GameEvents.consumable_used.connect(_on_consumable)
	GameEvents.mine_triggered.connect(_on_mine)
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	h.player.teleport(Vector2(300, LANE_Y))
	h.player.facing = Vector2.RIGHT


func after_each() -> void:
	GameEvents.consumable_used.disconnect(_on_consumable)
	GameEvents.mine_triggered.disconnect(_on_mine)
	h.destroy()


func _on_consumable(id: int, def_id: StringName, _at: Vector2) -> void:
	events.append([&"consumable", id, def_id])


func _on_mine(id: int, _at: Vector2) -> void:
	events.append([&"mine", id])


func _give(f: Fighter, id: StringName) -> WeaponItem:
	var item := h.sim.weapons.spawn(WeaponDef.load_by_id(id), f.global_position)
	h.sim.weapons.equip(f, item)
	return item


func _shoot(f: Fighter, dir: Vector2) -> void:
	var cmd := InputCommand.new()
	cmd.fire = true
	cmd.aim_dir = dir
	f.fire_ready_tick = 0
	h.sim.weapons.fire(f, cmd, h.sim.tick)


# --- Consumables --------------------------------------------------------------------------------

func test_every_pickup_loads_as_a_consumable() -> void:
	for id: StringName in [&"health", &"armor", &"haste", &"power"]:
		var def := WeaponDef.load_by_id(id)
		assert_not_null(def, String(id))
		assert_eq(def.kind, WeaponDef.Kind.CONSUMABLE, String(id))
		assert_gt(def.spawn_weight, 0.0, String(id))


func test_flying_through_a_med_kit_heals_up_to_full() -> void:
	h.player.hp = 30.0
	h.sim.weapons.spawn(WeaponDef.load_by_id(&"health"), h.player.global_position + Vector2(200, 0))
	h.player.velocity = Vector2(900, 0)
	assert_true(h.step_until(func() -> bool: return not events.is_empty(), 30), "picked up by touch")
	assert_eq(events[0], [&"consumable", h.player.fighter_id, &"health"])
	assert_almost_eq(h.player.hp, 70.0, 0.01)
	assert_eq(h.player.weapon_id, -1, "never held")
	assert_true(h.sim.weapons.items.is_empty(), "used up")
	h.player.hp = 90.0
	h.sim.weapons.consume(h.player, h.sim.weapons.spawn(WeaponDef.load_by_id(&"health"), h.player.global_position))
	assert_eq(h.player.hp, TuningDB.t.max_hp, "capped at max HP")


func test_roping_a_pickup_uses_it_and_keeps_the_held_weapon() -> void:
	var gun := _give(h.player, &"pistol")
	h.sim.weapons.spawn(WeaponDef.load_by_id(&"armor"), h.player.global_position + Vector2(400, 0))
	h.input.at(h.sim.tick + 1).rope_fire = true
	h.input.at(h.sim.tick + 1).rope_target = h.player.global_position + Vector2(400, 0)
	assert_true(h.step_until(func() -> bool: return not events.is_empty(), 60), "fetched and used")
	assert_gt(h.player.armor, 0.0)
	assert_eq(h.player.weapon_id, gun.id, "still holding the pistol")


func test_armor_soaks_damage_before_hp() -> void:
	h.sim.weapons.consume(h.player, h.sim.weapons.spawn(WeaponDef.load_by_id(&"armor"), h.player.global_position))
	var armor := h.player.armor
	assert_almost_eq(armor, 35.0, 0.01)
	h.player.take_hit(h.sim.tick, -1, 20.0, Vector2.ZERO, 0, &"shot")
	assert_almost_eq(h.player.armor, armor - 20.0, 0.01)
	assert_eq(h.player.hp, TuningDB.t.max_hp, "HP untouched while armor lasts")
	h.player.take_hit(h.sim.tick, -1, 25.0, Vector2.ZERO, 0, &"shot")
	assert_eq(h.player.armor, 0.0)
	assert_almost_eq(h.player.hp, TuningDB.t.max_hp - 10.0, 0.01, "the rest goes to HP")


func test_power_multiplies_damage_dealt() -> void:
	var enemy := h.add_enemy(Vector2(800, LANE_Y))
	h.sim.weapons.consume(h.player, h.sim.weapons.spawn(WeaponDef.load_by_id(&"power"), h.player.global_position))
	assert_true(h.player.is_powered(h.sim.tick))
	enemy.take_hit(h.sim.tick, h.player.fighter_id, 10.0, Vector2.ZERO, 0, &"shot")
	assert_almost_eq(enemy.hp, TuningDB.t.max_hp - 10.0 * TuningDB.t.power_mult, 0.01)
	h.step(SimIds.ticks(WeaponDef.load_by_id(&"power").effect_time) + 1)
	assert_false(h.player.is_powered(h.sim.tick), "wears off")


func test_haste_speeds_up_kicks_and_reels() -> void:
	var t := TuningDB.t
	h.player.teleport(Vector2(200, 540))
	h.player.velocity = Vector2(-600, 0)
	assert_true(h.step_until(h.player.is_clinging, 60), "reaches the wall")
	h.sim.weapons.consume(h.player, h.sim.weapons.spawn(WeaponDef.load_by_id(&"haste"), Vector2(900, 540)))
	h.input.at(h.sim.tick + 1).kick = true
	h.input.at(h.sim.tick + 1).kick_dir = Vector2.RIGHT
	h.step()
	assert_almost_eq(h.player.velocity.length(), t.kick_speed * t.haste_mult * exp(-t.drag / 60.0), 1.0)


func test_respawn_clears_pickups() -> void:
	h.player.armor = 30.0
	h.player.haste_until = h.sim.tick + 600
	h.player.power_until = h.sim.tick + 600
	h.player.respawn_at(Vector2(300, LANE_Y), h.sim.tick)
	assert_eq(h.player.armor, 0.0)
	assert_false(h.player.is_hasted(h.sim.tick))
	assert_false(h.player.is_powered(h.sim.tick))


func test_narrowed_modes_still_spawn_pickups() -> void:
	h.sim.weapons.allowed = [&"pistol"]
	var picked := {}
	for i in 200:
		var def := h.sim.weapons._pick_def()
		picked[def.id] = true
	assert_true(picked.has(&"pistol"))
	assert_true(picked.has(&"health"), "pickups aren't narrowed away")
	assert_false(picked.has(&"shotgun"))


func test_pickups_survive_a_state_round_trip() -> void:
	h.player.armor = 22.0
	h.player.haste_until = 500
	h.player.power_until = 600
	var s := h.player.get_state()
	h.player.armor = 0.0
	h.player.haste_until = 0
	h.player.power_until = 0
	h.player.set_state(s)
	assert_eq(h.player.armor, 22.0)
	assert_eq(h.player.haste_until, 500)
	assert_eq(h.player.power_until, 600)


# --- Sniper -------------------------------------------------------------------------------------

func test_sniper_is_a_slow_firing_long_range_gun() -> void:
	var sniper := WeaponDef.load_by_id(&"sniper")
	var pistol := WeaponDef.load_by_id(&"pistol")
	assert_eq(sniper.kind, WeaponDef.Kind.GUN)
	assert_gt(sniper.projectile_speed * sniper.projectile_lifetime, 3000.0, "crosses the arena")
	assert_lt(sniper.projectile_damage, TuningDB.t.max_hp * 0.5, "no one-shot kills")
	assert_gt(sniper.fire_cooldown, pistol.fire_cooldown * 4.0)


func test_sniper_hits_across_the_arena() -> void:
	var enemy := h.add_enemy(Vector2(1700, LANE_Y))
	_give(h.player, &"sniper")
	_shoot(h.player, Vector2.RIGHT)
	assert_true(h.step_until(func() -> bool: return enemy.hp < TuningDB.t.max_hp, 30), "hits")
	assert_almost_eq(enemy.hp, TuningDB.t.max_hp - WeaponDef.load_by_id(&"sniper").projectile_damage, 0.01)


# --- Proximity mine -----------------------------------------------------------------------------

func _place_mine() -> Dictionary:
	_give(h.player, &"prox_mine")
	_shoot(h.player, Vector2.DOWN)
	h.step_until(func() -> bool: return not h.sim.special_weapons.mines.is_empty(), 60)
	return h.sim.special_weapons.mines[0]


func test_prox_mine_blows_up_an_enemy_that_comes_close() -> void:
	var mine := _place_mine()
	assert_eq(mine["kind"], &"prox_mine")
	h.step(SimIds.ticks(SpecialWeapons.PROX_MINE_ARM) + 1)
	var enemy := h.add_enemy(mine["pos"] + Vector2(90, -40))
	h.step(2)
	assert_eq(events.filter(func(e: Array) -> bool: return e[0] == &"mine").size(), 1, "triggered")
	assert_lt(enemy.hp, TuningDB.t.max_hp - 10.0, "hurt by the blast")
	assert_true(h.sim.special_weapons.mines.is_empty(), "gone")


func test_prox_mine_ignores_its_owner_and_waits_to_arm() -> void:
	var mine := _place_mine()
	var enemy := h.add_enemy(mine["pos"] + Vector2(90, -40))
	h.step(2)
	assert_eq(enemy.hp, TuningDB.t.max_hp, "not armed yet")
	enemy.teleport(Vector2(1600, 300))
	h.player.teleport(mine["pos"] + Vector2(-60, -40))
	h.step(SimIds.ticks(SpecialWeapons.PROX_MINE_ARM) + 5)
	assert_eq(h.sim.special_weapons.mines.size(), 1, "the owner can't set it off")


# --- Repulsor -----------------------------------------------------------------------------------

func test_repulsor_blasts_the_cone_ahead_hard_enough_to_disarm() -> void:
	var ahead := h.add_enemy(Vector2(700, LANE_Y))
	_give(ahead, &"pistol")
	var behind := h.add_enemy(Vector2(100, LANE_Y))
	_give(h.player, &"repulsor")
	_shoot(h.player, Vector2.RIGHT)
	assert_gt(ahead.velocity.x, TuningDB.t.disarm_knockback * 0.9, "slammed away")
	assert_eq(ahead.weapon_id, -1, "disarmed")
	assert_lt(ahead.hp, TuningDB.t.max_hp)
	assert_eq(behind.hp, TuningDB.t.max_hp, "behind the user: untouched")
	assert_lt(h.player.velocity.x, -300.0, "kicks the user backward")


# --- 2v2 teammate rope --------------------------------------------------------------------------

func test_roping_a_teammate_brings_both_together() -> void:
	var mate := h.add_enemy(Vector2(900, LANE_Y))
	h.sim.teams = {h.player.fighter_id: 0, mate.fighter_id: 0}
	h.player.rope.pull_fighter(mate, h.sim.tick)
	var start := h.player.global_position.x
	h.step(10)
	assert_gt(h.player.global_position.x, start + 20.0, "the puller flies toward the teammate")
	assert_lt(mate.global_position.x, 900.0 - 20.0, "and the teammate toward the puller")
