class_name RangeIndicator
extends Node2D
## Rope range circle around the local player (ROPE-10, CTL-07, §4.7). During the cooldown the circle
## dims and a brighter arc fills clockwise. flash() is the "can't fire yet" feedback (§4.4 rule 5).

const LINE_WIDTH: float = 2.0
const ALPHA_READY: float = 0.15
const ALPHA_COOLDOWN: float = 0.06
const ARC_ALPHA: float = 0.4
const FLASH_DECAY: float = 4.0
const FLASH_COLOR: Color = Color(1.0, 0.45, 0.4)

var fighter: Fighter
var _flash: float = 0.0


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * FLASH_DECAY)
	visible = fighter.state != SimIds.FighterState.KO
	queue_redraw()


func _draw() -> void:
	var t := TuningDB.t
	var radius := t.rope_range
	var tick := fighter.sim.tick if fighter.sim != null else 0
	var total := SimIds.ticks(t.rope_cooldown)
	var left := fighter.rope_cooldown_until_tick - tick
	var alpha := ALPHA_READY
	if left > 0 and total > 0:
		alpha = ALPHA_COOLDOWN
		var progress := 1.0 - float(left) / float(total)
		draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 96, Color(1, 1, 1, ARC_ALPHA), LINE_WIDTH + 1.0, true)
	var color := Color(1, 1, 1, alpha).lerp(Color(FLASH_COLOR, 0.7), _flash)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 128, color, LINE_WIDTH, true)
