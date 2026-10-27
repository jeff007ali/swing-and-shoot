extends Node
## Signal bus between the simulation and everything that reacts to it (§3.1 rule 6, §3.7): views,
## sound, haptics, playtest logging and, later, stats and challenges (§7).
## Fighters are referred to by fighter_id so events stay network friendly.
## MatchSim queues events during a tick and emits them at the end of it (§3.3 step 7).

@warning_ignore_start("unused_signal")
signal rope_fired(fighter_id: int, target: Vector2)
signal rope_attached(fighter_id: int, mode: int, point: Vector2)
signal rope_missed(fighter_id: int)
## The hook hit a fighter it may not pull (pull immunity, spawn invulnerability) and clinked off.
signal rope_bounced(fighter_id: int, point: Vector2)
## fling_mode is ORBIT or SWING when the release flung the fighter (slingshot), else NONE.
signal rope_released(fighter_id: int, fling_mode: int)
signal clung(fighter_id: int, point: Vector2, normal: Vector2)
signal kicked_off(fighter_id: int, direction: Vector2)
signal melee_started(fighter_id: int, direction: Vector2)
signal hit_landed(attacker_id: int, victim_id: int, damage: float, knockback: float, is_combo: bool)
## cause and last_puller_id let future challenges ask "pulled into a hazard" (§7).
signal fighter_ko(fighter_id: int, killer_id: int, cause: StringName, last_puller_id: int)
signal fighter_respawned(fighter_id: int)
## Weapons (§6.3).
signal weapon_spawned(weapon_id: int, def_id: StringName, position: Vector2)
signal weapon_despawned(weapon_id: int, position: Vector2)
signal weapon_picked(fighter_id: int, weapon_id: int, def_id: StringName)
signal weapon_dropped(fighter_id: int, weapon_id: int, position: Vector2)
signal weapon_fired(fighter_id: int, def_id: StringName, muzzle: Vector2, direction: Vector2)
signal weapon_thrown(fighter_id: int, def_id: StringName, position: Vector2)
signal projectile_blocked(position: Vector2, def_id: StringName)
## Combat depth (§6.3).
signal parried(fighter_id: int, point: Vector2)
signal rope_cut(cutter_id: int, owner_id: int, point: Vector2)
signal rammed(rammer_id: int, victim_id: int, closing_speed: float)
## Hazards and mid-match events (§6.4).
signal shocked(fighter_id: int, point: Vector2)
signal vent_changed(vent_index: int, state: int)
signal object_broken(object_id: int, position: Vector2)
signal object_restored(object_id: int, position: Vector2)
signal tank_exploded(object_id: int, position: Vector2, radius: float)
signal match_event(event_id: StringName, started: bool, duration: float)
# Game modes (§6.5). winner is a score key (fighter or team id), -1 for a draw.
signal match_ended(winner: int)
signal bomb_passed(from_id: int, to_id: int)
signal bomb_exploded(fighter_id: int, position: Vector2)
signal level_up(fighter_id: int, level: int)
signal teammate_thrown(thrower_id: int, fighter_id: int)
# Phase 6 (§6.6)
signal legendary_incoming(def_id: StringName, position: Vector2, seconds: float)
signal blast(position: Vector2, radius: float)
signal laser_bounced(position: Vector2)
signal frozen(fighter_id: int, seconds: float)
signal tethered(fighter_id: int, other_id: int, kind: StringName)
signal tether_smash(a_id: int, b_id: int, position: Vector2)
signal grenade_stuck(fighter_id: int)
signal well_opened(position: Vector2, radius: float, black_hole: bool)
signal mine_placed(position: Vector2)
signal mine_triggered(fighter_id: int, position: Vector2)
signal repulsed(fighter_id: int, position: Vector2, radius: float)
signal boomerang_caught(fighter_id: int)
signal wrecking_ball(ball_id: int, victim_id: int, position: Vector2)
signal rope_clash(a_id: int, b_id: int, position: Vector2)
signal rope_duel_started(a_id: int, b_id: int, position: Vector2)
signal rope_duel_ended(winner_id: int, loser_id: int)
signal projectile_caught(fighter_id: int, position: Vector2)
signal projectile_whipped(fighter_id: int, position: Vector2)
signal shield_ripped(fighter_id: int, position: Vector2)
# Co-op Survival
signal wave_started(wave: int, boss: bool)
signal boss_hit(position: Vector2, damage: float)
@warning_ignore_restore("unused_signal")
