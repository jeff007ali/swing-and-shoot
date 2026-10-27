class_name MathUtil
## Small pure helpers used by the simulation.


## Corrects a kick that points into a surface so that dot(dir, normal) >= min_dot,
## keeping its along-surface part (§4.4 kick rules).
static func correct_kick_dir(dir: Vector2, normal: Vector2, min_dot: float) -> Vector2:
	var d := dir.normalized()
	if d.dot(normal) >= min_dot:
		return d
	var tangent := d - normal * d.dot(normal)
	if tangent.length_squared() < 0.000001:
		return normal
	return tangent.normalized() * sqrt(1.0 - min_dot * min_dot) + normal * min_dot


## Velocity multiplier for exponential drag over one step (PHY-02).
static func drag_factor(drag: float, dt: float) -> float:
	return exp(-drag * dt)
