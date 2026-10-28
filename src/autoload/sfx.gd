extends Node
## Named sound lookup (§3.7, §4.11). Each name maps to a few variations (an .ogg in DIR unless the
## name has an extension: tools/build_sfx.py writes .wav files); one is picked at random per
## play. Performance pass (§6.7): every variation has its own 2D player with a few voices of
## polyphony, so playing a sound never swaps a player's stream (that reset cost ~1 ms per sound).

const VOICES: int = 3
const DIR: String = "res://assets/audio/sfx/"
const SOUNDS: Dictionary = {
	&"rope_fire": ["laserSmall_000", "laserSmall_001", "laserSmall_002"],
	&"hook_attach": ["impactMetal_light_000", "impactMetal_light_001", "impactMetal_light_002"],
	&"hook_miss": ["impactGeneric_light_000", "impactGeneric_light_001"],
	&"hook_fighter": ["impactPunch_medium_000", "impactPunch_medium_001"],
	&"hook_bounce": ["impactMetal_000", "impactMetal_001", "impactMetal_002"],
	&"rope_hum": ["engineCircular_000"],
	&"cling": ["impactPlate_light_000", "impactPlate_light_001", "impactPlate_light_002"],
	&"kick": ["thrusterFire_000", "thrusterFire_001"],
	&"slingshot": ["forceField_000", "forceField_001"],
	&"cooldown": ["tick_001"],
	&"melee_swing": ["forceField_002", "forceField_003"],
	&"knife": ["knife_swish.wav"],
	&"hit_light": ["impactPunch_medium_000", "impactPunch_medium_001"],
	&"hit_heavy": ["impactPunch_heavy_000", "impactPunch_heavy_001"],
	&"ko": ["explosionCrunch_000"],
	&"respawn": ["confirmation_001"],
	&"ui_click": ["click_001", "click_002"],
	&"shot_pistol": ["sfx_laser1", "sfx_laser2"],
	&"shot_shotgun": ["laserLarge_000", "laserLarge_001"],
	&"shot_retro": ["laserRetro_000", "laserRetro_001"],
	&"shot_sniper": ["sniper_shot.wav"],
	&"sniper_bolt": ["sniper_bolt.wav"],
	&"pickup": ["confirmation_001"],
	&"mine_beep": ["tick_001"],
	&"weapon_spawn": ["sfx_twoTone"],
	&"weapon_pick": ["sfx_shieldUp"],
	&"weapon_drop": ["sfx_shieldDown"],
	&"weapon_gone": ["sfx_lose"],
	&"throw": ["thrusterFire_000", "thrusterFire_001"],
	&"bullet_wall": ["impactMetal_light_000", "impactMetal_light_001"],
	&"parry": ["forceField_004", "sfx_zap"],
	&"rope_cut": ["impactMetal_003", "doorClose_000"],
	&"explosion": ["explosionCrunch_001", "explosionCrunch_002", "lowFrequency_explosion_000"],
	&"shock": ["sfx_zap"],
	&"break": ["impactMetal_003", "impactPlate_light_002"],
	&"alarm": ["error_004"],
	&"vent_open": ["doorClose_000"],
	&"announce": ["confirmation_001"],
}

var _streams: Dictionary = {}
## sound -> Array[AudioStreamPlayer2D], one per variation
var _players: Dictionary = {}


func _ready() -> void:
	for sound: StringName in SOUNDS:
		var variations: Array[AudioStream] = []
		var players: Array[AudioStreamPlayer2D] = []
		for file: String in SOUNDS[sound]:
			var stream := load(DIR + file + ("" if "." in file else ".ogg")) as AudioStream
			variations.append(stream)
			var player := AudioStreamPlayer2D.new()
			player.stream = stream
			player.bus = &"SFX"
			player.max_distance = 5000.0
			player.attenuation = 0.3
			player.max_polyphony = VOICES
			add_child(player)
			players.append(player)
		_streams[sound] = variations
		_players[sound] = players


func play(sound: StringName, at: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var players: Array = _players.get(sound, [])
	if players.is_empty():
		push_warning("Unknown sound: %s" % sound)
		return
	var player: AudioStreamPlayer2D = players[randi() % players.size()]
	player.global_position = at
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.94, 1.06)
	player.play()


## First variation of a sound, for callers that loop it themselves (rope hum).
func stream(sound: StringName) -> AudioStream:
	var variations: Array = _streams.get(sound, [])
	return null if variations.is_empty() else variations[0]
