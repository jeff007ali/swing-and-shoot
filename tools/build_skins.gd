extends SceneTree
## Generates data/skins/alien_*.tres (SkinDef + SpriteFrames) from the packed character atlas.
## Run after tools/build_rope_art.gd, tools/build_atlases.gd and an import:
## godot --headless --path . -s res://tools/build_skins.gd

const SkinDefScript = preload("res://src/core/skin_def.gd")
## AtlasTexture per frame, written by tools/build_atlases.gd.
const ART_DIR: String = "res://assets/art/atlas/characters/"
const OUT_DIR: String = "res://data/skins/"
const HOOK_TEXTURE: String = "res://assets/art/atlas/characters/hook.tres"
const ROPE_TEXTURE: String = "res://assets/art/fx/rope_tile.png"

## animation -> [frames, fps, loop]. Frame names are the Kenney suffixes.
const ANIMATIONS: Dictionary = {
	"float": [["idle"], 6.0, true],
	"reel": [["jump"], 6.0, true],
	"cling": [["duck"], 6.0, true],
	"kick": [["jump"], 6.0, true],
	"melee": [["front", "jump", "idle"], 20.0, false],
	"hurt": [["hit"], 6.0, true],
	"ko": [["hit", "duck"], 6.0, false],
}

## color -> [display name, rope, hook, trail]
const COLORS: Dictionary = {
	"green": ["Green", Color("7be0a8"), Color("c8ffe0"), Color(0.48, 0.88, 0.66, 0.55)],
	"pink": ["Pink", Color("ff8fc0"), Color("ffd0e4"), Color(1.0, 0.56, 0.75, 0.55)],
	"yellow": ["Yellow", Color("ffd166"), Color("fff0c2"), Color(1.0, 0.82, 0.4, 0.55)],
	"purple": ["Purple", Color("b79cff"), Color("e3d8ff"), Color(0.72, 0.61, 1.0, 0.55)],
	"beige": ["Beige", Color("e8d3b0"), Color("fff4e2"), Color(0.91, 0.83, 0.69, 0.55)],
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for color: String in COLORS:
		var info: Array = COLORS[color]
		var frames := SpriteFrames.new()
		frames.remove_animation(&"default")
		for anim: String in ANIMATIONS:
			var spec: Array = ANIMATIONS[anim]
			frames.add_animation(anim)
			frames.set_animation_speed(anim, spec[1])
			frames.set_animation_loop(anim, spec[2])
			for frame: String in spec[0]:
				var texture := load("%scharacter_%s_%s.tres" % [ART_DIR, color, frame]) as Texture2D
				frames.add_frame(anim, texture)
		var skin = SkinDefScript.new()
		skin.id = StringName("alien_" + color)
		skin.display_name = info[0]
		skin.sprite_frames = frames
		skin.rope_color = info[1]
		skin.hook_color = info[2]
		skin.trail_color = info[3]
		skin.hook_texture = load(HOOK_TEXTURE)
		skin.rope_texture = load(ROPE_TEXTURE)
		var path := "%salien_%s.tres" % [OUT_DIR, color]
		var err := ResourceSaver.save(skin, path)
		print("%s -> %s" % [path, error_string(err)])
	quit()
