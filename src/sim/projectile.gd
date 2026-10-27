class_name Projectile
extends RefCounted
## A bullet, pellet, thrown empty weapon (§6.3) or a piece of Debris Storm rock (§6.4, def null). Moves in a straight line; hits the first wall or
## fighter on its path. Special kinds (rockets, grenades, lasers, ...) arrive with Phase 6.

enum Kind { BULLET, THROWN, DEBRIS }

var id: int = 0
var kind: Kind = Kind.BULLET
var def: WeaponDef
var owner_id: int = -1
var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var damage: float = 0.0
var knockback: float = 0.0
var radius: float = 6.0
var expire_tick: int = 0
## Behavior state for special projectiles (bounces left, stuck target, fuse...), Phase 6.
var extra: Dictionary = {}


func get_state() -> Dictionary:
	return {
		"id": id, "kind": kind, "def": def.id if def != null else &"", "owner": owner_id, "pos": pos, "vel": vel, "damage": damage,
		"knockback": knockback, "radius": radius, "expire": expire_tick, "extra": extra.duplicate(true),
	}


static func from_state(s: Dictionary) -> Projectile:
	var p := Projectile.new()
	p.id = s["id"]
	p.kind = s["kind"]
	p.def = WeaponDef.load_by_id(s["def"]) if not String(s["def"]).is_empty() else null
	p.owner_id = s["owner"]
	p.pos = s["pos"]
	p.prev_pos = p.pos
	p.vel = s["vel"]
	p.damage = s["damage"]
	p.knockback = s["knockback"]
	p.radius = s["radius"]
	p.expire_tick = s["expire"]
	p.extra = s["extra"].duplicate(true)
	return p
