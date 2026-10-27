class_name WeaponsView
extends Node2D
## Draws weapons and projectiles from the sim each frame (§6.3; WPN-03, WPN-06), interpolated
## between ticks: floating weapons spin and glow and blink faster as they are about to despawn;
## held weapons sit at the fighter's hand; bullets are glowing streaks; thrown guns spin.
## Phase 6 (§6.6): special projectiles (rockets, ricochet lasers, boomerangs, grenades, harpoons,
## freeze bolts, mines), gravity wells, tethers, rope duels, held shields and the announced spot of
## a legendary weapon. Visual only. Works across LAN rewinds because it reads the sim's lists fresh
## every frame.

const GLOW: Texture2D = preload("res://assets/art/fx/light_01.png")
const GLOW_SIZE: float = 150.0
const HAND_OFFSET: float = 26.0
const HELD_SCALE: float = 0.8
## Blink rate rises from BLINK_SLOW to BLINK_FAST (Hz) over the last WEAPON_BLINK_TIME seconds.
const BLINK_SLOW: float = 2.0
const BLINK_FAST: float = 10.0
const STREAK_TIME: float = 0.018
const SWORD_LENGTH: float = 78.0
const DEBRIS_TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/atlas/arena/spaceMeteors_001.tres"), preload("res://assets/art/atlas/arena/spaceMeteors_002.tres"),
	preload("res://assets/art/atlas/arena/spaceMeteors_003.tres"), preload("res://assets/art/atlas/arena/spaceMeteors_004.tres"),
]

var sim: MatchSim

var _glow_layer: Node2D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_glow_layer = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = add
	_glow_layer.show_behind_parent = true
	_glow_layer.draw.connect(_draw_glows)
	add_child(_glow_layer)


func _process(_delta: float) -> void:
	queue_redraw()
	_glow_layer.queue_redraw()


func _fraction() -> float:
	return Engine.get_physics_interpolation_fraction()


func _draw() -> void:
	if sim == null:
		return
	var f := _fraction()
	var now := Time.get_ticks_msec() / 1000.0
	var t := TuningDB.t
	for item in sim.weapons.items:
		match item.state:
			WeaponItem.State.HELD:
				_draw_held(item, f)
			_:
				var left := float(item.expire_tick - sim.tick) / SimIds.TICK_RATE
				if item.state == WeaponItem.State.FLOATING and left < t.weapon_blink_time:
					var rate := lerpf(BLINK_FAST, BLINK_SLOW, clampf(left / maxf(t.weapon_blink_time, 0.01), 0.0, 1.0))
					if int(now * rate * 2.0) % 2 == 1:
						continue
				_draw_item(item.def, item.prev_pos.lerp(item.pos, f), item.angle, 1.0)
	for p in sim.weapons.projectiles:
		var pos := p.prev_pos.lerp(p.pos, f)
		if p.kind == Projectile.Kind.THROWN:
			_draw_item(p.def, pos, now * 14.0, 0.9)
		elif p.kind == Projectile.Kind.DEBRIS:
			var tex := DEBRIS_TEXTURES[p.id % DEBRIS_TEXTURES.size()]
			draw_line(pos - p.vel * 0.08, pos, Color(1.0, 0.55, 0.2, 0.35), p.radius * 1.2, true)
			draw_set_transform(pos, now * 3.0 + p.id, Vector2.ONE * (p.radius * 2.2 / tex.get_width()))
			draw_texture(tex, -tex.get_size() * 0.5)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		elif not p.extra.get("special", false):
			var color := p.def.projectile_color if p.def != null else Color.WHITE
			draw_line(pos - p.vel * STREAK_TIME, pos, color, p.radius * 1.4, true)
			draw_circle(pos, p.radius, Color.WHITE)
		else:
			_draw_special(p, pos, now)
	_draw_special_world(now)


func _draw_special(p: Projectile, pos: Vector2, now: float) -> void:
	var color := p.def.projectile_color if p.def != null else Color.WHITE
	match p.extra.get("kind", &""):
		&"rocket":
			var dir := p.vel.normalized() if p.vel.length() > 1.0 else Vector2.RIGHT
			draw_line(pos - dir * (40.0 + 10.0 * sin(now * 50.0)), pos, Color(1.0, 0.7, 0.2, 0.8), 12.0, true)
			draw_set_transform(pos, dir.angle(), Vector2.ONE)
			draw_rect(Rect2(-16, -7, 30, 14), Color(0.85, 0.85, 0.9))
			draw_colored_polygon(PackedVector2Array([Vector2(14, -7), Vector2(24, 0), Vector2(14, 7)]), Color(1, 0.35, 0.2))
			draw_set_transform_matrix(Transform2D.IDENTITY)
		&"laser":
			draw_line(pos - p.vel * 0.03, pos, color, 7.0, true)
			draw_circle(pos, 5.0, Color.WHITE)
		&"freeze":
			draw_circle(pos, p.radius + 4.0, Color(color, 0.4))
			for i in 3:
				var a := now * 8.0 + TAU * i / 3.0
				draw_line(pos, pos + Vector2.from_angle(a) * p.radius * 1.4, Color.WHITE, 3.0)
		&"harpoon", &"tether_rope":
			var owner := sim.get_fighter(p.owner_id)
			if owner != null:
				draw_line(owner.view.global_position if owner.view != null else owner.global_position, pos, Color(color, 0.7), 3.0, true)
			var dir := p.vel.normalized() if p.vel.length() > 1.0 else Vector2.RIGHT
			draw_colored_polygon(PackedVector2Array([pos + dir * 16.0, pos - dir * 8.0 + dir.orthogonal() * 8.0, pos - dir * 8.0 - dir.orthogonal() * 8.0]), color)
		&"boomerang":
			_draw_boomerang(pos, now * 18.0, p.def.glow_color)
		_:
			# Grenades and mines in flight: their weapon sprite, spinning.
			_draw_item(p.def, pos, now * 6.0, 0.7)
			if p.extra.get("kind") == &"sticky" and p.extra.has("stuck"):
				var left := float(p.expire_tick - sim.tick) / SimIds.TICK_RATE
				if int(now * (4.0 if left > 0.8 else 12.0)) % 2 == 0:
					draw_circle(pos, 9.0, Color(1, 0.2, 0.1))


func _draw_boomerang(pos: Vector2, angle: float, color: Color) -> void:
	draw_set_transform(pos, angle, Vector2.ONE)
	var blade := PackedVector2Array([Vector2(-26, -4), Vector2(0, -10), Vector2(26, -4), Vector2(30, 4), Vector2(0, 0), Vector2(-30, 4)])
	draw_colored_polygon(blade, Color(color, 0.95))
	draw_polyline(blade + PackedVector2Array([blade[0]]), Color.WHITE, 2.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Wells, tethers, mines, rope duels and the announced legendary spot.
func _draw_special_world(now: float) -> void:
	var sw := sim.special_weapons
	for w in sw.wells:
		var at: Vector2 = w["pos"]
		var radius: float = w["radius"]
		var core: float = w["core"]
		var c := Color(0.8, 0.4, 1.0) if core > 0.0 else Color(0.6, 0.55, 1.0)
		draw_circle(at, radius, Color(c, 0.06))
		for i in 4:
			var k := fposmod(now * 0.8 + i / 4.0, 1.0)
			draw_arc(at, lerpf(radius, 20.0, k), now * 2.0 + i, now * 2.0 + i + 2.5, 24, Color(c, 0.5 * k), 3.0, true)
		if core > 0.0:
			draw_circle(at, core * 1.2, Color(1.0, 0.6, 0.2, 0.5))
			draw_circle(at, core, Color.BLACK)
	for tether in sw.tethers:
		var a := sim.get_fighter(int(tether["a"]))
		if a == null:
			continue
		var b := sim.get_fighter(int(tether["b"])) if int(tether["b"]) >= 0 else null
		var to: Vector2 = b.view.global_position if b != null else tether["point"]
		var col := Color(1.0, 0.85, 0.3) if tether["kind"] != &"mine" else Color(1.0, 0.35, 0.35)
		draw_line(a.view.global_position, to, col, 4.0, true)
	for m in sw.mines:
		var at: Vector2 = m["pos"]
		var armed := sim.tick >= int(m["armed"])
		draw_arc(at, float(m["radius"]), 0.0, TAU, 48, Color(1.0, 0.3, 0.3, 0.15 if armed else 0.05), 2.0, true)
		draw_circle(at, 14.0, Color(0.25, 0.25, 0.3))
		draw_circle(at, 6.0, Color(1.0, 0.2, 0.2) if armed and int(now * 3.0) % 2 == 0 else Color(0.5, 0.1, 0.1))
	for d in sw.duels:
		var point: Vector2 = d["point"]
		var pulse := 1.0 + 0.15 * sin(now * 20.0)
		draw_circle(point, 22.0 * pulse, Color(1.0, 0.9, 0.3, 0.8))
		draw_string(UiTheme.FONT, point + Vector2(-100, -40), "TAP!", HORIZONTAL_ALIGNMENT_CENTER, 200, 40, Color(1, 0.95, 0.5))
		draw_string(UiTheme.FONT, point + Vector2(-100, 60), "%d : %d" % [int(d["taps_a"]), int(d["taps_b"])], HORIZONTAL_ALIGNMENT_CENTER, 200, 26, Color.WHITE)
	var pending := sim.weapons.legendary_pending
	if not pending.is_empty():
		var at: Vector2 = pending["pos"]
		var left := maxf(0.0, float(int(pending["at"]) - sim.tick) / SimIds.TICK_RATE)
		var def := WeaponDef.load_by_id(pending["def"])
		var c := def.glow_color if def != null else Color.GOLD
		draw_arc(at, 70.0 + 20.0 * sin(now * 6.0), 0.0, TAU, 48, Color(c, 0.9), 5.0, true)
		draw_string(UiTheme.FONT, at + Vector2(-60, 14), "%d" % ceili(left), HORIZONTAL_ALIGNMENT_CENTER, 120, 44, Color(c, 0.95))


func _draw_glows() -> void:
	if sim == null:
		return
	var f := _fraction()
	for item in sim.weapons.items:
		if item.state == WeaponItem.State.HELD:
			continue
		var pos := item.prev_pos.lerp(item.pos, f)
		_glow_layer.draw_texture_rect(GLOW, Rect2(pos - Vector2.ONE * GLOW_SIZE * 0.5, Vector2.ONE * GLOW_SIZE), false, Color(item.def.glow_color, 0.55))
	for p in sim.weapons.projectiles:
		if p.kind == Projectile.Kind.BULLET and p.def != null:
			var pos := p.prev_pos.lerp(p.pos, f)
			_glow_layer.draw_texture_rect(GLOW, Rect2(pos - Vector2.ONE * 30.0, Vector2.ONE * 60.0), false, Color(p.def.projectile_color, 0.7))


func _draw_item(def: WeaponDef, pos: Vector2, angle: float, scale: float) -> void:
	if def == null:
		return
	draw_set_transform(pos, angle, Vector2.ONE * scale)
	if def.projectile_kind == &"shield":
		_draw_shield(def.glow_color)
	elif def.projectile_kind == &"boomerang":
		draw_set_transform_matrix(Transform2D.IDENTITY)
		_draw_boomerang(pos, angle, def.glow_color)
	elif def.texture != null:
		var size := Vector2.ONE * def.sprite_size
		draw_texture_rect(def.texture, Rect2(-size * 0.5, size), false, def.tint)
	else:
		_draw_sword(def.glow_color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_held(item: WeaponItem, f: float) -> void:
	var holder := sim.get_fighter(item.holder_id)
	if holder == null or holder.is_ko():
		return
	var pos := holder.prev_position.lerp(holder.global_position, f) + (holder.view.position if holder.view != null else Vector2.ZERO)
	var dir := holder.facing
	var angle := dir.angle()
	var phase := holder.melee_phase(sim.tick)
	if item.def.kind == WeaponDef.Kind.BLADE and phase != SimIds.MeleePhase.NONE:
		# Sweep through the swing arc during the melee.
		var t := TuningDB.t
		var total := float(t.melee_startup_ticks + t.melee_active_ticks)
		var k := clampf(float(sim.tick - holder.melee_start_tick) / total, 0.0, 1.0)
		var half := deg_to_rad(t.melee_arc_deg) * 0.5
		angle = holder.melee_dir.angle() + lerpf(-half, half, k)
		dir = Vector2.from_angle(angle)
	var flip := -1.0 if dir.x < 0.0 and item.def.kind != WeaponDef.Kind.BLADE else 1.0
	draw_set_transform(pos + dir * HAND_OFFSET, angle, Vector2(HELD_SCALE, HELD_SCALE * flip))
	if item.def.projectile_kind == &"shield":
		draw_set_transform(pos + dir * (TuningDB.t.fighter_radius + 8.0), angle, Vector2.ONE)
		_draw_shield(item.def.glow_color)
	elif item.def.projectile_kind == &"boomerang":
		if not item.extra.get("out", false):
			_draw_boomerang(pos + dir * HAND_OFFSET, angle, item.def.glow_color)
	elif item.def.texture != null:
		var size := Vector2.ONE * item.def.sprite_size
		draw_texture_rect(item.def.texture, Rect2(Vector2(-size.x * 0.3, -size.y * 0.5), size), false, item.def.tint)
	else:
		_draw_sword(item.def.glow_color, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## An energy shield: a curved plate facing +x.
func _draw_shield(color: Color) -> void:
	draw_arc(Vector2.ZERO, 34.0, -1.1, 1.1, 20, Color(color, 0.95), 10.0, true)
	draw_arc(Vector2.ZERO, 34.0, -1.1, 1.1, 20, Color(1, 1, 1, 0.8), 3.0, true)


## A glowing energy blade along +x: hilt at the origin when held, centered when floating.
func _draw_sword(color: Color, held: bool = false) -> void:
	var start := 0.0 if held else -SWORD_LENGTH * 0.5
	var guard := start + 14.0
	draw_rect(Rect2(start, -4, 16, 8), Color(0.35, 0.35, 0.45))
	draw_rect(Rect2(guard, -11, 6, 22), Color(0.75, 0.75, 0.85))
	var blade := PackedVector2Array([
		Vector2(guard + 6, -6), Vector2(start + SWORD_LENGTH - 10, -5),
		Vector2(start + SWORD_LENGTH, 0), Vector2(start + SWORD_LENGTH - 10, 5), Vector2(guard + 6, 6)])
	draw_colored_polygon(blade, Color(color, 0.95))
	draw_polyline(blade + PackedVector2Array([blade[0]]), Color.WHITE, 2.0, true)
