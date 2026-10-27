extends GutTest
## Aimed attacks: dragging HIT or FIRE picks the direction, a tap auto-aims, dragging back cancels;
## the sim swings and shoots along the aim.

const MatchHarness = preload("res://tests/helpers/match_harness.gd")
const LANE: Vector2 = Vector2(600, 930)

var h: MatchHarness
var hud: Hud
var router: TouchRouter


func before_each() -> void:
	TuningDB.reset_to_default()
	h = MatchHarness.new()
	h.create(self)
	await wait_physics_frames(2)
	hud = h.match_node.get("hud")
	router = h.match_node.get("router")
	h.player.teleport(LANE)
	h.player.facing = Vector2.RIGHT


func after_each() -> void:
	h.destroy()


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	hud._input(e)


func _drag(index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	hud._input(e)


func _melee_center() -> Vector2:
	return (hud.get("_melee_button") as Node2D).position


func test_dragging_hit_aims_the_swing() -> void:
	var c := _melee_center()
	_touch(0, c, true)
	_drag(0, c + Vector2(-120, 10))
	assert_true(router.build_command(1).melee == false, "nothing until the finger lifts")
	_touch(0, c + Vector2(-120, 10), false)
	var cmd := router.build_command(2)
	assert_true(cmd.melee)
	assert_almost_eq(cmd.aim_dir.angle(), Vector2(-120, 10).angle(), 0.01)


func test_a_tap_auto_aims() -> void:
	var c := _melee_center()
	_touch(0, c, true)
	_drag(0, c + Vector2(10, 5))
	_touch(0, c + Vector2(10, 5), false)
	var cmd := router.build_command(1)
	assert_true(cmd.melee)
	assert_eq(cmd.aim_dir, Vector2.ZERO)


func test_dragging_back_to_the_middle_cancels() -> void:
	var c := _melee_center()
	_touch(0, c, true)
	_drag(0, c + Vector2(0, -150))
	_drag(0, c + Vector2(4, 4))
	_touch(0, c + Vector2(4, 4), false)
	assert_false(router.build_command(1).melee)


func test_aimed_swing_goes_where_you_aim_not_at_the_nearest_enemy() -> void:
	var enemy := h.add_enemy(LANE + Vector2(70, 0))
	h.input.at(h.sim.tick + 1).melee = true
	h.input.at(h.sim.tick + 1).aim_dir = Vector2.LEFT
	h.step(TuningDB.t.melee_startup_ticks + TuningDB.t.melee_active_ticks + 2)
	assert_eq(h.player.melee_dir, Vector2.LEFT)
	assert_eq(enemy.hp, TuningDB.t.max_hp, "the enemy behind you isn't hit")
	h.player.melee_ready_tick = 0
	h.player.velocity = Vector2.ZERO
	h.input.at(h.sim.tick + 1).melee = true
	h.step(TuningDB.t.melee_startup_ticks + TuningDB.t.melee_active_ticks + 2)
	assert_lt(enemy.hp, TuningDB.t.max_hp, "an un-aimed tap still auto-aims at it")


func test_aimed_shot_flies_along_the_aim() -> void:
	h.add_enemy(LANE + Vector2(400, 0))
	var item := h.sim.weapons.spawn(WeaponDef.load_by_id(&"pistol"), h.player.global_position)
	h.sim.weapons.equip(h.player, item)
	h.input.at(h.sim.tick + 1).fire = true
	h.input.at(h.sim.tick + 1).aim_dir = Vector2.UP
	h.step(1)
	assert_eq(h.sim.weapons.projectiles.size(), 1)
	assert_lt(h.sim.weapons.projectiles[0].vel.y, -1000.0)
	assert_almost_eq(h.sim.weapons.projectiles[0].vel.x, 0.0, 1.0)


func test_aiming_with_a_sword_swings_that_way() -> void:
	var item := h.sim.weapons.spawn(WeaponDef.load_by_id(&"sword"), h.player.global_position)
	h.sim.weapons.equip(h.player, item)
	h.input.at(h.sim.tick + 1).fire = true
	h.input.at(h.sim.tick + 1).aim_dir = Vector2.DOWN
	h.step(1)
	assert_eq(h.player.melee_dir, Vector2.DOWN)


# --- Rope aim assist and leaving walls (D38) ---------------------------------------------------------

func test_a_tap_near_a_floating_weapon_snaps_to_it() -> void:
	var item := h.sim.weapons.spawn(WeaponDef.load_by_id(&"pistol"), LANE + Vector2(300, -200), Vector2(60, 0))
	var target := h.sim.aim_assist(item.pos + Vector2(70, 30), h.player)
	assert_lt(target.distance_to(item.pos), 30.0)
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.rope_fire = true
	cmd.rope_target = target
	var got := h.step_until(func() -> bool: return h.player.weapon_id == item.id, 90)
	assert_true(got, "fetched and equipped")


func test_a_tap_on_a_turbine_aims_at_its_hub() -> void:
	var turbine: ArenaObject = h.object_named("Turbine")
	var tap := turbine.global_position + Vector2(120, 40)
	assert_eq(h.sim.aim_assist(tap, h.player), turbine.global_position)


func test_a_rope_that_finds_nothing_pushes_off_the_wall() -> void:
	h.player.teleport(Vector2(960, 1000))
	h.player.velocity = Vector2(0, 300)
	h.step_until(func() -> bool: return h.player.is_clinging(), 30)
	assert_true(h.player.is_clinging())
	var cmd := h.input.at(h.sim.tick + 1)
	cmd.rope_fire = true
	cmd.rope_target = h.player.global_position + Vector2(-2000, -300)
	var left := h.step_until(func() -> bool: return not h.player.is_clinging(), 30)
	assert_true(left, "not stuck on the wall")
	assert_lt(h.player.velocity.x, -300.0, "off toward where the rope went")


# --- Rope stick, snap marker, out-of-range flash (D39) -----------------------------------------------

func _with_rope_stick() -> Vector2:
	var saved := Settings.rope_stick
	Settings.rope_stick = true
	Settings.apply()
	Settings.rope_stick = saved
	return (hud.get("_rope_stick") as Node2D).position


func test_rope_stick_aims_at_an_enemy_near_the_direction() -> void:
	var enemy := h.add_enemy(LANE + Vector2(400, -60))
	var ahead := h.sim.aim_direction(Vector2.RIGHT, h.player)
	assert_lt(ahead.distance_to(enemy.global_position), 5.0, "within the assist angle")
	var up := h.sim.aim_direction(Vector2.UP, h.player)
	assert_almost_eq(up.distance_to(h.player.global_position), TuningDB.t.rope_range, 0.5, "nothing there: full rope length")


func test_dragging_the_rope_stick_fires_along_the_drag() -> void:
	var c := _with_rope_stick()
	assert_true((hud.get("_rope_stick") as Node2D).visible)
	assert_eq(hud.call("_button_at", c), &"rope")
	_touch(3, c, true)
	_drag(3, c + Vector2(0, -150))
	_touch(3, c + Vector2(0, -150), false)
	var cmd := router.build_command(h.sim.tick + 1)
	assert_true(cmd.rope_fire)
	assert_lt(cmd.rope_target.y, h.player.global_position.y - 500.0, "straight up")
	assert_almost_eq(cmd.rope_target.x, h.player.global_position.x, 1.0)
	Settings.rope_stick = false
	Settings.apply()


func test_tapping_the_rope_stick_lets_go() -> void:
	var c := _with_rope_stick()
	h.player.rope.fire(h.sim.tick, h.player.global_position + Vector2(0, 200))
	_touch(3, c, true)
	_touch(3, c, false)
	assert_true(router.build_command(h.sim.tick + 1).rope_release)
	Settings.rope_stick = false
	Settings.apply()


func test_each_rope_reports_its_snap_and_far_taps_flash_the_range() -> void:
	var seen := []
	var far := [false]
	router.rope_aimed.connect(func(tap: Vector2, target: Vector2) -> void: seen.append([tap, target]))
	router.rope_out_of_range.connect(func() -> void: far[0] = true)
	h.player.rope_cooldown_until_tick = 0
	router.touch_down(5, router.get_viewport().get_canvas_transform() * (h.player.global_position + Vector2(1500, 0)))
	router.build_command(h.sim.tick + 1)
	assert_eq(seen.size(), 1)
	assert_true(far[0], "beyond rope range")
