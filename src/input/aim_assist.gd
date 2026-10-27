class_name AimAssist
## Rope aim assist (§4.5, CTL-06). Runs on the sender before the InputCommand is built, so the
## command already holds the final target and bots can skip it.
## Order: an enemy near the tap, then a floating weapon near the tap (both at their lead position,
## ROPE-02), then the nearest hookable surface. A tap on a turbine aims at its hub, so the hook hits
## the hub or an arm on the way instead of passing through a gap the arm has turned out of.

## Weapons are small and drift: they snap from a little farther than the aim-assist radius.
const WEAPON_RADIUS_MULT: float = 1.5
## Rope stick (D39): an enemy or weapon within this angle of the stick's direction is aimed at.
const DIRECTION_ASSIST_DEG: float = 12.0


## Rope stick aim: the enemy or floating weapon in rope range closest to dir (within
## DIRECTION_ASSIST_DEG), at its lead position; otherwise the point a full rope length along dir.
static func resolve_direction(shooter: Fighter, dir: Vector2, fighters: Array[Fighter], t: Tuning, items: Array[WeaponItem] = []) -> Vector2:
	var from := shooter.global_position
	var reach := t.rope_range + t.aim_assist_range_slack
	var max_angle := deg_to_rad(DIRECTION_ASSIST_DEG)
	var best := Vector2.INF
	var best_angle := max_angle
	for f in fighters:
		if f == shooter or not f.can_be_targeted():
			continue
		var offset := f.global_position - from
		var angle := absf(dir.angle_to(offset))
		if offset.length() <= reach and angle <= best_angle:
			best_angle = angle
			best = f.global_position + f.velocity * (offset.length() / t.hook_speed)
	for item in items:
		if item.state != WeaponItem.State.FLOATING:
			continue
		var offset := item.pos - from
		var angle := absf(dir.angle_to(offset))
		if offset.length() <= reach and angle < best_angle:
			best_angle = angle
			best = item.pos + item.vel * (offset.length() / t.hook_speed)
	if best != Vector2.INF:
		return best
	return from + dir.normalized() * t.rope_range


static func resolve(shooter: Fighter, point: Vector2, fighters: Array[Fighter], space: PhysicsDirectSpaceState2D, t: Tuning, items: Array[WeaponItem] = []) -> Vector2:
	# 1. Fighters first, aimed at their lead position.
	var best: Fighter = null
	var best_dist := INF
	for f in fighters:
		if f == shooter or not f.can_be_targeted():
			continue
		var d := f.global_position.distance_to(point)
		if d > t.aim_assist_radius or d >= best_dist:
			continue
		if shooter.global_position.distance_to(f.global_position) > t.rope_range + t.aim_assist_range_slack:
			continue
		best = f
		best_dist = d
	if best != null:
		var flight_time := shooter.global_position.distance_to(best.global_position) / t.hook_speed
		return best.global_position + best.velocity * flight_time
	# 2. Floating weapons.
	var best_item: WeaponItem = null
	best_dist = INF
	for item in items:
		if item.state != WeaponItem.State.FLOATING:
			continue
		var d := item.pos.distance_to(point)
		if d > t.aim_assist_radius * WEAPON_RADIUS_MULT or d >= best_dist:
			continue
		if shooter.global_position.distance_to(item.pos) > t.rope_range + t.aim_assist_range_slack:
			continue
		best_item = item
		best_dist = d
	if best_item != null:
		var flight_time := shooter.global_position.distance_to(best_item.pos) / t.hook_speed
		return best_item.pos + best_item.vel * flight_time
	# 3. Closest hookable surface near the tap; the hub of a turbine.
	var circle := CircleShape2D.new()
	circle.radius = t.aim_assist_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collision_mask = Layers.WORLD_HOOKABLE
	var info := space.get_rest_info(query)
	if not info.is_empty():
		var body := instance_from_id(info["collider_id"]) as RotatingBody
		if body != null:
			return body.global_position
		return info["point"]
	# 4. Exactly where the finger went.
	return point
