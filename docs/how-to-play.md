# Swing and Shoot: How to Play

A player's guide: controls, movement, fighting, every combo, weapons, pickups, arenas, modes and
bots. Numbers are the default tuning (`data/tuning/default_tuning.tres`) as of 2026-10-29. Distances
are in pixels of the 1920×1080 reference arena, speeds in px/s.

## The game in one minute

Swing and Shoot is a zero-gravity brawler for phones. You fire a grapple rope to fly around a space
arena, hook enemies, and knife or shoot them as they fly past. Nothing falls, everything keeps its
momentum, and the fastest hits do the most damage.

You win by scoring KOs (or the mode's goal) before the clock runs out. Every fighter has 100 HP. At
0 HP you are knocked out and respawn 2 s later, invulnerable for 1.5 s. Knocking someone into a
hazard (a vent, a black hole, an electric wall) counts as your KO too.

Play offline against bots, or on LAN with up to 4 phones: 7 arenas, 8 modes, 19 weapons and
4 pickups.

## Controls

Tap anywhere to fire your rope. The two buttons in the bottom corner are **KNIFE** and **FIRE**.

| Action | Phone | Desktop |
| --- | --- | --- |
| Fire the rope | Tap where you want to go. Aim assist snaps to a nearby enemy, weapon, pickup or turbine hub | Click |
| Let the rope finish on its own | Quick tap and lift: the rope reels you in and lets go about 120 px before the wall, so you coast in; a swing lets go by itself (see Wall swing) | Quick click |
| Let go of the rope now | Hold the tap for 0.2 s or more, then lift; or tap again (lets go and fires a new rope) | Hold, then release |
| Kick off a wall | While clinging, swipe the way you want to fly | Drag while clinging, or Shift (toward the mouse) |
| Air dash | Away from walls, swipe quickly the way you want to go (the rope that tap fired is called back) | Quick drag, or Shift (toward the mouse) |
| Knife (melee) | Tap KNIFE to swing at the nearest enemy, or drag it to aim, then let go | Space or J (aims at the mouse) |
| Use your weapon | Tap FIRE (shown only while you hold one), or drag it to aim | K (aims at the mouse) |
| Pause | Pause button, top left | Esc |

- **Rope stick (optional, in Settings):** a stick in the other bottom corner. Drag to aim, let go to
  fire, tap it to let go of the rope.
- **Thruster:** while the Thruster Pack burns, holding a touch steers toward your finger instead of
  firing a rope.
- **Desktop debug keys:** F1 debug overlay, R respawn, 1/2/3 bot difficulty (0 idle).

## Moving

There is no gravity and very little drag, so you fly in a straight line until you hit something or
fire a rope. What the rope does depends on what it hooks:

| The hook hits | What happens |
| --- | --- |
| A wall or box, while you're slow or flying at it | You are reeled toward it |
| A wall or box off to your side while you fly past fast | You **swing** around the hook in an arc; let go to fling off at 1.10× speed (see Wall swing below) |
| A round obstacle while you fly past it sideways | You orbit it like a ball on a string; let go to slingshot off at 1.10× speed |
| A spinning turbine | It swings you around; let go to be flung off at 1.15× speed |
| A smooth (shiny) panel | Nothing: the hook bounces off. Read the map before you grapple |
| An enemy | They are pulled toward you (see SNAP below) |
| A teammate (2v2) | You both fly toward each other |
| A weapon | It is pulled to you and you hold it |
| A pickup | It is used at once |
| A thrown grenade, rocket, boomerang or mine | You catch it and whip it back |

- **Cling and kick.** Reaching a surface sticks you to it for 1.2 s, then you drift off. While
  clinging, swipe to kick off at 950 px/s, or fire your next rope. A rope fired from a wall that
  finds nothing still kicks you off toward where you aimed.
- **Air dash.** Swipe in open space to turn and burst the way you swiped: at least 750 px/s, or 85% of
  your current speed if you're already faster. You have 2 dashes (the dots under your fighter); each
  comes back 1.5 s after you use it. Use it to dodge a shot, a hook or a knife, to change direction
  mid-flight, or to close the last gap for a SNAP. A dash lets go of a rope on a wall, but a rope
  pulling an enemy or a weapon keeps pulling.
- **Wall swing.** Hook a wall or box 45° or more off your flight direction while flying 350 px/s or
  faster sideways, and you swing around the hook instead of being reeled in. With a quick tap the
  rope lets go by itself once you've turned 90°, or as soon as the arc starts carrying you into that
  wall, so you fly out and skim along it. Hold the tap to keep swinging and lift to let go exactly
  when you want. A hook on a wall you're already flying into still reels you in.
- **Glancing.** Hit a wall at a shallow angle (30° or less) while flying fast (700 px/s or more) and
  you slide along it, keeping most of your speed, instead of sticking. Head-on or slow, you cling.
- **Turbines.** You can cling to a turbine arm and ride it. When you let go you keep the arm's speed,
  and the same turbine can't grab you again for 0.75 s.
- **Momentum.** Letting go of a rope keeps your speed and direction. Chaining ropes without stopping
  is how you get fast.

| Movement number | Value |
| --- | --- |
| Rope range | 720 px (the faint circle around you) |
| Rope cooldown | 0.25 s |
| Hook speed | 4400 px/s |
| Reel speed | up to 1550 px/s |
| Air dash | 750 px/s, 2 charges, 1.5 s each to come back |
| Kick speed | 950 px/s |
| Top speed | 2000 px/s |
| Cling time | 1.2 s |

## Fighting basics

Speed is damage: a knife hit is weak while you float still and strong when you and the target are
closing fast.

**Seeing hits.** A hit fighter squashes along the hit, flashes white then red, and shows a floating
damage number (yellow for a SNAP, blue when armor soaked it). Stars circle their head while they're
stunned, and a hard knockback leaves a smoke trail. HP bars show the lost part in white for a moment
before it drains. When you are hit the screen edge flashes red, and below 25 HP it pulses.

**The knife** is always available, with or without a weapon. A swing has a short wind-up, 6 active
frames that hit anyone in a 120° arc within 95 px, then a short recovery. You can swing again after
0.35 s. Tapped without aiming, it swings at the nearest enemy within 180 px.

```
knife damage = min(8 + 0.025 × closing speed, 45)
knockback    = min(350 + 1.1 × closing speed, 1700)
```

Closing speed counts both of you, so a target flying into you counts as much as you flying into
them.

- **Disarm:** a hit with 1200 px/s or more of knockback knocks the victim's weapon loose.
- **Hitstun:** a hit fighter tumbles and can't act for a moment; harder hits last longer.
- **KO and respawn:** at 0 HP you're out for 2 s, then respawn at the spawn point farthest from
  enemies, invulnerable (blinking) for 1.5 s.
- **Hazard KOs:** if someone dies to a vent, black hole or electric wall within 3 s of you hitting or
  pulling them, the KO is yours. Knockback carries far in zero-g, so a weak hit next to a hazard can
  be a kill.
- **Pull immunity:** after an enemy rope lets go of you, no enemy can rope you for 1 s (a blue ring
  shows it).
- **Clinging resists pulls:** a fighter stuck to a wall holds on, and the puller is dragged toward
  them until their grip runs out.

## Combos and skill moves

The game has one true combo, **SNAP**, which gets a damage bonus. Everything else here is a skill
move or an item interaction, and many of them set up a SNAP.

### SNAP (the signature combo)

Rope an enemy so they're pulled toward you, then hit KNIFE as they fly past. If the knife lands
while they're still being pulled, or within **0.35 s** after the pull ends, it's a SNAP: ×1.25
damage, a longer impact freeze, a heavier sound, stronger screen shake and a "SNAP!" pop-up.

```
SNAP damage = 1.25 × min(8 + 0.025 × closing speed, 45)
```

| Closing speed when it lands | Normal knife | SNAP |
| --- | --- | --- |
| 400 px/s (slow) | 18 | 22.5 |
| 800 px/s | 28 | 35 |
| 1200 px/s | 38 | 47.5 |
| 1480 px/s or more (full-speed pull) | 45 | 56 (max) |

A rope pulls at up to 1500 px/s, so a well-timed SNAP usually does 45–56 damage, and two SNAPs kill
from full health. Knockback gets no SNAP bonus, but a fast hit usually disarms anyway.

| SNAP stacked with | Max damage |
| --- | --- |
| Knife only | 56 |
| Power pickup (×1.5) | 84 |
| Sword (×1.6) | 90 |
| Sword and Power | 135 (a one-hit kill unless the target has Armor) |

### Melee moves

| Move | How | Payoff |
| --- | --- | --- |
| Dash dodge | Swipe sideways just before a shot, hook or knife reaches you | It misses; you keep moving |
| Dash in | Dash at an enemy just out of knife reach, then KNIFE | Closes the gap faster than a rope, and the dash speed adds to the hit |
| Parry | Swing just as a bullet or hook reaches you (about 0.1 s either side of the active frames) | Bullets fly back at the shooter and become yours; hooks are knocked away |
| Rope cut | Swing through someone's rope line (a sword cuts too) | Their rope breaks; cutting the rope pulling you frees you |
| Ram | Fly into an enemy at 900 px/s or more of closing speed, even unarmed | 6 + 0.02 × closing speed damage and big knockback; you keep 40% of your speed |
| Teammate throw (2v2) | Knife your teammate | No damage; they're launched at 1300 px/s, for example into an enemy |

### Rope moves

| Move | How | Payoff |
| --- | --- | --- |
| Release throw | Let go of an enemy mid-pull | They keep flying past you, ideally into a vent, black hole or electric wall |
| Tug-of-war | Your hook crosses an enemy's rope | A 1.2 s tapping duel; the winner pulls the loser in, which sets up a SNAP |
| Rope clash | Two players rope each other at the same time | You meet in the middle and both bounce apart at 1000 px/s |
| Catch and whip | Hook an incoming grenade, rocket, boomerang or mine | It's hauled in, then whipped back |
| Shield rip | Hook a shield holder from the front | The shield is torn off and pulled to you |
| Slingshot | Orbit a round obstacle, then let go | ×1.10 speed fling, for a faster ram or SNAP |
| Wall swing | Hook a wall to your side while flying fast; hold, and lift when you face where you want to go | ×1.10 speed fling around corners and toward fights |
| Turbine fling | Hook a turbine arm, ride it, then let go | ×1.15 speed fling |

### Weapon combos

| Move | How | Payoff |
| --- | --- | --- |
| Wrecking ball | Freeze an enemy, then rope or hit them so they fly at 600 px/s or more | Anyone they crash into takes speed × 0.022 damage, credited to whoever roped them |
| Tether smash | Hit an enemy with the Tether Rope | They're tied to the nearest other enemy and smashed together |
| Sticky on a rope | Throw a sticky grenade across someone's rope line | It sticks to the rope's owner |
| Repulsor into a hazard | Blast an enemy toward a vent or electric wall | The KO is yours |
| Mine trap | Pull an enemy across your armed Proximity Mine | It explodes on them |

### Limits on chaining

- After a pull ends, the target can't be roped by an enemy for 1 s, so you can't SNAP, re-rope and
  SNAP again. You need a ram, a shot or a teammate's rope in between.
- A target clinging to a wall resists your pull. Their grip drains twice as fast, and you're dragged
  toward them meanwhile.
- A well-timed knife from the target parries your incoming hook.

## Weapons

Weapons float in from spawn points every 6 s and drift slowly. Rope one to grab it (grabbing a
second drops the first). An unclaimed weapon blinks for its last 5 s and is gone after 15 s. An
empty gun becomes a throw: FIRE hurls it at the target.

Guns and blades:

| Weapon | Ammo | Between shots | Damage | What it does |
| --- | --- | --- | --- | --- |
| Pistol | 12 | 0.22 s | 9 | The common gun; light recoil |
| Shotgun | 4 | 0.75 s | 6 × 6 pellets | Wide spread, big recoil that launches you backward |
| Sniper | 4 | 1.4 s | 30 | Crosses the arena. Everyone hears the bolt and sees "X HAS THE SNIPER!" when it's picked up, sees its red laser sight, and hears the boom |
| Sword | – | knife timing | knife × 1.6 | Replaces the knife: 40 px more reach, ×1.3 knockback, cuts ropes |

Special weapons:

| Weapon | Ammo | What it does |
| --- | --- | --- |
| Rocket Launcher | 3 | Slow rocket that explodes on impact (34 damage, 260 px blast), huge recoil |
| Bouncing Laser | 6 | 11 damage, ricochets off walls up to 3 times |
| Boomerang Blade | – | Thrown out to 750 px and back (14 damage); cuts ropes both ways; catch it to throw again |
| Harpoon Launcher | 3 | A second rope: hooks an enemy (6 damage) and hauls them in while your own rope stays put |
| Freeze Ray | 3 | The target can't act for 3 s and keeps its speed, and can always be roped: make a wrecking ball |
| Magnet Glove | 3 | For 2.5 s, drags loose weapons and armed enemies within 800 px toward you |
| Sticky Grenade | 2 | Sticks to a fighter, a rope's owner or a wall, then blows 1.8 s later (30 damage) |
| Gravity Grenade | 2 | Opens a gravity well (480 px) for 3 s |
| Black Hole Bomb | 1 | Legendary. A stronger well for 4 s whose core KOs and swallows ropes and weapons |
| Repulsor | 4 | A 110° cone blast ahead (520 px, plus anything right next to you): 14 damage, knockback hard enough to disarm, turns shots around, breaks a pull on you, and kicks you backward |
| Tether Mine | 2 | Sticks to a wall; ropes the first enemy that comes within 240 px and holds them |
| Proximity Mine | 3 | Sticks to a wall, arms after 0.9 s, explodes (38 damage) when an enemy comes within 120 px. You and your teammates can't set it off |
| Tether Rope | 1 | Rare. Ties the enemy it hits to the nearest other enemy; they smash together |
| Shield | – | Blocks shots from the front; FIRE is a shield bash. An enemy rope from the front rips it away |
| Thruster Pack | – | For 7 s, hold a touch to steer and fly; then it's used up |

**Legendary weapons:** after 45 s, and then every 70 s, a legendary weapon is announced with a 3 s
countdown and appears in a dangerous spot (next to a vent, a fuel tank or the black hole).

## Pickups

Pickups spawn and float like weapons. Rope one or fly through it and it's used at once; you keep
your weapon. Modes that limit the weapons (Gun Game) still spawn pickups.

| Pickup | Icon | Effect |
| --- | --- | --- |
| Med Kit | Green cross | +40 HP, up to 100 |
| Armor | Blue plate | Absorbs the next 35 damage before HP (60 at most). Shown as a blue bubble and a blue strip on your HP bar |
| Haste | Yellow bolt | For 6 s: ×1.3 reel speed, kick speed and top speed, and a shorter rope cooldown |
| Power | Pink star | For 8 s: ×1.5 damage on everything you deal |

Your HUD shows armor next to your HP and the seconds left on Haste and Power under it. All pickups
are cleared when you are KO'd.

## Arenas and hazards

| Arena | What's special |
| --- | --- |
| Station | Wide open, three spinning turbines (the default arena) |
| Interior | Tight rooms, airlock vents that suck you out, fuel tanks, breakable panels, smooth panels |
| Asteroids | No walls: fly off one edge and come back on the other; drifting asteroids, fuel tanks |
| Derelict | A broken hull with electric edges, a vent, breakable panels, fuel tanks, smooth panels |
| Solar | Electric edges, drifting rocks, fuel tanks, smooth panels |
| Singularity | A black hole in the middle pulls everything in |
| Hangar | The small first arena with one turbine |

Hazards:

- **Turbines** spin at a steady speed. Ride them, swing on them, get flung.
- **Smooth panels** can't be hooked; fighters bounce off them instead of clinging.
- **Electric edges** bounce you hard and deal 8 damage (at most every 0.4 s).
- **Airlock vents** cycle every 14 s: a 1.5 s warning, then 3 s open, sucking fighters and weapons
  toward them. Being sucked out is a KO.
- **Fuel tanks** explode after 25 damage (shots or blasts): 30 damage and big knockback within
  330 px. They come back after 20 s.
- **Breakable panels** take damage from shots and blasts and break open.
- **Drifting asteroids** shove you aside for 12 damage.
- **The black hole** grows from 40 px to 170 px over 3 minutes and pulls from six times its size.
  Touching it is a KO.

**Mid-match events:** the first at 30 s, then one every 40 s, picked from the arena's own list (the
Hangar has none).

| Event | Lasts | What happens | Arenas |
| --- | --- | --- | --- |
| Lights Out | 12 s | The arena goes dark except for a small light around each fighter | Station, Interior, Asteroids, Derelict, Singularity |
| Vent Surge | 6 s | Every vent opens at once | Interior, Derelict |
| Closing Walls | 30 s | A safe zone shrinks to 55% of the arena; outside it you take damage and get pushed back in | Interior, Derelict, Solar |
| Debris Storm | 10 s | Rocks fly across the arena (10 damage each) | Station, Asteroids, Solar, Singularity |

## Game modes

| Mode | Players | How to win |
| --- | --- | --- |
| Duel | You vs one bot | Endless practice fight, no limit |
| Free-for-all | Four fighters | First to 10 KOs, 3 minutes |
| 2v2 | Blue vs red | First team to 10 KOs, 3 minutes. Ropes on teammates pull you together; knifing a teammate throws them |
| King of the Swing | Any | A zone moves through the arena. Hold it alone to score; first to 20 seconds of holding, 3 minutes |
| Hot Potato | Any | A bomb sticks to one fighter and passes when its carrier hooks or knifes someone. When the fuse runs out it blows up its carrier, and everyone else scores. First to 5, 4 minutes |
| Gun Game | Any | Every KO moves you to the next weapon: Pistol, Shotgun, Bouncing Laser, Rocket Launcher, Freeze Ray, Boomerang Blade, Sword. After the Sword you're unarmed, and the winning KO must be a knife hit. 5 minutes |
| Co-op Survival | You and an ally | Waves of bots, shared lives. Every 5th wave is a boss: rope onto it and hit its glowing spots. Clear 10 waves |
| Free Fly | You alone | Practice the rope |
| Tutorial | You | Learn the rope, the cling and kick, the slingshot and the pull-and-knife SNAP |

LAN Party: one phone hosts (picks the mode and arena) and up to 3 more join on the same Wi-Fi.

## Bots and difficulty

Bots play by the same rules as you: they send the same inputs a player would and never move their
fighter directly.

- Walls of every kind block their sight.
- They must keep you in sight for a moment before they shoot or rope you, so turning a corner buys
  you time.
- They lead moving targets only partly, so flying fast makes you harder to hit.
- On big arenas they come looking for you: an enemy more than 900 px away is hunted, hooking
  whatever wall gets them closer and dashing across open space.
- They air-dash too: sideways out of a shot or hook coming at them, and at you when you're just out
  of knife reach (they keep one dash for dodging).

| Difficulty | Reaction time | Aim error | Sees you before acting | Leads your movement | Shots per second | Ropes at you per second | Dodge chance per 0.1 s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Easy | 0.35 s | ±14° | 0.7 s | 30% | 1.0 | 0.6 | 6% |
| Normal | 0.22 s | ±8° | 0.45 s | 60% | 1.8 | 1.2 | 15% |
| Hard | 0.12 s | ±4° | 0.25 s | 85% | 2.8 | 2.0 | 30% |

Bots also rope away when you pull them (Easy rarely, Hard often), time SNAPs on their own pulls,
grab weapons, go for pickups when they help (a Med Kit when hurt, Armor when low), and flee hazards.

## Tips

1. Never stop moving: chain ropes so you arrive at fights fast. Speed is your damage.
2. Save a dash for defense. When you see a hook or a red laser line coming, swipe sideways.
3. Learn the SNAP first. Rope, wait for them to fly at you, then KNIFE. Drag KNIFE toward them if
   auto-aim picks the wrong target.
4. Fight near hazards. A release throw or repulsor blast toward a vent or electric wall is a free KO.
5. When someone ropes you, cling to a wall (it resists the pull), knife the rope, or rope away.
6. Watch for the red laser line: someone has the sniper. Break line of sight or close in fast; it
   fires only every 1.4 s.
7. Grab pickups on the way through: flying across a Med Kit costs you nothing.
8. Skim walls at a shallow angle instead of hitting them head-on to keep your speed. Hook walls to
   your side to swing round corners, and use the slingshot and turbine flings to cross the arena
   faster than reeling.
9. Don't drop a Proximity Mine at your own feet mid-fight; it takes 0.9 s to arm. Lay mines on
   the routes people swing through.
