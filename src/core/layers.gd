class_name Layers
## 2D physics layer bits (§3.5). Names match [layer_names] in project.godot.

const WORLD_HOOKABLE: int = 1 << 0
const WORLD_SMOOTH: int = 1 << 1
const FIGHTERS: int = 1 << 2
const WEAPONS: int = 1 << 3
const PROJECTILES: int = 1 << 4
const HAZARDS: int = 1 << 5

## What a fighter body collides with. Fighters never block each other (D14).
const FIGHTER_BODY_MASK: int = WORLD_HOOKABLE | WORLD_SMOOTH
## World surfaces a flying hook can hit. Fighters are tested separately (Rope._first_fighter_on);
## Phase 3 adds WEAPONS and PROJECTILES.
const HOOK_MASK: int = WORLD_HOOKABLE | WORLD_SMOOTH
