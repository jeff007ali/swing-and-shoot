class_name RotatingBody
extends ArenaObject
## Turbine-style obstacle (ROPE-05). Its angle is a pure function of the tick, so every device
## agrees without syncing (§3.1 rule 4). Use a StaticBody2D node, not AnimatableBody2D: see
## ArenaObject.sync_physics_transform().

@export var start_angle: float = 0.0
## 1 = clockwise on screen, -1 = counter-clockwise.
@export var spin_direction: float = 1.0


func _ready() -> void:
	is_moving = true
	super()


func step(tick: int) -> void:
	rotation = start_angle + spin_direction * TuningDB.t.turbine_omega * float(tick) / SimIds.TICK_RATE
	sync_physics_transform()
