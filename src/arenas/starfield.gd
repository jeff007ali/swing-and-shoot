extends Node2D
## Background stars. Visual only, so unseeded randomness is fine (§3.1 rule 5).
## Covers the parent arena's bounds plus a margin, so wide phones (stretch aspect "expand") see stars
## past the walls too; without an arena parent (main menu) it covers the reference screen.
## Performance pass (§6.7): all stars are one mesh, drawn in a single draw call.

## Stars per million square pixels.
const DENSITY: float = 85.0
const MARGIN: Vector2 = Vector2(700, 300)
## Corners of each star's polygon.
const SIDES: int = 6

var _mesh := ArrayMesh.new()


func _ready() -> void:
	var arena := get_parent() as Arena
	var area := (arena.bounds if arena != null else Rect2(0, 0, 1920, 1080)).grow_individual(MARGIN.x, MARGIN.y, MARGIN.x, MARGIN.y)
	var count := int(area.get_area() / 1000000.0 * DENSITY)
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	for i in count:
		var center := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		var radius := randf_range(0.6, 2.4)
		var color := Color(0.85, 0.9, 1.0, 0.15 + radius * 0.18)
		for k in SIDES:
			verts.append(center)
			verts.append(center + Vector2.from_angle(TAU * k / SIDES) * radius)
			verts.append(center + Vector2.from_angle(TAU * (k + 1) / SIDES) * radius)
			for c in 3:
				colors.append(color)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	queue_redraw()


func _draw() -> void:
	if _mesh.get_surface_count() > 0:
		draw_mesh(_mesh, null)
