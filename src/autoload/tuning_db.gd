extends Node
## Holds the live Tuning resource (§3.7). The debug overlay edits it; named presets are saved to
## user://tuning/. Always read values through TuningDB.t so preset loads take effect at once.

signal changed

const DEFAULT_PATH: String = "res://data/tuning/default_tuning.tres"
const PRESET_DIR: String = "user://tuning/"

var t: Tuning


func _init() -> void:
	reset_to_default()


func reset_to_default() -> void:
	var base := load(DEFAULT_PATH) as Tuning
	t = base.duplicate() as Tuning
	changed.emit()


func list_presets() -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return names
	for file in dir.get_files():
		if file.ends_with(".tres"):
			names.append(file.get_basename())
	names.sort()
	return names


func save_preset(preset_name: String) -> Error:
	var file_name := _file_name(preset_name)
	if file_name.is_empty():
		return ERR_INVALID_PARAMETER
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	return ResourceSaver.save(t, PRESET_DIR + file_name)


func load_preset(preset_name: String) -> bool:
	var path := PRESET_DIR + _file_name(preset_name)
	if not ResourceLoader.exists(path):
		return false
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Tuning
	if loaded == null:
		return false
	t = loaded
	changed.emit()
	return true


func _file_name(preset_name: String) -> String:
	var clean := preset_name.strip_edges().validate_filename()
	return "" if clean.is_empty() else clean + ".tres"
