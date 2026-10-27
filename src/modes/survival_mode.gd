class_name SurvivalMode
extends GameMode
## Co-op Survival (§6.6): the players (team 0) against waves of bot enemies (team 1). The enemy
## fighters exist from the start (ModeDef.enemy_slots) and sit benched until a wave calls them in;
## wave n brings n + 1 of them. Every BOSS_EVERY waves a giant boss joins: players rope onto it and
## hit its weak points. The team shares ModeDef.team_lives; surviving score_target waves wins.
## Score: waves cleared (key 0) and players lost (key 1).

const FIRST_WAVE: float = 3.0
const WAVE_BREAK: float = 5.0
const BOSS_EVERY: int = 5
const BOSS_SPEED: float = 150.0
const BOSS_HP_BASE: float = 260.0
const BOSS_HP_PER_PLAYER: float = 110.0
const WEAK_POINTS: int = 3
const WEAK_SPIN: float = 0.7
const WEAK_HIT_RADIUS: float = 70.0
const MELEE_WEAK_DAMAGE: float = 14.0
const BOSS_VOLLEY: float = 2.5
const BOSS_BULLETS: int = 10
const BOSS_BULLET_SPEED: float = 650.0
const BOSS_BULLET_DAMAGE: float = 9.0

var wave: int = 0
var lives: int = 0
var wave_active: bool = false
var next_wave: int = 0
var boss: BossBody
var boss_active: bool = false
var boss_hp: float = 0.0
var boss_max: float = 0.0
var boss_pos: Vector2 = Vector2.ZERO
var boss_next_volley: int = 0
## fighter id -> melee start tick already counted against the boss
var _melee_seen: Dictionary = {}


func is_team_mode() -> bool:
	return true


func start(tick: int) -> void:
	super.start(tick)
	var humans := sim.fighters.size() - def.enemy_slots
	for f in sim.fighters:
		sim.teams[f.fighter_id] = 0 if f.fighter_id < humans else 1
	scores = {0: 0, 1: 0}
	lives = def.team_lives
	for f in enemies():
		_bench(f)
	next_wave = tick + SimIds.ticks(FIRST_WAVE)
	_make_boss()


func enemies() -> Array[Fighter]:
	var out: Array[Fighter] = []
	for f in sim.fighters:
		if int(sim.teams.get(f.fighter_id, 0)) == 1:
			out.append(f)
	return out


func nearest_human(at: Vector2) -> Fighter:
	var best: Fighter = null
	for f in sim.fighters:
		if int(sim.teams.get(f.fighter_id, 0)) == 0 and not f.is_ko():
			if best == null or f.global_position.distance_to(at) < best.global_position.distance_to(at):
				best = f
	return best


func key_name(key: int) -> String:
	return "PLAYERS" if key == 0 else "ENEMIES"


func score_text(key: int) -> String:
	return "WAVE %d" % int(scores.get(0, 0)) if key == 0 else "%d LOST" % int(scores.get(1, 0))


func _bench(f: Fighter) -> void:
	f.state = SimIds.FighterState.KO
	f.hp = 0.0
	f.velocity = Vector2.ZERO
	f.respawn_tick = Fighter.BENCHED


func _make_boss() -> void:
	var host := sim.get_parent().get_node_or_null("Arena") if sim.get_parent() != null else null
	if host == null:
		return
	boss = BossBody.new()
	boss.name = "Boss"
	boss.mode = self
	boss.object_id = sim.arena_objects.size()
	host.add_child(boss)
	sim.arena_objects.append(boss)
	boss_pos = sim.hazards.bounds.get_center()
	boss.position = boss_pos
	boss.set_active(false)
	boss.sync_physics_transform()


func weak_points(tick: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in WEAK_POINTS:
		var a := WEAK_SPIN * float(tick) / SimIds.TICK_RATE + TAU * i / WEAK_POINTS
		out.append(boss_pos + Vector2.from_angle(a) * BossBody.RADIUS)
	return out


func on_tick(tick: int) -> void:
	if boss_active and boss != null:
		_move_boss()
	if not sim.authoritative:
		return
	if boss_active:
		_boss_melee(tick)
		if tick >= boss_next_volley:
			_volley(tick)
	if not wave_active:
		if tick >= next_wave and wave < def.score_target:
			_start_wave(tick)
		return
	var alive := enemies().filter(func(f: Fighter) -> bool: return not f.is_ko())
	if alive.is_empty() and not boss_active:
		wave_active = false
		scores[0] = wave
		next_wave = tick + SimIds.ticks(WAVE_BREAK)
		sim.queue_event(&"match_event", [&"wave_cleared", true, WAVE_BREAK])


func _start_wave(tick: int) -> void:
	wave += 1
	wave_active = true
	var is_boss := wave % BOSS_EVERY == 0 and boss != null
	var count := mini(def.enemy_slots, wave + 1)
	if is_boss:
		count = mini(def.enemy_slots, 2)
		var humans := sim.fighters.size() - def.enemy_slots
		boss_max = BOSS_HP_BASE + BOSS_HP_PER_PLAYER * humans
		boss_hp = boss_max
		boss_active = true
		boss_pos = _far_point()
		boss.position = boss_pos
		boss.set_active(true)
		boss.sync_physics_transform()
		boss_next_volley = tick + SimIds.ticks(BOSS_VOLLEY)
	var bench := enemies()
	for i in count:
		var f := bench[i]
		f.respawn_tick = tick
		sim.respawn(f)
	sim.queue_event(&"wave_started", [wave, is_boss])


## A spot away from the players for the boss to appear.
func _far_point() -> Vector2:
	var bounds := sim.hazards.bounds.grow(-BossBody.RADIUS - 80.0)
	var best := bounds.get_center()
	var best_d := -1.0
	for p: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), bounds.end, bounds.get_center()]:
		var h := nearest_human(p)
		var d := p.distance_to(h.global_position) if h != null else 0.0
		if d > best_d:
			best_d = d
			best = p
	return best


func _move_boss() -> void:
	var target := nearest_human(boss_pos)
	if target != null:
		var offset := target.global_position - boss_pos
		if offset.length() > BossBody.RADIUS + 60.0:
			boss_pos += offset.normalized() * BOSS_SPEED * SimIds.DT
	var bounds := sim.hazards.bounds.grow(-BossBody.RADIUS - 50.0)
	boss_pos = Vector2(clampf(boss_pos.x, bounds.position.x, bounds.end.x), clampf(boss_pos.y, bounds.position.y, bounds.end.y))
	boss.position = boss_pos
	boss.sync_physics_transform()


## A player's punch that lands near a weak point hurts the boss (once per swing).
func _boss_melee(tick: int) -> void:
	var reach := TuningDB.t.melee_range + WEAK_HIT_RADIUS * 0.5
	for f in sim.fighters:
		if int(sim.teams.get(f.fighter_id, 0)) != 0 or f.is_ko() or f.melee_phase(tick) != SimIds.MeleePhase.ACTIVE:
			continue
		if int(_melee_seen.get(f.fighter_id, SimIds.NO_TICK)) == f.melee_start_tick:
			continue
		for p in weak_points(tick):
			if f.global_position.distance_to(p) <= reach:
				_melee_seen[f.fighter_id] = f.melee_start_tick
				var blade := Melee.blade_of(f)
				damage_boss(MELEE_WEAK_DAMAGE * (blade.melee_damage_mult if blade != null else 1.0), p)
				break


func _volley(tick: int) -> void:
	boss_next_volley = tick + SimIds.ticks(BOSS_VOLLEY)
	var spin := sim.rng.randf() * TAU
	for i in BOSS_BULLETS:
		var dir := Vector2.from_angle(spin + TAU * i / BOSS_BULLETS)
		var p := Projectile.new()
		p.id = sim.next_entity_id()
		p.kind = Projectile.Kind.BULLET
		p.owner_id = -1
		p.pos = boss_pos + dir * (BossBody.RADIUS + 20.0)
		p.prev_pos = p.pos
		p.vel = dir * BOSS_BULLET_SPEED
		p.damage = BOSS_BULLET_DAMAGE
		p.knockback = 400.0
		p.radius = 12.0
		p.expire_tick = tick + SimIds.ticks(3.0)
		p.extra = {"boss": true}
		sim.weapons.projectiles.append(p)


func damage_boss(amount: float, at: Vector2) -> void:
	if not boss_active:
		return
	boss_hp -= amount
	sim.queue_event(&"boss_hit", [at, amount])
	if boss_hp > 0.0:
		return
	boss_active = false
	boss.set_active(false)
	for f in sim.fighters:
		if f.cling_object == boss:
			f.leave_surface()
		if f.rope.anchor_object == boss:
			f.rope.release(false)
	sim.queue_event(&"match_event", [&"boss_defeated", true, 0.0])


## Shots at the boss: only weak points take damage.
func on_object_hit(obj: ArenaObject, point: Vector2, damage: float, _owner_id: int, _tick: int) -> bool:
	if obj != boss or boss == null:
		return false
	if sim.authoritative:
		for p in weak_points(sim.tick):
			if p.distance_to(point) <= WEAK_HIT_RADIUS:
				damage_boss(damage, point)
				return true
		sim.queue_event(&"projectile_blocked", [point, &""])
	return true


func on_blast(at: Vector2, radius: float, damage: float, _owner_id: int, _tick: int) -> void:
	if not boss_active or not sim.authoritative:
		return
	for p in weak_points(sim.tick):
		if p.distance_to(at) <= radius + WEAK_HIT_RADIUS * 0.5:
			damage_boss(damage * 0.7, p)
			return


func on_ko(victim: Fighter, _killer_id: int, _cause: StringName) -> void:
	if int(sim.teams.get(victim.fighter_id, 0)) == 1:
		victim.respawn_tick = Fighter.BENCHED
		return
	lives -= 1
	scores[1] = int(scores.get(1, 0)) + 1


func is_over(_tick: int) -> bool:
	return lives <= 0 or int(scores.get(0, 0)) >= def.score_target


func finish(tick: int) -> void:
	ended = true
	end_tick = tick
	winner = 0 if lives > 0 else 1
	sim.queue_event(&"match_ended", [winner])


func ranking() -> Array[int]:
	var out: Array[int] = [0, 1]
	if winner == 1:
		out = [1, 0]
	return out


## Enemy bots chase the players; the players (bots among them) go for the boss's weak points.
func bot_goal(f: Fighter, tick: int) -> Vector2:
	if boss_active and int(sim.teams.get(f.fighter_id, 0)) == 0:
		var best := Vector2.INF
		for p in weak_points(tick):
			if f.global_position.distance_to(p) < f.global_position.distance_to(best):
				best = p
		return best
	return Vector2.INF


func _get_extra() -> Dictionary:
	return {
		"wave": wave, "lives": lives, "wave_active": wave_active, "next_wave": next_wave, "boss_active": boss_active,
		"boss_hp": boss_hp, "boss_max": boss_max, "boss_pos": boss_pos, "volley": boss_next_volley, "melee_seen": _melee_seen.duplicate(),
	}


func _set_extra(s: Dictionary) -> void:
	wave = s["wave"]
	lives = s["lives"]
	wave_active = s["wave_active"]
	next_wave = s["next_wave"]
	boss_hp = s["boss_hp"]
	boss_max = s["boss_max"]
	boss_pos = s["boss_pos"]
	boss_next_volley = s["volley"]
	_melee_seen = s["melee_seen"].duplicate()
	boss_active = s["boss_active"]
	if boss != null:
		boss.position = boss_pos
		boss.set_active(boss_active)
		boss.sync_physics_transform()
