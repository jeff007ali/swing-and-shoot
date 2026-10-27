class_name ModeView
extends Node2D
## World-space marks for the game mode (§6.5), drawn from the sim each frame: team rings under
## fighters in 2v2, the King of the Swing zone, and the Hot Potato bomb with its burning fuse.

const TEAM_RING: float = 46.0
const BOMB_OFFSET: Vector2 = Vector2(0, -78)
const BOMB_RADIUS: float = 20.0

var sim: MatchSim
var local_fighter_id: int = -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	queue_redraw()


func _fighter_pos(f: Fighter) -> Vector2:
	return f.view.global_position if f.view != null else f.global_position


func _draw() -> void:
	if sim == null or sim.mode == null:
		return
	var mode := sim.mode
	var now := Time.get_ticks_msec() / 1000.0
	if mode.is_team_mode():
		for f in sim.fighters:
			if not f.is_ko():
				var c := UiTheme.team_color(mode.key_of(f))
				draw_arc(_fighter_pos(f), TEAM_RING, 0.0, TAU, 40, Color(c, 0.8), 5.0, true)
	if mode is KingOfTheSwing:
		_draw_zone(mode as KingOfTheSwing, now)
	elif mode is HotPotato:
		_draw_bomb(mode as HotPotato, now)


func _draw_zone(koth: KingOfTheSwing, now: float) -> void:
	var at := koth.zone_center(sim.tick)
	var r := koth.def.zone_radius
	var color := Color(1, 1, 1)
	if koth.contested:
		color = Color(1.0, 0.85, 0.2)
	elif koth.holder >= 0:
		if koth.is_team_mode():
			color = UiTheme.team_color(koth.holder)
		else:
			color = UiTheme.ACCENT if koth.holder == local_fighter_id else UiTheme.ACCENT_2
	draw_circle(at, r, Color(color, 0.1 + 0.04 * sin(now * 4.0)))
	var dashes := 24
	for i in dashes:
		var a := TAU * i / dashes + now * 0.4
		draw_arc(at, r, a, a + TAU / dashes * 0.6, 6, Color(color, 0.85), 6.0, true)
	draw_string(UiTheme.FONT, at + Vector2(-120, 12), "ZONE", HORIZONTAL_ALIGNMENT_CENTER, 240, 34, Color(color, 0.35))


func _draw_bomb(potato: HotPotato, now: float) -> void:
	var holder := sim.get_fighter(potato.holder_id)
	if holder == null or holder.is_ko():
		return
	var left := potato.fuse_fraction(sim.tick)
	var at := _fighter_pos(holder) + BOMB_OFFSET + Vector2(0, sin(now * 6.0) * 4.0)
	var urgent := left < 0.25
	var blink := urgent and int(now * 10.0) % 2 == 0
	draw_circle(at, BOMB_RADIUS + 6.0, Color(1, 0.3, 0.1, 0.25 if not blink else 0.6))
	draw_circle(at, BOMB_RADIUS, Color(0.12, 0.12, 0.16) if not blink else Color(0.8, 0.15, 0.1))
	draw_arc(at, BOMB_RADIUS + 10.0, -PI * 0.5, -PI * 0.5 + TAU * left, 32, Color(1.0, 0.8 * left + 0.2, 0.2), 5.0, true)
	var spark := at + Vector2(10, -BOMB_RADIUS - 6)
	draw_line(at + Vector2(4, -BOMB_RADIUS), spark, Color(0.8, 0.7, 0.5), 3.0)
	draw_circle(spark, 5.0 + 2.0 * sin(now * 30.0), Color(1.0, 0.9, 0.3))
