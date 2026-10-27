class_name SimIds
## Enums and constants shared by the simulation, its views and its input sources.

const TICK_RATE: int = 60
const DT: float = 1.0 / 60.0

enum FighterState { FREE, REELING, ORBITING, SWINGING, CLINGING, BEING_PULLED, HITSTUN, KO }
enum RopeState { IDLE, FLYING, ATTACHED, RETRACTING }
## CATCH: hauling in a caught projectile (ROPE-06). DUEL: locked in a tug-of-war (ROPE-07).
enum RopeMode { NONE, REEL, ORBIT, SWING, PULL, FETCH, CATCH, DUEL }
enum MeleePhase { NONE, STARTUP, ACTIVE, RECOVERY }

## "Never" for tick fields such as the last melee start.
const NO_TICK: int = -1000000


## Converts a tuning value in seconds to whole ticks (§3.1 rule 4).
static func ticks(seconds: float) -> int:
	return roundi(seconds * TICK_RATE)
