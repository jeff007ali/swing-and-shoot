extends GutTest
## Phase 4 (§6.4): smooth and electric surfaces, wrap-around edges, vents with kill credit, fuel tanks,
## breakables, drifting asteroids, the black hole, Closing Walls, Debris Storm, the event scheduler,
## hazard state round trips, bots fleeing hazards, and every arena loading.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")

var h: MatchHarness
var events: Array = []
var _connected: Array = []
const RECORDED: Array[StringName] = [&"fighter_ko", &"shocked", &"tank_exploded", &"object_broken", &"object_restored", &"match_event", &"vent_changed"]


func before_each() -> void:
	TuningDB.reset_to_default()
	events = []
	_connected.clear()
	for sig in RECORDED:
		var recorder := _recorder(sig)
		GameEvents.connect(sig, recorder)
		_connected.append([sig, recorder])


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


func _arena(id: StringName, match_seed: int = 1234) -> void:
	h = MatchHarness.new()
	h.create(self, match_seed, id)
	await wait_physics_frames(2)


func test_every_arena_loads_and_runs() -> void:
	for id in ArenaRegistry.ids():
		await _arena(id)
		var arena := h.arena()
		assert_gt(arena.get_spawn_points().size(), 3, "%s spawns" % id)
		assert_gt(arena.get_bot_anchors().size(), 0, "%s anchors" % id)
		assert_true(arena.bounds.has_point(h.player.global_position), "%s player inside" % id)
		h.make_bot(h.player, &"hard")
		h.step(300)
		assert_eq(h.sim.tick, 300, "%s stepped" % id)
		h.destroy()
		h = null


func test_smooth_surface_bounces_instead_of_clinging() -> void:
	await _arena(&"interior")
	var panel := h.object_named("Box5")
	assert_eq(panel.surface_type, &"smooth")
	h.player.teleport(panel.global_position + Vector2(-160, 0))
	h.player.velocity = Vector2(900, 0)
	h.step(20)
	assert_ne(h.player.state, SimIds.FighterState.CLINGING)
	assert_lt(h.player.velocity.x, 0.0, "bounced back")


func test_electric_wall_shocks_and_throws_back() -> void:
	await _arena(&"derelict")
	h.player.teleport(Vector2(140, 1100))
	h.player.velocity = Vector2(-700, 0)
	h.step(20)
	assert_eq(_of(&"shocked").size(), 1)
	assert_lt(h.player.hp, TuningDB.t.max_hp)
	assert_gt(h.player.velocity.x, 0.0)
	assert_ne(h.player.state, SimIds.FighterState.CLINGING)


func test_wrap_edges_bring_fighters_back_on_the_other_side() -> void:
	await _arena(&"asteroids")
	h.player.teleport(Vector2(3560, 120))
	h.player.velocity = Vector2(900, 0)
	h.step(10)
	assert_lt(h.player.global_position.x, 400.0)
	assert_false(h.player.is_ko())
	h.player.teleport(Vector2(2000, 1980))
	h.player.velocity = Vector2(0, 900)
	h.step(10)
	assert_lt(h.player.global_position.y, 400.0)


func test_open_vent_sucks_a_fighter_out_and_credits_the_last_hitter() -> void:
	await _arena(&"interior")
	var enemy := h.add_enemy(Vector2(220, 900))
	enemy.take_hit(h.sim.tick, h.player.fighter_id, 1.0, Vector2.ZERO, 0)
	h.sim.hazards.start_event(&"vent_surge", h.sim.tick)
	var gone := h.step_until(func() -> bool: return enemy.is_ko(), 120)
	assert_true(gone, "sucked out")
	var ko := _of(&"fighter_ko")
	assert_eq(ko.size(), 1)
	assert_eq(ko[0][1][1], h.player.fighter_id, "kill credit")
	assert_eq(ko[0][1][2], &"vent")


func test_vent_cycles_warning_then_open_then_closed() -> void:
	await _arena(&"interior")
	var t := TuningDB.t
	var hz := h.sim.hazards
	var cycle := SimIds.ticks(t.vent_cycle)
	var states := {}
	for tick in cycle:
		states[hz.vent_state(0, tick)] = true
	assert_eq(states.size(), 3)
	var door: ArenaObject = hz.vents[0]["door"]
	assert_not_null(door)
	var open_tick := cycle - SimIds.ticks(t.vent_open)
	h.step(open_tick + 2)
	assert_eq(hz.vent_state(0, h.sim.tick), HazardSystem.VentState.OPEN)
	assert_false(door.active, "door open")
	h.step(SimIds.ticks(t.vent_open))
	assert_true(door.active, "door closed again")
	assert_gt(_of(&"vent_changed").size(), 1)


func test_shot_tank_explodes_hurts_nearby_fighters_and_respawns() -> void:
	await _arena(&"interior")
	var tank := h.object_named("Tank2")
	assert_true(tank.explosive)
	var enemy := h.add_enemy(tank.global_position + Vector2(-130, 0))
	h.sim.hazards.damage_object(tank, 100.0, h.player.fighter_id, h.sim.tick)
	h.step(1)
	assert_eq(_of(&"tank_exploded").size(), 1)
	assert_false(tank.active)
	assert_lt(enemy.hp, TuningDB.t.max_hp)
	assert_lt(enemy.velocity.x, 0.0, "blown away")
	assert_eq(enemy.last_hit_by_id, h.player.fighter_id)
	h.step(SimIds.ticks(TuningDB.t.tank_respawn) + 1)
	assert_true(tank.active, "respawned")
	assert_eq(_of(&"object_restored").size(), 1)


func test_bullets_break_breakables_and_drop_clingers() -> void:
	await _arena(&"interior")
	var crate := h.object_named("Box7")
	assert_gt(crate.max_hp, 0.0)
	var below := crate.global_position + Vector2(0, 260)
	h.player.teleport(below)
	var item := h.sim.weapons.spawn(WeaponDef.load_by_id(&"pistol"), below)
	h.sim.weapons.equip(h.player, item)
	var hp_before := crate.hp
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.fire = true
	cmd.aim_dir = Vector2.UP
	h.step(SimIds.ticks(0.5))
	assert_lt(crate.hp, hp_before, "a shot damages it")
	assert_true(crate.active)
	var clinger := h.add_enemy(crate.global_position + Vector2(-110, 0))
	clinger.velocity = Vector2(500, 0)
	h.step_until(func() -> bool: return clinger.is_clinging(), 30)
	assert_true(clinger.is_clinging())
	h.sim.hazards.damage_object(crate, 500.0, h.player.fighter_id, h.sim.tick)
	h.step(1)
	assert_false(crate.active)
	assert_eq(_of(&"object_broken").size(), 1)
	assert_false(clinger.is_clinging())


func test_drifting_asteroid_moves_and_shoves_fighters() -> void:
	await _arena(&"asteroids")
	var rock := h.object_named("Drifter1") as DriftingBody
	var start := rock.global_position
	h.step(60)
	assert_gt(rock.global_position.distance_to(start), 20.0, "it moves")
	var enemy := h.add_enemy(rock.global_position + Vector2(rock.pivot_radius() + TuningDB.t.fighter_radius - 6.0, 0))
	h.step(1)
	assert_lt(enemy.hp, TuningDB.t.max_hp)
	assert_gt(enemy.global_position.distance_to(rock.global_position), rock.pivot_radius() + TuningDB.t.fighter_radius - 1.0)


func test_black_hole_pulls_in_and_kos() -> void:
	await _arena(&"singularity")
	var hole: Vector2 = h.sim.hazards.black_holes[0]
	h.player.teleport(hole + Vector2(0, -170))
	var gone := h.step_until(func() -> bool: return h.player.is_ko(), 300)
	assert_true(gone)
	assert_eq(_of(&"fighter_ko")[0][1][2], &"black_hole")
	assert_gt(h.sim.hazards.black_hole_radius(SimIds.ticks(TuningDB.t.black_hole_growth_time)), h.sim.hazards.black_hole_radius(0))


func test_closing_walls_shrink_push_and_hurt() -> void:
	await _arena(&"interior")
	var hz := h.sim.hazards
	hz.start_event(&"closing_walls", h.sim.tick)
	h.step(SimIds.ticks(TuningDB.t.closing_walls_time * 0.7))
	var zone := hz.safe_zone(h.sim.tick)
	assert_lt(zone.size.x, hz.bounds.size.x * 0.6)
	h.player.teleport(Vector2(200, 200))
	h.player.velocity = Vector2.ZERO
	h.step(20)
	assert_lt(h.player.hp, TuningDB.t.max_hp)
	assert_gt(h.player.velocity.x, 0.0)
	h.step(SimIds.ticks(TuningDB.t.closing_walls_time))
	assert_eq(hz.event_id, &"")
	assert_eq(hz.safe_zone(h.sim.tick), hz.bounds)


func test_debris_storm_throws_rocks() -> void:
	await _arena(&"station")
	h.sim.hazards.start_event(&"debris_storm", h.sim.tick)
	h.step(60)
	var rocks := h.sim.weapons.projectiles.filter(func(p: Projectile) -> bool: return p.kind == Projectile.Kind.DEBRIS)
	assert_gt(rocks.size(), 0)


func test_events_are_scheduled_from_the_arena_list() -> void:
	TuningDB.t.event_first_delay = 1.0
	TuningDB.t.event_interval = 5.0
	await _arena(&"derelict")
	h.step(SimIds.ticks(1.0) + 2)
	var started := _of(&"match_event")
	assert_eq(started.size(), 1)
	assert_true(h.arena().events.has(started[0][1][0]))
	assert_true(started[0][1][1])


func test_hazard_state_round_trips() -> void:
	await _arena(&"interior")
	var hz := h.sim.hazards
	var tank := h.object_named("Tank1")
	hz.damage_object(tank, 100.0, -1, h.sim.tick)
	hz.start_event(&"closing_walls", h.sim.tick)
	h.step(30)
	var saved := h.sim.get_state()
	var pos := h.player.global_position
	h.step(SimIds.ticks(TuningDB.t.tank_respawn) + 5)
	assert_true(tank.active)
	h.sim.set_state(saved)
	assert_false(tank.active, "tank restored as broken")
	assert_eq(hz.event_id, &"closing_walls")
	assert_eq(h.player.global_position, pos)


func test_same_seed_hazard_match_replays_exactly() -> void:
	TuningDB.t.event_first_delay = 2.0
	TuningDB.t.event_interval = 6.0
	var finals: Array = []
	for run in 2:
		await _arena(&"derelict", 77)
		var enemy := h.add_enemy(Vector2(3100, 300))
		h.make_bot(h.player, &"hard")
		h.make_bot(enemy, &"normal")
		h.step(900)
		finals.append([h.player.global_position, enemy.global_position, h.player.hp, enemy.hp, h.sim.hazards.event_id])
		h.destroy()
		h = null
	assert_eq(finals[0], finals[1])


func test_bot_ropes_away_from_an_open_vent() -> void:
	await _arena(&"interior")
	var bot := h.make_bot(h.player, &"hard")
	h.player.teleport(Vector2(380, 760))
	h.player.velocity = Vector2.ZERO
	h.sim.hazards.start_event(&"vent_surge", h.sim.tick)
	var fled := h.step_until(func() -> bool: return bot.intent == &"escape_hazard", 30)
	assert_true(fled)
	assert_gt(bot.intent_point.x, h.player.global_position.x - 50.0, "away from the left vent")
