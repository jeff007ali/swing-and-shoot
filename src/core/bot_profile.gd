class_name BotProfile
extends Resource
## How one bot difficulty plays (§4.9). The first group is the difficulty table; the second holds
## behavior numbers that are the same for every difficulty, kept here so none are hard-coded.

const PROFILE_DIR: String = "res://data/bots/"

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Difficulty")
## Delay before a melee the bot decides on (s).
@export var reaction_time: float = 0.22
## Random spread when roping a fighter (± degrees).
@export var aim_error_deg: float = 6.0
## Attempts per second to rope the player when it can.
@export var aggression: float = 0.5
## Chance to rope away when pulled (rolled once per pull).
@export var escape_chance: float = 0.4
## How long the bot clings before grappling on (s).
@export var idle_cling_time: float = 0.6
## Random error (± ticks) on the melee timed for its own pull. Not in the §4.9 table: without it
## every difficulty lands the pull-and-punch combo frame-perfectly.
@export var melee_timing_error_ticks: int = 2
## Chance per perception to rope a floating weapon in reach while unarmed (§6.3).
@export var weapon_interest: float = 0.5
## Shots per second attempted while armed and in range.
@export var fire_rate: float = 2.0
## The player has to stay in sight this long before the bot shoots or ropes them (s): no snap shots
## the instant someone comes round a corner.
@export var acquire_time: float = 0.4
## Share of the target's motion the bot leads its shots and ropes by (1 = perfect lead).
@export var lead_skill: float = 0.6

@export_group("Behavior")
## Perception runs every this many ticks (0.1 s).
@export var perception_interval_ticks: int = 6
## Rule 3: melee when the player is within MELEE_RANGE + this and closing.
@export var melee_trigger_margin: float = 20.0
## Rule 5: "FREE and slow" means under this speed (px/s).
@export var slow_speed: float = 150.0
## Rule 5: preferred distance band from the player when picking an anchor (px).
@export var preferred_min_dist: float = 300.0
@export var preferred_max_dist: float = 550.0
## Rule 5: pick at random among this many best anchors.
@export var anchor_pick_count: int = 3
## Anchors closer than this to the bot are not worth a grapple (px).
@export var anchor_min_move: float = 80.0
## A ray toward an anchor counts as reaching it if it hits within this distance of it (px).
@export var anchor_hit_tolerance: float = 16.0
## Rule 5: extra ranking cost (px) for an anchor that has no line of sight to the player.
@export var no_sight_penalty: float = 400.0
## Rule 5: a clinging bot that can rope the player stays put instead of roaming.
@export var hold_position_when_ropeable: bool = true


static func load_by_id(profile_id: StringName) -> BotProfile:
	var path := PROFILE_DIR + String(profile_id) + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("Unknown bot profile: %s" % profile_id)
		return null
	return load(path) as BotProfile
