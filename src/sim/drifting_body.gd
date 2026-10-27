class_name DriftingBody
extends ArenaObject
## A drifting asteroid (ARN-02): a moving anchor and a hazard. It loops an ellipse around orbit_center;
## its position is a pure function of the tick, so every device agrees without syncing (§3.1 rule 4).
## HazardSystem shoves and damages fighters it runs into.

@export var orbit_center: Vector2 = Vector2.ZERO
@export var orbit_radii: Vector2 = Vector2(300, 150)
## Seconds per loop; negative goes the other way.
@export var period: float = 20.0
@export var phase: float = 0.0

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	is_moving = true
	super()


func step(tick: int) -> void:
	var w := TAU / period
	var a := phase + w * float(tick) / SimIds.TICK_RATE
	position = orbit_center + Vector2(cos(a) * orbit_radii.x, sin(a) * orbit_radii.y)
	velocity = Vector2(-sin(a) * orbit_radii.x, cos(a) * orbit_radii.y) * w
	rotation = a * 0.3
	sync_physics_transform()
