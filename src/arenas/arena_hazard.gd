class_name ArenaHazard
extends Node2D
## A hazard placed in an arena scene (§6.4): an airlock vent (ARN-04) or a black hole (ARN-10).
## HazardSystem reads these at match start; HazardView draws them.

## "vent" or "black_hole".
@export var kind: StringName = &"vent"
## Vent: direction out of the arena, through the opening.
@export var outward: Vector2 = Vector2.LEFT
## Vent: width of the opening (px).
@export var width: float = 240.0
## Vent: the door that closes the opening (an ArenaObject in the wall gap).
@export var door: NodePath
## Vent: shifts its cycle so several vents don't open together (s).
@export var cycle_offset: float = 0.0
