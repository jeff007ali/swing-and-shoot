extends SceneTree
## Store screenshots (§6.7): plays a few bot matches and saves frames to docs/store/screenshots/.
## Needs a window (not --headless). Run once per shot:
##   godot --path . --resolution 1920x1080 -s res://tools/capture_store_shots.gd -- shot=<name>
## Shots: menu, station_ffa, interior_koth, singularity_boss, asteroids_storm, derelict_potato

const OUT: String = "res://docs/store/screenshots/"
const SHOTS: Dictionary = {
	"station_ffa": {"arena": &"station", "mode": &"ffa", "tick": 900},
	"interior_koth": {"arena": &"interior", "mode": &"koth", "tick": 1500},
	"singularity_boss": {"arena": &"singularity", "mode": &"survival", "tick": 420, "boss": true},
	"asteroids_storm": {"arena": &"asteroids", "mode": &"gun_game", "tick": 600, "event": &"debris_storm"},
	"derelict_potato": {"arena": &"derelict", "mode": &"hot_potato", "tick": 700},
}

var shot := "station_ffa"
var match_node: Node
var sim: Node
var frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shot = arg.substr(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if shot == "menu":
		root.add_child((load("res://src/ui/main_menu.tscn") as PackedScene).instantiate())
		process_frame.connect(func() -> void:
			frames += 1
			if frames == 40:
				_save())
		return
	var cfg: Dictionary = SHOTS[shot]
	match_node = (load("res://src/match/match.tscn") as PackedScene).instantiate()
	match_node.set("match_seed", 11)
	match_node.set("mode", cfg["mode"])
	match_node.set("arena_id", cfg["arena"])
	match_node.set("log_playtest", false)
	match_node.set("record_results", false)
	root.add_child(match_node)
	physics_frame.connect(_tick)


func _tick() -> void:
	var cfg: Dictionary = SHOTS[shot]
	if sim == null:
		sim = match_node.get_node("MatchSim")
		var player: Node = match_node.get("player")
		var brain: Object = load("res://src/input/bot_controller.gd").new(player, sim, load("res://data/bots/hard.tres"), match_node.get("arena").call("get_bot_anchors"))
		sim.call("set_input_source", player.get("fighter_id"), brain)
		sim.get("weapons").set("next_spawn_tick", 30)
		if cfg.get("boss", false):
			sim.get("mode").set("wave", 4)
			sim.get("mode").set("next_wave", 60)
		return
	var t: int = sim.get("tick")
	if cfg.has("event") and t == int(cfg["tick"]) - 120:
		sim.get("hazards").call("start_event", cfg["event"], t)
	if t == int(cfg["tick"]):
		_save()


func _save() -> void:
	var path := ProjectSettings.globalize_path(OUT + shot + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
