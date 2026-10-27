class_name DebugWorld
extends Node2D
## World-space debug drawing, toggled from the debug overlay (§4.12): spawn points, bot anchors,
## rope anchors and pulls, melee hitboxes, the last aim-assist correction and the bot's intent.

var enabled: bool = false:
	set(value):
		enabled = value
		queue_redraw()

var arena: Arena
var sim: MatchSim
var router: TouchRouter
var bot_controller: BotController


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled or arena == null:
		return
	for p in arena.get_spawn_points():
		draw_arc(p, 20.0, 0.0, TAU, 24, Color(0.3, 1.0, 0.4, 0.8), 2.0)
	for p in arena.get_bot_anchors():
		draw_line(p + Vector2(-8, -8), p + Vector2(8, 8), Color(1.0, 0.9, 0.2, 0.9), 2.0)
		draw_line(p + Vector2(-8, 8), p + Vector2(8, -8), Color(1.0, 0.9, 0.2, 0.9), 2.0)
	if sim != null:
		var t := TuningDB.t
		for f in sim.fighters:
			var phase := f.melee_phase(sim.tick)
			if phase == SimIds.MeleePhase.ACTIVE or phase == SimIds.MeleePhase.STARTUP:
				var half := deg_to_rad(t.melee_arc_deg) * 0.5
				var mid := f.melee_dir.angle()
				var color := Color(1, 0.2, 0.2, 0.7) if phase == SimIds.MeleePhase.ACTIVE else Color(1, 0.6, 0.2, 0.4)
				draw_arc(f.global_position, t.melee_range, mid - half, mid + half, 24, color, 2.0)
				draw_line(f.global_position, f.global_position + Vector2.from_angle(mid - half) * t.melee_range, color, 2.0)
				draw_line(f.global_position, f.global_position + Vector2.from_angle(mid + half) * t.melee_range, color, 2.0)
			if f.rope.pull_target != null:
				draw_line(f.global_position, f.rope.pull_target.global_position, Color(1, 0.3, 0.3, 0.8), 2.0)
			if f.rope.is_attached():
				var pivot := f.rope.pivot_world()
				draw_circle(f.rope.anchor_world(), 6.0, Color(0.2, 1.0, 1.0))
				draw_circle(pivot, 4.0, Color(1.0, 0.5, 0.2))
				draw_arc(pivot, f.rope.length, 0.0, TAU, 64, Color(0.2, 1.0, 1.0, 0.25), 1.0)
	if bot_controller != null and bot_controller.intent_point != Vector2.INF:
		var from := bot_controller.fighter.global_position
		draw_dashed_line(from, bot_controller.intent_point, Color(1.0, 0.55, 0.85, 0.8), 2.0, 10.0)
		draw_string(ThemeDB.fallback_font, from + Vector2(-60, 60), String(bot_controller.intent), HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1.0, 0.55, 0.85))
	if router != null and router.last_tap_world != Vector2.INF:
		draw_arc(router.last_tap_world, TuningDB.t.aim_assist_radius, 0.0, TAU, 32, Color(1, 0.4, 1, 0.5), 1.0)
		draw_line(router.last_tap_world, router.last_aim_target, Color(1, 0.4, 1, 0.9), 2.0)
		draw_circle(router.last_aim_target, 5.0, Color(1, 0.4, 1))
