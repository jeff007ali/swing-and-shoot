class_name Arena
extends Node2D
## Root of an arena scene (§3.4, §4.2): geometry under any child, plus SpawnPoints and BotAnchors
## (Marker2D children). ArenaObjects are listed in tree order, which gives every device the same ids.
## Arenas may be bigger than the screen (D28); the camera then follows the local player.

@export var arena_name: String = ""
## The whole world, walls included. The camera stays inside it and the minimap draws it.
@export var bounds: Rect2 = Rect2(0, 0, 1920, 1080)
## "walls": the edges are solid. "wrap": leave one side, come back on the other (ARN-06).
@export var edge_mode: StringName = &"walls"
## Mid-match events this arena allows (§6.4): lights_out, vent_surge, closing_walls, debris_storm.
@export var events: Array[StringName] = []
## Background mood for views: station, asteroids, derelict, solar, singularity.
@export var theme: StringName = &"station"


func get_objects() -> Array[ArenaObject]:
	var found: Array[ArenaObject] = []
	_collect(self, found)
	return found


func get_spawn_points() -> Array[Vector2]:
	return _marker_positions(&"SpawnPoints")


func get_bot_anchors() -> Array[Vector2]:
	return _marker_positions(&"BotAnchors")


func get_hazards() -> Array[ArenaHazard]:
	var found: Array[ArenaHazard] = []
	var group := get_node_or_null(^"Hazards")
	if group != null:
		for child in group.get_children():
			if child is ArenaHazard:
				found.append(child)
	return found


## Where weapons appear (WPN-01).
func get_weapon_spawns() -> Array[Vector2]:
	return _marker_positions(&"WeaponSpawns")


func _collect(node: Node, found: Array[ArenaObject]) -> void:
	for child in node.get_children():
		if child is ArenaObject:
			found.append(child)
		_collect(child, found)


func _marker_positions(group_name: StringName) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var group := get_node_or_null(NodePath(group_name))
	if group == null:
		return points
	for child in group.get_children():
		var marker := child as Marker2D
		if marker != null:
			points.append(marker.global_position)
	return points
