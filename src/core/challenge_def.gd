class_name ChallengeDef
extends Resource
## A task counted from GameEvents (§7 daily challenges; the Phase 7 tutorial is built from these).
## It counts one event: the arg at actor_arg must be the local fighter, and every arg listed in
## match_args must equal the given value (or be one of the values, for an Array). Files live in
## data/challenges/<id>.tres.

const DIR: String = "res://data/challenges/"

@export var id: StringName = &""
## Shown to the player.
@export var text: String = ""
## A GameEvents signal name.
@export var event: StringName = &""
## Index of the argument that must be the local fighter id; -1 for any.
@export var actor_arg: int = 0
## Argument index -> required value, or an Array of allowed values.
@export var match_args: Dictionary = {}
@export var count: int = 1


static func load_by_id(challenge_id: StringName) -> ChallengeDef:
	var path := DIR + String(challenge_id) + ".tres"
	return load(path) as ChallengeDef if ResourceLoader.exists(path) else null


## Does this event (its args) count for local_id?
func matches(args: Array, local_id: int) -> bool:
	if actor_arg >= 0 and (actor_arg >= args.size() or args[actor_arg] != local_id):
		return false
	for index: int in match_args:
		if index >= args.size():
			return false
		var want: Variant = match_args[index]
		if want is Array:
			if not (want as Array).has(args[index]):
				return false
		elif args[index] != want:
			return false
	return true
