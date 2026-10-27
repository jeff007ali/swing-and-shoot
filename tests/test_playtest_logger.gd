extends GutTest
## §4.13: the playtest CSV gets one row per event and a summary row with the §5.1 gate numbers.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const TEST_DIR: String = "user://playtest_test/"

var h: MatchHarness
var logger: PlaytestLogger


func before_each() -> void:
	TuningDB.reset_to_default()
	_clean_dir()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	logger = PlaytestLogger.new()
	h.match_node.add_child(logger)
	logger.start(h.sim, h.player.fighter_id, "vs_bot", "normal", TEST_DIR)


func after_each() -> void:
	h.destroy()
	_clean_dir()


func _clean_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(TEST_DIR)


func _lines() -> PackedStringArray:
	return FileAccess.get_file_as_string(logger.file_path).strip_edges().split("\n")


func _events(lines: PackedStringArray) -> Array:
	var out: Array = []
	for line in lines.slice(1):
		out.append(line.split(",")[2])
	return out


func _detail(line: String) -> Dictionary:
	var out := {}
	for pair in line.split(",")[4].split(";"):
		var kv := pair.split("=")
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out


func test_summarize_math() -> void:
	var s := PlaytestLogger.summarize({
		"alive_ticks": 3600, "airborne_ticks": 2700, "ropes": 30, "orbits": 2, "slingshots": 1,
		"combos": 3, "hits": 5, "kos": 1, "deaths": 0,
	})
	assert_eq(s["duration_s"], 60.0)
	assert_eq(s["ropes_per_min"], 30.0)
	assert_eq(s["airborne_pct"], 75.0)
	assert_eq(s["combos"], 3)


func test_file_name_and_header() -> void:
	assert_true(logger.file_path.begins_with(TEST_DIR))
	assert_true(logger.file_path.get_file().match("????????_??????.csv"), "YYYYMMDD_HHMMSS.csv")
	var lines := _lines()
	assert_eq(lines[0], PlaytestLogger.HEADER)
	assert_eq(_events(lines)[0], "session_start")
	assert_eq(_detail(lines[1])["mode"], "vs_bot")


func test_events_and_summary_for_a_short_session() -> void:
	var enemy := h.add_enemy(Vector2(680, 930))
	h.player.teleport(Vector2(600, 930))
	# A rope to the floor that reels in and clings, then a punch on the enemy.
	var cmd := h.input.at(1)
	cmd.rope_fire = true
	cmd.rope_target = Vector2(600, 1040)
	h.step_until(h.player.is_clinging, 30)
	h.input.at(h.sim.tick + 1).melee = true
	enemy.teleport(h.player.global_position + Vector2(70, 0))
	h.step(30)
	logger.finish()
	var lines := _lines()
	var events := _events(lines)
	for e in ["rope_fired", "rope_attached", "cling", "hit", "summary"]:
		assert_has(events, e)
	var summary := _detail(lines[lines.size() - 1])
	assert_eq(summary["hits"], "1")
	assert_gt(float(summary["duration_s"]), 0.0)
	assert_lt(float(summary["airborne_pct"]), 100.0, "clinging counts as not airborne")
	assert_gt(float(summary["ropes_per_min"]), 0.0)


func test_only_the_local_players_stats_count() -> void:
	var enemy := h.add_enemy(Vector2(1000, 930))
	h.make_bot(enemy, &"hard")
	h.step(600)
	logger.finish()
	var lines := _lines()
	var enemy_ropes := 0
	for line in lines.slice(1):
		var cols := line.split(",")
		if cols[2] == "rope_fired" and cols[3] == str(enemy.fighter_id):
			enemy_ropes += 1
	assert_gt(enemy_ropes, 0, "the bot's ropes are logged as rows")
	assert_eq(_detail(lines[lines.size() - 1])["ropes_per_min"], "0.0", "but the idle player's summary has none")
