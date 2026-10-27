class_name WeaponDef
extends Resource
## One weapon (§6.3): numbers and look as data, so a new weapon is a .tres plus, at most, a small
## behavior in WeaponSystem. Files live in data/weapons/<id>.tres.

const DIR: String = "res://data/weapons/"

enum Kind { GUN, BLADE, SPECIAL }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.GUN
@export var texture: Texture2D
## Drawn size of the floating sprite (px).
@export var sprite_size: float = 72.0
@export var glow_color: Color = Color(1, 0.9, 0.4)
## Relative chance at a spawn point; 0 means never from a normal spawn.
@export var spawn_weight: float = 1.0
## Legendary weapons spawn only in dangerous spots with a countdown (Phase 6, WPN-04).
@export var legendary: bool = false

@export_group("Gun")
@export var ammo: int = 10
@export var fire_cooldown: float = 0.25
## Push on the shooter opposite the shot (px/s), PHY-06.
@export var recoil_impulse: float = 120.0
@export var projectile_count: int = 1
@export var spread_deg: float = 0.0
@export var projectile_speed: float = 2200.0
@export var projectile_damage: float = 10.0
@export var projectile_knockback: float = 300.0
@export var projectile_lifetime: float = 0.8
@export var projectile_radius: float = 6.0
@export var projectile_color: Color = Color(1, 0.9, 0.4)
## Phase 6 behavior (SPECIAL weapons, §6.6): rocket, laser, boomerang, harpoon, freeze, magnet,
## sticky, gravity, black_hole_bomb, repulsor, tether_mine, tether_rope, shield, thruster.
@export var projectile_kind: StringName = &""

@export_group("Special")
## Blast, well, field or trigger radius (px).
@export var effect_radius: float = 0.0
## Pull or push strength (px/s²), or blast knockback (px/s).
@export var effect_strength: float = 0.0
## Fuse, well, freeze, field or thrust time (s).
@export var effect_time: float = 0.0
## Bouncing laser: ricochets before it fades.
@export var bounces: int = 0
## Sprite color, for weapons that share a sprite.
@export var tint: Color = Color.WHITE

@export_group("Blade")
@export var melee_damage_mult: float = 1.0
@export var melee_range_bonus: float = 0.0
@export var melee_knockback_mult: float = 1.0
## Blades cut ropes they swing through (ROPE-14).
@export var cuts_ropes: bool = false


static var _cache: Dictionary = {}


static func load_by_id(weapon_id: StringName) -> WeaponDef:
	if _cache.has(weapon_id):
		return _cache[weapon_id]
	var path := DIR + String(weapon_id) + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("Unknown weapon: %s" % weapon_id)
		return null
	var def := load(path) as WeaponDef
	_cache[weapon_id] = def
	return def


## Every weapon in data/weapons, sorted by id so every device lists them the same way.
static func all() -> Array[WeaponDef]:
	var out: Array[WeaponDef] = []
	var files := Array(DirAccess.get_files_at(DIR))
	files.sort()
	for f: String in files:
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres"):
			var def := load_by_id(StringName(name.get_basename()))
			if def != null:
				out.append(def)
	return out
