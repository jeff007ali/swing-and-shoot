extends SceneTree
## Performance pass (§6.7): a 4-fighter bot match with hazards, events and fast weapon spawns.
## Headless it times MatchSim.step (CPU cost of the simulation); with a window it also reports
## frame rate and frame times while everything is drawn.
## Run: godot --headless --path . -s res://tools/benchmark.gd -- arena=interior mode=ffa seconds=60

var arena := &"interior"
var mode := &"ffa"
var seconds := 60.0
## Leave parts out to see what they cost: replay, bots.
var skip: Array = []
var match_node: Node
var sim: Node
var _step_usec: Array[int] = []
var _frame_ms: Array[float] = []
var _last_frame := 0
var _ticks := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		match kv[0]:
			"arena": arena = StringName(kv[1])
			"mode": mode = StringName(kv[1])
			"seconds": seconds = float(kv[1])
			"skip": skip = Array(kv[1].split(","))
	var tuning: Object = root.get_node("TuningDB").get("t")
	tuning.set("weapon_spawn_interval", 2.0)
	tuning.set("event_first_delay", 5.0)
	tuning.set("event_interval", 12.0)
	tuning.set("legendary_first_delay", 10.0)
	match_node = (load("res://src/match/match.tscn") as PackedScene).instantiate()
	match_node.set("match_seed", 4)
	match_node.set("mode", mode)
	match_node.set("arena_id", arena)
	match_node.set("log_playtest", false)
	match_node.set("record_results", false)
	root.add_child(match_node)
	physics_frame.connect(_tick)
	process_frame.connect(_frame)


func _tick() -> void:
	if sim == null:
		sim = match_node.get_node("MatchSim")
		sim.set("auto_step", false)
		var player: Node = match_node.get("player")
		var brain: Object = load("res://src/input/bot_controller.gd").new(player, sim, load("res://data/bots/hard.tres"), match_node.get("arena").call("get_bot_anchors"))
		sim.call("set_input_source", player.get("fighter_id"), brain)
		if "replay" in skip:
			var replay: Node = match_node.get("replay")
			sim.disconnect("ticked", Callable(replay, "_record"))
		if "bots" in skip:
			for f in sim.get("fighters"):
				sim.call("set_input_source", f.get("fighter_id"), null)
		return
	var t0 := Time.get_ticks_usec()
	sim.call("step")
	_step_usec.append(Time.get_ticks_usec() - t0)
	_ticks += 1
	if _ticks >= int(seconds * 60.0):
		_report()
		quit()


func _frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame > 0:
		_frame_ms.append((now - _last_frame) / 1000.0)
	_last_frame = now


func _report() -> void:
	_step_usec.sort()
	var total := 0
	for u in _step_usec:
		total += u
	var n := _step_usec.size()
	print("BENCH %s/%s: %d ticks, fighters %d, projectiles now %d" % [arena, mode, n, (sim.get("fighters") as Array).size(), (sim.get("weapons").get("projectiles") as Array).size()])
	print("BENCH sim.step  avg %.3f ms  p50 %.3f  p99 %.3f  max %.3f" % [total / float(n) / 1000.0, _step_usec[n / 2] / 1000.0, _step_usec[int(n * 0.99)] / 1000.0, _step_usec[n - 1] / 1000.0])
	if DisplayServer.get_name() != "headless" and not _frame_ms.is_empty():
		_frame_ms.sort()
		var m := _frame_ms.size()
		var sum := 0.0
		for f in _frame_ms:
			sum += f
		print("BENCH frames  avg %.2f ms (%.0f fps)  p99 %.2f ms  draw calls %d" % [sum / m, 1000.0 / (sum / m), _frame_ms[int(m * 0.99)], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
