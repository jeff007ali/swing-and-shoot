# Swing and Shoot — Implementation Plan

**Source of truth for features:** [requirements.md](requirements.md). This document says **how** we build it.
**Status:** Approved decisions as of 2026-10-26. Anything not listed in §1 or in a "Decision" note is an open change request, not an open question.
**Build status (2026-10-26):** Phases 1–7 are built and covered by GUT tests (192 tests). Phase 1 milestones M0–M6, LAN multiplayer (Phase 2), weapons (3), hazards, 7 arenas and mid-match events (4), game modes (5), the full arsenal, advanced rope and Co-op Survival (6), and polish and store prep (7). Still open, because they need people and devices: the M7 playtest, the §6.2 four-phone LAN session, the 60 fps check on the reference Android and iPhone, iOS builds (Xcode and the Apple Team ID) and store accounts. Decisions D15–D46 record where the build differs from the original plan; the sections below are updated to match.

**How this doc is organized**

1. Decisions log (what was decided and why)
2. Tech stack and project setup
3. Architecture (applies to every phase)
4. **Phase 1: MVP prototype**, in full detail
5. Phase 1 milestones, acceptance criteria and playtest gate
6. Roadmap (Phases 2–7)
7. Future enhancements and the openings we build for them now
8. Requirements traceability
9. Risks

All distances are in **world pixels** at the 1920×1080 reference arena. All times are in **seconds** unless marked as ticks. One tick = 1/60 s.

---

## 1. Decisions Log

| # | Topic | Decision | Notes |
|---|-------|----------|-------|
| D1 | Doc scope | MVP (requirements §12) in full detail, plus a phased roadmap for everything else. | |
| D2 | Engine | **Godot 4.7.2 (stable), GDScript with static typing.** | Built-in LAN multiplayer (ENet over UDP), strong 2D sprite/animation tools, native iOS/Android export, free (MIT). The browser-based Phaser stack was rejected because web pages cannot host a game server, which local play requires. |
| D3 | Renderer | Godot **Compatibility** renderer (OpenGL ES 3 / WebGL 2 class). | Widest Android device support and best performance for 2D. Glow is done with additive sprites, not post-processing. |
| D4 | Multiplayer | **Local only:** Wi-Fi LAN or phone hotspot, **no internet and no servers**, like Mini Militia / BombSquad. One phone **hosts** (runs the authoritative game), the others join. Solo play vs bots works fully offline. | Requirements say "online". This overrides that: internet play is out of scope. |
| D5 | Netcode model | **Host-authoritative** with client-side prediction for the local player. | Rollback was not chosen: it needs bit-exact determinism across devices, which GDScript floats cannot guarantee. |
| D6 | MVP enemy | A **simple bot** using the same input interface as a human. | Bots are needed later to fill empty slots anyway. |
| D7 | Rope input | **Hybrid:** quick tap fires a rope that completes on its own; holding then lifting releases early; a new tap releases and fires again. | Exact timings in §4.4. |
| D8 | Kick-off | **Swipe** away from the surface while clinging. Cling timeout makes the player drift off gently. | Exact rules in §4.4. |
| D9 | MVP art | Free **CC0** packs (Kenney) packed into texture atlases. All visuals go through data resources so custom art can replace them later without code changes. | Sprite specs in §3.8. |
| D10 | Section 11 (cosmetics, battle pass, ranked, daily challenges) and kill-clip sharing | **Future enhancements.** Not built now, but the code leaves hooks for them (§7). | Ranked play needs a trusted server, which conflicts with D4. See §7. |
| D11 | Order after MVP | LAN multiplayer comes **directly after** the MVP (Phase 2), before weapons. | Every later feature is then built and tested networked from the start instead of retrofitted. Matches requirements §10 ("plan netcode from day one"). |
| D12 | Ragdoll knockback | Faked with sprite tumble (spin based on knockback) + hurt frame, not a physics ragdoll. | Cheap, network friendly, fine for 2D. |
| D13 | Rope vs. geometry | After attaching, the rope is a **straight line** and does not wrap around or snag on obstacles. Firing still requires a clear path (the hook stops at the first thing it hits). | Rope wrapping can be revisited after the MVP playtest. |
| D14 | Fighter vs. fighter collision | Fighters **do not block each other** physically. Overlaps are gently pushed apart. Ramming (Phase 3) is detected separately. | Lets a pulled enemy fly past the puller (ROPE-13). |
| D15 | Moving arena bodies | Turbines are **`StaticBody2D`** whose transform is pushed to the physics server each tick, not `AnimatableBody2D`. | Godot applies a kinematic body's new transform only at the next physics step, so same-tick ray and motion queries hit the turbine where it was. Found in M3. |
| D16 | Hook vs. fighters | Hooks hit fighters by a **segment-vs-circle test on sim positions**, not a physics query on the `fighters` layer. | Same lag as D15: fighters are kinematic bodies. |
| D17 | Orbit taut rope | When orbiting, outward speed is **turned along the circle** (speed kept) instead of removed. | Removing it lost ~30 % of speed per second to the straight-line step and killed the slingshot. Reel still removes it. |
| D18 | Swing on a turbine | The anchor-to-fighter direction is stored in the turbine's local space and **turns with it**; the fighter moves there with collision. | The original "place along the current direction" rule drags the fighter inward to radius √(R² − L²) ≈ 130 px, inside the arm sweep, so it always hit the arm. |
| D19 | Latched vs. held rope | `InputCommand.rope_held` (§3.2) tells the sim whether the rope's finger is still down. | The sim needs it for latched orbit/swing/reel time limits. Bots leave it false. |
| D20 | Extra tuning keys | `ROPE_RETRACT_TIME` (0.1 s), `AIM_ASSIST_RANGE_SLACK` (40 px, the "+40" of §4.5), `MELEE_ARC_DEG` (120), `HITSTOP_BASE_TICKS` 3, `HITSTOP_DAMAGE_STEP` 8, `HITSTOP_MAX_TICKS` 9, `HITSTOP_COMBO_BONUS_TICKS` 3 (the §4.8 hitstop table). | Keeps every gameplay number in the `Tuning` resource. |
| D21 | Bot tuning (after M5 measurements) | A clinging bot **holds position while the player is ropeable**; roam anchors with no line of sight to the player are penalised; anchors on the surface the bot clings to are skipped; with no anchor in the 300–550 px band the bot heads for the best fit. New profile value `melee_timing_error_ticks`. Aggression raised to 0.6 / 1.2 / 2.0. Two anchors added (Asteroid 3 sides, 14 total). | As specified, Hard landed 0.7 KOs/min on an idle player; after tuning 3.3 KOs/min, and strength orders Easy < Normal < Hard. |
| D22 | Bot escape roll | A failed escape roll falls through to the melee rule, so a pulled bot can swing back. | §4.9 rule 2 otherwise makes a pulled bot do nothing. |
| D23 | Art packs and atlases | Kenney replaced Platformer Pack Redux and Space Shooter Redux with **New Platformer Pack** and **Space Shooter (Remastered)**, used instead. Atlases are packed by `tools/build_atlases.gd` (characters + hook, arena sprites) because Godot's Texture Atlas import only runs in the editor. Tiled, nine-patch and particle textures stay standalone. | |
| D24 | Playtest log retrieval | On Android `user://` is the app's private storage: read it with `adb shell run-as <package>` (debug builds). iOS builds enable Files-app sharing. Logging can be turned off in Settings. | `adb pull` of `/sdcard` does not reach it. |
| D25 | Menus | The main menu picks mode and bot difficulty; the pause menu is Resume / Restart / Settings / Main Menu. Desktop keys 0–3 switch the bot live (0 = idle). | |
| D26 | Event payloads | `melee_started` adds the direction, `rope_released` adds `fling_mode`, `fighter_ko` adds `killer_id`; new `rope_bounced`. | HUD score, slingshot logging and feedback need them. |
| D27 | Android toolchain | The standard (non-Gradle) export works with the installed JDK 21; JDK 17 is only needed for Gradle builds (Play Store `.aab`). The project enables `import_etc2_astc`, which Godot requires for Android. | |
| D28 | Arena size (changes ARN-01) | Arenas may be **bigger than the screen** (Station 3840×2160; the themed arenas 3200–3600 × 1800–2160). The camera follows the local fighter with a little lookahead and stays inside the arena; a minimap and off-screen arrows show everyone else. The Hangar stays single-screen. Big arenas are generated from data by `tools/build_arenas.gd`. | Requested after the MVP build: the map should scroll to different areas. |
| D29 | LAN client view | Clients **predict the whole world** each tick (other fighters with no input) and rewind to every snapshot, instead of showing other fighters 100 ms in the past. Corrections under 150 px are smoothed by the fighter views. | One code path, and pulls/hits on the local fighter line up with what others are doing. |
| D30 | Final-kill slow motion | On **every device, offline too**, the match end replays the last 0.75 s at 0.3× from a `ReplayBuffer` (sim states at 30 Hz, last 6 s: also the kill-clip opening of §7). The shared sim stops when the match ends, so nothing desyncs. | One path for offline and LAN, and it shows the KO itself instead of its aftermath. |
| D31 | Phase 3 details | Cling resistance (CNT-01): the clinging target holds still and its grip drains faster; the puller is dragged toward it. Ramming ignores a pair just after one pulled the other, so pull-and-punch isn't a ram. Shots and blasts damage breakables and set off tanks. | |
| D32 | Phase 4 details | Vents are gaps in the walls closed by smooth doors; leaving the arena bounds is the vent KO. Events are drawn with `MatchSim.rng` from each arena's own list. Lights Out is a darkness overlay with light pools around fighters (weapons and effects stay readable). Bots flee open vents, black holes and the Closing Walls (bot rule 1b). Electric edges are the default only on the Derelict and Solar arenas; Asteroids wraps; the others keep normal walls so the rope has walls to grab. | |
| D33 | Phase 5 details | `GameMode` lives **in the sim** (its state is in every snapshot); only the authoritative sim scores and ends a match. 2v2 teams alternate by slot; no friendly fire; a teammate's pull earns no kill credit. King of the Swing: a figure-eight path (a loop around the middle on the black hole map), points only when one side holds the zone alone, scored in ticks, shown in seconds, target 20 s. Hot Potato: survivors score a point per blast; a new bomb 3 s later. Gun Game: loose weapons vanish; the mode hands out each level's weapon. Results are saved locally as `MatchResult` records. Bots get a **mode goal** (the zone, away from the bomb, the boss's weak points) and aim free rope spots toward it; a grapple that ends where it started blocks that anchor for 5 s. | Measured: bots reach and hold the zone on every arena. |
| D34 | Phase 6 details | All special weapons live in `SpecialWeapons`. Harpoon: a separate tether that hauls the victim in, not a second `Rope` node. Magnet: "metal-armored" means holding any weapon. Shield: an enemy hook from the front rips it off and fetches it. Sticky grenades stick to fighters, to a rope's owner or to walls. Freeze: 3 s, can always be roped, a fast frozen fighter hits whoever it touches (credited to whoever roped it). Legendary: the black hole bomb, in an open spot beside a vent, tank or black hole, or mid-arena. A caught projectile is whipped back automatically at the nearest enemy. Tug-of-war lasts 1.2 s, any tap counts, a tie releases both. Co-op Survival: enemy fighters exist from the start and sit benched between waves (fixed slots keep LAN simple); wave n brings n + 1; a boss every 5th wave is a round arena object you rope onto, hurt only at three rotating weak points; shared lives; 10 waves win. | |
| D35 | Phase 7 details | The tutorial is a list of `ChallengeDef` resources (event, conditions, count) counted by a `ChallengeTracker`: the same data the future daily challenges use (two examples ship). Accessibility: left-handed buttons, button size 0.7–1.5×, Okabe-Ito colors for players and teams. Performance pass (`tools/benchmark.gd`): 4 hard bots with hazards, events and fast weapon spawns cost 0.25 ms per tick on a desktop with a window (≈1.2 ms headless); the starfield became one mesh (≈1,040 → 110 draw calls per frame), particle bursts use a pool, and each sound variation has its own player (swapping streams cost ~1 ms per sound). `Store` autoload stub; the profile's loadout travels in the LAN handshake. | Measuring on the reference phones is still to do. |
| D36 | LAN protocol version | `NetProtocol.VERSION` is 6 since D41–D46 (5 added weapons, hazards, mode state, special-weapon state, thruster steering and the loadout). | Older builds are told to update. |
| D37 | Aimed attacks | HIT and FIRE work as **aim sticks**: a quick tap attacks at once with auto-aim (§4.8, CTL-05); press and drag past a 36 px dead zone shows an aim arrow from the fighter (the melee arc for HIT, a line for FIRE) and letting go attacks that way; dragging back into the middle cancels. The aim goes in `InputCommand.aim_dir`, which melee, blades and the shield bash now use too. On desktop, Space/J and K aim at the mouse cursor. | Requested after playtesting on the laptop: players need to choose the direction. |
| D38 | Rope aim assist and leaving walls | Aim assist (§4.5) now also snaps to **floating weapons** near the tap (1.5× the radius, at their lead position), and a tap on a **turbine** aims at its hub, so the hook hits the hub or an arm on the way instead of a gap the arm has turned out of. A rope fired from a wall that finds nothing (out of range, empty space) **kicks the fighter off toward where it was aimed**, so a far tap never leaves you stuck. | Found on the laptop: on the big arenas many taps are beyond the 640 px rope range. |
| D39 | Rope stick (optional) and rope feedback | Tapping anywhere stays the rope control (CTL-02). Settings adds an optional **rope stick** in the other bottom corner: drag to aim (an enemy or floating weapon within 12° of the direction is aimed at, else a full rope length that way), let go to fire, tap it to let go of the rope. Every rope shows a short **snap marker** where aim assist sent it, with a line from the finger when it moved, and a tap beyond rope range **flashes the range circle**. | So players can compare tap and stick on real phones; the playtest decides the default. |
| D40 | Menu and LAN lobby redesign | The home screen has one big **PLAY**, then Tutorial, Free Fly and LAN Party, with Settings in the corner. PLAY opens a **match setup** page: mode tiles (with who plays), the arena with a thumbnail and arrows, and the bot level, then START. LAN hosting uses the same picker, so the host now picks the **arena** too, next to the join code and four player slots. Join lists games with host, mode, arena and players, and gives up on a silent host after 8 s. Buttons are flat dark tiles, with one filled green button per screen. | The old menu put every option on one screen, and LAN hosts couldn't pick an arena. |
| D41 | Leaving a turbine | A fighter that lets go of a **moving surface** (kick, cling timeout, rope, recoil) keeps the surface's speed, and for `MOVING_RELEASE_GRACE` (0.75 s) touching that same object **pushes it off** (at least `KICK_MIN_NORMAL_DOT × KICK_SPEED` away from the surface) instead of clinging again; each push restarts the grace. | Playtest: you sometimes couldn't get off a turbine. The arm turns before the fighter moves each tick, so it swept into the fighter and re-clung it, over and over on its leading face. |
| D42 | Movement pass | Faster and longer reach: `HOOK_SPEED` 3600 → 4400, `ROPE_RANGE` 640 → 720, `ROPE_COOLDOWN` 0.35 → 0.25, `REEL_ACCEL` 4200 → 5400, `REEL_MAX_SPEED` 1400 → 1650, `KICK_SPEED` 750 → 950, `MAX_SPEED` 1800 → 2000. In 2v2, roping a **teammate** pulls both of you together, so you reach them in about half the time. | Playtest: too slow to reach an opponent, help a teammate or counterattack. |
| D43 | Bots play fair | Bot sight is blocked by **every** wall (smooth panels used to be see-through for bots). A bot must keep the player in sight for `acquire_time` (Easy 0.7 s, Normal 0.45, Hard 0.25) before it shoots or ropes them, and leads moving targets by `lead_skill` (0.3 / 0.6 / 0.85) instead of perfectly. Aim error and Hard's fire rate were raised and lowered a little. | Playtest: bots hit players they couldn't see, with perfect accuracy. |
| D44 | New weapons and the repulsor | **Sniper** (gun): 4 shots, 6000 px/s, 30 damage, 1.4 s between shots. It can't hide: a loud bolt sound and a "HAS THE SNIPER" message when picked up, a red **laser sight** everyone sees, a booming shot and a tracer. **Proximity mine**: thrown, sticks, arms after 0.9 s, explodes (38 damage) when an enemy comes within 120 px; the owner and teammates can't set it off. The **repulsor** is now a 110° cone ahead (plus anything right next to you), 520 px, strong enough to disarm, and kicks the user backward; it still breaks pulls and turns shots around. | Playtest: the repulsor was useless (a weak push in every direction); mines and a sniper were asked for. |
| D45 | Pickups | Four **consumables** spawn and float like weapons (WeaponDef kind CONSUMABLE) and are used the moment you rope them or fly through them, without dropping your weapon: **Med Kit** +40 HP, **Armor** soaks the next 35 damage (60 max), **Haste** ×1.3 reel, kick, top speed and rope cooldown for 6 s, **Power** ×1.5 damage for 8 s. Modes that narrow the weapons still spawn pickups. Bots rope a pickup when it would help. | Playtest request. |
| D46 | KNIFE button | The melee button is labeled **KNIFE** (or the blade's name while holding one) with a knife icon, and the swing draws a knife: pulled back during the wind-up, swept across the arc with a smear, then held while it fades; the body lunges with the active frames. New sounds (sniper shot and bolt, knife swish) are made by `tools/build_sfx.py`. | Playtest: "HIT" didn't say what it does, and the swing had no animation. |

---

## 2. Tech Stack and Project Setup

### 2.1 Toolchain

| Item | Version / choice |
|------|------------------|
| Engine | Godot **4.7.2-stable** (standard build, not .NET) + matching export templates |
| Language | GDScript, static typing required (`var speed: float = 0.0`, typed function signatures) |
| Unit tests | **GUT** (Godot Unit Test) addon, Godot 4 branch, installed under `addons/gut/` |
| Android build | Android SDK + **JDK 17**, Godot's standard (non-Gradle) export; debug keystore for development |
| iOS build | Xcode on this Mac, Apple Developer account for device builds |
| Art | Kenney CC0 packs (see §3.8), packed into atlases by `tools/build_atlases.gd` (D23) |
| Audio | Kenney CC0 audio packs (impact, sci-fi, interface sounds) |
| Version control | Git (the user commits manually). `.gitignore` excludes `.godot/`, `export/`, `*.keystore`, `*.ipa`, `*.apk`, `*.aab` |

### 2.2 Project settings (`project.godot`)

| Setting | Value | Why |
|---------|-------|-----|
| `display/window/size/viewport_width` × `height` | 1920 × 1080 | Reference resolution = arena size |
| `display/window/stretch/mode` | `canvas_items` | Crisp sprites and UI at any resolution |
| `display/window/stretch/aspect` | `expand` | Wide phones (~19.5:9) show extra background at the sides instead of black bars; the arena is always fully visible (ARN-01) |
| `display/window/handheld/orientation` | `sensor_landscape` | CTL-01 |
| `rendering/renderer/rendering_method` (+ `.mobile`) | `gl_compatibility` | D3 |
| `physics/common/physics_ticks_per_second` | 60 | Fixed simulation tick |
| `physics/common/physics_interpolation` | `true` | Smooth rendering on 90/120 Hz screens while simulating at 60 Hz |
| `input_devices/pointing/emulate_touch_from_mouse` | `true` | Desktop testing with a mouse |
| `application/run/low_processor_mode` | `false` | |
| Audio buses | `Master` → `SFX`, `Music` | Separate volume sliders |

Android export: permission `VIBRATE` (Phase 1). Phase 2 adds `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` (Godot needs `INTERNET` for any socket, including LAN).
iOS export: landscape only. Phase 2 adds `NSLocalNetworkUsageDescription` and the multicast entitlement (see §6.2).

### 2.3 Folder structure

```
swing-and-shoot/
  project.godot
  .gitignore
  docs/                      requirements.md, implementation.md
  addons/gut/                unit test framework
  icon.png                   app icon (tools/build_icon.gd)
  export_presets.cfg         Android and iOS presets
  assets/
    art/                     source PNGs (characters/, arena/, fx/, ui/), icon/ layers
    art/atlas/               packed atlases + one AtlasTexture .tres per sprite (generated)
    audio/sfx/, audio/music/
    fonts/                   Kenvector (Kenney)
    CREDITS.md               every third-party asset: pack, author, license, URL
  data/
    tuning/default_tuning.tres     all gameplay numbers (Tuning resource)
    skins/*.tres                    SkinDef resources (character visuals)
    bots/easy.tres, normal.tres, hard.tres   BotProfile resources
  src/
    autoload/                game_events.gd, tuning_db.gd, haptics.gd, sfx.gd,
                             settings.gd, profile_store.gd
    core/                    input_command.gd, sim_ids.gd, layers.gd, math_util.gd,
                             tuning.gd, skin_def.gd, bot_profile.gd
    sim/                     match_sim.gd, fighter.gd, rope.gd, melee.gd,
                             arena_object.gd, rotating_body.gd
    input/                   touch_router.gd, desktop_input.gd, aim_assist.gd, bot_controller.gd
    fx/                      fighter_view.gd, rope_view.gd, camera_shake.gd,
                             impact_fx.gd, range_indicator.gd, debug_world.gd
    ui/                      main_menu.tscn/.gd, hud.gd, pause_menu.gd, settings_screen.gd,
                             debug_overlay.gd, ui_theme.gd (UI built in code)
    arenas/                  arena_base.gd, starfield.gd, arena_01_hangar.tscn
    match/                   match.tscn, match.gd (spawning, scores, flow), playtest_logger.gd
  tools/                     build_skins.gd, build_atlases.gd, build_rope_art.gd, build_icon.gd
                             (run with godot --headless --path . -s res://tools/<name>.gd)
  tests/                     test_*.gd (GUT), helpers/
  export/                    build outputs (git-ignored)
```

Naming: files and functions `snake_case`, classes `PascalCase` via `class_name`, signals in past tense (`rope_attached`, `hit_landed`). **No gameplay number may be hard-coded**; it lives in the `Tuning` resource (§4.10).

---

## 3. Architecture (applies to every phase)

### 3.1 Rules that keep the game network-ready from day one

1. **One tick driver.** `MatchSim` is the only node with gameplay logic in `_physics_process`. It calls each system in a fixed order (§3.3). Fighters, ropes and arena objects have `set_physics_process(false)` and expose `step(tick)` methods. Nothing gameplay-related runs in `_process` (that is for visuals only).
2. **Everything is driven by input commands.** A fighter never reads touch, keyboard or AI directly. Each tick it receives an `InputCommand` (§3.2). Touch, desktop keys, bots and (in Phase 2) the network all produce the same commands.
3. **Sim state is serializable.** Every sim object implements `get_state() -> Dictionary` and `set_state(state: Dictionary)`. Phase 2 uses this for snapshots and prediction rewind; §7 uses it for replays.
4. **Time is tick-based.** Timers are stored as tick counts (`cling_ticks_left`, `cooldown_until_tick`), not seconds, and not with Godot `Timer` nodes. Rotating obstacles compute their angle from the tick number (`angle = start_angle + omega * tick / 60.0`), so every device agrees on it.
5. **Randomness is seeded.** `MatchSim` owns one `RandomNumberGenerator` with a match seed. Visual-only randomness (particles) may use anything.
6. **Sim and view are separate.** Sim objects emit signals through the `GameEvents` autoload (`hit_landed`, `rope_attached`, `fighter_ko`, ...). View nodes (sprites, particles, sound, haptics, screen shake) listen and react. The sim never touches audio, haptics or the camera.
7. **Hitstop is per entity.** A hit sets `freeze_ticks` on the attacker and the victim only. The rest of the world keeps running. This works in multiplayer, where one player's hit must not pause everyone.

### 3.2 `InputCommand`

```gdscript
class_name InputCommand
var tick: int
var rope_fire: bool          # fire a rope this tick
var rope_target: Vector2     # world point (after aim assist) for rope_fire
var rope_release: bool       # release the current rope this tick
var rope_held: bool          # the finger that fired the rope is still down (D19)
var melee: bool              # melee pressed this tick (edge, not hold)
var fire: bool               # weapon fire pressed (Phase 3+)
var kick: bool               # kick off the current surface this tick
var kick_dir: Vector2        # normalized swipe direction
```

Aim assist (§4.5) runs on the **sender side** before the command is created, so the command holds the final target point. This keeps the sim simple and lets bots provide exact points.

### 3.3 Tick order (`MatchSim._physics_process`)

```
tick += 1
1. Arena objects step (rotating bodies set their transform for this tick)
2. Gather one InputCommand per fighter (human router, bots, later network)
3. For each fighter (fixed order by fighter_id):
     a. decrement freeze_ticks; if frozen, skip b–e
     b. apply command: rope fire/release, kick, melee start
     c. rope step (hook flight, attach checks, pull/reel/orbit/swing forces)
     d. integrate velocity: rope forces, drag, max speed clamp
     e. move with collision (move_and_collide), resolve cling
4. Melee resolution (active hitboxes vs fighters) for all fighters
5. Fighter separation (soft push apart on overlap)
6. Status timers: cooldowns, immunity, hitstun, cling timeout, respawn
7. Emit queued GameEvents for views
```

### 3.4 Scene tree (`match.tscn`)

```
Match (Node2D, match.gd: spawning, KO/respawn, match flow)
  MatchSim (Node, match_sim.gd: the tick driver)
  Arena (instance of arena_XX.tscn)
    Background (Sprite2D / parallax, view only)
    Walls (StaticBody2D, 4 boundary segments)
    Obstacles (StaticBody2D children, each with ArenaObject metadata)
    Turbine (StaticBody2D + rotating_body.gd, D15)
    SpawnPoints (Marker2D ×4)
    BotAnchors (Marker2D ×14)
  Fighters (Node2D)
    Fighter (CharacterBody2D, fighter.gd)  ×N
      CollisionShape2D (CircleShape2D r = 28)
      Rope (Node, rope.gd)
      View (Node2D, fighter_view.gd: AnimatedSprite2D, HP bar, range circle)
  RopeViews (Node2D, one rope_view.gd per fighter: Line2D + hook sprite)
  Fx (Node2D, impact particles, trails)
  Camera2D (fixed at arena center, camera_shake.gd)
  HUD (CanvasLayer, hud.tscn)
  DebugOverlay (CanvasLayer, debug_overlay.tscn, hidden by default)
```

### 3.5 Physics layers

| Layer | Name | Contents |
|-------|------|----------|
| 1 | `world_hookable` | Walls and obstacles the rope can attach to |
| 2 | `world_smooth` | Non-stick panels (Phase 4, ROPE-08): solid, but the rope bounces off |
| 3 | `fighters` | Fighter bodies (do not collide with each other, D14) |
| 4 | `weapons` | Floating weapons (Phase 3) |
| 5 | `projectiles` | Bullets, grenades (Phase 3) |
| 6 | `hazards` | Hazard trigger areas (Phase 4) |

Fighter body: layer 3, mask 1 + 2. Hook queries: mask 1 + 2 + 3 (+ 4, 5 later).

### 3.6 Fighter movement model

Fighters are `CharacterBody2D` with `motion_mode = MOTION_MODE_FLOATING`. We do **not** use Godot's rigid-body solver. Velocity is integrated manually each tick and the body is moved with `move_and_collide()`. This gives full control of feel and lets Phase 2 replay inputs for prediction.

Per tick (`dt = 1/60`):
1. `velocity += rope_acceleration * dt` (from the rope, if any)
2. Drag (PHY-02): `velocity *= exp(-DRAG * dt)`
3. Clamp `velocity.length()` to `MAX_SPEED`
4. `collision = move_and_collide(velocity * dt)`
5. If `collision` hits layer 1 or 2 → **cling** (§4.3). Phase 4 changes this per surface type (electric edges bounce and damage, etc.).

### 3.7 Autoloads

| Autoload | Purpose |
|----------|---------|
| `GameEvents` | Signal bus: `rope_fired`, `rope_attached`, `rope_released`, `clung`, `kicked_off`, `melee_started`, `hit_landed(attacker, victim, damage, knockback, is_combo)`, `fighter_ko`, `fighter_respawned`, plus the weapon, hazard, mode and special-weapon events of Phases 3–6. Also the hook for stats, challenges and battle pass (§7); the tutorial's `ChallengeTracker` already listens to it. |
| `TuningDB` | Loads `default_tuning.tres`. The debug overlay edits it live. Can save/load named presets to `user://tuning/`. |
| `Haptics` | Wraps `Input.vibrate_handheld(ms, amplitude)`. Respects the settings toggle. |
| `Sfx` | Named sound lookup; one `AudioStreamPlayer2D` with a few voices per sound variation (D35). |
| `Settings` | Haptics on/off, SFX/music volume, show debug, bot difficulty, last mode and arena, left-handed buttons, button size, colorblind colors, tutorial done. Saved to `user://settings.cfg`. |
| `ProfileStore` | Local player profile (§7): a generated player ID, display name, loadout and lifetime stats; the last 50 `MatchResult` records in `user://match_results.json`. |
| `Net` | LAN session (`NetSession`, §6.2): hosting, discovery, lobby, match start. |
| `Store` | In-app purchase interface, a stub in this build (§7). |

### 3.8 Art pipeline and sprite specs

**MVP asset packs (Kenney, CC0):**
- Characters: **New Platformer Pack** astronaut aliens (beige, green, pink, purple, yellow; successor of Platformer Pack Redux, D23). Frames: idle (float), jump (reel, kick), duck (cling), hit (hurt, KO).
- Arena: **Space Shooter (Remastered)** for backgrounds, UI buttons and the Kenvector font; **Space Shooter Extension** ("Sprites X2") for meteors and the wall, box and turbine panels. Background stars are drawn in code.
- FX: **Particle Pack** (sparks, smoke, flares) for impacts and glow sprites.
- Audio: **Impact Sounds**, **Sci-Fi Sounds**, **Interface Sounds**.

Before importing, confirm each pack's license is CC0 and add it to `assets/CREDITS.md`.

**Data-driven visuals.** A fighter's look comes from a `SkinDef` resource (`data/skins/*.tres`): `SpriteFrames`, tint, hook sprite, rope texture, trail color. Code only references skin IDs. This is how custom art and future cosmetics (§7) plug in.

**Specs for custom art (for an artist later):**

| Asset | Canvas size | Pivot | Notes |
|-------|-------------|-------|-------|
| Character frames | 128 × 128 px | Center | Body fits a 56 px diameter circle (collision radius 28). Animations: `float` (loop, 6 fps), `reel` (1–2 frames), `cling` (1), `kick` (2), `melee` (3: wind-up, strike, recover), `hurt` (1), `ko` (2). Facing right; code flips. |
| Hook | 32 × 32 px | Rope attach point at the left-center edge | |
| Rope | 16 × 8 px tile, repeats horizontally | | `Line2D` with `texture_mode = TILE` |
| Weapons (Phase 3) | 96 × 96 px | Center (grip) | Plus a glow sprite of the same size |
| Obstacles | Any; collision drawn in the editor | | Round obstacles meant for orbiting must be circular (§4.6) |
| Atlases | ≤ 2048 × 2048 px per atlas | | One atlas per group: characters, arena, fx, ui |

Glow (WPN-06, lights-out event) uses additive-blend glow sprites (`CanvasItemMaterial.blend_mode = ADD`), which work on the Compatibility renderer.

---

## 4. Phase 1 — MVP Prototype (full detail)

### 4.1 Scope

Goal (requirements §12): **prove the rope is fun on its own.**

**In scope**
1. One arena: boundary walls, static obstacles (2 boxes, 3 round asteroids) and 1 rotating turbine.
2. Tap-to-rope onto walls and obstacles, with aim assist, range circle and cooldown.
3. Cling on arrival and swipe to kick off.
4. Rope an enemy (bot) and pull them into a melee hit, with full game feel (hitstop, shake, sound, haptics).
5. Orbit and slingshot around obstacles; swing and fling on the rotating turbine.
6. Health, KO and respawn, so practice against the bot loops endlessly.
7. Pull immunity (CNT-03), needed so the bot and player can't chain-pull each other forever.
8. Two modes: **Free Fly** (alone in the arena) and **Vs Bot** (Easy / Normal / Hard).
9. Debug overlay with live tuning sliders, and local playtest logging.
10. Builds running on one Android phone and one iPhone.

**Out of scope for Phase 1:** weapons, fire button, hazards, parry, ramming, rope cutting, cling resistance (CNT-01), multiplayer, game modes, cosmetics.

### 4.2 Arena 01 "Hangar" layout

World rectangle 1920 × 1080; origin top-left; the camera is fixed at (960, 540) with zoom 1.

| Object | Shape | Position / size | Notes |
|--------|-------|-----------------|-------|
| Boundary walls | 4 rectangles, 40 px thick | Inner playable area: (40, 40) to (1880, 1040) | Hookable, cling-able |
| Box A | Rectangle 220 × 90 | Center (480, 300) | Hookable |
| Box B | Rectangle 220 × 90 | Center (1440, 780) | Hookable |
| Asteroid 1 | Circle r 55 | (420, 800) | `orbit_pivot = true` |
| Asteroid 2 | Circle r 55 | (1500, 280) | `orbit_pivot = true` |
| Asteroid 3 | Circle r 40 | (960, 170) | `orbit_pivot = true` |
| Turbine | Hub circle r 45 + 3 arms (each 170 × 30) | Center (960, 600) | Rotates at `TURBINE_OMEGA`; hub and arms are hookable |
| Spawn points | Marker2D ×4 | (150, 150), (1770, 150), (150, 930), (1770, 930) | Respawn picks the point farthest from living enemies |
| Bot anchors | Marker2D ×14 | On wall midpoints, box tops/bottoms and the sides of all three asteroids | Bot navigation targets (§4.9); Asteroid 3's two added in D21 |

Each obstacle has an `ArenaObject` script with: `hookable: bool`, `orbit_pivot: bool`, `is_moving: bool`, `surface_type` (`"normal"` in MVP; Phase 4 adds `"smooth"`, `"electric"`, ...).

### 4.3 Fighter states

```
FREE ──rope attaches to surface──▶ REELING ──hits surface──▶ CLINGING
  ▲                                   │                         │
  │                                   ├─sideways speed─▶ ORBITING (static, §4.6)
  │                                   └─moving surface─▶ SWINGING (turbine, §4.7)
  │                                                          │
  └──── release / kick / cling timeout ◀─────────────────────┘

Any state ──pulled by enemy rope──▶ BEING_PULLED ──release / arrival──▶ FREE
Any state ──hit──▶ HITSTUN ──timer──▶ FREE
Any state ──HP ≤ 0──▶ KO ──respawn timer──▶ FREE (at spawn, invulnerable)
```

Flags that sit on top of any state: `freeze_ticks` (hitstop), `pull_immune_until_tick`, `invulnerable_until_tick`, `rope_cooldown_until_tick`, `melee_phase`.

**What each state allows**

| State | Fire rope | Melee | Kick | Notes |
|-------|-----------|-------|------|-------|
| FREE | ✓ | ✓ | ✗ | Drifting with drag |
| REELING / ORBITING / SWINGING | ✓ (releases current and fires new) | ✓ | ✗ | |
| CLINGING | ✓ | ✓ | ✓ | Velocity is zero; follows moving surfaces |
| BEING_PULLED | ✓ (forces add up, a basic tug) | ✓ | ✗ | |
| HITSTUN | ✗ | ✗ | ✗ | Duration from §4.10 |
| KO | ✗ | ✗ | ✗ | Hidden, waiting to respawn |

**Cling (PHY-03).** When a fighter's `move_and_collide` hits a layer-1 surface in any state except KO:
- Velocity becomes zero; the fighter snaps to the contact point plus normal × radius.
- State becomes CLINGING with `cling_ticks_left = CLING_TIME × 60`. Any active self-rope (REELING/ORBITING/SWINGING) detaches automatically.
- If the surface moves (turbine), the fighter stores its position in the surface's local space and follows it each tick.
- When the cling timer reaches zero, the fighter drifts off along the surface normal at `CLING_DRIFT_SPEED` (state FREE).
- A fighter in BEING_PULLED that hits a surface also clings, and the enemy's rope releases.

### 4.4 Touch input (`touch_router.gd`)

**Screen layout (landscape)**
- **Melee button:** circle, 170 px diameter, bottom-right, 40 px from the edges, inside the safe area (`DisplayServer.get_display_safe_area()`).
- **Fire button:** reserved spot just above melee; hidden in Phase 1.
- **Pause button:** 90 px, top-left.
- Everywhere else is the **rope zone**.

Buttons are `TouchScreenButton` nodes (they handle multi-touch, unlike `Control` buttons, which only see the first touch). The router keeps a list of button rectangles and **ignores any touch that starts inside one**, so pressing melee never fires a rope.

**Rope gestures (hybrid, D7)**
The router tracks only **one rope touch** at a time (by touch index). Button touches are independent, so the player can hold a rope and press melee with the other thumb.

1. **Touch down in the rope zone, fighter NOT clinging:** fire a rope at the touch point immediately (after aim assist, §4.5). Remember `touch_start_tick`.
2. **Touch down in the rope zone, fighter IS clinging:** open a kick window of `KICK_WINDOW` (0.12 s).
   - If the finger moves ≥ `SWIPE_MIN_DIST` (30 px) within the window → **kick off** in the swipe direction. No rope fires.
   - If the finger lifts or the window ends without that movement → fire the rope at the original touch-down point and continue with rule 3.
3. **Touch up:**
   - Held less than `HOLD_THRESHOLD` (0.20 s) since the rope fired → **latched rope**: it keeps going until it completes on its own (§4.6–4.8 say when).
   - Held `HOLD_THRESHOLD` or longer → **release the rope now** (ROPE-12, PHY-04: velocity is kept).
4. **New touch down while a rope is out (in flight or attached):** release the current rope. If the cooldown is over (`ROPE_COOLDOWN` counts from the previous **fire**, not release), fire a new rope at the new point; otherwise only release.
5. **Rope fire while on cooldown:** nothing fires. The range circle flashes once as feedback.

**Kick rules**
- Kick velocity = `swipe_dir × KICK_SPEED`.
- If the swipe points into the surface, the direction is corrected so that `dot(dir, surface_normal) ≥ KICK_MIN_NORMAL_DOT` (0.2), keeping its along-surface part.
- Swipes when not clinging do nothing in Phase 1.

**Desktop controls (development only, `desktop_input.gd`)**
Mouse click / hold / drag = touch (emulated). `Space` or `J` = melee, `K` = fire (Phase 3), `F1` = debug overlay, `R` = respawn everyone, `1/2/3` = bot difficulty.

### 4.5 Aim assist (CTL-06)

Runs when a rope is fired at a touch point `P` (screen point converted to world point):

1. **Fighters first.** Each enemy within `AIM_ASSIST_RADIUS` (64 px) of `P`, not KO, within `ROPE_RANGE + 40` of the shooter: pick the one closest to `P`. Aim at its **lead position**: `enemy.pos + enemy.velocity × (distance / HOOK_SPEED)`.
2. **Weapons** (Phase 3) come next, same rule.
3. **Surfaces.** Shape query: a circle of radius `AIM_ASSIST_RADIUS` at `P` against layer 1. If it overlaps a surface, aim at the closest contact point (`PhysicsDirectSpaceState2D.get_rest_info`).
4. Otherwise aim at `P` exactly.

The hook then flies in a straight line from the fighter toward the aim point (D13). If the aim point is farther than `ROPE_RANGE`, the hook still flies in that direction up to the range limit.

### 4.6 Rope (`rope.gd`)

**Rope states:** `IDLE`, `FLYING`, `ATTACHED`, `RETRACTING` (visual only, 0.1 s).

**Firing**
- Allowed if the fighter state allows it (§4.3) and `tick ≥ rope_cooldown_until_tick`.
- Sets `rope_cooldown_until_tick = tick + ROPE_COOLDOWN × 60`.
- The hook starts at the fighter center and moves at `HOOK_SPEED`. Each tick it sweeps a ray from its last position to its new position (mask 1 + 3; Phase 3 adds weapons and projectiles).
- **It hits nothing within `ROPE_RANGE`** → RETRACTING, then IDLE ("miss").
- **It hits a fighter with pull immunity** (or who is invulnerable or KO) → it bounces off with a "clink" effect and the rope goes to RETRACTING.
- **It hits a surface** → attach (below). **It hits a fighter** → enemy pull (§4.8).

**Attaching to a surface.** Store the attach point in the hit object's **local space** (so it moves with moving objects). Then pick the mode:

| Condition (checked at the moment of attaching) | Mode | State |
|-----------------------------------------------|------|-------|
| Hit object `is_moving` (turbine) | **Swing** | SWINGING |
| Tangential speed ≥ `ORBIT_MIN_TANGENT_SPEED` **and** the angle between velocity and rope direction ≥ `ORBIT_MIN_ANGLE` | **Orbit** | ORBITING |
| Otherwise | **Reel** | REELING |

Tangential speed = the part of the fighter's velocity perpendicular to the rope direction (from fighter to anchor).

**Reel (ROPE-01)**
- Acceleration `REEL_ACCEL` toward the anchor, speed toward the anchor capped at `REEL_MAX_SPEED`.
- Rope length `L` only shrinks: `L = min(L, distance)`. If the fighter ends a tick farther than `L`, it is pulled back onto the circle and any outward velocity is removed (taut, inelastic rope).
- Completes when the fighter hits any surface and clings (§4.3). A latched reel also completes after `REEL_MAX_TIME` (2.0 s) as a safety.

**Orbit (ROPE-04)**
- **Pivot:** if the hit object has `orbit_pivot = true` (round asteroids), the pivot is the **object's center** and the rope is drawn to the surface point facing the fighter. Otherwise the pivot is the attach point.
- No reel acceleration. Rope length is fixed except for a slow tighten at `ORBIT_REEL_SPEED` down to `ORBIT_MIN_LENGTH` (measured from the pivot, plus the object radius when pivoting on a center).
- Tightening keeps angular momentum: `tangential_speed_new = tangential_speed_old × L_old / L_new`, capped at `MAX_SPEED`. Orbiting longer makes you faster, which is what makes the slingshot.
- The taut-rope constraint is the same as in Reel, except that outward speed is turned along the circle instead of removed (D17).
- **Release:** the fighter keeps its velocity × `SLINGSHOT_RELEASE_BONUS` (capped at `MAX_SPEED`).
- A latched orbit (quick tap) auto-releases after `LATCHED_ORBIT_MAX_TIME`. To aim a slingshot, the player holds and lifts at the right moment.

**Swing on a rotating obstacle (ROPE-05)**
- The anchor is a point on the turbine, so it moves every tick.
- The rope reels in at `REEL_MAX_SPEED` down to `SWING_MIN_LENGTH`, then holds that length.
- Each tick the fighter moves (with collision) to `anchor + dir × L`, where `dir` is the anchor-to-fighter direction at attach time, stored in the turbine's local space so it turns with the turbine (D18). Velocity is set to `(new_pos − old_pos) / dt`, capped at `MAX_SPEED`. The fighter is carried around at the turbine's speed.
- **Release:** velocity × `SWING_RELEASE_BONUS`.
- A latched swing auto-releases after `LATCHED_ORBIT_MAX_TIME`.

**Release (any mode).** Rope goes to RETRACTING; the fighter keeps its current velocity (PHY-04). The rope also releases when its owner is hit (HITSTUN), clings or goes KO.

### 4.7 Rope range circle and cooldown display (ROPE-10, CTL-07)

- `range_indicator.gd` draws a circle of radius `ROPE_RANGE` around the **local player only**: 2 px line, white, 15% opacity.
- During cooldown the circle drops to 6% opacity and a brighter arc fills clockwise as the cooldown runs out.
- Bots and other players do not show a circle.

### 4.8 Pulling an enemy and melee

**Enemy pull (ROPE-03, ROPE-13)**
- On hit: the target becomes BEING_PULLED by this rope.
- Target acceleration: `PULL_ACCEL` toward the puller's **current** position, with the target's speed toward the puller capped at `PULL_MAX_SPEED`.
- Reaction on the puller: `PULL_REACTION × PULL_ACCEL` toward the target (a small lurch forward).
- **Ends when:** the target is within `PULL_ARRIVE_DIST` of the puller, or after `PULL_MAX_TIME`, or the puller releases, or either fighter is hit, or the target clings to a surface.
- When the pull ends, the target keeps its velocity. Fighters don't block each other (D14), so the target **flies past** the puller (ROPE-13). That moment, as it flies past, is when to melee.
- After any pull ends, the target gets **pull immunity** for `PULL_IMMUNITY` (CNT-03), shown as a faint blue outline.

**Melee (MEL-01, MEL-02, MEL-03)**
- Press melee → wind-up `MELEE_STARTUP_TICKS`, active `MELEE_ACTIVE_TICKS`, recovery `MELEE_RECOVERY_TICKS`. A new melee cannot start until `MELEE_COOLDOWN` has passed since the last one started.
- **Aim:** the nearest living enemy within `MELEE_AUTOAIM_RANGE` (180 px). If none, the fighter's movement direction; if still, the facing direction.
- **Lunge:** on startup, add `MELEE_LUNGE_SPEED` in the aim direction.
- **Hitbox:** a 120° arc of radius `MELEE_RANGE` (center to center) in the aim direction, checked during the active ticks. Each victim can be hit once per swing.
- **Closing speed** = `max(0, dot(attacker.vel − victim.vel, dir_to_victim))`. This rewards an enemy flying into you just as much as you flying into them.
- **Damage** = `min(MELEE_BASE_DAMAGE + MELEE_DAMAGE_PER_SPEED × closing, MELEE_MAX_DAMAGE)`.
- **Knockback** = `min(MELEE_KB_BASE + MELEE_KB_PER_SPEED × closing, MELEE_KB_MAX)` along `dir_to_victim`, added to the victim's velocity after that velocity is cleared.
- **Signature combo (MEL-03):** if the attacker was pulling this victim at any point in the last `COMBO_WINDOW`, damage × `COMBO_DAMAGE_MULT`, plus stronger feel (below) and a "SNAP!" text pop.
- **Victim effects:** rope released, HITSTUN for `HITSTUN_BASE + knockback / HITSTUN_KB_DIVISOR` seconds, sprite tumble with spin proportional to knockback (D12).
- Invulnerable or KO fighters cannot be hit.

**Game feel per hit (triggered from `GameEvents.hit_landed`)**

| Effect | Normal hit | Signature combo |
|--------|-----------|-----------------|
| Hitstop (`freeze_ticks`, attacker and victim) | `3 + floor(damage / 8)`, max 9 | +3 more |
| Screen shake trauma (0–1) | `0.2 + damage / 100` | 0.75 |
| Haptics (local player involved) | 30 ms, amplitude 0.5 | 70 ms, amplitude 1.0 |
| Sound | `hit_light` (damage < 20) or `hit_heavy` | `hit_combo` (heavy impact + whoosh) |
| Particles | Small spark burst | Large burst + shockwave ring |

Screen shake uses the trauma model: offset = `trauma² × SHAKE_MAX_OFFSET` (24 px) with random direction each frame, trauma decays at 1.5 per second.

**Health, KO, respawn (HP-01)**
- `MAX_HP` 100. KO at 0: KO animation + sound, fighter hidden, rope released.
- Respawn after `RESPAWN_TIME` at the spawn point farthest from living enemies, with `SPAWN_INVULN` invulnerability (sprite blinks).
- The HUD counts KOs for each side. Phase 1 has no win condition (endless practice).

**Fighter separation (D14).** If two fighters overlap, each is pushed apart at `SEPARATION_SPEED`. Their velocities are otherwise unchanged.

### 4.9 Bot (`bot_controller.gd`)

The bot produces `InputCommand`s like a human. It never moves the fighter directly.

**Perception** runs every 6 ticks (0.1 s) and reads: own state, player position/velocity/state, line of sight (raycast), list of `BotAnchors`.

**Behavior (priority order, first match wins)**

| # | Situation | Action |
|---|-----------|--------|
| 1 | HITSTUN or KO | Nothing |
| 2 | BEING_PULLED by the player | With chance `escape_chance` (rolled once per pull), fire a rope at the reachable anchor pointing most away from the player. A failed roll falls through to rule 3 (D22) |
| 3 | Player within `MELEE_RANGE + 20` and closing, or arriving from the bot's own pull | Press melee after a `reaction_time` delay |
| 4 | Player in rope range, in line of sight, not pull-immune, bot rope ready | With chance `aggression` per second, rope the player (aim error ± `aim_error_deg`) |
| 5 | CLINGING for more than `idle_cling_time` while the player is **not** ropeable, or FREE and slow (< 150 px/s) | Grapple to an anchor: pick a reachable, in-range anchor that keeps the bot 300–550 px from the player and can see them (random among the best 3 in the band; the best fit if none is). Never an anchor on the surface the bot clings to (D21) |
| 6 | Otherwise | Keep doing the current action (latched ropes finish on their own) |

**Difficulty profiles (`BotProfile` resources)**

| Parameter | Easy | Normal | Hard |
|-----------|------|--------|------|
| `reaction_time` (s) | 0.35 | 0.22 | 0.12 |
| `aim_error_deg` | 12 | 6 | 2 |
| `aggression` (attempts / s) | 0.6 | 1.2 | 2.0 |
| `escape_chance` | 0.2 | 0.4 | 0.7 |
| `idle_cling_time` (s) | 0.9 | 0.6 | 0.35 |
| `melee_timing_error_ticks` (± ticks on the pull-and-punch) | 4 | 2 | 0 |

Aggression was 0.3 / 0.5 / 0.8 before the M5 tuning pass (D21). Measured per 60 s against an idle player after tuning: Easy 2.7 pulls / 0.0 KOs, Normal 6.3 / 1.3, Hard 10.3 / 3.3.

### 4.10 Tuning table (starting values, `default_tuning.tres`)

All values are editable live in the debug overlay. Playtesting will change them; these are the agreed starting points.

| Key | Value | Unit | Requirement |
|-----|-------|------|-------------|
| `FIGHTER_RADIUS` | 28 | px | |
| `DRAG` | 0.25 | 1/s (exponential) | PHY-02 |
| `MAX_SPEED` | 2000 (D42) | px/s | |
| `HOOK_SPEED` | 4400 (D42) | px/s | |
| `ROPE_RANGE` | 720 (D42) | px | ROPE-10 |
| `ROPE_COOLDOWN` | 0.25 (D42) | s from fire | ROPE-11 |
| `REEL_ACCEL` | 5400 (D42) | px/s² | ROPE-01 |
| `REEL_MAX_SPEED` | 1650 (D42) | px/s | |
| `REEL_MAX_TIME` | 2.0 | s | |
| `ORBIT_MIN_TANGENT_SPEED` | 260 | px/s | ROPE-04 |
| `ORBIT_MIN_ANGLE` | 55 | degrees | ROPE-04 |
| `ORBIT_REEL_SPEED` | 60 | px/s | |
| `ORBIT_MIN_LENGTH` | 90 | px | |
| `LATCHED_ORBIT_MAX_TIME` | 1.5 | s | |
| `SLINGSHOT_RELEASE_BONUS` | 1.10 | × | ROPE-04 |
| `TURBINE_OMEGA` | 1.8 | rad/s | ROPE-05 |
| `SWING_MIN_LENGTH` | 110 | px | ROPE-05 |
| `SWING_RELEASE_BONUS` | 1.15 | × | ROPE-05 |
| `PULL_ACCEL` | 5200 | px/s² | ROPE-03 |
| `PULL_MAX_SPEED` | 1500 | px/s | |
| `PULL_REACTION` | 0.15 | × | |
| `PULL_ARRIVE_DIST` | 70 | px | |
| `PULL_MAX_TIME` | 1.0 | s | |
| `PULL_IMMUNITY` | 1.0 | s | CNT-03 |
| `CLING_TIME` | 1.2 | s | PHY-03 |
| `CLING_DRIFT_SPEED` | 60 | px/s | PHY-03 |
| `KICK_SPEED` | 950 (D42) | px/s | PHY-03 |
| `KICK_WINDOW` | 0.12 | s | |
| `SWIPE_MIN_DIST` | 30 | px (reference) | |
| `KICK_MIN_NORMAL_DOT` | 0.2 | | |
| `MOVING_RELEASE_GRACE` | 0.75 | s | D41 |
| `HOLD_THRESHOLD` | 0.20 | s | CTL-03 |
| `AIM_ASSIST_RADIUS` | 64 | px | CTL-06 |
| `MELEE_RANGE` | 95 | px center to center | |
| `MELEE_AUTOAIM_RANGE` | 180 | px | |
| `MELEE_STARTUP_TICKS` / `ACTIVE` / `RECOVERY` | 2 / 6 / 14 | ticks | |
| `MELEE_COOLDOWN` | 0.35 | s | |
| `MELEE_LUNGE_SPEED` | 140 | px/s | |
| `MELEE_BASE_DAMAGE` | 8 | HP | MEL-01 |
| `MELEE_DAMAGE_PER_SPEED` | 0.025 | HP per px/s | MEL-02 |
| `MELEE_MAX_DAMAGE` | 45 | HP | |
| `MELEE_KB_BASE` | 350 | px/s | |
| `MELEE_KB_PER_SPEED` | 1.1 | × | MEL-02 |
| `MELEE_KB_MAX` | 1700 | px/s | PHY-05 |
| `COMBO_WINDOW` | 0.35 | s | MEL-03 |
| `COMBO_DAMAGE_MULT` | 1.25 | × | MEL-03 |
| `HITSTUN_BASE` | 0.12 | s | |
| `HITSTUN_KB_DIVISOR` | 4000 | px/s per s | |
| `MAX_HP` | 100 | HP | HP-01 |
| `RESPAWN_TIME` | 2.0 | s | |
| `SPAWN_INVULN` | 1.5 | s | |
| `SEPARATION_SPEED` | 200 | px/s | |
| `SHAKE_MAX_OFFSET` | 24 | px | |
| `ROPE_RETRACT_TIME` | 0.1 | s | D20 |
| `AIM_ASSIST_RANGE_SLACK` | 40 | px | D20 |
| `MELEE_ARC_DEG` | 120 | degrees | D20 |
| `HITSTOP_BASE_TICKS` / `DAMAGE_STEP` / `MAX_TICKS` / `COMBO_BONUS_TICKS` | 3 / 8 / 9 / 3 | ticks, HP per tick | D20 |

Sanity check: a still melee does 8 damage before the lunge (the 140 px/s lunge adds closing speed, so a standing punch lands for about 11); meeting a pulled enemy at a 1,500 px/s closing speed does 45 (56 with the combo bonus), so two combos KO. Knockback of 1700 px/s with drag 0.25 carries far across the arena (PHY-05).

### 4.11 Views, audio and haptics

**Fighter view:** `AnimatedSprite2D` from the skin, flips to face movement/aim, plays the animation for the current state, tumbles in HITSTUN, shows a small HP bar above enemies, pull-immunity outline, invulnerability blink. Speed trail (`Line2D`, last 12 positions) shows above 900 px/s.

**Rope view:** `Line2D` from the fighter's hand to the hook, with a tiled rope texture. Width 6 px; it brightens with tension (when reel/pull acceleration is active). Hook sprite rotated along the rope. Attach spark particles.

**Sounds (Kenney CC0)**

| Event | Sound |
|-------|-------|
| Rope fired | Short whoosh |
| Hook attached (surface) | Metallic clank |
| Hook attached (fighter) | Thud + clank |
| Rope tension | Looping creak/hum while reeling or pulling; pitch rises with speed (§9 "rope tension sound") |
| Cling | Magnetic clunk |
| Kick-off | Air puff |
| Melee swing | Swoosh |
| Hit light / heavy / combo | Three impact layers |
| KO / respawn | Burst / chime |
| UI | Click |

**Haptics (CTL-08):** rope attached 15 ms, amplitude 0.3; cling 10 ms, 0.2; hits per the table in §4.8; KO 90 ms, 1.0. Only for events involving the local player.

### 4.12 Screens

- **Main menu:** Free Fly, Vs Bot (difficulty picker: Easy/Normal/Hard), Settings, version label.
- **Settings:** Haptics on/off, SFX volume, Music volume, Show debug overlay.
- **In match:** HUD (own HP top-left, KO counter top-center, pause top-left, melee button bottom-right). The pause menu offers Resume, Restart, Main Menu. Pausing stops `MatchSim` (offline only).
- **Debug overlay (F1 on desktop, three-finger tap on device):** FPS, tick, own state, speed, rope state; a slider for every tuning value; save/load tuning presets; checkboxes to draw hitboxes, rope pivots and bot intents.

### 4.13 Playtest logging

`playtest_logger.gd` listens to `GameEvents` and writes one CSV per session to `user://playtest/YYYYMMDD_HHMMSS.csv`.
Events logged: `rope_fired`, `rope_attached(mode)`, `rope_missed`, `cling`, `kick`, `hit(damage, is_combo)`, `ko`.
Each session also gets a summary row: duration, ropes per minute, % of time airborne, orbits, slingshots, combos, KOs.
Getting the files (D24): on Android `user://` is the app's private storage, readable on debug builds with `adb shell run-as com.jefflabs.swingandshoot ls files/playtest` and `adb exec-out run-as com.jefflabs.swingandshoot cat files/playtest/<name>.csv > <name>.csv`. On iOS, Files app → On My iPhone → Swing and Shoot, or Xcode's container download. Logging can be switched off in Settings.

### 4.14 Tests (GUT)

| Test file | What it checks |
|-----------|----------------|
| `test_touch_router.gd` | Tap → latched; hold ≥ 0.2 s then lift → release; retap → release + refire; retap during cooldown → release only; swipe while clinging → kick, no rope; touch on a button rect → ignored |
| `test_rope_modes.gd` | Mode selection (reel / orbit / swing) for given velocities and targets; orbit tightening keeps angular momentum; release keeps velocity |
| `test_melee.gd` | Damage/knockback formulas at closing speeds 0, 750 and 1500; combo multiplier only within `COMBO_WINDOW`; one hit per victim per swing |
| `test_pull_rules.gd` | Immunity blocks pulls; pull ends on arrival, timeout, hit or cling |
| `test_sim_repeatability.gd` | Two runs of 600 ticks with the same seed and a scripted input list end in identical `get_state()` (same device). This protects the input-driven design that Phase 2 relies on. |

Run headless: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`.

Also built: `test_cling_and_kick.gd`, `test_rope_reel.gd`, `test_bot_controller.gd` (each rule, bot vs idle player, Hard beats Easy), `test_playtest_logger.gd`, `test_menus_and_settings.gd` (menu, settings persistence, tuning presets).

---

## 5. Phase 1 Milestones and Acceptance Criteria

Each milestone ends with a build on at least one real phone.

| Milestone | Content | Done when |
|-----------|---------|-----------|
| **M0 Setup** | Godot 4.7.2 project, settings (§2.2), folder structure, autoload stubs, GUT installed, Android + iOS export presets, CC0 packs imported and credited | An empty arena scene runs on an Android phone and an iPhone in landscape at 60 fps |
| **M1 Drift and cling** | Arena 01 geometry, fighter movement model (§3.6), cling + drift-off, kick-off swipe, desktop controls, debug overlay with FPS and state | You can kick between walls; clinging, timeout drift and kick direction correction all behave per §4.3/§4.4 |
| **M2 Rope core** | Hook flight, aim assist, reel, hybrid input rules, cooldown, range circle, rope view + sounds | Every row of `test_touch_router.gd` passes; on a phone, tapping walls and obstacles moves you as expected with no accidental ropes from button presses |
| **M3 Orbit and swing** | Orbit mode with pivots, tightening and slingshot bonus; rotating turbine with swing mode | A sideways pass by an asteroid with a held rope orbits it, and a release flings you out faster than you came in; the turbine swing flings you on release |
| **M4 Pull and melee** | Enemy pull, ROPE-13 fly-past, melee with formulas, signature combo, hitstop/shake/haptics/particles, HP/KO/respawn, pull immunity. Test against a bot set to "idle" | Pull-then-melee on a moving target hits for ≥ 40 damage with the full combo feel; chain-pulling the same target within 1 s is impossible |
| **M5 Bot** | Bot controller and 3 difficulty profiles | Normal bot roams, pulls and melees you; Easy is beatable by a first-time player; Hard regularly beats the team |
| **M6 Content pass** | Final MVP sprites from the CC0 packs, all sounds, menus, settings, playtest logger, tuning presets | All §4.11–§4.13 items work on both phones |
| **M7 Playtest and tune** | Run the playtest below and tune | Gate passed (below) |

### 5.1 MVP success gate (requirements §12 "Success test")

Protocol: at least **5 testers**, each plays **5 minutes of Free Fly** and then **10 minutes of Vs Bot (Normal)** on a phone, then answers 3 questions (1–5 scale): "Moving around was fun", "Pulling and punching felt satisfying", "I wanted to keep playing".

**Pass** if all of the following hold:
- Average "Moving around was fun" ≥ 4.0 **and** at least 4 of 5 testers answer ≥ 4 to "I wanted to keep playing".
- Logs show testers airborne (not clinging) ≥ 60% of Free Fly time, with at least one slingshot per minute after the first 2 minutes.
- Stable 60 fps on both test phones, with no crashes.

**If it fails:** tune and repeat (up to 3 rounds), then decide whether to rethink the rope (for example rope wrapping, D13) before starting Phase 2.

---

## 6. Roadmap (Phases 2–7)

These phases are specified enough to build in order. Each one starts with a short detail pass that turns it into milestones in this same format (§5), applying the architecture rules in §3.

### 6.1 Phase order

| Phase | Theme | Main contents |
|-------|-------|---------------|
| 2 | **LAN multiplayer** | Host/join over Wi-Fi or hotspot, lobby, bots fill slots, MVP mechanics networked |
| 3 | **Weapons and combat depth** | Pistol, shotgun, sword; pickup, despawn, recoil, disarm, throw when empty; parry, ramming, rope cutting, cling resistance, fire button + auto-aim |
| 4 | **Hazards and arenas** | Electric edges, wrap-around edges, smooth panels, airlock vents, fuel tanks, breakable obstacles, drifting asteroids, black hole map; 4 themed arenas; mid-match events |
| 5 | **Game modes** | Free-for-all, 2v2, King of the Swing, Hot Potato, Gun Game; match results screen |
| 6 | **Full arsenal and advanced rope** | Remaining 14 weapons, legendary spawns, projectile catch, rope tug-of-war, mutual rope clash, Co-op Survival (waves + rope-able boss) |
| 7 | **Polish and release** | Final-kill slow motion, onboarding tutorial, left-handed layout, accessibility, performance pass, store builds |

### 6.2 Phase 2 — LAN multiplayer (no internet, no servers)

**Status:** built (`src/net/`, `NetSession`, `NetMatch`, lobby screen); tested in-process and between two processes on one machine. Clients predict the whole world (D29). The four-phone session below is still to do.

**Transport.** Godot high-level multiplayer with `ENetMultiplayerPeer` (UDP).
- Host: `create_server(7777, 3)`; the host is also a player (peer ID 1).
- Clients: `create_client(host_ip, 7777)`.
- Up to 4 humans; the host fills empty slots with bots, and bots run on the host.

**Finding a game**
1. **Auto discovery (beacons).** The host broadcasts a small UDP beacon on port **7778** once per second to `255.255.255.255` and to each local IPv4 address's `/24` broadcast address (`PacketPeerUDP.set_broadcast_enabled(true)`). Beacon contents: `{"g":"sns","v":PROTOCOL_VERSION,"n":host_name,"p":players,"m":max_players,"port":7777,"mode":mode_id}`. Clients listen on 7778 and list the games they hear.
2. **Join code fallback (always shown on the host's lobby screen).** The code is the host's last two IPv4 octets as 4 base-36 characters (for example `5A-01`). The client combines it with the first two octets of its own address. This covers home Wi-Fi and phone hotspots. An "Enter IP" field is the last resort.
3. **Hotspot play.** The hosting phone may also be the hotspot; this needs no special handling beyond the above.

**Platform requirements**
- **Android:** the permissions in §2.2. Godot's Android socket layer takes the Wi-Fi multicast lock when broadcast is enabled; verify this on two Android phones early.
- **iOS:** `NSLocalNetworkUsageDescription` in Info.plist (iOS shows a local network permission prompt on first use). Sending and receiving **broadcast** on iOS needs Apple's `com.apple.developer.networking.multicast` entitlement, which must be **requested from Apple**. Apply at the start of Phase 2. Until it is approved, iPhones use the join code, which works without it.

**Sync model (host-authoritative, D5)**
- Host simulates at 60 Hz with the same `MatchSim`.
- Clients send their `InputCommand` every tick, unreliable, each packet also carrying the previous 3 commands to cover packet loss.
- Host sends a full-state snapshot 30 times per second (unreliable ordered): tick, all fighters' `get_state()`, ropes, and later weapons and projectiles. Roughly 200–400 bytes for 4 players, so delta compression is unnecessary.
- **Other fighters** are shown 100 ms in the past, interpolated between snapshots.
- **Own fighter** is predicted: apply own inputs immediately; when a snapshot arrives, rewind to it via `set_state()` and replay unacknowledged inputs. Errors under 150 px are smoothed out visually over 100 ms; larger ones snap.
- **Only the host decides** rope hits on fighters, melee hits, damage, KOs and pickups. Clients show their own hook flying immediately (predicted) but confirm fighter hits only from the host.
- Turbines and all moving arena objects are functions of the tick number (§3.1 rule 4), so they need no syncing.
- Hitstop is per entity (§3.1 rule 7). The match never pauses.
- Reliable RPCs for match events: lobby state, match start, KO, score, match end.

**Session rules**
- Handshake checks `PROTOCOL_VERSION`; on mismatch the client is told "Update the game to join".
- No joining a match in progress (lobby only).
- A client that disconnects is replaced by a bot.
- If the **host** leaves, the match ends for everyone ("Host left"). No host migration.

**Lobby screen:** host name, mode, join code, player list with skin colors, "Fill with bots" toggle, Start (host only).

**Done when:** 4 phones (at least one iOS and one Android) play a 10-minute session on a **phone hotspot with mobile data turned off**, with no visible teleporting under normal conditions and correct hits, KOs and scores.

### 6.3 Phase 3 — Weapons and combat depth

**Status:** built (`WeaponSystem`, `WeaponDef` resources in `data/weapons/`, `WeaponsView`); details in D31.

| Item | Implementation notes | Req |
|------|---------------------|-----|
| Weapon spawner | Spawn points per arena; weapons drift at 40–80 px/s, spin, and glow | WPN-01, WPN-06 |
| Pickup by rope | Hook mask adds layer 4; a weapon hit is pulled to the fighter at `PULL_MAX_SPEED` and auto-equipped on contact. Holding a weapon and grabbing another drops the current one with a small push | ROPE-02, WPN-02 |
| Despawn | Unclaimed lifetime 15 s; blinking starts at 5 s left and speeds up | WPN-03 |
| Fire button + auto-aim | Fire button appears when armed; aims at the nearest enemy within a 30° cone of the fighter's facing, else straight ahead | CTL-05 |
| Recoil | Each weapon has a `recoil_impulse` (pistol 120, shotgun 700, rocket 1100 px/s) applied opposite the shot | PHY-06 |
| Pistol / Shotgun / Sword | Defined in `WeaponDef` resources (damage, fire rate, ammo, recoil, projectile, sprite) so new weapons are data plus small scripts | §5.2 |
| Throw when empty | At 0 ammo the fire button throws the weapon as a projectile (damage scales with speed) | WPN-05 |
| Disarm | A hit with knockback ≥ 1200 px/s drops the victim's weapon with a random drift | HP-03 |
| Parry | Melee active frames within 0.1 s of an incoming bullet reflect it; an incoming hook is knocked away | MEL-04, CNT-02 |
| Ramming | Fighter contact with closing speed ≥ 900 px/s: the faster one deals ram damage and knockback, unarmed | MEL-05 |
| Rope cutting | Sword swings and well-timed melee cut a rope segment they intersect | ROPE-14 |
| Cling resistance | A clinging target resists pulls: pull acceleration × 0.35 and the cling timer drains twice as fast; when it runs out, the target is pulled normally | CNT-01 |

### 6.4 Phase 4 — Hazards and arenas

**Status:** built (`HazardSystem`, `HazardView`, `ArenaHazard`, `DriftingBody`). Arenas: Station Interior (vents, tanks, breakables, smooth panels), Asteroid Field (wrap-around, drifting asteroids), Derelict Ship (electric edges, breakables, two turbines), Near-Star Solar Platform (electric edges, smooth solar panels) and Singularity (the black hole map), plus Station and the Hangar. Details in D28 and D32.

- **Surface types** on `ArenaObject.surface_type`: `normal` (cling), `smooth` (layer 2: solid, the rope bounces off, the fighter bounces instead of clinging; ROPE-08, ARN-07), `electric` (bounce + damage; default for screen edges, ARN-05).
- **Wrap-around edges** (ARN-06): arenas flagged `edge_mode = WRAP` replace boundary walls with portals; fighters and objects teleport to the opposite side (`reset_physics_interpolation()` on teleport).
- **Hazards** (`hazards` layer, HP-02, MEL-06): airlock vent (periodic suction; crossing the vent line = KO; ARN-04), fuel tank (explodes when shot, radial knockback; ARN-08), breakable obstacles (HP; ARN-09), drifting asteroids as moving anchors and hazards (ARN-02), black hole (center pull, grows over the match; ARN-10).
- **Kill credit:** the last fighter who hit or pulled the victim within 3 s gets the kill for hazard deaths.
- **Arenas:** one per theme: Space Station Interior, Asteroid Field, Derelict Ship, Near-Star Solar Platform (requirements §6.3).
- **Mid-match events** (requirements §6.2): Lights Out (darkened canvas; only additive-glow sprites remain visible), Vent Surge, Closing Walls, Debris Storm. A match event scheduler runs on the host and uses the match seed.

### 6.5 Phase 5 — Game modes

**Status:** built (`src/modes/`, `ModeDef` resources in `data/modes/`, `ModeView`, results screen, mode picker in the menu and the LAN lobby). Hooks are `start`, `on_ko`, `on_contact`, `on_tick`, `is_over`. Details in D33.

A `GameMode` base class with hooks `on_match_start`, `on_ko`, `on_tick`, `check_end` and a `ModeDef` resource (name, team size, score target, time limit, allowed weapons).
- **Free-for-all:** 3–4 players, first to N KOs (default 10), 3-minute time limit.
- **2v2:** teams; teammate ropes pull without damage; melee on a teammate is a "throw" (knockback without damage).
- **King of the Swing:** a moving zone on a path; score per second inside it.
- **Hot Potato:** a bomb is attached to one player and passes on rope hit or melee hit; it explodes on a timer.
- **Gun Game:** weapon sequence per `ModeDef`; the last kill must be melee.

### 6.6 Phase 6 — Full arsenal and advanced rope

**Status:** built (`SpecialWeapons`, 14 new `WeaponDef`s with Blaster Kit sprites, `SurvivalMode`, `BossBody`; thruster steering in `TouchRouter`). Details in D34.

- Remaining weapons from requirements §5.2: rocket launcher, boomerang blade, harpoon launcher (second rope), freeze ray (frozen target becomes a rope-able wrecking ball), magnet glove, sticky grenade, bouncing laser, gravity grenade, black hole bomb, repulsor blast, tether mine, tether rope, shield, thruster pack.
  - **Thruster steering:** while the thruster is active, a touch held longer than `HOLD_THRESHOLD` steers (the fighter accelerates toward the finger) instead of roping; a quick tap still fires a rope, sent when the finger lifts.
- Legendary weapon spawns in dangerous spots with a 3-second countdown banner (WPN-04).
- Projectile catch by rope (ROPE-06), rope-vs-rope tug-of-war tap duel (ROPE-07), mutual rope clash (ROPE-15).
- Co-op Survival: waves of bot enemies, plus a large boss with rope-able weak points.

### 6.7 Phase 7 — Polish and release

**Status:** built, except what needs devices and accounts: slow-motion replay (D30), tutorial (main menu → Tutorial, D35), accessibility settings, performance pass (D35), Store stub, store texts in `docs/store/`, screenshots (`tools/capture_store_shots.gd`) and the release-signing guide in `docs/release.md`.

- Final-kill slow motion (requirements §9): every device replays the last 0.75 s at 0.3× from its replay buffer, so the shared simulation never slows (D30).
- Onboarding tutorial built from daily-challenge-style tasks (rope to wall, orbit, pull + punch).
- Left-handed (mirrored) button layout, button size slider, colorblind-safe player colors.
- Performance pass: 60 fps on the reference Android and iPhone with 4 players, all hazards and particles.
- Store prep: icons, screenshots, privacy text (local network use only, no data collected), release signing.

---

## 7. Future Enhancements (not scheduled) and the Openings We Build Now

These come from requirements §11 and the kill-clip feature in §9, deferred by decision D10. The table lists what we build **now** so that adding them later doesn't need a rewrite.

| Future feature | Opening built now | Built in |
|----------------|-------------------|----------|
| **Cosmetics** (skins, rope trails, hook shapes, kill effects, emotes) | All visuals come from `SkinDef` resources referenced by ID (§3.8). A `PlayerLoadout` dictionary (`skin_id`, `trail_id`, `hook_id`, `kill_fx_id`, `emote_id`) is part of the player's profile and is sent in the Phase 2 lobby handshake, so other devices render the right look. | Phase 1 (`SkinDef`), Phase 2 (loadout in handshake) |
| **Battle pass** | `GameEvents` already reports every meaningful action. A future `ProgressTracker` subscribes to it and awards XP. `ProfileStore` has a `schema_version` field and a migration function so new fields can be added safely. | Phase 1 |
| **Daily challenges** | Same event bus. Challenge definitions will be data resources (`event`, `condition`, `count`), for example "Pull 5 enemies into hazards" = `fighter_ko` where `cause == hazard` and `last_puller == me`. To make that possible, `fighter_ko` already carries `cause` and `last_puller`. | Phase 1 (event fields), Phase 4 (hazard causes) |
| **Purchases** (cosmetics, battle pass) | A `Store` autoload interface with a stub implementation (everything locked or free in development). Later it is backed by App Store / Play Store in-app purchases via Godot's platform plugins. | Phase 7 (stub) |
| **Ranked mode** | Needs a trusted, internet-connected server to stop cheating, which conflicts with D4. Opening: every match produces a `MatchResult` record (players, mode, scores, duration, protocol version) stored locally. If a backend is ever added, these records are what it would receive. Until then, local-only stats replace ranked. | Phase 5 |
| **Accounts and cloud save** | `ProfileStore` is an interface; the MVP implementation saves to `user://profile.json`. A cloud version can implement the same interface. The player ID is a random UUID generated on first launch. | Phase 1 |
| **Kill-clip sharing** (5-second final-kill clip) | The host and each client keep a ring buffer of the last 6 s of snapshots (Phase 2 already needs snapshots). A future replay player renders it and records video via a platform plugin, then opens the OS share sheet. No server needed. | Phase 2 (buffer), Phase 7 (local replay) |
| **Internet play** | Not planned (D4). The `InputCommand`/snapshot protocol is transport-independent, so a relay transport could be added without changing gameplay code. | Phase 2 |

---

## 8. Requirements Traceability

| Requirement | Phase | Where |
|-------------|-------|-------|
| PHY-01, PHY-02 | 1 | §3.6 |
| PHY-03 | 1 | §4.3, §4.4 |
| PHY-04 | 1 | §4.6 Release |
| PHY-05 | 1 (melee), 3 (weapons) | §4.8, §4.10 |
| PHY-06 | 3 | §6.3 |
| ROPE-01, ROPE-03, ROPE-04, ROPE-05 | 1 | §4.6, §4.8 |
| ROPE-02 | 3 | §6.3 |
| ROPE-06, ROPE-07, ROPE-15 | 6 | §6.6 |
| ROPE-08 | 4 | §6.4 |
| ROPE-10, ROPE-11, ROPE-12, ROPE-13 | 1 | §4.4, §4.6, §4.7, §4.8 |
| ROPE-14 | 3 | §6.3 |
| MEL-01, MEL-02, MEL-03 | 1 | §4.8 |
| MEL-04, MEL-05 | 3 | §6.3 |
| MEL-06 | 4 | §6.4 |
| CNT-01, CNT-02 | 3 | §6.3 |
| CNT-03 | 1 | §4.8 |
| HP-01 | 1 | §4.8 |
| HP-02 | 4 | §6.4 |
| HP-03 | 3 | §6.3 |
| WPN-01, WPN-02, WPN-03, WPN-05, WPN-06 | 3 | §6.3 |
| WPN-04 | 6 | §6.6 |
| Weapon list (§5.2) | 3 (pistol, shotgun, sword), 6 (rest) | §6.3, §6.6 |
| ARN-01 | 1, changed by D28 (bigger scrolling arenas) | §2.2, §4.2, D28 |
| ARN-03 | 1 (turbine), 4 (more debris) | §4.2, §6.4 |
| ARN-02, ARN-04 – ARN-10 | 4 | §6.4 |
| Mid-match events, arena themes | 4 | §6.4 |
| Game modes (§7) | 5 (5 modes), 6 (Co-op Survival) | §6.5, §6.6 |
| CTL-01, CTL-02, CTL-03, CTL-04, CTL-06, CTL-07, CTL-08 | 1 | §2.2, §4.4, §4.5, §4.7, §4.11 |
| CTL-05 | 3 | §6.3 |
| Game feel (§9): hitstop, shake, rope sound, ragdoll-style knockback | 1 | §4.8, §4.11, D12 |
| Game feel (§9): final-kill slow motion | 7 | §6.7 |
| Game feel (§9): 5-second kill clip | Future | §7 |
| Risks (§10) | 1–2 | CNT-03 (§4.8), cooldown (§4.6), despawn (§6.3), drag + cling (§3.6, §4.3), netcode (§3.1, §6.2) |
| Progression and monetization (§11) | Future | §7 |
| "Online, 2–4 players with bots" | 2 (as LAN/hotspot, D4) | §6.2 |

---

## 9. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| The rope doesn't feel fun | Whole game | Live tuning sliders, playtest gate (§5.1), rope wrapping kept as a fallback idea (D13) |
| iOS multicast entitlement delayed or refused | iPhones can't auto-discover games | Apply at the start of Phase 2; the join code works without it (§6.2) |
| Some Wi-Fi networks block device-to-device traffic (guest/corporate networks with client isolation) | Can't connect | Recommend a phone hotspot in the lobby help text; show a clear "Can't reach host" error |
| Prediction errors when being pulled or hit by others (the host decides those) | Brief corrections on clients | Interpolated smoothing (§6.2); LAN latency is typically low; pull speeds are capped |
| GDScript performance on low-end Android with 4 fighters, bots and particles | Frame drops | Sim is light (no rigid-body solver); pooled CPU particles; ~110 draw calls per frame (D35); `tools/benchmark.gd` measures the sim; profile on the reference phones; move hot code to C++ GDExtension only if profiling demands it |
| Touch ambiguity between rope taps, swipes and buttons | Misfires | Button exclusion zones, kick window only while clinging (§4.4), covered by unit tests (§4.14) |
| Third-party asset licenses | Legal | CC0 only in Phase 1; every asset recorded in `assets/CREDITS.md` |
