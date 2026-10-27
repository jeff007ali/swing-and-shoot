class_name HazardView
extends Node2D
## Draws the arena hazards from the sim each frame (§6.4): vent warning lamps and suction streaks
## (ARN-04), the black hole and its pull (ARN-10), the Closing Walls zone (ARN-09) and the Lights Out
## darkness, which leaves a pool of light around each fighter. Visual only.

const LAMP_RADIUS: float = 14.0
const STREAKS: int = 14
const LIGHT_RADIUS: float = 300.0
const MAX_LIGHTS: int = 8
## Lights Out fades in and out over this long (s).
const DARK_FADE: float = 0.6
const DARKNESS: float = 0.93

const DARK_SHADER: String = """
shader_type canvas_item;
uniform vec2 lights[8];
uniform int light_count = 0;
uniform float radius = 300.0;
uniform float darkness = 0.0;
varying vec2 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	float lit = 0.0;
	for (int i = 0; i < light_count; i++) {
		lit = max(lit, 1.0 - smoothstep(radius * 0.35, radius, distance(world, lights[i])));
	}
	COLOR = vec4(0.0, 0.0, 0.02, darkness * (1.0 - lit));
}
"""

var sim: MatchSim

var _dark: Node2D
var _dark_material: ShaderMaterial
var _darkness: float = 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_dark = Node2D.new()
	_dark.name = "LightsOut"
	_dark.z_index = 50
	var shader := Shader.new()
	shader.code = DARK_SHADER
	_dark_material = ShaderMaterial.new()
	_dark_material.shader = shader
	_dark.material = _dark_material
	_dark.draw.connect(_draw_dark)
	_dark.visible = false
	add_child(_dark)


func _process(delta: float) -> void:
	queue_redraw()
	if sim == null:
		return
	var target := 1.0 if sim.hazards.event_id == &"lights_out" else 0.0
	_darkness = move_toward(_darkness, target, delta / DARK_FADE)
	_dark.visible = _darkness > 0.0
	if _dark.visible:
		var lights := PackedVector2Array()
		for f in sim.fighters:
			if not f.is_ko() and lights.size() < MAX_LIGHTS:
				lights.append(f.view.global_position if f.view != null else f.global_position)
		var count := lights.size()
		lights.resize(MAX_LIGHTS)
		_dark_material.set_shader_parameter("lights", lights)
		_dark_material.set_shader_parameter("light_count", count)
		_dark_material.set_shader_parameter("radius", LIGHT_RADIUS)
		_dark_material.set_shader_parameter("darkness", _darkness * DARKNESS)
		_dark.queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var hz := sim.hazards
	var now := Time.get_ticks_msec() / 1000.0
	for i in hz.vents.size():
		_draw_vent(hz.vents[i], hz.vent_state(i, sim.tick), now)
	var r := hz.black_hole_radius(sim.tick)
	for hole in hz.black_holes:
		_draw_black_hole(hole, r, now)
	if hz.event_id == &"closing_walls":
		_draw_zone(hz.safe_zone(sim.tick), hz.bounds, now)


func _draw_vent(vent: Dictionary, state: HazardSystem.VentState, now: float) -> void:
	var at: Vector2 = vent["pos"]
	var out: Vector2 = vent["outward"]
	var side := out.orthogonal()
	var half: float = vent["width"] * 0.5
	var color := Color(0.3, 1.0, 0.45)
	match state:
		HazardSystem.VentState.WARNING:
			color = Color(1.0, 0.25, 0.15) if int(now * 6.0) % 2 == 0 else Color(0.35, 0.08, 0.05)
		HazardSystem.VentState.OPEN:
			color = Color(1.0, 0.2, 0.1)
	for s: float in [-1.0, 1.0]:
		var lamp := at + side * (half + LAMP_RADIUS + 6.0) * s - out * 4.0
		draw_circle(lamp, LAMP_RADIUS + 6.0, Color(color, 0.25))
		draw_circle(lamp, LAMP_RADIUS, color)
	if state != HazardSystem.VentState.OPEN:
		# Hazard stripes on the inside of the door.
		for k in 6:
			var a := at - out * 6.0 + side * lerpf(-half, half, (k + 0.5) / 6.0)
			draw_line(a - side * 12.0, a + side * 12.0 - out * 10.0, Color(1.0, 0.8, 0.1, 0.8), 5.0)
		return
	# Suction: streaks flowing toward the opening.
	var reach := TuningDB.t.vent_reach
	for k in STREAKS:
		var seed := float(k) * 1.618
		var travel := fposmod(now * 1.4 + seed, 1.0)
		var lateral := (fposmod(seed * 3.7, 2.0) - 1.0) * half * 1.6
		var start := at - out * reach * (1.0 - travel) + side * lateral * (1.0 - travel)
		var end := start + (at - start).normalized() * 50.0
		draw_line(start, end, Color(0.8, 0.9, 1.0, 0.5 * travel), 3.0, true)


func _draw_black_hole(at: Vector2, r: float, now: float) -> void:
	var t := TuningDB.t
	draw_circle(at, r * t.black_hole_influence, Color(0.5, 0.2, 0.8, 0.05))
	draw_arc(at, r * t.black_hole_influence, 0.0, TAU, 96, Color(0.6, 0.3, 1.0, 0.18), 2.0, true)
	for k in 4:
		var start := now * (1.2 + k * 0.3) + k * TAU / 4.0
		draw_arc(at, r * (1.25 + k * 0.22), start, start + 2.2, 32, Color(0.85, 0.5, 1.0, 0.55 - k * 0.1), 4.0, true)
	draw_circle(at, r * 1.12, Color(1.0, 0.6, 0.2, 0.6))
	draw_circle(at, r, Color(0.0, 0.0, 0.0))


func _draw_zone(zone: Rect2, bounds: Rect2, now: float) -> void:
	var outer := bounds.grow(400.0)
	var shade := Color(0.9, 0.1, 0.05, 0.22 + 0.06 * sin(now * 6.0))
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, zone.position.y - outer.position.y)), shade)
	draw_rect(Rect2(Vector2(outer.position.x, zone.end.y), Vector2(outer.size.x, outer.end.y - zone.end.y)), shade)
	draw_rect(Rect2(Vector2(outer.position.x, zone.position.y), Vector2(zone.position.x - outer.position.x, zone.size.y)), shade)
	draw_rect(Rect2(Vector2(zone.end.x, zone.position.y), Vector2(outer.end.x - zone.end.x, zone.size.y)), shade)
	draw_rect(zone, Color(1.0, 0.3, 0.2, 0.9), false, 8.0)


func _draw_dark() -> void:
	if sim == null:
		return
	var area := sim.hazards.bounds.grow(1600.0)
	_dark.draw_rect(area, Color.WHITE)
