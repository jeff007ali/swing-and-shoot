extends Node
## Vibration wrapper (CTL-08). Respects the settings toggle and does nothing off device.


func pulse(duration_ms: int, amplitude: float) -> void:
	if not Settings.haptics_enabled or not OS.has_feature("mobile"):
		return
	Input.vibrate_handheld(duration_ms, amplitude)
