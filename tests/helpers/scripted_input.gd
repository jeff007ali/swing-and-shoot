extends RefCounted
## Test input source: returns a prepared InputCommand on given ticks and an empty one otherwise.

var commands: Dictionary = {}


func at(tick: int) -> InputCommand:
	if not commands.has(tick):
		commands[tick] = InputCommand.new()
	return commands[tick]


func build_command(tick: int) -> InputCommand:
	var cmd: InputCommand = commands.get(tick, InputCommand.new())
	return InputCommand.from_dict(cmd.to_dict())
