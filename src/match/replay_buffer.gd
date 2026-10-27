class_name ReplayBuffer
extends Node
## Keeps the last BUFFER_TIME seconds of sim states (§7: the opening for kill-clip sharing) and
## plays the final-KO slow motion from them (requirements §9, §6.7): when the match ends, every
## device, offline or LAN, replays the last REPLAY_TIME seconds at REPLAY_SPEED. The shared
## simulation itself never slows down. Visual only: replayed states emit no events.

signal finished

const BUFFER_TIME: float = 6.0
## States are kept every this many ticks (30 Hz); the replay blends fighters in between.
const RECORD_EVERY: int = 2
const REPLAY_TIME: float = 0.75
const REPLAY_SPEED: float = 0.3

var sim: MatchSim
var playing: bool = false

## tick -> MatchSim.get_state()
var _states: Dictionary = {}
var _to: int = 0
var _pos: float = 0.0


func attach(match_sim: MatchSim) -> void:
	sim = match_sim
	sim.ticked.connect(_record)


func _record(tick: int) -> void:
	if playing or tick % RECORD_EVERY != 0:
		return
	_states[tick] = sim.get_state()
	_states.erase(tick - SimIds.ticks(BUFFER_TIME))


## States of the last `seconds`, oldest first (a future kill clip, §7).
func clip(seconds: float) -> Array:
	var out: Array = []
	for t in range(sim.tick - SimIds.ticks(seconds), sim.tick + 1):
		if _states.has(t):
			out.append(_states[t])
	return out


func play_final() -> void:
	_to = sim.tick
	_states[_to] = sim.get_state()
	var from := _to - SimIds.ticks(REPLAY_TIME)
	from -= posmod(from, RECORD_EVERY)
	while from < _to and not _states.has(from):
		from += 1
	_pos = float(from)
	playing = true
	sim.auto_step = false


func _physics_process(_delta: float) -> void:
	if not playing:
		return
	_pos += REPLAY_SPEED
	if _pos >= float(_to):
		playing = false
		_apply(_to, _to, 0.0)
		finished.emit()
		return
	var k := int(_pos)
	k -= posmod(k, RECORD_EVERY)
	var next := mini(k + RECORD_EVERY, _to)
	_apply(k, next, (_pos - float(k)) / float(maxi(1, next - k)))


## Shows state a, with fighters placed between a and b (the views stay smooth at 0.3x).
func _apply(a: int, b: int, frac: float) -> void:
	if not _states.has(a):
		return
	sim.set_state(_states[a])
	var next: Array = _states.get(b, _states[a])["fighters"]
	for fs: Dictionary in next:
		var f := sim.get_fighter(fs["id"])
		if f == null:
			continue
		f.global_position = f.global_position.lerp(fs["pos"], frac)
		f.prev_position = f.global_position
