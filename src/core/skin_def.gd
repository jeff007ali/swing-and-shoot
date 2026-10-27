class_name SkinDef
extends Resource
## How one fighter looks (§3.8). Code refers to skins by id only, so custom art and future
## cosmetics plug in as data files in data/skins/.

const SKIN_DIR: String = "res://data/skins/"

@export var id: StringName = &""
@export var display_name: String = ""
## Animations: float, reel, cling, kick, melee, hurt, ko.
@export var sprite_frames: SpriteFrames
@export var sprite_scale: float = 0.7
@export var tint: Color = Color.WHITE
@export var rope_color: Color = Color.WHITE
@export var hook_color: Color = Color.WHITE
@export var trail_color: Color = Color(1, 1, 1, 0.5)
## White art tinted with hook_color: 32 x 32, rope end at the left-center edge (§3.8).
@export var hook_texture: Texture2D
## White art tinted with rope_color: 16 x 8 tile that repeats along the rope (§3.8).
@export var rope_texture: Texture2D


static func load_by_id(skin_id: StringName) -> SkinDef:
	var path := SKIN_DIR + String(skin_id) + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("Unknown skin id: %s" % skin_id)
		return null
	return load(path) as SkinDef
