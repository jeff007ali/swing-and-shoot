class_name Minimap
extends Node2D
## Top-right overview of an arena bigger than the screen (D28): obstacles, fighters and the area the
## camera shows. Drawn every frame from the live arena, so turbines turn on it too. Visual only.

const WIDTH: float = 280.0
const BACKGROUND: Color = Color(0.03, 0.04, 0.09, 0.7)
const BORDER: Color = Color(1, 1, 1, 0.35)
const OBSTACLE: Color = Color(0.62, 0.7, 0.82, 0.75)
const VIEW: Color = Color(1, 1, 1, 0.5)
const DOT_RADIUS: float = 5.0

var arena: Arena
var sim: MatchSim
var camera: CameraShake
var local_fighter_id: int = -1



## Map size for the current arena.
func map_size() -> Vector2:
	if arena == null:
		return Vector2.ZERO
	return arena.bounds.size * (WIDTH / arena.bounds.size.x)


func _process(_delta: float) -> void:
	visible = arena != null and camera != null and camera.is_scrolling()
	if visible:
		queue_redraw()


func _draw() -> void:
	var b := arena.bounds
	var k := WIDTH / b.size.x
	var to_map := Transform2D(0.0, Vector2(k, k), 0.0, -b.position * k)
	draw_rect(Rect2(Vector2.ZERO, map_size()), BACKGROUND)
	for obj in arena.get_objects():
		for child in obj.get_children():
			var cs := child as CollisionShape2D
			if cs == null or cs.shape == null:
				continue
			draw_set_transform_matrix(to_map * obj.global_transform * cs.transform)
			if cs.shape is RectangleShape2D:
				var size := (cs.shape as RectangleShape2D).size
				draw_rect(Rect2(-size * 0.5, size), OBSTACLE)
			elif cs.shape is CircleShape2D:
				draw_circle(Vector2.ZERO, (cs.shape as CircleShape2D).radius, OBSTACLE)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if sim != null:
		for f in sim.fighters:
			if f.is_ko():
				continue
			var p := to_map * f.global_position
			if f.fighter_id == local_fighter_id:
				draw_circle(p, DOT_RADIUS + 2.0, Color.WHITE)
			draw_circle(p, DOT_RADIUS, _color(f))
	var view := camera.get_viewport_rect().size / camera.zoom
	var view_rect := Rect2(camera.global_position - view * 0.5, view)
	draw_rect(Rect2(to_map * view_rect.position, view_rect.size * k), VIEW, false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, map_size()), BORDER, false, 2.0)


func _color(f: Fighter) -> Color:
	return UiTheme.player_color(f.skin_id)
