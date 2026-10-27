extends RefCounted
## Builds a real match (arena + player) for sim tests, with manual stepping and scripted input.

const MATCH_SCENE: PackedScene = preload("res://src/match/match.tscn")
const ScriptedInput = preload("res://tests/helpers/scripted_input.gd")

var match_node: Node2D
var sim: MatchSim
var player: Fighter
var input := ScriptedInput.new()


## Adds the match under parent. Await test.wait_physics_frames(2) before stepping so the
## physics space has the arena bodies.
func create(parent: Node, match_seed: int = 1234, arena_id: StringName = &"hangar", mode: StringName = &"free_fly") -> void:
	match_node = MATCH_SCENE.instantiate()
	match_node.set("match_seed", match_seed)
	match_node.set("mode", mode)
	match_node.set("log_playtest", false)
	match_node.set("record_results", false)
	match_node.set("arena_id", arena_id)
	sim = match_node.get_node("MatchSim")
	sim.auto_step = false
	parent.add_child(match_node)
	player = match_node.get("player")
	sim.set_input_source(player.fighter_id, input)
	# Weapon spawns would drift through other tests' rope paths; weapon tests switch it back on.
	sim.weapons.spawning = false


func arena() -> Arena:
	return match_node.get("arena")


## The arena object (wall, box, tank...) by node name, or null.
func object_named(node_name: String) -> ArenaObject:
	return arena().find_child(node_name, true, false) as ArenaObject


## Replaces the match's rules with mode_id (or a ModeDef), started now with the fighters there are.
func use_mode(mode: Variant) -> GameMode:
	var def: ModeDef = mode if mode is ModeDef else ModeDef.load_by_id(mode)
	sim.mode = GameMode.create(def, sim)
	sim.mode.start(sim.tick)
	sim.weapons.spawning = false
	return sim.mode


## Adds an idle enemy (no input source) at pos.
func add_enemy(pos: Vector2) -> Fighter:
	var enemy: Fighter = match_node.call("spawn_fighter", &"alien_pink", false)
	enemy.teleport(pos)
	return enemy


## Puts a bot brain on a fighter (the player included). profile may be a BotProfile or an id.
func make_bot(f: Fighter, profile: Variant) -> BotController:
	var p: BotProfile = profile if profile is BotProfile else BotProfile.load_by_id(profile)
	var arena: Arena = match_node.get("arena")
	var bot := BotController.new(f, sim, p, arena.get_bot_anchors())
	sim.set_input_source(f.fighter_id, bot)
	return bot


func step(n: int = 1) -> void:
	for i in n:
		sim.step()


func step_until(condition: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		sim.step()
		if condition.call():
			return true
	return false


func destroy() -> void:
	if match_node != null and is_instance_valid(match_node):
		match_node.get_parent().remove_child(match_node)
		match_node.free()
	match_node = null
