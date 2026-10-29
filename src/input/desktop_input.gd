class_name DesktopInput
extends Node
## Development keys (§4.4). The mouse is handled by TouchRouter as emulated touch.
## Space/J melee, K fire and Shift dash (or kick off a wall), all aimed at the mouse cursor; F1 debug overlay, R respawn, 1/2/3 bot
## difficulty (0 idle), Esc pause.

signal debug_toggle_requested
signal respawn_requested
signal bot_difficulty_requested(level: String)
signal pause_requested

var router: TouchRouter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## From the local fighter toward the mouse cursor, in the world.
func _mouse_aim() -> Vector2:
	if router == null or router.fighter == null:
		return Vector2.ZERO
	var world := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var offset := world - router.fighter.global_position
	return offset.normalized() if offset.length() > 1.0 else Vector2.ZERO


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE, KEY_J:
			if router != null and not get_tree().paused:
				router.queue_melee(_mouse_aim())
		KEY_K:
			if router != null and not get_tree().paused:
				router.queue_fire(_mouse_aim())
		KEY_SHIFT:
			if router != null and not get_tree().paused:
				router.queue_dash(_mouse_aim())
		KEY_F1:
			debug_toggle_requested.emit()
		KEY_R:
			respawn_requested.emit()
		KEY_0:
			bot_difficulty_requested.emit("idle")
		KEY_1:
			bot_difficulty_requested.emit("easy")
		KEY_2:
			bot_difficulty_requested.emit("normal")
		KEY_3:
			bot_difficulty_requested.emit("hard")
		KEY_ESCAPE:
			pause_requested.emit()
		_:
			return
	get_viewport().set_input_as_handled()
