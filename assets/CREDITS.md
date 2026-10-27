# Asset Credits

Every third-party asset in this project. Phase 1 uses CC0 assets only (implementation.md §3.8, §9).
All packs below were downloaded from kenney.nl on 2026-10-26 and each pack's own License.txt says
"Creative Commons Zero, CC0" (http://creativecommons.org/publicdomain/zero/1.0/).

| Pack | Author | License | URL | Used for | Files |
|------|--------|---------|-----|----------|-------|
| New Platformer Pack 1.1 | Kenney | CC0 | https://kenney.nl/assets/new-platformer-pack | Fighter sprites (astronaut aliens) | `art/characters/character_*.png` |
| Space Shooter (Remastered) | Kenney | CC0 | https://kenney.nl/assets/space-shooter-remastered | Arena backgrounds, UI buttons, Kenvector fonts | `art/arena/{black,blue,darkPurple,purple}.png`, `art/ui/button*.png`, `fonts/kenvector_future*.ttf` |
| Space Shooter Extension | Kenney | CC0 | https://kenney.nl/assets/space-shooter-extension | Asteroids; wall, box and turbine panels (the "Sprites X2" set) | `art/arena/spaceMeteors_*.png`, `art/arena/spaceStation_003.png`, `art/arena/spaceBuilding_00{5,6,9}.png` |
| Particle Pack | Kenney | CC0 | https://kenney.nl/assets/particle-pack | Sparks, glows, smoke | `art/fx/*.png` |
| Impact Sounds | Kenney | CC0 | https://kenney.nl/assets/impact-sounds | Hook attach, cling, hits | `audio/sfx/impact*.ogg` |
| Sci-Fi Sounds | Kenney | CC0 | https://kenney.nl/assets/sci-fi-sounds | Rope fire, kick, rope hum, KO | `audio/sfx/{laserSmall,thrusterFire,forceField,engineCircular,impactMetal_00,explosionCrunch}*.ogg` |
| Interface Sounds | Kenney | CC0 | https://kenney.nl/assets/interface-sounds | UI clicks, cooldown tick | `audio/sfx/{click,confirmation,error,tick}_*.ogg` |
| Blaster Kit 2.1 | Kenney | CC0 | https://kenney.nl/assets/blaster-kit | Weapon sprites (Phase 3 and 6) | `art/weapons/{blaster-*,grenade-*,crate-small,target-detail}.png` |
| Space Shooter (Remastered) sounds | Kenney | CC0 | https://kenney.nl/assets/space-shooter-remastered | Shots, pickups, shield, zap | `audio/sfx/sfx_*.ogg` |

Made for this project (no third-party license): `art/fx/hook.png` and `art/fx/rope_tile.png`, drawn by
`tools/build_rope_art.gd`; the app icon (`tools/build_icon.gd`); the sword, boomerang, shield, Survival boss,
hazards and weapon effects, drawn in code.

Notes:
- The implementation plan names "Platformer Pack Redux" and "Space Shooter Redux". Kenney has since replaced
  them with "New Platformer Pack" and "Space Shooter (Remastered)", which are used instead.
- Simple Space was downloaded but not used yet; background stars are drawn in code.

Code: GUT (Godot Unit Test) 9.7.1 by Butch Wesley, MIT License, https://github.com/bitwes/Gut (`addons/gut/`).
