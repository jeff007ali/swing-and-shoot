class_name ModeDef
extends Resource
## One game mode (§6.5) as data: name, team size, score target, time limit, weapons. The rules
## themselves are a GameMode subclass picked by `rule`. Files live in data/modes/<id>.tres.

const DIR: String = "res://data/modes/"

@export var id: StringName = &""
@export var display_name: String = ""
## For the main menu's mode buttons.
@export var short_name: String = ""
@export_multiline var description: String = ""
## kos (score KOs), koth, hot_potato, gun_game or survival.
@export var rule: StringName = &"kos"
## Order in the menus.
@export var sort_order: int = 0
## Fighters in an offline match, the player included; bots fill the rest.
@export_range(1, 4) var players: int = 4
## 0: everyone for themselves. 2: fighters alternate between two teams (2v2).
@export_range(0, 2) var team_count: int = 0
## Points to win (KOs, seconds in the zone, rounds survived...). 0: no target.
@export var score_target: int = 10
## Seconds. 0: no limit.
@export var time_limit: float = 180.0
## Normal weapon spawns (§6.3). Gun Game hands out its own.
@export var weapon_spawns: bool = true
## Weapon ids that may spawn; empty allows every weapon.
@export var allowed_weapons: Array[StringName] = []
## Gun Game: the weapon for each level; after the last one, the final kill must be melee.
@export var weapon_sequence: Array[StringName] = []
## King of the Swing: zone radius (px) and time for one lap of its path (s).
@export var zone_radius: float = 280.0
@export var zone_period: float = 40.0
## Hot Potato: fuse length range (s).
@export var fuse_min: float = 12.0
@export var fuse_max: float = 20.0
## Tutorial: ChallengeDef ids to complete in order (§6.7).
@export var challenges: Array[StringName] = []
## Co-op Survival: enemy bot fighters (benched between waves) and the team's shared lives.
@export var enemy_slots: int = 0
@export var team_lives: int = 5
## Listed in the main menu / the LAN lobby.
@export var offline: bool = true
@export var lan: bool = true


static var _cache: Dictionary = {}


static func load_by_id(mode_id: StringName) -> ModeDef:
	if _cache.has(mode_id):
		return _cache[mode_id]
	var path := DIR + String(mode_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var def := load(path) as ModeDef
	_cache[mode_id] = def
	return def


## Every mode in data/modes, in menu order.
static func all() -> Array[ModeDef]:
	var out: Array[ModeDef] = []
	for f: String in DirAccess.get_files_at(DIR):
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var def := load_by_id(StringName(name.get_basename()))
			if def != null:
				out.append(def)
	out.sort_custom(func(a: ModeDef, b: ModeDef) -> bool: return a.sort_order < b.sort_order)
	return out
