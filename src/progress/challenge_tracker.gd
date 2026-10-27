class_name ChallengeTracker
extends Node
## Counts ChallengeDefs from GameEvents for the local player, one after another (the tutorial,
## §6.7) or all at once (daily challenges, §7). View-side: it only listens, like a future
## ProgressTracker would.

signal step_completed(index: int)
signal all_completed

var challenges: Array[ChallengeDef] = []
var local_fighter_id: int = 0
## true: only the current challenge counts (tutorial). false: every one counts at once.
var in_order: bool = true
var current: int = 0
var progress: Array[int] = []

var _connected: Array = []


func start(defs: Array[ChallengeDef], local_id: int, ordered: bool = true) -> void:
	challenges = defs
	local_fighter_id = local_id
	in_order = ordered
	current = 0
	progress.clear()
	progress.resize(defs.size())
	progress.fill(0)
	var events: Array[StringName] = []
	for def in defs:
		if not events.has(def.event):
			events.append(def.event)
	for e in events:
		var listener := _listener(e)
		GameEvents.connect(e, listener)
		_connected.append([e, listener])


func is_done() -> bool:
	return current >= challenges.size() if in_order else _all_counted()


func current_def() -> ChallengeDef:
	return challenges[current] if current < challenges.size() else null


func _all_counted() -> bool:
	for i in challenges.size():
		if progress[i] < challenges[i].count:
			return false
	return true


func _listener(event: StringName) -> Callable:
	return func(...args: Array) -> void: _on_event(event, args)


func _on_event(event: StringName, args: Array) -> void:
	for i in challenges.size():
		if in_order and i != current:
			continue
		var def := challenges[i]
		if def.event != event or progress[i] >= def.count or not def.matches(args, local_fighter_id):
			continue
		progress[i] += 1
		if progress[i] >= def.count:
			step_completed.emit(i)
			if in_order:
				current += 1
			if is_done():
				all_completed.emit()
		return


func _exit_tree() -> void:
	for pair in _connected:
		if GameEvents.is_connected(pair[0], pair[1]):
			GameEvents.disconnect(pair[0], pair[1])
	_connected.clear()
