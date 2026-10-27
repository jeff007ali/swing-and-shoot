class_name PlaytestLogger
extends Node
## Playtest logging (§4.13): one CSV per match in user://playtest/YYYYMMDD_HHMMSS.csv, one row per
## event, plus a summary row for the local player with what the §5.1 success gate needs.
## Read it like the rest of the views: it listens to GameEvents and samples the local fighter, and
## never changes the sim.
##
## Columns: tick, time_s, event, fighter_id, detail ("key=value;key=value").
## A summary row is written whenever the session ends or the app goes to the background (mobile
## apps may be killed there); the last one in the file is the final one.
## Get the files from Android (user:// is the app's private files dir; debug builds allow run-as):
##   adb shell run-as com.jefflabs.swingandshoot ls files/playtest
##   adb exec-out run-as com.jefflabs.swingandshoot cat files/playtest/<name>.csv > <name>.csv
## iOS builds share user:// in the Files app (On My iPhone > Swing and Shoot), or use
## Xcode > Devices > the app > Download Container.

const DIR: String = "user://playtest/"
const HEADER: String = "tick,time_s,event,fighter_id,detail"

var file_path: String = ""
var local_fighter_id: int = -1

var _sim: MatchSim
var _file: FileAccess
var _stats := {
	"alive_ticks": 0,
	"airborne_ticks": 0,
	"ropes": 0,
	"orbits": 0,
	"slingshots": 0,
	"combos": 0,
	"hits": 0,
	"kos": 0,
	"deaths": 0,
}


## Opens the session file. dir is for tests; the game uses DIR.
func start(sim: MatchSim, local_id: int, mode: String, difficulty: String, dir: String = DIR) -> void:
	_sim = sim
	local_fighter_id = local_id
	DirAccess.make_dir_recursive_absolute(dir)
	file_path = dir + Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "_") + ".csv"
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_warning("Playtest log not writable: %s" % file_path)
		return
	_file.store_line(HEADER)
	_row(&"session_start", local_id, {
		"mode": mode,
		"difficulty": difficulty,
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"player": ProfileStore.player_id(),
		"platform": OS.get_name(),
	})
	sim.ticked.connect(_on_ticked)
	GameEvents.rope_fired.connect(_on_rope_fired)
	GameEvents.rope_attached.connect(_on_rope_attached)
	GameEvents.rope_missed.connect(_on_rope_missed)
	GameEvents.rope_released.connect(_on_rope_released)
	GameEvents.clung.connect(_on_clung)
	GameEvents.kicked_off.connect(_on_kicked_off)
	GameEvents.hit_landed.connect(_on_hit_landed)
	GameEvents.fighter_ko.connect(_on_fighter_ko)


## Writes the summary row. Safe to call more than once.
func finish() -> void:
	if _file == null:
		return
	_row(&"summary", local_fighter_id, summarize(_stats))


## The §4.13 summary from raw counts: duration, ropes per minute, % of time airborne (not clinging,
## out of the time alive), orbits, slingshots, combos, KOs.
static func summarize(stats: Dictionary) -> Dictionary:
	var alive: int = stats["alive_ticks"]
	var minutes := float(alive) / SimIds.TICK_RATE / 60.0
	return {
		"duration_s": snappedf(float(alive) / SimIds.TICK_RATE, 0.1),
		"ropes_per_min": snappedf(float(stats["ropes"]) / minutes, 0.1) if minutes > 0.0 else 0.0,
		"airborne_pct": snappedf(100.0 * float(stats["airborne_ticks"]) / float(alive), 0.1) if alive > 0 else 0.0,
		"orbits": stats["orbits"],
		"slingshots": stats["slingshots"],
		"combos": stats["combos"],
		"hits": stats["hits"],
		"kos": stats["kos"],
		"deaths": stats["deaths"],
	}


func _on_ticked(_tick: int) -> void:
	var me := _sim.get_fighter(local_fighter_id)
	if me == null or me.is_ko():
		return
	_stats["alive_ticks"] += 1
	if not me.is_clinging():
		_stats["airborne_ticks"] += 1


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_TREE, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			finish()


func _row(event: StringName, fighter_id: int, detail: Dictionary = {}) -> void:
	if _file == null:
		return
	var tick := _sim.tick if _sim != null else 0
	var parts := PackedStringArray()
	for key: String in detail:
		parts.append("%s=%s" % [key, str(detail[key]).replace(",", " ").replace(";", " ")])
	_file.store_line("%d,%.3f,%s,%d,%s" % [tick, float(tick) / SimIds.TICK_RATE, event, fighter_id, ";".join(parts)])
	_file.flush()


func _mine(fighter_id: int) -> bool:
	return fighter_id == local_fighter_id


func _on_rope_fired(fighter_id: int, target: Vector2) -> void:
	if _mine(fighter_id):
		_stats["ropes"] += 1
	_row(&"rope_fired", fighter_id, {"x": roundi(target.x), "y": roundi(target.y)})


func _on_rope_attached(fighter_id: int, mode: int, _point: Vector2) -> void:
	if _mine(fighter_id) and mode == SimIds.RopeMode.ORBIT:
		_stats["orbits"] += 1
	_row(&"rope_attached", fighter_id, {"mode": SimIds.RopeMode.keys()[mode].to_lower()})


func _on_rope_missed(fighter_id: int) -> void:
	_row(&"rope_missed", fighter_id)


func _on_rope_released(fighter_id: int, fling_mode: int) -> void:
	if fling_mode == SimIds.RopeMode.NONE:
		return
	if _mine(fighter_id):
		_stats["slingshots"] += 1
	_row(&"slingshot", fighter_id, {"mode": SimIds.RopeMode.keys()[fling_mode].to_lower()})


func _on_clung(fighter_id: int, _point: Vector2, _normal: Vector2) -> void:
	_row(&"cling", fighter_id)


func _on_kicked_off(fighter_id: int, _direction: Vector2) -> void:
	_row(&"kick", fighter_id)


func _on_hit_landed(attacker_id: int, victim_id: int, damage: float, _knockback: float, is_combo: bool) -> void:
	if _mine(attacker_id):
		_stats["hits"] += 1
		if is_combo:
			_stats["combos"] += 1
	_row(&"hit", attacker_id, {"victim": victim_id, "damage": snappedf(damage, 0.1), "combo": is_combo})


func _on_fighter_ko(fighter_id: int, killer_id: int, cause: StringName, last_puller_id: int) -> void:
	if _mine(killer_id) and killer_id != fighter_id:
		_stats["kos"] += 1
	if _mine(fighter_id):
		_stats["deaths"] += 1
	_row(&"ko", fighter_id, {"killer": killer_id, "cause": cause, "last_puller": last_puller_id})
