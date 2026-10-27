class_name TutorialMode
extends GameMode
## The onboarding tutorial (§6.7): a practice match against an idle dummy. Its steps are
## ChallengeDefs counted by a ChallengeTracker in the match, which ends the match when the last
## one is done. Nothing is scored and there is no time limit.


func on_ko(_victim: Fighter, _killer_id: int, _cause: StringName) -> void:
	pass


func is_over(_tick: int) -> bool:
	return false


func finish(tick: int) -> void:
	ended = true
	end_tick = tick
	winner = 0
	sim.queue_event(&"match_ended", [winner])
