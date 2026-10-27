class_name InputCommand
extends RefCounted
## One tick of intent for one fighter (§3.2). Touch, desktop keys, bots and, in Phase 2, the network
## all produce these; a fighter never reads input directly.

var tick: int = 0
var rope_fire: bool = false
## World point after aim assist (§4.5).
var rope_target: Vector2 = Vector2.ZERO
var rope_release: bool = false
## True while the finger that fired the current rope is still down. Once it is false while a rope is
## out, the rope is latched and finishes on its own (§4.4 rule 3). Bots leave it false.
var rope_held: bool = false
var melee: bool = false
var fire: bool = false
var kick: bool = false
var kick_dir: Vector2 = Vector2.ZERO
## Explicit fire direction (bots). Zero means "use auto-aim" (CTL-05).
var aim_dir: Vector2 = Vector2.ZERO
## Thruster pack (§6.6): direction to accelerate in while a touch is held. Zero: no steering.
var steer: Vector2 = Vector2.ZERO


func to_dict() -> Dictionary:
	return {
		"tick": tick,
		"rope_fire": rope_fire,
		"rope_target": rope_target,
		"rope_release": rope_release,
		"rope_held": rope_held,
		"melee": melee,
		"fire": fire,
		"kick": kick,
		"kick_dir": kick_dir,
		"aim_dir": aim_dir,
		"steer": steer,
	}


static func from_dict(d: Dictionary) -> InputCommand:
	var cmd := InputCommand.new()
	cmd.tick = d.get("tick", 0)
	cmd.rope_fire = d.get("rope_fire", false)
	cmd.rope_target = d.get("rope_target", Vector2.ZERO)
	cmd.rope_release = d.get("rope_release", false)
	cmd.rope_held = d.get("rope_held", false)
	cmd.melee = d.get("melee", false)
	cmd.fire = d.get("fire", false)
	cmd.kick = d.get("kick", false)
	cmd.kick_dir = d.get("kick_dir", Vector2.ZERO)
	cmd.aim_dir = d.get("aim_dir", Vector2.ZERO)
	cmd.steer = d.get("steer", Vector2.ZERO)
	return cmd
