class_name Melee
## Melee formulas and hit resolution (§4.8, MEL-01 to MEL-03), plus the Phase 3 combat depth (§6.3):
## blades hit harder and reach further, any swing cuts ropes in its arc (ROPE-14, CNT-02), and fast
## fighters ram (MEL-05). MatchSim calls resolve() and resolve_rams() once per tick after every
## fighter has moved (§3.3 step 4).


## MEL-02: damage scales with closing speed. The combo bonus applies after the cap (45 -> 56).
static func damage(closing: float, is_combo: bool, t: Tuning) -> float:
	var d := minf(t.melee_base_damage + t.melee_damage_per_speed * closing, t.melee_max_damage)
	return d * t.combo_damage_mult if is_combo else d


static func knockback(closing: float, t: Tuning) -> float:
	return minf(t.melee_kb_base + t.melee_kb_per_speed * closing, t.melee_kb_max)


## Per-entity hitstop (§3.1 rule 7, §4.8 table).
static func hitstop_ticks(dmg: float, is_combo: bool, t: Tuning) -> int:
	var ticks := mini(t.hitstop_base_ticks + floori(dmg / t.hitstop_damage_step), t.hitstop_max_ticks)
	return ticks + t.hitstop_combo_bonus_ticks if is_combo else ticks


## Closing speed: rewards a victim flying into you as much as you flying into them.
static func closing_speed(attacker: Fighter, victim: Fighter, dir_to_victim: Vector2) -> float:
	return maxf(0.0, (attacker.velocity - victim.velocity).dot(dir_to_victim))


## MEL-03: the attacker was pulling this victim at some point in the last COMBO_WINDOW.
static func is_combo(attacker: Fighter, victim: Fighter, tick: int, t: Tuning) -> bool:
	return victim.last_pulled_by_id == attacker.fighter_id and tick - victim.last_pulled_tick <= SimIds.ticks(t.combo_window)


## The blade the attacker holds, or null.
static func blade_of(attacker: Fighter) -> WeaponDef:
	if attacker.sim == null:
		return null
	var item := attacker.sim.weapons.held_by(attacker)
	return item.def if item != null and item.def.kind == WeaponDef.Kind.BLADE else null


static func reach(attacker: Fighter, t: Tuning) -> float:
	var blade := blade_of(attacker)
	return t.melee_range + (blade.melee_range_bonus if blade != null else 0.0)


static func resolve(fighters: Array[Fighter], tick: int, t: Tuning) -> void:
	var half_arc := deg_to_rad(t.melee_arc_deg) * 0.5
	for attacker in fighters:
		if attacker.is_ko() or attacker.melee_phase(tick) != SimIds.MeleePhase.ACTIVE:
			continue
		var range := reach(attacker, t)
		_cut_ropes(attacker, fighters, range, half_arc)
		for victim in fighters:
			if victim == attacker or not victim.can_be_hit(tick) or attacker.melee_hit_ids.has(victim.fighter_id):
				continue
			var offset := victim.global_position - attacker.global_position
			var dist := offset.length()
			if dist > range:
				continue
			var dir := attacker.melee_dir
			if dist > 0.001:
				dir = offset / dist
				if absf(attacker.melee_dir.angle_to(dir)) > half_arc:
					continue
			if attacker.sim != null and not attacker.sim.are_enemies(attacker, victim):
				_throw_teammate(attacker, victim, dir, t)
				continue
			_hit(attacker, victim, dir, tick, t)
			if attacker.is_ko():
				break


## ROPE-14 / CNT-02: a swing cuts any other fighter's rope whose line passes through its arc.
static func _cut_ropes(attacker: Fighter, fighters: Array[Fighter], range: float, half_arc: float) -> void:
	for owner in fighters:
		if owner == attacker or not owner.rope.is_out():
			continue
		var a := owner.global_position
		var b := owner.rope.hook_pos
		var closest := Geometry2D.get_closest_point_to_segment(attacker.global_position, a, b)
		var offset := closest - attacker.global_position
		if offset.length() > range:
			continue
		if offset.length() > 1.0 and absf(attacker.melee_dir.angle_to(offset)) > half_arc:
			continue
		owner.rope.release(false)
		attacker.emit_event(&"rope_cut", [attacker.fighter_id, owner.fighter_id, closest])


static func _hit(attacker: Fighter, victim: Fighter, dir: Vector2, tick: int, t: Tuning) -> void:
	var closing := closing_speed(attacker, victim, dir)
	var combo := is_combo(attacker, victim, tick, t)
	var dmg := damage(closing, combo, t)
	var kb := knockback(closing, t)
	var blade := blade_of(attacker)
	if blade != null:
		dmg *= blade.melee_damage_mult
		kb *= blade.melee_knockback_mult
	var stop := hitstop_ticks(dmg, combo, t)
	attacker.melee_hit_ids.append(victim.fighter_id)
	attacker.emit_event(&"hit_landed", [attacker.fighter_id, victim.fighter_id, dmg, kb, combo])
	victim.take_hit(tick, attacker.fighter_id, dmg, dir * kb, stop)
	if attacker.sim != null:
		attacker.sim.on_contact(attacker, victim, &"melee")
	attacker.freeze_ticks = maxi(attacker.freeze_ticks, stop)
	if not victim.is_ko():
		victim.freeze_ticks = maxi(victim.freeze_ticks, stop)


## §6.5 2v2: melee on a teammate throws them (knockback, no damage), for example at an enemy.
static func _throw_teammate(attacker: Fighter, victim: Fighter, dir: Vector2, t: Tuning) -> void:
	attacker.melee_hit_ids.append(victim.fighter_id)
	victim.leave_surface()
	if victim.rope.is_out():
		victim.rope.release(false)
	victim.velocity = dir * t.team_throw_speed + attacker.velocity * 0.3
	attacker.emit_event(&"teammate_thrown", [attacker.fighter_id, victim.fighter_id])
	attacker.sim.on_contact(attacker, victim, &"throw")


## MEL-05: two fighters touching at a high closing speed: the faster one rams the other, unarmed.
## Each pair can ram once per RAM_COOLDOWN (stored in the sim, so it survives rewinds).
static func resolve_rams(sim: MatchSim, tick: int, t: Tuning) -> void:
	var fighters := sim.fighters
	var touch := t.fighter_radius * 2.0 + 4.0
	for i in fighters.size():
		var a := fighters[i]
		if a.is_ko():
			continue
		for j in range(i + 1, fighters.size()):
			var b := fighters[j]
			if b.is_ko() or not sim.are_enemies(a, b):
				continue
			var offset := b.global_position - a.global_position
			var dist := offset.length()
			if dist > touch or dist < 0.001:
				continue
			var n := offset / dist
			var closing := (a.velocity - b.velocity).dot(n)
			if closing < t.ram_min_closing:
				continue
			# A pulled enemy flies past its puller to be punched (ROPE-13, MEL-03), not into a ram.
			if _pulled_recently(a, b, tick, t) or _pulled_recently(b, a, tick, t):
				continue
			var key := "%d:%d" % [a.fighter_id, b.fighter_id]
			if tick < int(sim.ram_cooldowns.get(key, -1)):
				continue
			sim.ram_cooldowns[key] = tick + SimIds.ticks(t.ram_cooldown)
			var rammer := a if a.velocity.length() >= b.velocity.length() else b
			var victim := b if rammer == a else a
			if not victim.can_be_hit(tick):
				continue
			var dir := n if rammer == a else -n
			var dmg := t.ram_damage_base + t.ram_damage_per_speed * closing
			var kb := minf(closing * t.ram_knockback_mult, t.melee_kb_max)
			var stop := hitstop_ticks(dmg, false, t)
			sim.queue_event(&"rammed", [rammer.fighter_id, victim.fighter_id, closing])
			sim.queue_event(&"hit_landed", [rammer.fighter_id, victim.fighter_id, dmg, kb, false])
			victim.take_hit(tick, rammer.fighter_id, dmg, dir * kb, stop)
			rammer.velocity *= t.ram_attacker_keep
			rammer.freeze_ticks = maxi(rammer.freeze_ticks, stop)
			if not victim.is_ko():
				victim.freeze_ticks = maxi(victim.freeze_ticks, stop)


static func _pulled_recently(puller: Fighter, target: Fighter, tick: int, t: Tuning) -> bool:
	return target.pulled_by_id == puller.fighter_id or is_combo(puller, target, tick, t)
