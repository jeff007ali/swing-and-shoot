class_name ArenaRegistry
## Every playable arena by id: display name and scene. The main menu lists them in this order.

const ARENAS: Array[Dictionary] = [
	{"id": &"station", "name": "Station", "scene": "res://src/arenas/arena_02_station.tscn"},
	{"id": &"interior", "name": "Interior", "scene": "res://src/arenas/arena_03_interior.tscn"},
	{"id": &"asteroids", "name": "Asteroids", "scene": "res://src/arenas/arena_04_asteroids.tscn"},
	{"id": &"derelict", "name": "Derelict", "scene": "res://src/arenas/arena_05_derelict.tscn"},
	{"id": &"solar", "name": "Solar", "scene": "res://src/arenas/arena_06_solar.tscn"},
	{"id": &"singularity", "name": "Singularity", "scene": "res://src/arenas/arena_07_singularity.tscn"},
	{"id": &"hangar", "name": "Hangar", "scene": "res://src/arenas/arena_01_hangar.tscn"},
]
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


static func instantiate(arena_id: StringName) -> Arena:
	var scene := load(info(arena_id)["scene"]) as PackedScene
	return scene.instantiate() as Arena
