class_name HotPotato
extends GameMode
## Hot Potato (§6.5): a bomb sticks to one fighter and passes only when its carrier hooks or hits
## someone. When the fuse runs out it blows up its carrier and everyone else still standing scores a
## point. A new bomb arrives a few seconds later on a random fighter. KOs don't score.

## Seconds before the first bomb and between bombs.
const FIRST_BOMB: float = 3.0
const NEXT_BOMB: float = 3.0
## The new carrier can't hand it straight back for this long (s).
const PASS_COOLDOWN: float = 0.8
const BLAST_RADIUS: float = 320.0
const BLAST_KNOCKBACK: float = 1300.0

var holder_id: int = -1
var fuse_end: int = SimIds.NO_TICK
var fuse_length: int = 1
var pass_ready: int = 0
var next_bomb: int = 0


func start(tick: int) -> void:
	super.start(tick)
	next_bomb = tick + SimIds.ticks(FIRST_BOMB)


func on_tick(tick: int) -> void:
	if not sim.authoritative:
		return
	if holder_id < 0:
		if tick >= next_bomb:
			_give_new_bomb(tick)
		return
	var holder := sim.get_fighter(holder_id)
	if holder == null or holder.is_ko():
		_drop_bomb(tick)
	elif tick >= fuse_end:
		_explode(holder, tick)


## 0..1 of the fuse left, for the view.
func fuse_fraction(tick: int) -> float:
	if holder_id < 0:
		return 0.0
	return clampf(float(fuse_end - tick) / float(fuse_length), 0.0, 1.0)


func on_contact(attacker: Fighter, victim: Fighter, _kind: StringName) -> void:
	if attacker.fighter_id != holder_id or victim.is_ko() or sim.tick < pass_ready:
		return
	holder_id = victim.fighter_id
	pass_ready = sim.tick + SimIds.ticks(PASS_COOLDOWN)
	sim.queue_event(&"bomb_passed", [attacker.fighter_id, victim.fighter_id])


func on_ko(victim: Fighter, _killer_id: int, _cause: StringName) -> void:
	if victim.fighter_id == holder_id:
		_drop_bomb(sim.tick)


func _give_new_bomb(tick: int) -> void:
	var alive: Array[Fighter] = []
	for f in sim.fighters:
		if not f.is_ko():
			alive.append(f)
	if alive.size() < 2:
		return
	holder_id = alive[sim.rng.randi_range(0, alive.size() - 1)].fighter_id
	fuse_length = maxi(1, SimIds.ticks(sim.rng.randf_range(def.fuse_min, def.fuse_max)))
	fuse_end = tick + fuse_length
	pass_ready = tick + SimIds.ticks(PASS_COOLDOWN)
	sim.queue_event(&"bomb_passed", [-1, holder_id])


func _drop_bomb(tick: int) -> void:
	holder_id = -1
	next_bomb = tick + SimIds.ticks(NEXT_BOMB)


func _explode(holder: Fighter, tick: int) -> void:
	var at := holder.global_position
	sim.queue_event(&"bomb_exploded", [holder.fighter_id, at])
	for f in sim.fighters:
		if f == holder or f.is_ko():
			continue
		var k := key_of(f)
		scores[k] = int(scores.get(k, 0)) + 1
		var offset := f.global_position - at
		if offset.length() < BLAST_RADIUS:
			f.velocity += offset.normalized() * BLAST_KNOCKBACK * (1.0 - offset.length() / BLAST_RADIUS)
	_drop_bomb(tick)
	holder.knock_out(tick, -1, &"bomb")


func bot_goal(f: Fighter, _tick: int) -> Vector2:
	var holder := sim.get_fighter(holder_id)
	if holder == null or holder.is_ko():
		return Vector2.INF
	if f == holder:
		var best := Vector2.INF
		for other in sim.fighters:
			if other != f and not other.is_ko() and f.global_position.distance_to(other.global_position) < f.global_position.distance_to(best):
				best = other.global_position
		return best
	# Everyone else keeps away from the carrier.
	var away := (f.global_position - holder.global_position).normalized()
	var bounds := sim.hazards.bounds.grow(-200.0)
	var goal := f.global_position + away * 900.0
	return Vector2(clampf(goal.x, bounds.position.x, bounds.end.x), clampf(goal.y, bounds.position.y, bounds.end.y))


func _get_extra() -> Dictionary:
	return {"holder": holder_id, "fuse_end": fuse_end, "fuse_length": fuse_length, "pass_ready": pass_ready, "next": next_bomb}


func _set_extra(s: Dictionary) -> void:
	holder_id = s["holder"]
	fuse_end = s["fuse_end"]
	fuse_length = s["fuse_length"]
	pass_ready = s["pass_ready"]
	next_bomb = s["next"]
