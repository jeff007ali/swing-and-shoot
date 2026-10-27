extends SceneTree
## Arena thumbnails for the match setup screen: renders each arena in ArenaRegistry to
## assets/art/ui/arenas/<id>.png. Needs a window (not --headless). Rerun after changing an arena:
##   godot --path . -s res://tools/capture_arena_thumbs.gd

const OUT: String = "res://assets/art/ui/arenas/"
const SIZE: Vector2i = Vector2i(480, 270)

var _viewport: SubViewport
var _index := -1
var _frames := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	process_frame.connect(_frame)
	_next()


func _next() -> void:
	_index += 1
	for child in _viewport.get_children():
		child.queue_free()
	if _index >= ArenaRegistry.ARENAS.size():
		quit()
		return
	var arena := ArenaRegistry.instantiate(ArenaRegistry.ARENAS[_index]["id"])
	_viewport.add_child(arena)
	var bounds: Rect2 = arena.bounds
	var camera := Camera2D.new()
	camera.position = bounds.get_center()
	var fit := minf(SIZE.x / bounds.size.x, SIZE.y / bounds.size.y)
	camera.zoom = Vector2.ONE * fit
	_viewport.add_child(camera)
	camera.make_current()
	_frames = 0


func _frame() -> void:
	if _index >= ArenaRegistry.ARENAS.size():
		return
	_frames += 1
	if _frames == 20:
		var id := String(ArenaRegistry.ARENAS[_index]["id"])
		var path := ProjectSettings.globalize_path(OUT + id + ".png")
		_viewport.get_texture().get_image().save_png(path)
		print("saved ", path)
		_next()
