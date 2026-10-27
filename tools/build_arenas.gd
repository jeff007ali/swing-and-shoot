extends SceneTree
## Builds the large arena scenes from the layouts below (D28, §6.4), so big maps stay easy to edit as
## data. Run: godot --headless --path . -s res://tools/build_arenas.gd
## The Hangar (arena_01) is hand-made and not touched.
##
## Arena keys: name, size, spawns, weapon_spawns, objects, and optionally
##   edges: "walls" | "electric" | "wrap"   (ARN-05, ARN-06)
##   theme: station | asteroids | derelict | solar | singularity   (look only)
##   events: mid-match events allowed (§6.4)
##   background: texture path, tint: Color for walls and boxes
## Object entries (positions in world px, origin top-left; trailing options dict optional):
##   ["box", center, size, {surface: "smooth"|"electric", hp: float, rot: radians}]
##   ["asteroid", center, radius, meteor 1..4]          round, orbit pivot
##   ["drifter", orbit_center, radius, radii, period_s, phase, meteor]   moving asteroid (ARN-02)
##   ["turbine", center, spin_direction]                hub r45 + 3 arms 170 x 30
##   ["tank", center, radius]                           fuel tank, explodes when shot (ARN-08)
##   ["vent", side "left"|"right"|"top"|"bottom", along, width, cycle_offset_s]   airlock (ARN-04)
##   ["black_hole", center]                             grows over the match (ARN-10)
## Walls (40 px) go around the bounds unless edges is "wrap"; vents cut gaps into them, closed by a
## smooth door. Bot anchors are generated on grippable faces: walls every ANCHOR_SPACING px, box
## faces, asteroid and tank sides.

const OUT_DIR: String = "res://src/arenas/"
const WALL_THICKNESS: float = 40.0
const ANCHOR_SPACING: float = 560.0

const WALL_TEX: String = "res://assets/art/arena/spaceStation_003.png"
const BOX_TEX: String = "res://assets/art/arena/spaceBuilding_006.png"
const ARM_TEX: String = "res://assets/art/arena/spaceBuilding_005.png"
const HUB_TEX: String = "res://assets/art/atlas/arena/spaceBuilding_009.tres"
const METEOR_TEX: String = "res://assets/art/atlas/arena/spaceMeteors_00%d.tres"
const BG_DARK_PURPLE: String = "res://assets/art/arena/darkPurple.png"
const BG_BLUE: String = "res://assets/art/arena/blue.png"
const BG_BLACK: String = "res://assets/art/arena/black.png"
const BG_PURPLE: String = "res://assets/art/arena/purple.png"

const ARENA_BASE: String = "res://src/arenas/arena_base.gd"
const ARENA_OBJECT: String = "res://src/sim/arena_object.gd"
const ROTATING_BODY: String = "res://src/sim/rotating_body.gd"
const DRIFTING_BODY: String = "res://src/sim/drifting_body.gd"
const ARENA_HAZARD: String = "res://src/arenas/arena_hazard.gd"
const STARFIELD: String = "res://src/arenas/starfield.gd"

const LAYOUTS: Dictionary = {
	"arena_02_station": {
		"name": "Station",
		"size": Vector2(3840, 2160),
		"spawns": [Vector2(220, 220), Vector2(3620, 220), Vector2(220, 1940), Vector2(3620, 1940), Vector2(1330, 1080), Vector2(2510, 1080)],
		"weapon_spawns": [Vector2(1920, 820), Vector2(1920, 1340), Vector2(900, 560), Vector2(2940, 1600), Vector2(660, 1500), Vector2(3180, 620)],
		"events": [&"lights_out", &"debris_storm"],
		"objects": [
			["turbine", Vector2(1920, 1080), 1.0],
			["turbine", Vector2(880, 1080), -1.0],
			["turbine", Vector2(2960, 1080), -1.0],
			["box", Vector2(1920, 540), Vector2(380, 70)],
			["box", Vector2(1920, 1620), Vector2(380, 70)],
			["box", Vector2(560, 360), Vector2(240, 90)],
			["box", Vector2(3280, 360), Vector2(240, 90)],
			["box", Vector2(560, 1800), Vector2(240, 90)],
			["box", Vector2(3280, 1800), Vector2(240, 90)],
			["box", Vector2(1380, 300), Vector2(90, 220)],
			["box", Vector2(2460, 1860), Vector2(90, 220)],
			["asteroid", Vector2(1920, 220), 48.0, 3],
			["asteroid", Vector2(1920, 1940), 48.0, 4],
			["asteroid", Vector2(330, 760), 58.0, 1],
			["asteroid", Vector2(3510, 1400), 58.0, 2],
			["asteroid", Vector2(330, 1400), 50.0, 2],
			["asteroid", Vector2(3510, 760), 50.0, 1],
			["asteroid", Vector2(1180, 1840), 42.0, 4],
			["asteroid", Vector2(2660, 320), 42.0, 3],
			["asteroid", Vector2(2400, 760), 36.0, 1],
			["asteroid", Vector2(1440, 1400), 36.0, 2],
		],
	},
	"arena_03_interior": {
		"name": "Station Interior",
		"theme": &"station",
		"background": BG_BLUE,
		"size": Vector2(3200, 1800),
		"events": [&"lights_out", &"vent_surge", &"closing_walls"],
		"spawns": [Vector2(220, 220), Vector2(2980, 220), Vector2(220, 1580), Vector2(2980, 1580)],
		"weapon_spawns": [Vector2(1250, 900), Vector2(1950, 900), Vector2(720, 380), Vector2(2480, 1420), Vector2(1600, 300)],
		"objects": [
			["vent", "left", 900.0, 260.0, 0.0],
			["vent", "right", 900.0, 260.0, 7.0],
			["box", Vector2(775, 600), Vector2(950, 50)],
			["box", Vector2(2425, 600), Vector2(950, 50)],
			["box", Vector2(775, 1200), Vector2(950, 50)],
			["box", Vector2(2425, 1200), Vector2(950, 50)],
			["box", Vector2(900, 900), Vector2(50, 300), {"surface": "smooth"}],
			["box", Vector2(2300, 900), Vector2(50, 300), {"surface": "smooth"}],
			["turbine", Vector2(1600, 900), 1.0],
			["box", Vector2(1600, 300), Vector2(150, 150), {"hp": 40.0}],
			["box", Vector2(1600, 1500), Vector2(150, 150), {"hp": 40.0}],
			["box", Vector2(500, 320), Vector2(140, 140), {"hp": 40.0}],
			["box", Vector2(2700, 1480), Vector2(140, 140), {"hp": 40.0}],
			["box", Vector2(1100, 330), Vector2(220, 60)],
			["box", Vector2(2100, 1470), Vector2(220, 60)],
			["box", Vector2(1100, 1470), Vector2(220, 60)],
			["box", Vector2(2100, 330), Vector2(220, 60)],
			["tank", Vector2(460, 900), 42.0],
			["tank", Vector2(2740, 900), 42.0],
			["tank", Vector2(1600, 640), 36.0],
		],
	},
	"arena_04_asteroids": {
		"name": "Asteroid Field",
		"theme": &"asteroids",
		"background": BG_BLACK,
		"edges": "wrap",
		"size": Vector2(3600, 2000),
		"events": [&"debris_storm", &"lights_out"],
		"spawns": [Vector2(400, 400), Vector2(3200, 400), Vector2(400, 1600), Vector2(3200, 1600)],
		"weapon_spawns": [Vector2(1800, 1000), Vector2(900, 1000), Vector2(2700, 1000), Vector2(1800, 300), Vector2(1800, 1700)],
		"objects": [
			["asteroid", Vector2(700, 300), 70.0, 1],
			["asteroid", Vector2(1300, 600), 55.0, 2],
			["asteroid", Vector2(1900, 250), 45.0, 3],
			["asteroid", Vector2(2500, 600), 80.0, 4],
			["asteroid", Vector2(3100, 280), 50.0, 1],
			["asteroid", Vector2(300, 1000), 60.0, 2],
			["asteroid", Vector2(1100, 1250), 85.0, 3],
			["asteroid", Vector2(2300, 1350), 60.0, 1],
			["asteroid", Vector2(3300, 1000), 70.0, 4],
			["asteroid", Vector2(700, 1750), 50.0, 2],
			["asteroid", Vector2(1700, 1700), 65.0, 4],
			["asteroid", Vector2(2900, 1700), 55.0, 3],
			["drifter", Vector2(1800, 1000), 60.0, Vector2(500, 260), 22.0, 0.0, 2],
			["drifter", Vector2(900, 750), 45.0, Vector2(260, 200), -16.0, 1.0, 1],
			["drifter", Vector2(2700, 1150), 50.0, Vector2(300, 220), 18.0, 2.5, 3],
			["drifter", Vector2(1500, 1450), 40.0, Vector2(380, 120), -14.0, 4.0, 4],
			["turbine", Vector2(1800, 600), -1.0],
			["tank", Vector2(600, 1200), 38.0],
			["tank", Vector2(3000, 750), 38.0],
		],
	},
	"arena_05_derelict": {
		"name": "Derelict Ship",
		"theme": &"derelict",
		"background": BG_DARK_PURPLE,
		"tint": Color(0.85, 0.62, 0.5),
		"edges": "electric",
		"size": Vector2(3400, 1900),
		"events": [&"lights_out", &"closing_walls", &"vent_surge"],
		"spawns": [Vector2(300, 300), Vector2(3100, 300), Vector2(300, 1600), Vector2(3100, 1600)],
		"weapon_spawns": [Vector2(1700, 950), Vector2(800, 500), Vector2(2600, 1400), Vector2(1700, 300), Vector2(1700, 1600)],
		"objects": [
			["vent", "bottom", 1700.0, 300.0, 3.0],
			["turbine", Vector2(1000, 950), 1.0],
			["turbine", Vector2(2400, 950), -1.0],
			["box", Vector2(1700, 950), Vector2(120, 380), {"surface": "smooth"}],
			["box", Vector2(600, 450), Vector2(380, 60), {"hp": 35.0, "rot": 0.25}],
			["box", Vector2(2800, 1450), Vector2(380, 60), {"hp": 35.0, "rot": 0.25}],
			["box", Vector2(2800, 450), Vector2(380, 60), {"hp": 35.0, "rot": -0.25}],
			["box", Vector2(600, 1450), Vector2(380, 60), {"hp": 35.0, "rot": -0.25}],
			["box", Vector2(1700, 420), Vector2(500, 60)],
			["box", Vector2(1700, 1480), Vector2(500, 60)],
			["box", Vector2(1200, 250), Vector2(60, 260), {"hp": 30.0}],
			["box", Vector2(2200, 1650), Vector2(60, 260), {"hp": 30.0}],
			["box", Vector2(1000, 250), Vector2(220, 60)],
			["box", Vector2(2400, 1650), Vector2(220, 60)],
			["box", Vector2(250, 600), Vector2(60, 220)],
			["box", Vector2(3150, 1300), Vector2(60, 220)],
			["box", Vector2(400, 950), Vector2(60, 400), {"surface": "smooth"}],
			["box", Vector2(3000, 950), Vector2(60, 400), {"surface": "smooth"}],
			["asteroid", Vector2(1250, 1500), 45.0, 2],
			["asteroid", Vector2(2150, 400), 45.0, 3],
			["tank", Vector2(1700, 700), 36.0],
			["tank", Vector2(1700, 1200), 36.0],
		],
	},
	"arena_06_solar": {
		"name": "Solar Platform",
		"theme": &"solar",
		"background": BG_PURPLE,
		"tint": Color(1.0, 0.85, 0.6),
		"edges": "electric",
		"size": Vector2(3600, 2000),
		"events": [&"closing_walls", &"debris_storm"],
		"spawns": [Vector2(350, 350), Vector2(3250, 350), Vector2(350, 1650), Vector2(3250, 1650)],
		"weapon_spawns": [Vector2(1800, 1000), Vector2(1000, 600), Vector2(2600, 1400), Vector2(1000, 1400), Vector2(2600, 600)],
		"objects": [
			["box", Vector2(1000, 500), Vector2(560, 50), {"surface": "smooth"}],
			["box", Vector2(2600, 500), Vector2(560, 50), {"surface": "smooth"}],
			["box", Vector2(1000, 1500), Vector2(560, 50), {"surface": "smooth"}],
			["box", Vector2(2600, 1500), Vector2(560, 50), {"surface": "smooth"}],
			["box", Vector2(1800, 1000), Vector2(260, 260)],
			["box", Vector2(600, 1000), Vector2(200, 80)],
			["box", Vector2(3000, 1000), Vector2(200, 80)],
			["box", Vector2(1800, 300), Vector2(300, 60)],
			["box", Vector2(1800, 1700), Vector2(300, 60)],
			["box", Vector2(250, 1650), Vector2(60, 240)],
			["box", Vector2(3350, 350), Vector2(60, 240)],
			["asteroid", Vector2(1200, 1000), 50.0, 1],
			["asteroid", Vector2(2400, 1000), 50.0, 2],
			["asteroid", Vector2(400, 600), 45.0, 3],
			["asteroid", Vector2(3200, 1400), 45.0, 4],
			["drifter", Vector2(1800, 1000), 40.0, Vector2(700, 520), 26.0, 0.0, 3],
			["drifter", Vector2(1800, 1000), 40.0, Vector2(700, 520), 26.0, PI, 4],
			["tank", Vector2(1450, 700), 36.0],
			["tank", Vector2(2150, 1300), 36.0],
		],
	},
	"arena_07_singularity": {
		"name": "Singularity",
		"theme": &"singularity",
		"background": BG_BLACK,
		"size": Vector2(3200, 2000),
		"events": [&"debris_storm", &"lights_out"],
		"spawns": [Vector2(250, 250), Vector2(2950, 250), Vector2(250, 1750), Vector2(2950, 1750)],
		"weapon_spawns": [Vector2(900, 1000), Vector2(2300, 1000), Vector2(1600, 400), Vector2(1600, 1600)],
		"objects": [
			["black_hole", Vector2(1600, 1000)],
			["asteroid", Vector2(1100, 600), 55.0, 1],
			["asteroid", Vector2(2100, 600), 55.0, 2],
			["asteroid", Vector2(1100, 1400), 55.0, 3],
			["asteroid", Vector2(2100, 1400), 55.0, 4],
			["asteroid", Vector2(700, 1000), 45.0, 2],
			["asteroid", Vector2(2500, 1000), 45.0, 1],
			["box", Vector2(1600, 300), Vector2(400, 60)],
			["box", Vector2(1600, 1700), Vector2(400, 60)],
			["box", Vector2(450, 450), Vector2(220, 80)],
			["box", Vector2(2750, 1550), Vector2(220, 80)],
			["box", Vector2(2750, 450), Vector2(220, 80)],
			["box", Vector2(450, 1550), Vector2(220, 80)],
			["turbine", Vector2(1600, 1000) + Vector2(-600, 0), 1.0],
			["tank", Vector2(1600, 650), 34.0],
		],
	},
}


func _initialize() -> void:
	for scene_name: String in LAYOUTS:
		_build(scene_name, LAYOUTS[scene_name])
	quit()


func _build(scene_name: String, layout: Dictionary) -> void:
	var size: Vector2 = layout["size"]
	var edges: String = layout.get("edges", "walls")
	var tint: Color = layout.get("tint", Color.WHITE)
	var root := Node2D.new()
	root.name = scene_name.to_pascal_case()
	root.set_script(load(ARENA_BASE))
	root.set("arena_name", layout["name"])
	root.set("bounds", Rect2(Vector2.ZERO, size))
	root.set("edge_mode", &"wrap" if edges == "wrap" else &"walls")
	root.set("theme", layout.get("theme", &"station"))
	var events: Array[StringName] = []
	for e in layout.get("events", []):
		events.append(e)
	root.set("events", events)

	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = load(layout.get("background", BG_DARK_PURPLE))
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.region_enabled = true
	bg.region_rect = Rect2(Vector2.ZERO, size + Vector2(1600, 800))
	bg.position = size * 0.5
	_add(root, root, bg)
	var stars := Node2D.new()
	stars.name = "Starfield"
	stars.set_script(load(STARFIELD))
	_add(root, root, stars)

	var anchors: Array[Vector2] = []
	var vents: Array = layout["objects"].filter(func(e: Array) -> bool: return e[0] == "vent")
	var hazards := _group(root, "Hazards")
	if edges != "wrap":
		_build_walls(root, size, edges, tint, vents, hazards, anchors)

	var obstacles := _group(root, "Obstacles")
	var counts := {}
	for entry: Array in layout["objects"]:
		var kind: String = entry[0]
		if kind == "vent":
			continue
		counts[kind] = counts.get(kind, 0) + 1
		var node_name := "%s%d" % [kind.to_pascal_case(), counts[kind]]
		match kind:
			"box":
				var opts: Dictionary = entry[3] if entry.size() > 3 else {}
				_box(root, obstacles, node_name, entry[1], entry[2], opts, tint, anchors)
			"asteroid":
				var center: Vector2 = entry[1]
				var radius: float = entry[2]
				_asteroid(root, obstacles, node_name, center, radius, entry[3])
				anchors.append(center + Vector2(-radius, 0))
				anchors.append(center + Vector2(radius, 0))
			"drifter":
				_drifter(root, obstacles, node_name, entry)
			"turbine":
				_turbine(root, obstacles, node_name, entry[1], entry[2])
			"tank":
				var center: Vector2 = entry[1]
				var radius: float = entry[2]
				_tank(root, obstacles, node_name, center, radius)
				anchors.append(center + Vector2(-radius, 0))
				anchors.append(center + Vector2(radius, 0))
			"black_hole":
				var hole := Node2D.new()
				hole.set_script(load(ARENA_HAZARD))
				hole.name = node_name
				hole.position = entry[1]
				hole.set("kind", &"black_hole")
				_add(root, hazards, hole)

	var spawns := _group(root, "SpawnPoints")
	for i in layout["spawns"].size():
		_marker(root, spawns, "Spawn%d" % (i + 1), layout["spawns"][i])
	var weapon_group := _group(root, "WeaponSpawns")
	var weapon_spawns: Array = layout.get("weapon_spawns", [])
	for i in weapon_spawns.size():
		_marker(root, weapon_group, "Weapon%d" % (i + 1), weapon_spawns[i])
	var anchor_group := _group(root, "BotAnchors")
	for i in anchors.size():
		_marker(root, anchor_group, "Anchor%d" % (i + 1), anchors[i])

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_DIR + scene_name + ".tscn")
	print("%s: %d objects, %d anchors, edges %s -> %s" % [scene_name, layout["objects"].size(), anchors.size(), edges, error_string(err)])
	root.free()


## Four walls, split around vent openings; each opening gets a smooth door and an ArenaHazard.
func _build_walls(root: Node, size: Vector2, edges: String, tint: Color, vents: Array, hazards: Node, anchors: Array[Vector2]) -> void:
	var walls := _group(root, "Walls")
	var t := WALL_THICKNESS
	var surface := &"electric" if edges == "electric" else &"normal"
	var sides := {
		"top": {"axis": 0, "length": size.x, "fixed": t * 0.5, "inner": t, "outward": Vector2.UP},
		"bottom": {"axis": 0, "length": size.x, "fixed": size.y - t * 0.5, "inner": size.y - t, "outward": Vector2.DOWN},
		"left": {"axis": 1, "length": size.y, "fixed": t * 0.5, "inner": t, "outward": Vector2.LEFT},
		"right": {"axis": 1, "length": size.y, "fixed": size.x - t * 0.5, "inner": size.x - t, "outward": Vector2.RIGHT},
	}
	var vent_count := 0
	for side: String in sides:
		var info: Dictionary = sides[side]
		var gaps: Array = []
		for v: Array in vents:
			if v[1] == side:
				gaps.append(v)
		gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
		var cursor := 0.0
		var segment := 0
		for g: Array in gaps:
			var along: float = g[2]
			var width: float = g[3]
			_wall_segment(root, walls, side, segment, info, cursor, along - width * 0.5, surface, tint)
			segment += 1
			cursor = along + width * 0.5
			vent_count += 1
			var door := _wall_segment(root, walls, "%sVentDoor" % side, vent_count, info, along - width * 0.5, along + width * 0.5, &"smooth", tint)
			var hazard := Node2D.new()
			hazard.set_script(load(ARENA_HAZARD))
			hazard.name = "Vent%d" % vent_count
			hazard.position = _point_on(info, along, info["inner"])
			hazard.set("kind", &"vent")
			hazard.set("outward", info["outward"])
			hazard.set("width", width)
			hazard.set("cycle_offset", g[4])
			_add(root, hazards, hazard)
			hazard.set("door", hazard.get_path_to(door))
		_wall_segment(root, walls, side, segment, info, cursor, info["length"], surface, tint)
		if surface == &"normal":
			for a in _spread(t, float(info["length"]) - t):
				var inside := true
				for g: Array in gaps:
					if absf(a - float(g[2])) < float(g[3]) * 0.5 + 60.0:
						inside = false
				if inside:
					anchors.append(_point_on(info, a, info["inner"]))


func _point_on(info: Dictionary, along: float, across: float) -> Vector2:
	return Vector2(along, across) if info["axis"] == 0 else Vector2(across, along)


func _wall_segment(root: Node, parent: Node, side: String, index: int, info: Dictionary, from: float, to: float, surface: StringName, tint: Color) -> ArenaObject:
	if to - from < 1.0:
		return null
	var length := to - from
	var center := _point_on(info, from + length * 0.5, info["fixed"])
	var size := Vector2(length, WALL_THICKNESS) if info["axis"] == 0 else Vector2(WALL_THICKNESS, length)
	var body := _body(ARENA_OBJECT)
	body.name = "%s%d" % [side.to_pascal_case(), index]
	body.position = center
	body.set("surface_type", surface)
	body.set("panel_texture", load(WALL_TEX))
	body.set("panel_margin", 10.0)
	body.set("tile_panel", true)
	body.modulate = tint
	_add(root, parent, body)
	_rect_shape(root, body, size)
	return body as ArenaObject


## Points every ANCHOR_SPACING along [low, high], centered, skipping the corners.
func _spread(low: float, high: float) -> Array[float]:
	var out: Array[float] = []
	var n := int((high - low) / ANCHOR_SPACING)
	var step := (high - low) / float(n + 1)
	for i in n:
		out.append(low + step * (i + 1))
	return out


func _add(root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = root


func _group(root: Node, group_name: String) -> Node2D:
	var g := Node2D.new()
	g.name = group_name
	_add(root, root, g)
	return g


func _body(script_path: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.set_script(load(script_path))
	return body


func _rect_shape(root: Node, body: Node, size: Vector2, at: Vector2 = Vector2.ZERO, rotation: float = 0.0, shape_name: String = "Shape") -> void:
	var cs := CollisionShape2D.new()
	cs.name = shape_name
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	cs.position = at
	cs.rotation = rotation
	_add(root, body, cs)


func _circle_shape(root: Node, body: Node, radius: float) -> void:
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	_add(root, body, cs)


func _box(root: Node, parent: Node, box_name: String, center: Vector2, size: Vector2, opts: Dictionary, tint: Color, anchors: Array[Vector2]) -> void:
	var body := _body(ARENA_OBJECT)
	body.name = box_name
	body.position = center
	body.rotation = opts.get("rot", 0.0)
	var surface: StringName = StringName(opts.get("surface", "normal"))
	body.set("surface_type", surface)
	body.set("max_hp", opts.get("hp", 0.0))
	body.set("panel_texture", load(BOX_TEX))
	body.set("panel_margin", 22.0)
	body.modulate = tint
	_add(root, parent, body)
	_rect_shape(root, body, size)
	if surface != &"normal":
		return
	var half := size * 0.5
	var faces: Array[Vector2] = []
	if size.x >= size.y:
		faces.append_array([Vector2(0, -half.y), Vector2(0, half.y)])
	else:
		faces.append_array([Vector2(-half.x, 0), Vector2(half.x, 0)])
	for f in faces:
		anchors.append(center + f.rotated(body.rotation))


func _asteroid(root: Node, parent: Node, asteroid_name: String, center: Vector2, radius: float, meteor: int, script_path: String = ARENA_OBJECT) -> StaticBody2D:
	var body := _body(script_path)
	body.name = asteroid_name
	body.position = center
	body.set("orbit_pivot", true)
	body.set("draw_shapes", false)
	_add(root, parent, body)
	_circle_shape(root, body, radius)
	var art := Sprite2D.new()
	art.name = "Art"
	var tex := load(METEOR_TEX % meteor) as Texture2D
	art.texture = tex
	art.scale = Vector2.ONE * (radius * 2.0 * 1.06 / tex.get_width())
	art.rotation = fposmod(center.x * 0.013 + center.y * 0.007, TAU)
	_add(root, body, art)
	return body


func _drifter(root: Node, parent: Node, drifter_name: String, entry: Array) -> void:
	var orbit_center: Vector2 = entry[1]
	var radii: Vector2 = entry[3]
	var phase: float = entry[5]
	var start := orbit_center + Vector2(cos(phase) * radii.x, sin(phase) * radii.y)
	var body := _asteroid(root, parent, drifter_name, start, entry[2], entry[6], DRIFTING_BODY)
	body.set("orbit_center", orbit_center)
	body.set("orbit_radii", radii)
	body.set("period", entry[4])
	body.set("phase", phase)


func _turbine(root: Node, parent: Node, turbine_name: String, center: Vector2, spin: float) -> void:
	var body := _body(ROTATING_BODY)
	body.name = turbine_name
	body.position = center
	body.set("spin_direction", spin)
	body.set("fill_color", Color(0.33, 0.2, 0.12, 1))
	body.set("border_color", Color(1, 0.62, 0.25, 1))
	body.set("panel_texture", load(ARM_TEX))
	body.set("panel_margin", 12.0)
	body.set("disc_texture", load(HUB_TEX))
	_add(root, parent, body)
	for i in 3:
		var a := TAU / 3.0 * i
		_rect_shape(root, body, Vector2(170, 30), Vector2(85, 0).rotated(a), a, "Arm%d" % (i + 1))
	var hub := CollisionShape2D.new()
	hub.name = "Hub"
	var circle := CircleShape2D.new()
	circle.radius = 45.0
	hub.shape = circle
	_add(root, body, hub)


func _tank(root: Node, parent: Node, tank_name: String, center: Vector2, radius: float) -> void:
	var body := _body(ARENA_OBJECT)
	body.name = tank_name
	body.position = center
	body.set("explosive", true)
	body.set("fill_color", Color(0.75, 0.12, 0.08))
	body.set("border_color", Color(1, 0.85, 0.15))
	_add(root, parent, body)
	_circle_shape(root, body, radius)


func _marker(root: Node, parent: Node, marker_name: String, at: Vector2) -> void:
	var m := Marker2D.new()
	m.name = marker_name
	m.position = at
	_add(root, parent, m)
