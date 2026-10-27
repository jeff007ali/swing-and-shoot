extends GutTest
## Phase 5 (§6.5): mode definitions, KO scoring and limits (Free-for-all), teams (no friendly fire,
## teammate throws, no credit for teammates), King of the Swing, Hot Potato, Gun Game, mode state in
## snapshots, full bot matches in every mode, the end of a match (results screen, saved result) and
## the menu's mode picker.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const RESULTS_FILE: String = "user://test_match_results.json"

var h: MatchHarness
var events: Array = []
var _connected: Array = []
const RECORDED: Array[StringName] = [&"match_ended", &"bomb_passed", &"bomb_exploded", &"level_up", &"teammate_thrown", &"fighter_ko", &"hit_landed"]


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
	get_tree().paused = false


func _recorder(sig: StringName) -> Callable:
	return func(...args: Array) -> void: events.append([sig, args])


func _of(name: StringName) -> Array:
	return events.filter(func(ev: Array) -> bool: return ev[0] == name)


func _match(arena: StringName = &"hangar", mode: StringName = &"free_fly") -> void:
	h = MatchHarness.new()
	h.create(self, 1234, arena, mode)
	await wait_physics_frames(2)


func _ko(victim: Fighter, killer: Fighter, cause: StringName = &"melee") -> void:
	victim.take_hit(h.sim.tick, killer.fighter_id if killer != null else -1, 999.0, Vector2.ZERO, 0, cause)


func _def(id: StringName) -> ModeDef:
	return ModeDef.load_by_id(id).duplicate()


func test_every_mode_definition_loads() -> void:
	var ids := ModeDef.all().map(func(d: ModeDef) -> StringName: return d.id)
	for id in [&"free_fly", &"vs_bot", &"ffa", &"teams", &"koth", &"hot_potato", &"gun_game"]:
		assert_has(ids, id)
	assert_eq(ModeDef.load_by_id(&"teams").team_count, 2)
	assert_gt(ModeDef.load_by_id(&"gun_game").weapon_sequence.size(), 2)


func test_ffa_scores_kos_and_ends_at_the_target() -> void:
	await _match()
	var a := h.add_enemy(Vector2(900, 300))
	var b := h.add_enemy(Vector2(1300, 300))
	var d := _def(&"ffa")
	d.score_target = 2
	var mode := h.use_mode(d)
	_ko(a, h.player)
	h.step(1)
	assert_eq(mode.scores[h.player.fighter_id], 1)
	_ko(b, b)
	h.step(1)
	assert_eq(mode.scores[b.fighter_id], 0, "self-KO scores nothing")
	h.step(SimIds.ticks(TuningDB.t.respawn_time) + 2)
	_ko(a, h.player)
	h.step(1)
	assert_true(mode.ended)
	assert_eq(_of(&"match_ended").size(), 1)
	assert_eq(mode.winner, h.player.fighter_id)
	assert_eq(mode.ranking()[0], h.player.fighter_id)


func test_time_limit_ends_in_a_draw_when_tied() -> void:
	await _match()
	h.add_enemy(Vector2(900, 300))
	var d := _def(&"ffa")
	d.time_limit = 1.0
	var mode := h.use_mode(d)
	h.step(SimIds.ticks(1.0) - 1)
	assert_false(mode.ended)
	h.step(2)
	assert_true(mode.ended)
	assert_eq(mode.winner, -1)


func test_teams_alternate_and_score_together() -> void:
	await _match()
	var foe := h.add_enemy(Vector2(900, 300))
	var ally := h.add_enemy(Vector2(1300, 300))
	var foe2 := h.add_enemy(Vector2(1300, 700))
	var mode := h.use_mode(&"teams")
	assert_eq(h.sim.teams, {0: 0, 1: 1, 2: 0, 3: 1})
	assert_false(h.sim.are_enemies(h.player, ally))
	assert_true(h.sim.are_enemies(h.player, foe))
	_ko(foe, ally)
	_ko(foe2, h.player)
	h.step(1)
	assert_eq(mode.scores[0], 2)
	assert_eq(mode.score_text(0), "2")
	assert_eq(mode.key_name(1), "RED")


func test_no_friendly_fire_and_a_punch_throws_a_teammate() -> void:
	await _match()
	h.add_enemy(Vector2(1500, 300))
	var ally := h.add_enemy(h.player.global_position + Vector2(150, 0))
	h.add_enemy(Vector2(1500, 700))
	h.use_mode(&"teams")
	assert_false(h.sim.are_enemies(h.player, ally))
	h.player.facing = Vector2.RIGHT
	var item := h.sim.weapons.spawn(WeaponDef.load_by_id(&"pistol"), h.player.global_position)
	h.sim.weapons.equip(h.player, item)
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.fire = true
	cmd.aim_dir = Vector2.RIGHT
	h.step(10)
	assert_eq(ally.hp, TuningDB.t.max_hp, "bullets pass teammates")
	ally.teleport(h.player.global_position + Vector2(60, 0))
	# The recoil pushed the player back: stand still, facing the teammate.
	h.player.velocity = Vector2.ZERO
	h.player.facing = Vector2.RIGHT
	h.input.at(h.sim.tick + 1).melee = true
	h.step(TuningDB.t.melee_startup_ticks + TuningDB.t.melee_active_ticks + 2)
	assert_eq(_of(&"teammate_thrown").size(), 1)
	assert_eq(ally.hp, TuningDB.t.max_hp, "a throw does no damage")
	assert_gt(ally.velocity.length(), TuningDB.t.team_throw_speed * 0.5)
	assert_eq(_of(&"hit_landed").size(), 0)


func test_teammate_pull_into_a_hazard_gives_no_point() -> void:
	await _match()
	var foe := h.add_enemy(Vector2(1500, 300))
	var ally := h.add_enemy(Vector2(1300, 300))
	h.add_enemy(Vector2(1500, 700))
	var mode := h.use_mode(&"teams")
	ally.last_pulled_by_id = h.player.fighter_id
	ally.last_pulled_tick = h.sim.tick
	ally.hazard_ko(h.sim.tick, &"vent")
	h.step(1)
	assert_eq(mode.scores[0], 0)
	assert_eq(mode.scores[1], 0)
	assert_false(foe.is_ko())


func test_king_of_the_swing_scores_only_an_uncontested_zone() -> void:
	await _match()
	var enemy := h.add_enemy(Vector2(200, 200))
	var mode := h.use_mode(&"koth") as KingOfTheSwing
	for i in 60:
		h.player.teleport(mode.zone_center(h.sim.tick + 1))
		h.step(1)
	assert_eq(mode.score_text(h.player.fighter_id), "1")
	assert_eq(mode.holder, h.player.fighter_id)
	for i in 30:
		var c := mode.zone_center(h.sim.tick + 1)
		h.player.teleport(c)
		enemy.teleport(c + Vector2(60, 0))
		h.step(1)
	assert_true(mode.contested)
	assert_eq(int(mode.scores[h.player.fighter_id]), 60, "no points while contested")
	assert_eq(int(mode.scores[enemy.fighter_id]), 0)
	assert_ne(mode.zone_center(0), mode.zone_center(600), "the zone moves")
	assert_ne(mode.bot_goal(enemy, h.sim.tick), Vector2.INF)


func test_hot_potato_passes_on_contact_and_blows_up() -> void:
	await _match()
	var enemy := h.add_enemy(h.player.global_position + Vector2(60, 0))
	var third := h.add_enemy(Vector2(1500, 300))
	var d := _def(&"hot_potato")
	d.fuse_min = 2.0
	d.fuse_max = 2.0
	var mode := h.use_mode(d) as HotPotato
	assert_eq(mode.holder_id, -1)
	h.step(SimIds.ticks(HotPotato.FIRST_BOMB) + 1)
	assert_gte(mode.holder_id, 0)
	# Hand it to the player, then punch the enemy to pass it.
	mode.holder_id = h.player.fighter_id
	mode.pass_ready = h.sim.tick
	mode.fuse_end = h.sim.tick + SimIds.ticks(2.0)
	h.player.facing = Vector2.RIGHT
	h.input.at(h.sim.tick + 1).melee = true
	h.step(TuningDB.t.melee_startup_ticks + TuningDB.t.melee_active_ticks + 2)
	assert_eq(mode.holder_id, enemy.fighter_id, "passed by the punch")
	assert_eq(_of(&"bomb_passed").back()[1], [h.player.fighter_id, enemy.fighter_id])
	var gone := h.step_until(func() -> bool: return enemy.is_ko(), SimIds.ticks(2.5))
	assert_true(gone, "the fuse ran out")
	assert_eq(_of(&"bomb_exploded").size(), 1)
	assert_eq(_of(&"fighter_ko").back()[1][2], &"bomb")
	assert_eq(int(mode.scores[h.player.fighter_id]), 1)
	assert_eq(int(mode.scores[third.fighter_id]), 1)
	assert_eq(int(mode.scores[enemy.fighter_id]), 0)
	assert_eq(mode.holder_id, -1)


func test_gun_game_moves_up_the_sequence_and_ends_on_a_melee_ko() -> void:
	await _match()
	var enemy := h.add_enemy(Vector2(1500, 300))
	var mode := h.use_mode(&"gun_game") as GunGame
	var seq := mode.def.weapon_sequence
	h.step(1)
	assert_eq(h.sim.weapons.held_by(h.player).def.id, seq[0])
	assert_eq(h.sim.weapons.held_by(enemy).def.id, seq[0])
	for level in seq.size():
		_ko(enemy, h.player, &"bullet")
		h.step(1)
		assert_eq(int(mode.levels[h.player.fighter_id]), level + 1)
		enemy.respawn_at(Vector2(1500, 300), h.sim.tick)
		h.step(1)
	assert_null(h.sim.weapons.held_by(h.player), "unarmed at the final level")
	assert_eq(mode.weapon_for(h.player), &"")
	_ko(enemy, h.player, &"bullet")
	h.step(1)
	assert_false(mode.ended, "the final KO must be melee")
	enemy.respawn_at(Vector2(1500, 300), h.sim.tick)
	_ko(enemy, h.player, &"melee")
	h.step(1)
	assert_true(mode.ended)
	assert_eq(mode.winner, h.player.fighter_id)
	assert_eq(mode.score_text(h.player.fighter_id), "%d/%d" % [seq.size() + 1, seq.size() + 1])


func test_mode_state_round_trips() -> void:
	await _match()
	h.add_enemy(Vector2(1500, 300))
	h.add_enemy(Vector2(1500, 700))
	var mode := h.use_mode(&"hot_potato") as HotPotato
	h.step(SimIds.ticks(HotPotato.FIRST_BOMB) + 5)
	var saved := h.sim.get_state()
	var holder := mode.holder_id
	h.step(SimIds.ticks(30.0))
	h.sim.set_state(saved)
	assert_eq(mode.holder_id, holder)
	assert_false(mode.ended)


func test_every_party_mode_runs_with_bots() -> void:
	for id in [&"ffa", &"teams", &"koth", &"hot_potato", &"gun_game"]:
		await _match(&"station", id)
		assert_eq(h.sim.fighters.size(), 4, "%s fighters" % id)
		assert_eq(h.sim.mode.def.id, id)
		h.make_bot(h.player, &"hard")
		h.step(1500)
		assert_eq(h.sim.tick, 1500)
		if id == &"gun_game":
			for f in h.sim.fighters:
				assert_true(f.is_ko() or h.sim.weapons.held_by(f) != null or (h.sim.mode as GunGame).weapon_for(f).is_empty(), "everyone armed by the mode")
		if id == &"koth" or id == &"hot_potato":
			var total := 0
			for k: int in h.sim.mode.scores:
				total += int(h.sim.mode.scores[k])
			assert_gt(total, 0, "%s: someone scores" % id)
		h.destroy()
		h = null


func test_the_end_of_a_match_shows_results_and_saves_them() -> void:
	ProfileStore.results_path = RESULTS_FILE
	if FileAccess.file_exists(RESULTS_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULTS_FILE))
	await _match(&"hangar", &"vs_bot")
	h.match_node.set("record_results", true)
	var mode := h.sim.mode
	mode.scores[h.player.fighter_id] = 3
	mode.finish(h.sim.tick)
	h.step(1)
	var replay: ReplayBuffer = h.match_node.get("replay")
	assert_true(replay.playing, "slow-motion replay of the final moment")
	var end_tick := h.sim.tick
	# The match pauses the tree, so wait on a timer that runs while paused.
	await get_tree().create_timer(ReplayBuffer.REPLAY_TIME / ReplayBuffer.REPLAY_SPEED + 0.5, true, false, true).timeout
	var results: ResultsScreen = h.match_node.get("results")
	assert_true(results.visible)
	assert_true(get_tree().paused)
	assert_eq(h.sim.tick, end_tick, "back on the final state")
	var saved := ProfileStore.match_results()
	assert_eq(saved.size(), 1)
	assert_eq(saved[0]["mode"], "vs_bot")
	assert_eq(ResultsScreen.headline(saved[0]), "VICTORY!")
	ProfileStore.results_path = ProfileStore.RESULTS_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULTS_FILE))


func test_menu_mode_picker_starts_the_picked_mode() -> void:
	Settings.path_override = "user://test_settings_modes.cfg"
	var menu := MainMenu.new()
	menu.change_scene = false
	add_child_autofree(menu)
	menu.call("_pick_mode", &"koth")
	menu.start_match(menu.get("_play_mode"))
	assert_eq(Settings.last_mode, "koth")
	Settings.path_override = ""
