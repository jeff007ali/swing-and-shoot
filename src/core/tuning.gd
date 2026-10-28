class_name Tuning
extends Resource
## Every gameplay number (§4.10). Property names are the doc's keys in snake_case.
## The live copy lives in TuningDB and the debug overlay builds a slider for each property.

@export_group("Body")
@export_range(10, 60, 1) var fighter_radius: float = 28.0
@export_range(0, 3, 0.01) var drag: float = 0.25
@export_range(200, 4000, 10) var max_speed: float = 2000.0

@export_group("Rope")
@export_range(500, 8000, 50) var hook_speed: float = 4400.0
@export_range(200, 1400, 10) var rope_range: float = 720.0
@export_range(0, 2, 0.01) var rope_cooldown: float = 0.25
@export_range(0, 1, 0.01) var rope_retract_time: float = 0.1
@export_range(0, 12000, 50) var reel_accel: float = 5400.0
@export_range(100, 4000, 10) var reel_max_speed: float = 1650.0
@export_range(0.2, 6, 0.1) var reel_max_time: float = 2.0

@export_group("Orbit and swing")
@export_range(0, 1500, 10) var orbit_min_tangent_speed: float = 260.0
@export_range(0, 90, 1) var orbit_min_angle: float = 55.0
@export_range(0, 400, 5) var orbit_reel_speed: float = 60.0
@export_range(20, 400, 5) var orbit_min_length: float = 90.0
@export_range(0.2, 5, 0.1) var latched_orbit_max_time: float = 1.5
@export_range(1, 2, 0.01) var slingshot_release_bonus: float = 1.10
@export_range(0, 6, 0.05) var turbine_omega: float = 1.8
@export_range(20, 400, 5) var swing_min_length: float = 110.0
@export_range(1, 2, 0.01) var swing_release_bonus: float = 1.15

@export_group("Enemy pull")
@export_range(0, 12000, 50) var pull_accel: float = 5200.0
@export_range(100, 4000, 10) var pull_max_speed: float = 1500.0
@export_range(0, 1, 0.01) var pull_reaction: float = 0.15
@export_range(10, 300, 5) var pull_arrive_dist: float = 70.0
@export_range(0.1, 3, 0.05) var pull_max_time: float = 1.0
@export_range(0, 3, 0.05) var pull_immunity: float = 1.0

@export_group("Cling and kick")
@export_range(0, 5, 0.05) var cling_time: float = 1.2
@export_range(0, 400, 5) var cling_drift_speed: float = 60.0
@export_range(100, 2500, 10) var kick_speed: float = 950.0
@export_range(0, 0.5, 0.01) var kick_window: float = 0.12
@export_range(5, 150, 1) var swipe_min_dist: float = 30.0
@export_range(0, 1, 0.01) var kick_min_normal_dot: float = 0.2
## After letting go of a moving surface (turbine) a fighter can't cling to it again for this long (s).
@export_range(0, 2, 0.05) var moving_release_grace: float = 0.75

@export_group("Touch and aim")
@export_range(0.05, 1, 0.01) var hold_threshold: float = 0.20
@export_range(0, 200, 1) var aim_assist_radius: float = 64.0
## Extra reach beyond rope_range for snapping onto a fighter ("ROPE_RANGE + 40" in §4.5).
@export_range(0, 200, 1) var aim_assist_range_slack: float = 40.0

@export_group("Melee")
@export_range(20, 300, 1) var melee_range: float = 95.0
@export_range(20, 500, 5) var melee_autoaim_range: float = 180.0
## Width of the melee hit arc (§4.8: 120 degrees).
@export_range(10, 360, 5) var melee_arc_deg: float = 120.0
@export_range(0, 20, 1) var melee_startup_ticks: int = 2
@export_range(1, 30, 1) var melee_active_ticks: int = 6
@export_range(0, 60, 1) var melee_recovery_ticks: int = 14
@export_range(0, 2, 0.01) var melee_cooldown: float = 0.35
@export_range(0, 1000, 10) var melee_lunge_speed: float = 140.0
@export_range(0, 50, 0.5) var melee_base_damage: float = 8.0
@export_range(0, 0.1, 0.001) var melee_damage_per_speed: float = 0.025
@export_range(1, 100, 1) var melee_max_damage: float = 45.0
@export_range(0, 2000, 10) var melee_kb_base: float = 350.0
@export_range(0, 3, 0.05) var melee_kb_per_speed: float = 1.1
@export_range(100, 4000, 10) var melee_kb_max: float = 1700.0
@export_range(0, 1.5, 0.01) var combo_window: float = 0.35
@export_range(1, 3, 0.05) var combo_damage_mult: float = 1.25
@export_range(0, 1, 0.01) var hitstun_base: float = 0.12
@export_range(500, 10000, 100) var hitstun_kb_divisor: float = 4000.0

@export_group("Health and match")
@export_range(1, 500, 1) var max_hp: float = 100.0
@export_range(0, 10, 0.1) var respawn_time: float = 2.0
@export_range(0, 5, 0.1) var spawn_invuln: float = 1.5
@export_range(0, 1000, 10) var separation_speed: float = 200.0

@export_group("Feel")
@export_range(0, 80, 1) var shake_max_offset: float = 24.0
## Hitstop per hit (§4.8 table): base + floor(damage / step) ticks, capped, plus a combo bonus.
@export_range(0, 20, 1) var hitstop_base_ticks: int = 3
@export_range(1, 50, 1) var hitstop_damage_step: float = 8.0
@export_range(0, 30, 1) var hitstop_max_ticks: int = 9
@export_range(0, 20, 1) var hitstop_combo_bonus_ticks: int = 3

@export_group("Weapons")
## Pickup and hook radius of a floating weapon (px).
@export_range(10, 80, 1) var weapon_radius: float = 30.0
## Floating weapons drift at 40-80 px/s (§6.3).
@export_range(0, 200, 5) var weapon_drift_min: float = 40.0
@export_range(0, 300, 5) var weapon_drift_max: float = 80.0
## Spin while floating (rad/s), WPN-06.
@export_range(0, 10, 0.1) var weapon_spin: float = 1.6
## Unclaimed weapons despawn after this (s), WPN-03.
@export_range(1, 60, 0.5) var weapon_lifetime: float = 15.0
## Blinking starts this long before despawn (s).
@export_range(0, 20, 0.5) var weapon_blink_time: float = 5.0
## A spawn point is filled this often (s), WPN-01.
@export_range(0.5, 60, 0.5) var weapon_spawn_interval: float = 6.0
## WPN-04: first legendary weapon after this long, then one every LEGENDARY_INTERVAL (s), each
## announced LEGENDARY_COUNTDOWN seconds before it appears.
@export_range(5, 600, 5) var legendary_first_delay: float = 45.0
@export_range(10, 600, 5) var legendary_interval: float = 70.0
@export_range(0, 10, 0.5) var legendary_countdown: float = 3.0
## Speed of a dropped weapon (px/s).
@export_range(0, 1500, 10) var weapon_drop_push: float = 260.0
## Fire auto-aims at the nearest enemy within this cone of facing (CTL-05).
@export_range(0, 180, 1) var fire_autoaim_cone_deg: float = 30.0
## An empty gun is thrown at this speed (WPN-05).
@export_range(200, 4000, 10) var throw_speed: float = 1500.0
@export_range(0, 100, 1) var throw_damage_base: float = 10.0
@export_range(0, 0.1, 0.001) var throw_damage_per_speed: float = 0.02
@export_range(0, 3000, 10) var throw_knockback: float = 650.0
## Hitstop on a fighter hit by a projectile.
@export_range(0, 20, 1) var projectile_hitstop_ticks: int = 2

@export_group("Pickups")
## Haste pickup: reel, kick and top speed x this, rope cooldown / this.
@export_range(1, 3, 0.05) var haste_mult: float = 1.3
## Power pickup: damage dealt x this.
@export_range(1, 3, 0.05) var power_mult: float = 1.5
## Armor pickup: soaks damage before HP, up to this much.
@export_range(0, 200, 1) var max_armor: float = 60.0

@export_group("Combat depth")
## A hit with at least this knockback knocks the weapon loose (HP-03).
@export_range(0, 4000, 10) var disarm_knockback: float = 1200.0
## Melee parries bullets and hooks this long around its active frames (MEL-04).
@export_range(0, 0.5, 0.01) var parry_window: float = 0.1
## Ramming needs this closing speed (MEL-05).
@export_range(100, 3000, 10) var ram_min_closing: float = 900.0
## §6.5 2v2: speed a teammate is thrown at by a melee hit (px/s).
@export_range(0, 3000, 10) var team_throw_speed: float = 1300.0
@export_range(0, 100, 1) var ram_damage_base: float = 6.0
@export_range(0, 0.1, 0.001) var ram_damage_per_speed: float = 0.02
## Knockback = closing speed x this.
@export_range(0, 3, 0.05) var ram_knockback_mult: float = 0.9
## The rammer keeps this share of its speed.
@export_range(0, 1, 0.05) var ram_attacker_keep: float = 0.4
## Same pair can't ram again within this (s).
@export_range(0, 3, 0.05) var ram_cooldown: float = 0.5
## A clinging target holds on; the puller is dragged at pull accel x this (CNT-01).
@export_range(0, 1, 0.01) var cling_pull_resistance: float = 0.35
## A pulled clinging target's cling timer drains this many times faster.
@export_range(1, 10, 0.1) var cling_pull_drain_mult: float = 2.0

@export_group("Surfaces")
## Smooth panels bounce fighters back with this share of their speed (ARN-07).
@export_range(0, 1, 0.01) var smooth_restitution: float = 0.85
## Electric edges bounce and damage (ARN-05).
@export_range(0, 100, 1) var electric_damage: float = 8.0
## Minimum speed away from an electric surface.
@export_range(0, 2000, 10) var electric_bounce_speed: float = 650.0
## A fighter takes electric damage at most this often (s).
@export_range(0, 3, 0.05) var electric_cooldown: float = 0.4
## A hazard KO counts for whoever hit or pulled the victim this recently (§6.4).
@export_range(0, 10, 0.1) var kill_credit_time: float = 3.0

@export_group("Hazards")
## Airlock vent: one full closed-warning-open cycle (s), ARN-04.
@export_range(2, 60, 0.5) var vent_cycle: float = 14.0
@export_range(0, 5, 0.1) var vent_warning: float = 1.5
@export_range(0.5, 15, 0.1) var vent_open: float = 3.0
## Suction reaches this far from the vent (px).
@export_range(100, 3000, 10) var vent_reach: float = 950.0
## Suction acceleration at the vent (px/s^2).
@export_range(0, 10000, 50) var vent_strength: float = 2600.0
## Fuel tanks explode after this much damage (ARN-08).
@export_range(1, 300, 1) var tank_hp: float = 25.0
## Blast radius (px).
@export_range(50, 1000, 10) var tank_radius: float = 330.0
## Blast damage at the center.
@export_range(0, 200, 1) var tank_damage: float = 30.0
## Blast knockback at the center (px/s).
@export_range(0, 4000, 10) var tank_knockback: float = 1500.0
## A blown tank is replaced after this (s); 0 = never.
@export_range(0, 120, 1) var tank_respawn: float = 20.0
## A drifting asteroid that runs into a fighter (ARN-02).
@export_range(0, 100, 1) var asteroid_damage: float = 12.0
@export_range(0, 3000, 10) var asteroid_knockback: float = 900.0
@export_range(0, 3, 0.05) var asteroid_hit_cooldown: float = 0.6
## Black hole event horizon at the start (px), ARN-10.
@export_range(5, 500, 1) var black_hole_start_radius: float = 40.0
## ... and once fully grown.
@export_range(5, 800, 1) var black_hole_end_radius: float = 170.0
## Seconds to grow from start to end radius.
@export_range(1, 900, 5) var black_hole_growth_time: float = 180.0
## Pull reaches this many horizon radii.
@export_range(1, 20, 0.5) var black_hole_influence: float = 6.0
## Pull acceleration at the horizon (px/s^2).
@export_range(0, 10000, 50) var black_hole_strength: float = 2200.0

@export_group("Match events")
## First mid-match event after this (s), §6.4.
@export_range(0, 300, 5) var event_first_delay: float = 30.0
## Time between event starts (s).
@export_range(5, 300, 5) var event_interval: float = 40.0
@export_range(1, 60, 1) var lights_out_time: float = 12.0
@export_range(1, 60, 1) var vent_surge_time: float = 6.0
## Closing Walls lasts this long; the zone shrinks over two thirds of it.
@export_range(5, 120, 1) var closing_walls_time: float = 30.0
## The safe zone shrinks to this share of the arena.
@export_range(0.1, 1, 0.01) var closing_walls_min: float = 0.55
## Damage per half second outside the zone.
@export_range(0, 100, 1) var closing_damage: float = 6.0
## Push back toward the zone (px/s^2).
@export_range(0, 5000, 50) var closing_push: float = 1500.0
@export_range(1, 60, 1) var debris_storm_time: float = 10.0
## Debris per second during a storm.
@export_range(0.1, 20, 0.1) var debris_rate: float = 2.5
@export_range(50, 3000, 10) var debris_speed_min: float = 600.0
@export_range(50, 3000, 10) var debris_speed_max: float = 950.0
@export_range(0, 100, 1) var debris_damage: float = 10.0
@export_range(0, 3000, 10) var debris_knockback: float = 700.0
