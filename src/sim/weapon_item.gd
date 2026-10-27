class_name WeaponItem
extends RefCounted
## A weapon in the arena (§6.3): floating and spinning, being fetched by a rope, or held.

enum State { FLOATING, FETCHED, HELD }

var id: int = 0
var def: WeaponDef
var state: State = State.FLOATING
var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var angle: float = 0.0
var spin: float = 0.0
var ammo: int = 0
var holder_id: int = -1
var fetcher_id: int = -1
## Despawns at this tick while unclaimed (WPN-03).
var expire_tick: int = 0
## Special-weapon state (charges, timers), Phase 6.
var extra: Dictionary = {}


func get_state() -> Dictionary:
	return {
		"id": id, "def": def.id, "state": state, "pos": pos, "vel": vel, "angle": angle, "spin": spin,
		"ammo": ammo, "holder": holder_id, "fetcher": fetcher_id, "expire": expire_tick, "extra": extra.duplicate(true),
	}


static func from_state(s: Dictionary) -> WeaponItem:
	var item := WeaponItem.new()
	item.id = s["id"]
	item.def = WeaponDef.load_by_id(s["def"])
	item.state = s["state"]
	item.pos = s["pos"]
	item.prev_pos = item.pos
	item.vel = s["vel"]
	item.angle = s["angle"]
	item.spin = s["spin"]
	item.ammo = s["ammo"]
	item.holder_id = s["holder"]
	item.fetcher_id = s["fetcher"]
	item.expire_tick = s["expire"]
	item.extra = s["extra"].duplicate(true)
	return item
