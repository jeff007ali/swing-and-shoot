class_name OffscreenMarkers
extends Node2D
## Arrows at the screen edge pointing to fighters the camera can't see (D28), in their skin color,
## with the distance in meters (100 px = 1 m). Visual only.

const INSET: float = 64.0
const SIZE: float = 26.0
const PX_PER_METER: float = 100.0

var sim: MatchSim
var local_fighter_id: int = -1
var top_inset: float = 0.0



func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var me := sim.get_fighter(local_fighter_id)
	var screen := get_viewport().get_visible_rect()
	var area := Rect2(screen.position + Vector2(INSET, INSET + top_inset), screen.size - Vector2(INSET * 2.0, INSET * 2.0 + top_inset))
	var to_screen := get_viewport().get_canvas_transform()
	var font := UiTheme.FONT
	for f in sim.fighters:
		if f.fighter_id == local_fighter_id or f.is_ko():
			continue
		var p := to_screen * f.global_position
		if screen.grow(-8.0).has_point(p):
			continue
		var center := area.get_center()
		var dir := (p - center).normalized()
		var edge := _edge_point(area, center, dir)
		var color := _color(f)
		var tip := edge + dir * SIZE
		var side := dir.orthogonal() * SIZE * 0.7
		draw_colored_polygon(PackedVector2Array([tip, edge + side, edge - side]), color)
		draw_polyline(PackedVector2Array([tip, edge + side, edge - side, tip]), Color(0, 0, 0, 0.6), 2.0, true)
		if me != null:
			var meters := roundi(me.global_position.distance_to(f.global_position) / PX_PER_METER)
			draw_string(font, edge - dir * 34.0 + Vector2(-40, 8), "%dm" % meters, HORIZONTAL_ALIGNMENT_CENTER, 80, 22, color)


## Where a ray from center along dir leaves the rect.
static func _edge_point(rect: Rect2, center: Vector2, dir: Vector2) -> Vector2:
	var t := INF
	if dir.x > 0.0001:
		t = minf(t, (rect.end.x - center.x) / dir.x)
	elif dir.x < -0.0001:
		t = minf(t, (rect.position.x - center.x) / dir.x)
	if dir.y > 0.0001:
		t = minf(t, (rect.end.y - center.y) / dir.y)
	elif dir.y < -0.0001:
		t = minf(t, (rect.position.y - center.y) / dir.y)
	return center + dir * t


func _color(f: Fighter) -> Color:
	return UiTheme.player_color(f.skin_id)
