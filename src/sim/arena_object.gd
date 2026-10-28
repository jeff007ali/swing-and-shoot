class_name ArenaObject
extends StaticBody2D
## A piece of arena geometry (§4.2): wall, box, asteroid or turbine. Phase 4 (§6.4) adds surface
## types (smooth: the rope can't grab it and fighters bounce, ARN-07; electric: fighters bounce and
## take damage, ARN-05), breakable objects (ARN-09) and fuel tanks that explode (ARN-08).
## It draws itself from its CollisionShape2D children: rectangles with panel_texture as a nine-patch
## (rotated for tall, tiled panels), circles with disc_texture; flat colors if a texture is unset.

@export var hookable: bool = true
## Round obstacles orbit around their center instead of the hook point (§4.6, M3).
@export var orbit_pivot: bool = false
@export var is_moving: bool = false
## "normal" (cling), "smooth" or "electric".
@export var surface_type: StringName = &"normal"
## Breakable when above 0: damaged by shots and blasts, gone at 0 (ARN-09).
@export var max_hp: float = 0.0
## A fuel tank: explodes when shot (ARN-08). Uses TANK_HP unless max_hp is set.
@export var explosive: bool = false

@export_group("Look")
@export var draw_shapes: bool = true
@export var fill_color: Color = Color("262c40")
@export var border_color: Color = Color("6c7aa6")
@export var border_width: float = 4.0
## Nine-patch art for rectangle shapes.
@export var panel_texture: Texture2D
## Border of panel_texture that is not stretched (px of the texture).
@export var panel_margin: float = 8.0
## Repeat the panel along its length instead of stretching it (walls). Tall panels are drawn rotated.
@export var tile_panel: bool = false
## Art for circle shapes, stretched to the circle's diameter.
@export var disc_texture: Texture2D

## Set by HazardSystem: remaining hp (for cracks) and whether the object exists right now.
var hp: float = 0.0
var active: bool = true

var _panel_style: StyleBoxTexture
var _current_shape_xform: Transform2D = Transform2D.IDENTITY

## Index in MatchSim.arena_objects. Same on every device because it follows tree order.
var object_id: int = -1


func _ready() -> void:
	if surface_type == &"smooth":
		hookable = false
	collision_layer = Layers.WORLD_HOOKABLE if hookable else Layers.WORLD_SMOOTH
	collision_mask = 0
	hp = max_hp
	set_process(surface_type == &"electric")
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func is_breakable() -> bool:
	return max_hp > 0.0 or explosive


## Turns the object on or off at once: collision (in the physics server, for same-tick queries) and
## drawing. Used for broken obstacles, blown tanks and open vent doors.
func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	visible = on
	var shape_index := 0
	for child in get_children():
		if child is CollisionShape2D:
			PhysicsServer2D.body_set_shape_disabled(get_rid(), shape_index, not on)
			shape_index += 1
	queue_redraw()


## Center of mass for blasts and pulls.
func center() -> Vector2:
	return global_position


## Called by MatchSim at the start of every tick (§3.3 step 1). Static objects do nothing.
func step(_tick: int) -> void:
	pass


## Velocity of the surface at world point (px/s). A fighter that lets go keeps it.
func surface_velocity(_point: Vector2) -> Vector2:
	return Vector2.ZERO


## Godot hands a moved node's transform to the physics server only once per frame. The sim moves
## bodies and then queries physics in the same tick, so moving objects push it right away.
## This only takes effect at once for static bodies: kinematic ones (AnimatableBody2D) apply a new
## transform at the next physics step, so moving arena objects must be StaticBody2D nodes.
func sync_physics_transform() -> void:
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, global_transform)


## Radius of the first circle shape, used when orbiting around the center (§4.6).
func pivot_radius() -> float:
	for child in get_children():
		var cs := child as CollisionShape2D
		if cs != null and cs.shape is CircleShape2D:
			return (cs.shape as CircleShape2D).radius
	return 0.0


func _draw() -> void:
	if not draw_shapes:
		return
	for child in get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		draw_set_transform_matrix(cs.transform)
		_current_shape_xform = cs.transform
		if cs.shape is RectangleShape2D:
			var size := (cs.shape as RectangleShape2D).size
			_draw_panel(size)
			draw_set_transform_matrix(cs.transform)
			_draw_surface_rect(size)
		elif cs.shape is CircleShape2D:
			var radius := (cs.shape as CircleShape2D).radius
			_draw_disc(radius)
			_draw_surface_disc(radius)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Smooth sheen, electric crackle and damage cracks on top of a panel.
func _draw_surface_rect(size: Vector2) -> void:
	var rect := Rect2(-size * 0.5, size)
	match surface_type:
		&"smooth":
			draw_rect(rect, Color(0.85, 0.95, 1.0, 0.25))
			var step := 36.0
			var x := rect.position.x
			while x < rect.end.x:
				draw_line(Vector2(x, rect.end.y), Vector2(minf(x + size.y * 0.6, rect.end.x), rect.position.y), Color(1, 1, 1, 0.35), 3.0)
				x += step
		&"electric":
			_draw_crackle(rect)
	_draw_cracks(rect.get_center(), minf(size.x, size.y) * 0.5)


func _draw_surface_disc(radius: float) -> void:
	if explosive:
		draw_circle(Vector2.ZERO, radius, Color(0.75, 0.12, 0.08))
		for i in 4:
			var a := TAU / 4.0 * i + PI / 4.0
			draw_arc(Vector2.ZERO, radius * 0.72, a - 0.35, a + 0.35, 10, Color(1, 0.85, 0.15), radius * 0.4)
		draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 32, Color(1, 0.85, 0.15), 4.0, true)
		draw_string(ThemeDB.fallback_font, Vector2(-radius, radius * 0.25), "!", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(radius * 0.9), Color.WHITE)
	_draw_cracks(Vector2.ZERO, radius)


## Fresh zig-zag sparks along the edges each frame.
func _draw_crackle(rect: Rect2) -> void:
	draw_rect(rect, Color(0.3, 0.8, 1.0, 0.25))
	draw_rect(rect, Color(0.5, 0.9, 1.0, 0.9), false, 3.0)
	var length := (rect.size.x + rect.size.y) * 2.0
	var bolts := clampi(int(length / 260.0), 2, 24)
	for b in bolts:
		var along := randf() * length
		var start := _perimeter_point(rect, along)
		var points := PackedVector2Array([start])
		var p := start
		for k in 5:
			p += Vector2(randf_range(-14, 14), randf_range(-14, 14))
			points.append(p)
		draw_polyline(points, Color(0.75, 0.95, 1.0, 0.9), 2.0, true)


static func _perimeter_point(rect: Rect2, along: float) -> Vector2:
	var w := rect.size.x
	var h := rect.size.y
	along = fmod(along, (w + h) * 2.0)
	if along < w:
		return rect.position + Vector2(along, 0)
	along -= w
	if along < h:
		return rect.position + Vector2(w, along)
	along -= h
	if along < w:
		return rect.end - Vector2(along, 0)
	return rect.position + Vector2(0, h - (along - w))


## Cracks grow as a breakable object loses hp.
func _draw_cracks(at: Vector2, radius: float) -> void:
	if not is_breakable() or max_hp <= 0.0 or hp >= max_hp:
		return
	var damage := 1.0 - clampf(hp / max_hp, 0.0, 1.0)
	var count := 1 + int(damage * 6.0)
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = object_id + 17
	for i in count:
		var a := seed_rng.randf() * TAU
		var p := at
		var points := PackedVector2Array([p])
		for k in 4:
			p += Vector2.from_angle(a + seed_rng.randf_range(-0.6, 0.6)) * radius * 0.28
			points.append(p)
		draw_polyline(points, Color(0.05, 0.05, 0.08, 0.85), 3.0, true)


func _draw_panel(size: Vector2) -> void:
	if panel_texture != null:
		_draw_textured_panel(size)
		return
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, fill_color)
	draw_rect(rect.grow(-border_width * 0.5), border_color, false, border_width)
	var inner := rect.grow(-border_width - 6.0)
	if inner.size.x > 12.0 and inner.size.y > 12.0:
		draw_rect(inner, fill_color.lightened(0.08), false, 2.0)
	var inset := border_width + 8.0
	if size.x > inset * 4.0 and size.y > inset * 2.0:
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var c: Vector2 = corner
			draw_circle(c + (rect.get_center() - c).sign() * inset, 3.0, border_color)


func _draw_textured_panel(size: Vector2) -> void:
	if _panel_style == null:
		_panel_style = StyleBoxTexture.new()
		_panel_style.texture = panel_texture
		_panel_style.set_texture_margin_all(panel_margin)
		if tile_panel:
			_panel_style.texture_margin_left = 0.0
			_panel_style.texture_margin_right = 0.0
			_panel_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	if tile_panel and size.y > size.x:
		# Lay the tiled panel along the tall axis.
		draw_set_transform_matrix(_current_shape_xform * Transform2D(PI * 0.5, Vector2.ZERO))
		size = Vector2(size.y, size.x)
	draw_style_box(_panel_style, Rect2(-size * 0.5, size))


func _draw_disc(radius: float) -> void:
	if disc_texture != null:
		draw_texture_rect(disc_texture, Rect2(Vector2(-radius, -radius), Vector2(radius, radius) * 2.0), false)
		return
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius - border_width * 0.5, 0.0, TAU, 48, border_color, border_width, true)
	draw_circle(Vector2.ZERO, radius * 0.35, border_color)
