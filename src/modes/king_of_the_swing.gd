class_name KingOfTheSwing
extends GameMode
## King of the Swing (§6.5): a zone moves along a figure-eight through the arena (a plain loop
## around the middle when there is a black hole there). Being the only
## side inside it scores one point per tick; a contested zone scores nothing. Scores are kept in
## ticks and shown in seconds; the target is in seconds.

## Is the zone contested right now (for the view).
var contested: bool = false
## Score key holding the zone, or -1.
var holder: int = -1


func zone_center(tick: int) -> Vector2:
	var bounds := sim.hazards.bounds
	var a := TAU * float(tick - start_tick) / maxf(1.0, def.zone_period * SimIds.TICK_RATE)
	if not sim.hazards.black_holes.is_empty():
		return bounds.get_center() + Vector2(cos(a), sin(a)) * bounds.size * 0.33
	var r := bounds.size * Vector2(0.3, 0.26)
	return bounds.get_center() + Vector2(cos(a) * r.x, sin(2.0 * a) * r.y)


func on_tick(tick: int) -> void:
	var center := zone_center(tick)
	var inside: Array[int] = []
	for f in sim.fighters:
		if not f.is_ko() and f.global_position.distance_to(center) <= def.zone_radius:
			var k := key_of(f)
			if not inside.has(k):
				inside.append(k)
	contested = inside.size() > 1
	holder = inside[0] if inside.size() == 1 else -1
	if holder >= 0:
		scores[holder] = int(scores.get(holder, 0)) + 1


## KOs don't score here.
func on_ko(_victim: Fighter, _killer_id: int, _cause: StringName) -> void:
	pass


func target_points() -> int:
	return def.score_target * SimIds.TICK_RATE


func score_text(key: int) -> String:
	return "%d" % (int(scores.get(key, 0)) / SimIds.TICK_RATE)


func bot_goal(_f: Fighter, tick: int) -> Vector2:
	return zone_center(tick + SimIds.ticks(1.5))


func _get_extra() -> Dictionary:
	return {"contested": contested, "holder": holder}


func _set_extra(s: Dictionary) -> void:
	contested = s["contested"]
	holder = s["holder"]
