extends GutTest
## M5 (§4.9): each behavior rule on its own, the bot's pull-and-punch, a Normal bot that roams, pulls
## and melees, and Hard beating Easy over several bot-vs-bot matches.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const PLAYER_POS := Vector2(600, 930)
const BOT_POS := Vector2(1000, 930)

var h: MatchHarness
var enemy: Fighter
var events: Array = []


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	h.player.teleport(PLAYER_POS)
	enemy = h.add_enemy(BOT_POS)
	events = []
	GameEvents.rope_fired.connect(_on_rope_fired)
	GameEvents.rope_attached.connect(_on_rope_attached)
	GameEvents.melee_started.connect(_on_melee_started)
	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.fighter_ko.connect(_on_fighter_ko)


func after_each() -> void:
	GameEvents.rope_fired.disconnect(_on_rope_fired)
	GameEvents.rope_attached.disconnect(_on_rope_attached)
	GameEvents.melee_started.disconnect(_on_melee_started)
	GameEvents.hit_landed.disconnect(_on_hit_landed)
	GameEvents.fighter_ko.disconnect(_on_fighter_ko)
	h.destroy()


func _on_rope_fired(id: int, target: Vector2) -> void:
	events.append([&"fired", id, target])


func _on_rope_attached(id: int, mode: int, point: Vector2) -> void:
	events.append([&"attached", id, mode, point])


func _on_melee_started(id: int, _dir: Vector2) -> void:
	events.append([&"melee", id])


func _on_hit_landed(attacker: int, victim: int, damage: float, _kb: float, combo: bool) -> void:
	events.append([&"hit", attacker, victim, damage, combo])


func _on_fighter_ko(id: int, killer: int, _cause: StringName, _puller: int) -> void:
	events.append([&"ko", id, killer])


func _of(kind: StringName, fighter_id: int) -> Array:
	return events.filter(func(e: Array) -> bool: return e[0] == kind and e[1] == fighter_id)


## The Normal profile with some fields overridden.
func _profile(overrides: Dictionary) -> BotProfile:
	var p := BotProfile.load_by_id(&"normal").duplicate() as BotProfile
	for key: String in overrides:
		p.set(key, overrides[key])
	return p


func _fires_near(fighter_id: int, point: Vector2, radius: float) -> Array:
	return _of(&"fired", fighter_id).filter(func(e: Array) -> bool: return (e[2] as Vector2).distance_to(point) <= radius)


# --- Rule 4: rope the player ------------------------------------------------------------------

func test_bot_ropes_the_player_in_range() -> void:
	var bot := h.make_bot(enemy, _profile({"aggression": 100.0, "aim_error_deg": 0.0, "acquire_time": 0.0}))
	h.step(6)
	assert_eq(_fires_near(enemy.fighter_id, PLAYER_POS, 1.0).size(), 1, "aims exactly at the still player")
	assert_eq(bot.intent, &"rope_player")
	assert_true(h.step_until(func() -> bool: return h.player.pulled_by_id == enemy.fighter_id, 15), "and pulls")


func test_bot_needs_to_see_the_player_for_a_moment_first() -> void:
	h.make_bot(enemy, _profile({"aggression": 100.0, "aim_error_deg": 0.0, "acquire_time": 0.5}))
	h.step(SimIds.ticks(0.5) - 6)
	assert_eq(_fires_near(enemy.fighter_id, PLAYER_POS, 1.0).size(), 0, "no snap rope before acquire_time")
	h.step(12)
	assert_eq(_fires_near(enemy.fighter_id, PLAYER_POS, 1.0).size(), 1, "ropes once the player has been in sight long enough")


func test_bot_does_not_rope_a_player_out_of_sight() -> void:
	# Box B sits between them.
	h.player.teleport(Vector2(1440, 900))
	enemy.teleport(Vector2(1440, 670))
	h.make_bot(enemy, _profile({"aggression": 100.0, "aim_error_deg": 0.0}))
	h.step(30)
	assert_eq(_fires_near(enemy.fighter_id, h.player.global_position, 60.0).size(), 0)


func test_bot_does_not_rope_a_pull_immune_player() -> void:
	h.player.pull_immune_until_tick = 1000
	h.make_bot(enemy, _profile({"aggression": 100.0, "aim_error_deg": 0.0}))
	h.step(30)
	assert_eq(_fires_near(enemy.fighter_id, PLAYER_POS, 60.0).size(), 0)


# --- Rule 2: escape a pull --------------------------------------------------------------------

## Pulls the bot before it gets a brain (an idle bot would grapple away on its first think).
func _pull_the_bot() -> void:
	var cmd := h.input.at(1)
	cmd.rope_fire = true
	cmd.rope_target = BOT_POS
	assert_true(h.step_until(func() -> bool: return enemy.pulled_by_id == h.player.fighter_id, 15), "player pulls the bot")


func test_pulled_bot_ropes_away_with_full_escape_chance() -> void:
	_pull_the_bot()
	var bot := h.make_bot(enemy, _profile({"escape_chance": 1.0, "aggression": 0.0}))
	h.step(6)
	var fires := _of(&"fired", enemy.fighter_id)
	assert_eq(fires.size(), 1, "one escape rope")
	assert_eq(bot.intent, &"escape")
	var away := (fires[0][2] as Vector2) - enemy.global_position
	assert_gt(away.x, 0.0, "away from the player")
	assert_true(h.sim.get_state()["fighters"].size() == 2)


func test_pulled_bot_stays_put_with_zero_escape_chance() -> void:
	_pull_the_bot()
	h.make_bot(enemy, _profile({"escape_chance": 0.0, "aggression": 0.0}))
	h.step(12)
	assert_eq(_of(&"fired", enemy.fighter_id).size(), 0)


# --- Rule 3: melee ----------------------------------------------------------------------------

func test_bot_swings_at_a_player_flying_in() -> void:
	h.make_bot(enemy, _profile({"aggression": 0.0}))
	h.player.teleport(BOT_POS + Vector2(100, 0))
	h.player.velocity = Vector2(-400, 0)
	h.step(6 + SimIds.ticks(0.22) + 1)
	assert_eq(_of(&"melee", enemy.fighter_id).size(), 1, "swings after its reaction time")


func test_bot_times_a_pull_and_punch_combo() -> void:
	h.make_bot(enemy, _profile({"aggression": 100.0, "aim_error_deg": 0.0, "melee_timing_error_ticks": 0}))
	h.step(120)
	var hits := _of(&"hit", enemy.fighter_id)
	assert_gt(hits.size(), 0, "the bot lands a hit")
	assert_true(hits[0][4], "the first hit is the signature combo")
	assert_gte(hits[0][3], 40.0)


# --- Rule 5: roam -----------------------------------------------------------------------------

func test_clinging_bot_grapples_to_an_anchor_after_its_idle_time() -> void:
	var bot := h.make_bot(enemy, _profile({"aggression": 0.0}))
	enemy.teleport(Vector2(1830, 700))
	enemy.velocity = Vector2(900, 0)
	assert_true(h.step_until(enemy.is_clinging, 10), "bot reaches the right wall")
	var clung_at := h.sim.tick
	assert_true(h.step_until(func() -> bool: return _of(&"fired", enemy.fighter_id).size() > 0, 90), "grapples on")
	assert_eq(bot.intent, &"grapple")
	assert_gte(h.sim.tick - clung_at, SimIds.ticks(bot.profile.idle_cling_time), "not before idle_cling_time")
	var target: Vector2 = _of(&"fired", enemy.fighter_id)[0][2]
	var arena: Arena = h.match_node.get("arena")
	assert_has(arena.get_bot_anchors(), target, "aims at a bot anchor")


func test_clinging_bot_holds_position_while_the_player_is_ropeable() -> void:
	var bot := h.make_bot(enemy, _profile({"aggression": 0.0}))
	# Clings to the bottom wall within easy rope range and sight of the player.
	enemy.teleport(Vector2(900, 980))
	enemy.velocity = Vector2(0, 900)
	assert_true(h.step_until(enemy.is_clinging, 10))
	h.step(SimIds.ticks(TuningDB.t.cling_time) - 6)
	assert_true(enemy.is_clinging(), "still clinging past idle_cling_time")
	assert_eq(_of(&"fired", enemy.fighter_id).size(), 0, "no roaming away")
	assert_eq(bot.intent, &"aim")


func test_roaming_skips_anchors_on_the_surface_it_clings_to() -> void:
	var bot := h.make_bot(enemy, _profile({"aggression": 0.0}))
	h.player.teleport(Vector2(1770, 930))
	enemy.teleport(Vector2(590, 200))
	enemy.velocity = Vector2(0, 900)
	assert_true(h.step_until(enemy.is_clinging, 10), "lands on top of Box A")
	assert_eq(enemy.cling_object.name, &"BoxA")
	assert_true(h.step_until(func() -> bool: return _of(&"fired", enemy.fighter_id).size() > 0, 90))
	assert_ne(_of(&"fired", enemy.fighter_id)[0][2], Vector2(480, 255), "not Box A's own top anchor")
	assert_eq(bot.intent, &"grapple")


func test_roaming_prefers_anchors_that_can_see_the_player() -> void:
	# From above Box A, both Box A Top and Wall Left are reachable and in the distance band, but the
	# box hides the player from Box A Top.
	var bot := h.make_bot(enemy, _profile({"aggression": 0.0}))
	h.player.teleport(Vector2(480, 600))
	enemy.teleport(Vector2(480, 120))
	assert_eq(bot._roam_anchor(h.player), Vector2(40, 540))


func test_normal_bot_roams_pulls_and_melees() -> void:
	h.make_bot(enemy, &"normal")
	h.step(30 * SimIds.TICK_RATE)
	var mine := _of(&"attached", enemy.fighter_id)
	var grapples := mine.filter(func(e: Array) -> bool: return e[2] == SimIds.RopeMode.REEL)
	var pulls := mine.filter(func(e: Array) -> bool: return e[2] == SimIds.RopeMode.PULL)
	gut.p("30 s Normal bot vs idle player: %d grapples, %d pulls, %d swings, %d hits, %d KOs" % [grapples.size(), pulls.size(), _of(&"melee", enemy.fighter_id).size(), _of(&"hit", enemy.fighter_id).size(), events.filter(func(e: Array) -> bool: return e[0] == &"ko" and e[2] == enemy.fighter_id).size()])
	assert_gte(grapples.size(), 5, "roams between anchors")
	assert_gte(pulls.size(), 2, "pulls the player")
	assert_gte(_of(&"hit", enemy.fighter_id).size(), 2, "and hits")
	assert_gte(events.filter(func(e: Array) -> bool: return e[0] == &"ko" and e[2] == enemy.fighter_id).size(), 1, "and scores a KO")


# --- Difficulty -------------------------------------------------------------------------------

func _kos_in_bot_match(hard_first: bool, match_seed: int) -> Vector2i:
	h.destroy()
	await wait_physics_frames(2)
	h = MatchHarness.new()
	h.create(self, match_seed)
	await wait_physics_frames(2)
	enemy = h.add_enemy(Vector2(1770, 930))
	var hard := h.player if hard_first else enemy
	var easy := enemy if hard_first else h.player
	h.make_bot(hard, &"hard")
	h.make_bot(easy, &"easy")
	# As in real play: weapons spawn (§6.3).
	h.sim.weapons.spawning = true
	events = []
	h.step(60 * SimIds.TICK_RATE)
	var by := func(killer: Fighter) -> int:
		return events.filter(func(e: Array) -> bool: return e[0] == &"ko" and e[2] == killer.fighter_id).size()
	return Vector2i(by.call(hard), by.call(easy))


func test_hard_beats_easy_over_several_matches() -> void:
	var total := Vector2i.ZERO
	for match_seed in [11, 22, 33]:
		for hard_first in [true, false]:
			var kos: Vector2i = await _kos_in_bot_match(hard_first, match_seed)
			total += kos
	gut.p("Hard vs Easy, 6 x 60 s: Hard %d KOs, Easy %d KOs" % [total.x, total.y])
	assert_gt(total.x, total.y, "Hard scores more KOs than Easy")
	assert_gte(total.x, 4, "and actually scores")
