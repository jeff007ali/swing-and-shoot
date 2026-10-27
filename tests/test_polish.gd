extends GutTest
## Phase 7 (§6.7): challenge definitions and the tracker (tutorial, daily-challenge opening), the
## tutorial match, left-handed and resizable buttons, colorblind-safe colors, the replay buffer
## behind the final-KO slow motion (kill-clip opening), and the Store stub.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const TEST_SETTINGS: String = "user://test_settings_polish.cfg"
const KEYS := ["left_handed", "button_scale", "colorblind", "tutorial_done", "rope_stick"]

var h: MatchHarness
var _saved: Dictionary = {}


func before_each() -> void:
	TuningDB.reset_to_default()
	for key: String in KEYS:
		_saved[key] = Settings.get(key)
	Settings.path_override = TEST_SETTINGS


func after_each() -> void:
	if h != null:
		h.destroy()
	h = null
	for key: String in KEYS:
		Settings.set(key, _saved[key])
	Settings.apply()
	Settings.path_override = ""
	DirAccess.remove_absolute(TEST_SETTINGS)
	get_tree().paused = false


func test_challenge_matching() -> void:
	var combo := ChallengeDef.load_by_id(&"tut_06_combo")
	assert_true(combo.matches([0, 1, 30.0, 900.0, true], 0))
	assert_false(combo.matches([0, 1, 30.0, 900.0, false], 0), "not a combo")
	assert_false(combo.matches([1, 0, 30.0, 900.0, true], 0), "someone else's")
	var hazards := ChallengeDef.load_by_id(&"daily_hazard_pulls")
	assert_true(hazards.matches([2, -1, &"vent", 0], 0), "pulled into a vent by me")
	assert_false(hazards.matches([2, -1, &"melee", 0], 0))


func test_tracker_counts_steps_in_order() -> void:
	var tracker := ChallengeTracker.new()
	add_child_autofree(tracker)
	var steps: Array[ChallengeDef] = [ChallengeDef.load_by_id(&"tut_02_kick"), ChallengeDef.load_by_id(&"tut_08_fire")]
	tracker.start(steps, 0)
	var done := [false]
	tracker.all_completed.connect(func() -> void: done[0] = true)
	GameEvents.weapon_fired.emit(0, &"pistol", Vector2.ZERO, Vector2.RIGHT)
	assert_eq(tracker.current, 0, "the second step doesn't count yet")
	GameEvents.kicked_off.emit(1, Vector2.UP)
	assert_eq(tracker.current, 0, "another fighter's kick doesn't count")
	GameEvents.kicked_off.emit(0, Vector2.UP)
	assert_eq(tracker.current, 1)
	GameEvents.weapon_fired.emit(0, &"pistol", Vector2.ZERO, Vector2.RIGHT)
	GameEvents.weapon_fired.emit(0, &"pistol", Vector2.ZERO, Vector2.RIGHT)
	assert_true(done[0])
	assert_true(tracker.is_done())


func test_tutorial_match_runs_its_steps_and_ends() -> void:
	Settings.tutorial_done = false
	h = MatchHarness.new()
	h.create(self, 1234, &"hangar", &"tutorial")
	await wait_physics_frames(2)
	assert_eq(h.sim.fighters.size(), 2, "player and dummy")
	var tracker: ChallengeTracker = h.match_node.get("tracker")
	assert_not_null(tracker)
	assert_eq(tracker.challenges.size(), 8)
	for def in tracker.challenges:
		var args := _default_args(def.event)
		args[def.actor_arg] = h.player.fighter_id
		for i: int in def.match_args:
			var want: Variant = def.match_args[i]
			args[i] = want[0] if want is Array else want
		for n in def.count:
			GameEvents.emit_signal.callv([def.event] + args)
	assert_true(tracker.is_done())
	h.step(1)
	assert_true(h.sim.mode.ended)
	assert_true(Settings.tutorial_done)


## Harmless values of the right types for a GameEvents signal's arguments.
func _default_args(event: StringName) -> Array:
	var defaults := {TYPE_INT: -1, TYPE_FLOAT: 0.0, TYPE_BOOL: false, TYPE_VECTOR2: Vector2.ZERO, TYPE_STRING_NAME: &"pistol"}
	for sig in GameEvents.get_signal_list():
		if sig["name"] == event:
			return sig["args"].map(func(a: Dictionary) -> Variant: return defaults.get(a["type"], null))
	return []


func test_left_handed_and_bigger_buttons() -> void:
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	var hud: Hud = h.match_node.get("hud")
	var melee: Node2D = hud.get("_melee_button")
	Settings.left_handed = false
	Settings.button_scale = 1.0
	Settings.apply()
	var right_x := melee.position.x
	var r: float = hud.call("_melee_radius")
	Settings.left_handed = true
	Settings.button_scale = 1.4
	Settings.apply()
	assert_lt(melee.position.x, right_x * 0.5, "moved to the left")
	assert_almost_eq(hud.call("_melee_radius"), r * 1.4, 0.01)
	var router: TouchRouter = h.match_node.get("router")
	assert_true(router.button_rects[0].has_point(melee.position), "the router knows where it went")


func test_colorblind_colors() -> void:
	Settings.colorblind = false
	var normal := UiTheme.player_color(&"alien_green")
	Settings.colorblind = true
	assert_ne(UiTheme.player_color(&"alien_green"), normal)
	assert_ne(UiTheme.player_color(&"alien_pink"), UiTheme.player_color(&"alien_green"))
	assert_eq(UiTheme.team_color(0), UiTheme.SAFE_TEAM_COLORS[0])


func test_replay_buffer_keeps_six_seconds() -> void:
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	var replay: ReplayBuffer = h.match_node.get("replay")
	h.step(SimIds.ticks(ReplayBuffer.BUFFER_TIME) + 60)
	var clip := replay.clip(ReplayBuffer.BUFFER_TIME)
	assert_almost_eq(clip.size(), SimIds.ticks(ReplayBuffer.BUFFER_TIME) / ReplayBuffer.RECORD_EVERY, 2)
	assert_gte(clip.back()["tick"], h.sim.tick - ReplayBuffer.RECORD_EVERY)


func test_store_stub() -> void:
	assert_false(Store.is_available())
	assert_true(Store.is_owned(&"alien_green"))
	assert_false(Store.is_owned(&"gold_rope"))
	var result := [null]
	Store.purchase_finished.connect(func(id: StringName, ok: bool, _m: String) -> void: result[0] = [id, ok], CONNECT_ONE_SHOT)
	Store.purchase(&"gold_rope")
	await wait_process_frames(2)
	assert_eq(result[0], [&"gold_rope", false])
