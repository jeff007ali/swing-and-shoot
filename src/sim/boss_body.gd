class_name BossBody
extends ArenaObject
## The Co-op Survival boss (§6.6): a giant round body that players rope onto and cling to. Only its
## glowing weak points take damage. SurvivalMode owns it: moves it, tracks its HP and decides hits.

const RADIUS: float = 130.0

var mode: SurvivalMode


func _ready() -> void:
	is_moving = true
	orbit_pivot = true
	draw_shapes = false
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	cs.shape = circle
	add_child(cs)
	super()
	set_process(true)


func _draw() -> void:
	if not active or mode == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	draw_circle(Vector2.ZERO, RADIUS + 10.0, Color(0.9, 0.2, 0.4, 0.25))
	draw_circle(Vector2.ZERO, RADIUS, Color(0.22, 0.08, 0.2))
	draw_arc(Vector2.ZERO, RADIUS - 4.0, 0.0, TAU, 64, Color(0.95, 0.35, 0.55), 6.0, true)
	for i in 8:
		var a := TAU * i / 8.0 + now * 0.2
		draw_line(Vector2.from_angle(a) * RADIUS * 0.45, Vector2.from_angle(a) * RADIUS * 0.85, Color(0.6, 0.2, 0.4), 6.0)
	# Eye looking at the nearest player.
	var look := Vector2.ZERO
	var target := mode.nearest_human(global_position)
	if target != null:
		look = (target.global_position - global_position).normalized() * 18.0
	draw_circle(Vector2.ZERO, 46.0, Color(1, 0.95, 0.9))
	draw_circle(look, 22.0, Color(0.9, 0.15, 0.3))
	draw_circle(look, 9.0, Color.BLACK)
	for p in mode.weak_points(mode.sim.tick):
		var local := to_local(p)
		var pulse := 1.0 + 0.2 * sin(now * 8.0)
		draw_circle(local, SurvivalMode.WEAK_HIT_RADIUS * 0.45 * pulse, Color(1.0, 0.9, 0.3, 0.35))
		draw_circle(local, 16.0, Color(1.0, 0.85, 0.2))
	var frac := clampf(mode.boss_hp / maxf(mode.boss_max, 1.0), 0.0, 1.0)
	draw_arc(Vector2.ZERO, RADIUS + 22.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 64, Color(1.0, 0.3, 0.4), 8.0, true)
