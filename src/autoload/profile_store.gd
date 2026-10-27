extends Node
## Local player profile (§3.7, §7). Saved as JSON in user://profile.json. A cloud store could
## implement the same methods later. schema_version plus _migrate() let new fields be added safely.

const PATH: String = "user://profile.json"
## Finished matches (§7 MatchResult), newest last, at most MAX_RESULTS. Local only.
const RESULTS_PATH: String = "user://match_results.json"
const MAX_RESULTS: int = 50
const SCHEMA_VERSION: int = 1

var data: Dictionary = {}
## Tests point this at a temp file.
var results_path: String = RESULTS_PATH


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	var parsed: Variant = null
	if FileAccess.file_exists(PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		data = _migrate(parsed)
	else:
		data = _new_profile()
		save_profile()


func save_profile() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


func player_id() -> String:
	return data.get("player_id", "")


func display_name() -> String:
	return data.get("display_name", "Player")


## Stores a finished match and counts it in the stats.
func record_match(result: Dictionary) -> void:
	var list := match_results()
	list.append(result)
	while list.size() > MAX_RESULTS:
		list.pop_front()
	var file := FileAccess.open(results_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(list, "\t"))
	var stats: Dictionary = data["stats"]
	stats["matches"] = int(stats.get("matches", 0)) + 1
	if int(result.get("winner", -1)) >= 0 and result.get("winner") == result.get("local_key"):
		stats["wins"] = int(stats.get("wins", 0)) + 1
	save_profile()


func match_results() -> Array:
	if not FileAccess.file_exists(results_path):
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(results_path)) != OK or not json.data is Array:
		return []
	return json.data


func _new_profile() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"player_id": _uuid4(),
		"display_name": "Player",
		"loadout": {"skin_id": "alien_green", "trail_id": "", "hook_id": "", "kill_fx_id": "", "emote_id": ""},
		"stats": {"matches": 0, "wins": 0, "kos": 0, "ropes_fired": 0},
	}


func _migrate(old: Dictionary) -> Dictionary:
	var fresh := _new_profile()
	for key: String in fresh:
		if not old.has(key):
			old[key] = fresh[key]
	old["schema_version"] = SCHEMA_VERSION
	return old


func _uuid4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
