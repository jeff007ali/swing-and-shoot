extends Node2D
## One match (§3.4): wires the sim, arena, fighters, views and UI, and handles pause and the end of
## the match. The mode (§6.5) comes from the main menu: Free Fly (alone), Duel (Vs Bot; its
## difficulty can be changed live with keys 0-3 on desktop, "idle" gives it no input) or one of the
## party modes, with bots filling the slots. In a LAN match (§6.2) the slots come from the host's
## match config and a NetMatch child keeps everyone in sync. When the mode ends the match, every
## device replays the final moment in slow motion (§9, ReplayBuffer), the result is saved locally
## (§7 MatchResult) and the results screen opens.

const FIGHTER_SCENE: PackedScene = preload("res://src/sim/fighter.tscn")
const PLAYER_SKINS: Array[StringName] = [&"alien_green", &"alien_pink", &"alien_yellow", &"alien_purple"]
## Co-op Survival enemies.
const ENEMY_SKIN: StringName = &"alien_purple"
## Survival enemy bots get tougher: difficulty from this wave on.
const SURVIVAL_DIFFICULTY: Array = [[1, &"easy"], [3, &"normal"], [6, &"hard"]]
const MODE_FREE_FLY: StringName = &"free_fly"
const MODE_VS_BOT: StringName = &"vs_bot"
const MAIN_MENU_SCENE: String = "res://src/ui/main_menu.tscn"
## Difficulty for bots that take over from players who left a LAN match.
const REPLACEMENT_BOT: StringName = &"normal"
## Mode for LAN configs without a known mode id.
const DEFAULT_LAN_MODE: StringName = &"ffa"
## HUD banner for each mid-match event (§6.4).
const EVENT_NAMES: Dictionary = {
	&"lights_out": "LIGHTS OUT!", &"vent_surge": "VENT SURGE!", &"closing_walls": "WALLS CLOSING IN!", &"debris_storm": "DEBRIS STORM!",
}

## 0 picks a random seed.
@export var match_seed: int = 0
## Empty uses the last mode picked in the main menu (Settings.last_mode).
@export var mode: StringName = &""
## Writes a playtest CSV (§4.13) when Settings.playtest_logging is on. Tests turn this off.
@export var log_playtest: bool = true
## Arena id from ArenaRegistry. Empty uses the last arena picked in the main menu.
@export var arena_id: StringName = &""
## Save a MatchResult when the match ends. Tests turn this off.
@export var record_results: bool = true

## LAN session for a networked match. Tests set it; the game uses the Net autoload when it is in a match.
var net: NetSession
var net_match: NetMatch
var arena: Arena
var player: Fighter
var bot: Fighter
var bot_controller: BotController
var mode_def: ModeDef
## Tutorial step counter, or null.
var tracker: ChallengeTracker
var _bots: Dictionary = {}
var _finished: bool = false
var replay: ReplayBuffer

@onready var sim: MatchSim = $MatchSim
@onready var fighters_root: Node2D = $Fighters
@onready var rope_views: Node2D = $RopeViews
@onready var fx: ImpactFx = $Fx
@onready var weapons_view: WeaponsView = $Weapons
@onready var hazard_view: HazardView = $HazardView
@onready var debug_world: DebugWorld = $DebugWorld
@onready var camera: CameraShake = $Camera2D
@onready var router: TouchRouter = $TouchRouter
@onready var desktop: DesktopInput = $DesktopInput
@onready var hud: Hud = $HUD
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var mode_view: ModeView = $ModeView
@onready var results: ResultsScreen = $ResultsScreen


func _ready() -> void:
	if net == null and Net.in_match():
		net = Net
	if net != null:
		_setup_networked()
	else:
		_setup_offline()
	_setup_common()


func _setup_offline() -> void:
	if mode.is_empty():
		mode = StringName(Settings.last_mode)
	if arena_id.is_empty():
		arena_id = StringName(Settings.last_arena)
	mode_def = ModeDef.load_by_id(mode)
	if mode_def == null:
		mode = MODE_VS_BOT
		mode_def = ModeDef.load_by_id(mode)
	_load_arena(arena_id)
	sim.setup(arena.get_objects(), arena.get_spawn_points(), match_seed if match_seed != 0 else randi(), arena.get_weapon_spawns(), arena.bounds)
	sim.hazards.setup(sim, arena)
	player = spawn_fighter(PLAYER_SKINS[0], true, "You")
	if mode == MODE_VS_BOT:
		bot = spawn_fighter(PLAYER_SKINS[1], false, "Bot")
		set_bot_difficulty(Settings.bot_difficulty)
	elif mode_def.rule == &"tutorial":
		# An idle practice dummy.
		spawn_fighter(PLAYER_SKINS[1], false, "Dummy")
	else:
		var profile := BotProfile.load_by_id(StringName(Settings.bot_difficulty))
		for i in range(1, mode_def.players):
			var f := spawn_fighter(PLAYER_SKINS[i], false, _bot_name(i))
			_bots[f.fighter_id] = BotController.new(f, sim, profile, arena.get_bot_anchors())
			sim.set_input_source(f.fighter_id, _bots[f.fighter_id])
		for i in mode_def.enemy_slots:
			var f := spawn_fighter(ENEMY_SKIN, false, "Drone %d" % (i + 1))
			_bots[f.fighter_id] = BotController.new(f, sim, BotProfile.load_by_id(&"easy"), arena.get_bot_anchors())
			sim.set_input_source(f.fighter_id, _bots[f.fighter_id])
	sim.set_input_source(player.fighter_id, router)
	_start_mode()


func _setup_networked() -> void:
	var config := net.match_config
	mode = StringName(config["mode"])
	mode_def = ModeDef.load_by_id(mode)
	if mode_def == null:
		mode = DEFAULT_LAN_MODE
		mode_def = ModeDef.load_by_id(mode)
	arena_id = StringName(config["arena"])
	_load_arena(arena_id)
	sim.setup(arena.get_objects(), arena.get_spawn_points(), config["seed"], arena.get_weapon_spawns(), arena.bounds)
	sim.hazards.setup(sim, arena)
	var local_id := net.local_fighter_id()
	for slot: Dictionary in config["slots"]:
		var is_local: bool = slot["fighter"] == local_id
		var f := spawn_fighter(StringName(slot["skin"]), is_local, "You" if is_local else String(slot["name"]))
		if is_local:
			player = f
		if net.is_host() and not String(slot["bot"]).is_empty():
			var profile := BotProfile.load_by_id(StringName(slot["bot"]))
			_bots[f.fighter_id] = BotController.new(f, sim, profile, arena.get_bot_anchors())
	_start_mode()
	net_match = NetMatch.new()
	net_match.name = "NetMatch"
	add_child(net_match)
	net_match.setup(net, sim, router, player.fighter_id, _bots)
	net.host_left.connect(_on_host_left)
	pause_menu.networked = true


func _setup_common() -> void:
	router.fighter = player
	router.aim_resolver = sim.aim_assist.bind(player)
	router.direction_resolver = sim.aim_direction.bind(player)
	router.rope_blocked_by_cooldown.connect(_on_rope_blocked)
	router.rope_out_of_range.connect(func() -> void:
		if player.view.range_indicator != null:
			player.view.range_indicator.flash())
	router.debug_toggle_requested.connect(debug_overlay.toggle)

	replay = ReplayBuffer.new()
	replay.name = "Replay"
	add_child(replay)
	replay.attach(sim)
	fx.sim = sim
	fx.camera = camera
	weapons_view.sim = sim
	hazard_view.sim = sim
	mode_view.sim = sim
	mode_view.local_fighter_id = player.fighter_id
	fx.local_fighter_id = player.fighter_id
	var others: Array[Fighter] = []
	for f in sim.fighters:
		if f != player:
			others.append(f)
	hud.setup(router, player, others)
	hud.mode = sim.mode
	hud.attach_world(sim, arena, camera)
	camera.follow(player, arena.bounds)
	hud.pause_pressed.connect(pause_menu.open)

	desktop.router = router
	desktop.debug_toggle_requested.connect(debug_overlay.toggle)
	desktop.respawn_requested.connect(respawn_all)
	desktop.pause_requested.connect(pause_menu.toggle)
	desktop.bot_difficulty_requested.connect(_on_difficulty_requested)

	pause_menu.restart_requested.connect(restart)
	pause_menu.main_menu_requested.connect(go_to_main_menu)
	results.rematch_requested.connect(restart)
	results.main_menu_requested.connect(go_to_main_menu)
	results.allow_rematch = net == null

	debug_overlay.sim = sim
	debug_overlay.player = player
	debug_overlay.world_debug_toggled.connect(func(on: bool) -> void: debug_world.enabled = on)
	debug_world.arena = arena
	debug_world.sim = sim
	debug_world.router = router
	debug_world.bot_controller = bot_controller

	GameEvents.match_event.connect(_on_match_event)
	GameEvents.match_ended.connect(_on_match_ended)
	GameEvents.wave_started.connect(_on_wave_started)
	GameEvents.legendary_incoming.connect(func(def_id: StringName, _at: Vector2, seconds: float) -> void:
		var def := WeaponDef.load_by_id(def_id)
		hud.show_message("LEGENDARY %s IN %d!" % [def.display_name.to_upper() if def != null else "WEAPON", ceili(seconds)], 2.5))

	if not mode_def.challenges.is_empty() and net == null:
		_start_tutorial()

	if log_playtest and Settings.playtest_logging:
		var logger := PlaytestLogger.new()
		add_child(logger)
		logger.start(sim, player.fighter_id, String(mode), Settings.bot_difficulty if bot != null else "")


## The tutorial's steps (§6.7): a ChallengeTracker counts them; the last one ends the match.
func _start_tutorial() -> void:
	var steps: Array[ChallengeDef] = []
	for id in mode_def.challenges:
		var def := ChallengeDef.load_by_id(id)
		if def != null:
			steps.append(def)
	tracker = ChallengeTracker.new()
	tracker.name = "Tutorial"
	add_child(tracker)
	tracker.start(steps, player.fighter_id)
	hud.tracker = tracker
	tracker.step_completed.connect(func(_i: int) -> void:
		Sfx.play(&"respawn", camera.global_position, 0.0, 1.2)
		hud.show_message("NICE!", 1.0))
	tracker.all_completed.connect(func() -> void:
		Settings.tutorial_done = true
		Settings.save_settings()
		sim.mode.finish(sim.tick))
	sim.weapons.next_spawn_tick = sim.tick + SimIds.ticks(2.0)


func _start_mode() -> void:
	sim.mode = GameMode.create(mode_def, sim)
	sim.mode.start(sim.tick)


## Offline bot names; in 2v2 the player's teammate (fighter 2) is the ally.
func _bot_name(fighter_id: int) -> String:
	if mode_def.rule == &"survival":
		return "Ally"
	if mode_def.team_count == 2 and fighter_id % 2 == 0:
		return "Ally"
	return "Bot %d" % (fighter_id if mode_def.team_count == 0 else (fighter_id + 1) / 2)


func _load_arena(id: StringName) -> void:
	arena = ArenaRegistry.instantiate(id)
	arena.name = "Arena"
	add_child(arena)
	move_child(arena, sim.get_index() + 1)


func spawn_fighter(skin_id: StringName, is_local: bool, display_name: String = "") -> Fighter:
	var f := FIGHTER_SCENE.instantiate() as Fighter
	f.fighter_id = sim.fighters.size()
	f.skin_id = skin_id
	f.is_local_player = is_local
	f.display_name = display_name
	fighters_root.add_child(f)
	sim.add_fighter(f)
	f.teleport(_spawn_point_for(f))
	var rope_view := RopeView.new()
	rope_view.fighter = f
	rope_views.add_child(rope_view)
	return f


## Swaps the offline bot's brain mid-match. "idle" leaves it with no input source.
func set_bot_difficulty(level: String) -> void:
	if bot == null or net != null:
		return
	var profile := BotProfile.load_by_id(StringName(level)) if level != "idle" else null
	bot_controller = BotController.new(bot, sim, profile, arena.get_bot_anchors()) if profile != null else null
	sim.set_input_source(bot.fighter_id, bot_controller)
	debug_world.bot_controller = bot_controller
	hud.bot_label = level.to_upper()


## LAN host: a player left, so a bot takes over their fighter (§6.2).
func replace_with_bot(fighter_id: int) -> void:
	var f := sim.get_fighter(fighter_id)
	if f == null:
		return
	var brain := BotController.new(f, sim, BotProfile.load_by_id(REPLACEMENT_BOT), arena.get_bot_anchors())
	_bots[fighter_id] = brain
	net_match.replace_input(fighter_id, brain)
	f.display_name += " (bot)"


func respawn_all() -> void:
	if net != null:
		return
	for f in sim.fighters:
		f.respawn_at(_spawn_point_for(f), sim.tick)


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func go_to_main_menu() -> void:
	get_tree().paused = false
	if net != null:
		net.leave()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Android back button: pause, or resume when already paused.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pause_menu.toggle()


## Match start places fighters by slot; KO respawns are picked by MatchSim.respawn().
func _spawn_point_for(f: Fighter) -> Vector2:
	var points := arena.get_spawn_points()
	return points[f.fighter_id % points.size()]


## The mode ended the match: replay the final moment in slow motion, save the result, show the
## results. In a LAN match the shared sim stops here too: the match is over (D30).
func _on_match_ended(_winner: int) -> void:
	if _finished:
		return
	_finished = true
	var result := sim.mode.result(arena_id)
	result["local_key"] = sim.mode.key_of(player)
	if record_results:
		ProfileStore.record_match(result)
	if net_match != null:
		net_match.set_physics_process(false)
	hud.show_message(ResultsScreen.headline(result), ReplayBuffer.REPLAY_TIME / ReplayBuffer.REPLAY_SPEED)
	replay.play_final()
	await replay.finished
	if not is_inside_tree():
		return
	get_tree().paused = true
	results.open(result, sim.mode)


func _on_wave_started(wave: int, boss_wave: bool) -> void:
	hud.show_message("BOSS WAVE %d!" % wave if boss_wave else "WAVE %d" % wave, 2.5)
	Sfx.play(&"announce", camera.global_position, 0.0, 0.7)
	var level: StringName = &"easy"
	for step: Array in SURVIVAL_DIFFICULTY:
		if wave >= int(step[0]):
			level = step[1]
	for id: int in _bots:
		if int(sim.teams.get(id, 0)) == 1:
			(_bots[id] as BotController).profile = BotProfile.load_by_id(level)


func _on_match_event(event_id: StringName, started: bool, _duration: float) -> void:
	if started:
		hud.show_message(EVENT_NAMES.get(event_id, String(event_id).capitalize()), 2.5)
		Sfx.play(&"announce", camera.global_position, -2.0, 0.8)


func _on_host_left() -> void:
	hud.show_message("Host left the match")
	get_tree().create_timer(2.0).timeout.connect(go_to_main_menu)


func _on_difficulty_requested(level: String) -> void:
	if net != null:
		return
	Settings.bot_difficulty = level
	Settings.save_settings()
	set_bot_difficulty(level)


func _on_rope_blocked() -> void:
	if player.view.range_indicator != null:
		player.view.range_indicator.flash()
	Sfx.play(&"cooldown", player.global_position, -10.0)
