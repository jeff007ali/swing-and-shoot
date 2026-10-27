class_name GunGame
extends GameMode
## Gun Game (§6.5): every fighter starts on the first weapon of ModeDef.weapon_sequence and moves
## to the next with each KO. After the last weapon they are unarmed, and the winning KO must be a
## melee hit. Weapons are handed out by the mode: no normal spawns, no picking up others' weapons.
## The score is the level reached.

## fighter id -> level (index into the sequence; == sequence size means unarmed, final kill)
var levels: Dictionary = {}


func start(tick: int) -> void:
	super.start(tick)
	sim.weapons.spawning = false
	levels.clear()
	for f in sim.fighters:
		levels[f.fighter_id] = 0


func on_tick(tick: int) -> void:
	if not sim.authoritative:
		return
	# Loose weapons (dropped, thrown) vanish: you only use your own level's weapon.
	for item in sim.weapons.items.duplicate():
		if item.state != WeaponItem.State.HELD:
			sim.weapons.discard(item)
	for f in sim.fighters:
		if f.is_ko():
			continue
		var want := weapon_for(f)
		var held := sim.weapons.held_by(f)
		if held != null and (want.is_empty() or held.def.id != want):
			sim.weapons.discard(held)
			held = null
		if held == null and not want.is_empty():
			var def := WeaponDef.load_by_id(want)
			if def != null:
				sim.weapons.equip(f, sim.weapons.spawn(def, f.global_position))


## The weapon id for f's level, or empty at the final (melee) level.
func weapon_for(f: Fighter) -> StringName:
	var level: int = levels.get(f.fighter_id, 0)
	return def.weapon_sequence[level] if level < def.weapon_sequence.size() else &""


func on_ko(victim: Fighter, killer_id: int, cause: StringName) -> void:
	var killer := sim.get_fighter(killer_id)
	if killer == null or killer == victim or not sim.are_enemies(killer, victim):
		return
	var level: int = levels.get(killer_id, 0)
	if level >= def.weapon_sequence.size() and cause != &"melee":
		return
	levels[killer_id] = level + 1
	scores[key_of(killer)] = levels[killer_id]
	sim.queue_event(&"level_up", [killer_id, level + 1])


func target_points() -> int:
	return def.weapon_sequence.size() + 1


func score_text(key: int) -> String:
	return "%d/%d" % [int(scores.get(key, 0)), target_points()]


func _get_extra() -> Dictionary:
	return {"levels": levels.duplicate()}


func _set_extra(s: Dictionary) -> void:
	levels = s["levels"].duplicate()
