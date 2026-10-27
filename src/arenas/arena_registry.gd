class_name ArenaRegistry
## Every playable arena by id: display name, a one-line description for the menu, and scene. The main menu lists them in this order.

const ARENAS: Array[Dictionary] = [
	{"id": &"station", "name": "Station", "blurb": "Wide open, three spinning turbines.", "scene": "res://src/arenas/arena_02_station.tscn"},
	{"id": &"interior", "name": "Interior", "blurb": "Tight rooms and vents that suck you out.", "scene": "res://src/arenas/arena_03_interior.tscn"},
	{"id": &"asteroids", "name": "Asteroids", "blurb": "No walls: fly off one edge, come back on the other.", "scene": "res://src/arenas/arena_04_asteroids.tscn"},
	{"id": &"derelict", "name": "Derelict", "blurb": "A broken hull with electric edges.", "scene": "res://src/arenas/arena_05_derelict.tscn"},
	{"id": &"solar", "name": "Solar", "blurb": "Electric edges and drifting rocks.", "scene": "res://src/arenas/arena_06_solar.tscn"},
	{"id": &"singularity", "name": "Singularity", "blurb": "A black hole pulls everything in.", "scene": "res://src/arenas/arena_07_singularity.tscn"},
	{"id": &"hangar", "name": "Hangar", "blurb": "The small first arena.", "scene": "res://src/arenas/arena_01_hangar.tscn"},
]
## Menu thumbnails, made by tools/capture_arena_thumbs.gd.
const THUMBS: String = "res://assets/art/ui/arenas/%s.png"
const DEFAULT: StringName = &"station"


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for a in ARENAS:
		out.append(a["id"])
	return out


static func info(arena_id: StringName) -> Dictionary:
	for a in ARENAS:
		if a["id"] == arena_id:
			return a
	return ARENAS[0]


## The arena's menu thumbnail, or null if it hasn't been made yet.
static func thumbnail(arena_id: StringName) -> Texture2D:
	var path := THUMBS % arena_id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func instantiate(arena_id: StringName) -> Arena:
	var scene := load(info(arena_id)["scene"]) as PackedScene
	return scene.instantiate() as Arena
