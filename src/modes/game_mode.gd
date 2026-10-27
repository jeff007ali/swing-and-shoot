class_name GameMode
extends RefCounted
## The rules of one match (§6.5): teams, scoring and when it ends. Part of the sim: MatchSim steps
## it after the hazards, fighters report KOs and contacts (rope or melee hits) to it, and its state
## is in every snapshot. Only the authoritative sim scores and ends the match.
## The base class scores KOs, which covers Free-for-all, 2v2 and the endless practice modes;
## subclasses override the hooks: start / on_ko / on_contact / on_tick / is_over.

const TEAM_NAMES: Array[String] = ["BLUE", "RED"]

var def: ModeDef
var sim: MatchSim
## Score key (fighter id, or team id in team modes) -> points.
var scores: Dictionary = {}
var start_tick: int = 0
var ended: bool = false
var end_tick: int = SimIds.NO_TICK
## Winning score key, or -1 for a draw.
var winner: int = -1


static func create(mode_def: ModeDef, match_sim: MatchSim) -> GameMode:
	var mode: GameMode
	match mode_def.rule:
		&"koth": mode = KingOfTheSwing.new()
		&"hot_potato": mode = HotPotato.new()
		&"gun_game": mode = GunGame.new()
		&"survival": mode = SurvivalMode.new()
		&"tutorial": mode = TutorialMode.new()
		_: mode = GameMode.new()
	mode.def = mode_def
	mode.sim = match_sim
	return mode


## Called once every fighter is in: teams, weapon rules, empty scores.
func start(tick: int) -> void:
	start_tick = tick
	sim.teams.clear()
	if def.team_count > 0:
		for f in sim.fighters:
			sim.teams[f.fighter_id] = f.fighter_id % def.team_count
	sim.weapons.spawning = def.weapon_spawns
	sim.weapons.allowed = def.allowed_weapons.duplicate()
	scores.clear()
	for key in keys():
		scores[key] = 0


func is_team_mode() -> bool:
	return def.team_count > 0


func key_of(f: Fighter) -> int:
	return int(sim.teams.get(f.fighter_id, f.fighter_id)) if is_team_mode() else f.fighter_id


## Every score key, sorted.
func keys() -> Array[int]:
	var out: Array[int] = []
	for f in sim.fighters:
		var k := key_of(f)
		if not out.has(k):
			out.append(k)
	out.sort()
	return out


func key_name(key: int) -> String:
	if is_team_mode():
		return TEAM_NAMES[key % TEAM_NAMES.size()]
	var f := sim.get_fighter(key)
	return f.display_name if f != null else "?"


## What the HUD shows for a score.
func score_text(key: int) -> String:
	return "%d" % scores.get(key, 0)


## Keys from first to last place.
func ranking() -> Array[int]:
	var out := keys()
	out.sort_custom(func(a: int, b: int) -> bool:
		var sa: int = scores.get(a, 0)
		var sb: int = scores.get(b, 0)
		return sa > sb or (sa == sb and a < b))
	return out


## Seconds left, or -1 without a time limit.
func time_left(tick: int) -> float:
	if def.time_limit <= 0.0:
		return -1.0
	return maxf(0.0, def.time_limit - float(tick - start_tick) / SimIds.TICK_RATE)


func step(tick: int) -> void:
	if ended:
		return
	on_tick(tick)
	if sim.authoritative and is_over(tick):
		finish(tick)


func finish(tick: int) -> void:
	ended = true
	end_tick = tick
	var order := ranking()
	winner = order[0] if not order.is_empty() else -1
	if order.size() > 1 and scores.get(order[0], 0) == scores.get(order[1], 0):
		winner = -1
	sim.queue_event(&"match_ended", [winner])


## A summary of the finished match (§7 MatchResult): stored locally, never sent anywhere.
func result(arena_id: StringName) -> Dictionary:
	var rows: Array = []
	for key in ranking():
		rows.append({"key": key, "name": key_name(key), "score": score_text(key)})
	return {
		"mode": String(def.id), "arena": String(arena_id), "winner": winner, "ranking": rows,
		"duration": float(maxi(0, (end_tick if end_tick != SimIds.NO_TICK else sim.tick) - start_tick)) / SimIds.TICK_RATE,
		"protocol": NetProtocol.VERSION, "time": Time.get_datetime_string_from_system(true),
	}


# --- Hooks ---------------------------------------------------------------------------------------

## A KO, reported by the authoritative sim. KOs credited to a teammate (a pull into a hazard) and
## self-KOs score nothing.
func on_ko(victim: Fighter, killer_id: int, _cause: StringName) -> void:
	var killer := sim.get_fighter(killer_id)
	if killer == null or killer == victim or not sim.are_enemies(killer, victim):
		return
	var k := key_of(killer)
	scores[k] = int(scores.get(k, 0)) + 1


## A shot hit an arena object; true if the mode handled it (the Survival boss).
func on_object_hit(_obj: ArenaObject, _point: Vector2, _damage: float, _owner_id: int, _tick: int) -> bool:
	return false


## A blast went off (rockets, grenades).
func on_blast(_at: Vector2, _radius: float, _damage: float, _owner_id: int, _tick: int) -> void:
	pass


## attacker's rope or melee (kind: rope, melee, throw) touched victim.
func on_contact(_attacker: Fighter, _victim: Fighter, _kind: StringName) -> void:
	pass


func on_tick(_tick: int) -> void:
	pass


func is_over(tick: int) -> bool:
	if target_points() > 0:
		for key: int in scores:
			if int(scores[key]) >= target_points():
				return true
	return def.time_limit > 0.0 and time_left(tick) <= 0.0


## Points needed to win, in the units scores are kept in.
func target_points() -> int:
	return def.score_target


## Where a bot in this mode wants to be, or INF to just fight (§4.9 rule 5).
func bot_goal(_f: Fighter, _tick: int) -> Vector2:
	return Vector2.INF


# --- State ---------------------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {"scores": scores.duplicate(), "start": start_tick, "ended": ended, "end": end_tick, "winner": winner, "teams": sim.teams.duplicate(), "extra": _get_extra()}


func set_state(s: Dictionary) -> void:
	scores = s["scores"].duplicate()
	start_tick = s["start"]
	ended = s["ended"]
	end_tick = s["end"]
	winner = s["winner"]
	sim.teams = s["teams"].duplicate()
	_set_extra(s["extra"])


func _get_extra() -> Dictionary:
	return {}


func _set_extra(_s: Dictionary) -> void:
	pass
