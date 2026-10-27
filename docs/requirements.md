# Swing and Shoot — Game Requirements

**Platform:** Mobile (iOS / Android), landscape orientation
**Genre:** Arena brawler / physics combat
**Players:** 2–4 per match (online, with bots to fill empty slots)
**Match length:** Short rounds, roughly 2–3 minutes

---

## 1. Core Concept

Players float in a **zero-gravity space arena** that fits on a single screen, with obstacles throughout. The **rope (grapple)** is the heart of the game: it is the main way to move, the way to pick up weapons, and a way to pull enemies in for attacks.

Weapons drift around the arena. Players grab them with the rope and use them to fight. Weapons that nobody picks up **vanish after a while**. **Melee is always available**, so a player is never defenseless.

**Design principle:** one mechanic, the rope, does everything — movement, looting and combat. Every grapple is a decision about where to go, what to grab and who to drag.

---

## 2. Physics Rules (Zero Gravity)

| ID | Requirement |
|----|-------------|
| PHY-01 | There is no gravity. Objects keep moving in a straight line until something stops or deflects them. |
| PHY-02 | Apply a small amount of drag so players and objects slow down gradually instead of drifting forever. |
| PHY-03 | When a player reaches a surface, they **cling** to it briefly (like magnetic boots), then can kick off or fire the next rope. |
| PHY-04 | Momentum is preserved when a rope is released mid-pull: the player or object keeps its speed and direction. |
| PHY-05 | Knockback carries a long way in zero-g; a hit near a hazard can be lethal even if it does little damage. |
| PHY-06 | Every gun produces **recoil** that pushes the shooter backward. Light weapons barely nudge; heavy weapons launch the player across the arena. |

---

## 3. Rope Mechanics

### 3.1 Behavior by target

| ID | Rope hits… | Result |
|----|------------|--------|
| ROPE-01 | Wall / obstacle | The player is reeled toward it. |
| ROPE-02 | Weapon | The weapon is pulled to the player and picked up. |
| ROPE-03 | Enemy | The enemy is pulled toward the player. |
| ROPE-04 | Obstacle while drifting sideways past it | The player **orbits** around it like a ball on a string. Releasing slingshots them off at speed. |
| ROPE-05 | Rotating obstacle (e.g. turbine) | The player is swung around at the obstacle's speed and flung off on release. |
| ROPE-06 | Incoming projectile (e.g. grenade) | The projectile is caught and can be whipped back. High-skill move. |
| ROPE-07 | Another player's rope | Mid-air tug-of-war, decided by a quick tap/swipe duel. Winner reels in the loser. |
| ROPE-08 | Smooth / non-stick panel | Rope does not attach. Players must read the map before grappling. |

### 3.2 General rope rules

| ID | Requirement |
|----|-------------|
| ROPE-10 | The rope has a **limited range**, shown as a faint circle around the player. |
| ROPE-11 | The rope has a short **cooldown** to prevent spamming. |
| ROPE-12 | Releasing early during a pull is allowed and keeps momentum (see PHY-04). |
| ROPE-13 | Releasing an enemy mid-pull **throws** them past you in the direction they were travelling (e.g. into a hazard). |
| ROPE-14 | Ropes can be **cut** by blade weapons and by a well-timed melee hit. |
| ROPE-15 | If two players rope each other at the same time, both are pulled together and meet in the middle for a mid-air clash. |

---

## 4. Combat

### 4.1 Melee (always available)

| ID | Requirement |
|----|-------------|
| MEL-01 | Melee is available at all times, with or without a weapon. |
| MEL-02 | **Melee damage and knockback scale with speed.** A hit while moving fast is much stronger than one thrown while floating still. |
| MEL-03 | **Signature combo:** pull an enemy with the rope, then melee them as they arrive at speed. This must feel great (hitstop, screen shake, strong impact sound). |
| MEL-04 | **Parry:** a perfectly timed melee deflects bullets and knocks away incoming ropes. |
| MEL-05 | **Ramming:** flying into an enemy at high speed knocks them away, even unarmed. |
| MEL-06 | Knockback into hazards is a primary way to score kills. |

### 4.2 Counterplay to being pulled

| ID | Requirement |
|----|-------------|
| CNT-01 | A player clinging to a surface **resists** being pulled, creating a tug-of-war. |
| CNT-02 | A well-timed melee cuts an incoming rope. |
| CNT-03 | After being pulled, a player gets a **short pull immunity** so they can't be chain-pulled to death. |

### 4.3 Health and kills

| ID | Requirement |
|----|-------------|
| HP-01 | Players have health that weapons and melee reduce. |
| HP-02 | Hazards (vents, electric walls, black holes, sawblades, explosions) can kill or heavily damage players. |
| HP-03 | A hard hit can **disarm** a player; the weapon drifts away for anyone to grab. |

---

## 5. Weapons

### 5.1 Pickup and despawn

| ID | Requirement |
|----|-------------|
| WPN-01 | Weapons spawn and drift slowly around the arena. |
| WPN-02 | Weapons are picked up by hitting them with the rope. |
| WPN-03 | Unclaimed weapons **despawn after a set time**. They blink faster as they are about to vanish. |
| WPN-04 | Occasionally a **legendary weapon** spawns in a dangerous spot, announced with a short countdown, to pull players into the same fight. |
| WPN-05 | When a weapon runs out of ammo, it can be **thrown** as a projectile instead of simply disappearing. |
| WPN-06 | Weapons spin and glow while floating so they are easy to spot. |

### 5.2 Weapon list

| Weapon | Behavior |
|--------|----------|
| Pistol | Basic gun, low recoil. |
| Shotgun | Spread shot with big recoil; doubles as a movement burst. |
| Rocket launcher | Explosive shot with very large recoil. |
| Sword / blade | Strong melee that also **cuts ropes**. |
| Boomerang blade | Thrown; cuts ropes on the way out and back. |
| Harpoon launcher | Fires a **second rope**, so a player can stay anchored while pulling an enemy. |
| Freeze ray | Freezes a target; a frozen player can be roped and swung as a **wrecking ball** into others. |
| Magnet glove | Pulls nearby drifting weapons and metal-armored players toward the user. |
| Sticky grenade | Sticks to players or ropes, endangering whoever holds that rope. |
| Bouncing laser | Ricochets off obstacles, rewarding geometry tricks. |
| Gravity grenade | Creates a small gravity well that pulls in players, weapons and debris for a few seconds. |
| Black hole bomb | A stronger, longer gravity well that swallows everything nearby, including ropes. |
| Repulsor blast | Pushes everything away from the user, including enemies being pulled in. |
| Tether mine | Sticks to a surface and ropes anyone who drifts near it. |
| Tether rope (rare) | Ties two enemies together so they smash into each other. |
| Shield | Blocks bullets from the front; can be pulled off by an enemy's rope. |
| Thruster pack | Temporary pickup that allows free steering without the rope. |

---

## 6. Arenas

### 6.1 Arena features

| ID | Requirement |
|----|-------------|
| ARN-01 | Each arena fits on a **single screen**. |
| ARN-02 | **Drifting asteroids** act as both moving anchor points and hazards. |
| ARN-03 | **Rotating debris and turbines** support slingshot swings. |
| ARN-04 | **Airlock vent:** periodically opens and sucks players and weapons toward it. Being sucked out is a kill. |
| ARN-05 | **Electric edges:** screen edges bounce and damage players (default). |
| ARN-06 | **Wrap-around edges** as an alternative on some maps: exit left, re-enter right. |
| ARN-07 | **Smooth panels** that the rope cannot attach to. |
| ARN-08 | **Fuel tanks** that explode when shot and launch nearby players. |
| ARN-09 | **Breakable obstacles**, so maps open up and get more dangerous as the match goes on. |
| ARN-10 | **Black hole map:** a black hole in the center slowly grows during the match. |

### 6.2 Mid-match events

- **Lights out:** only weapons and rope tips glow.
- **Vent surge:** airlocks open across the map at once.
- **Closing walls:** the arena slowly shrinks to force a finish.
- **Debris storm:** a wave of asteroids sweeps across the screen.

### 6.3 Arena themes

Space station interior, asteroid field, derelict ship, near-star solar platform.

---

## 7. Game Modes

| Mode | Description |
|------|-------------|
| Free-for-all | 3–4 players, first to N kills. |
| 2v2 | Teams can rope each other: pull a teammate out of danger or throw them at an enemy. |
| King of the Swing | Hold a moving zone to score points. |
| Hot Potato | A bomb sticks to one player and can only be passed by rope or melee hit. |
| Gun Game | Each kill swaps you to the next weapon in a sequence; the final kill must be melee. |
| Co-op Survival | Fight waves of AI enemies or a giant boss you must rope onto. |

---

## 8. Mobile Controls

| ID | Requirement |
|----|-------------|
| CTL-01 | Landscape orientation. No movement joystick (there is no walking in zero-g). |
| CTL-02 | **Tap anywhere to fire the rope** at that spot. Tap a wall to go there; tap an enemy or weapon to pull it. |
| CTL-03 | Hold to keep the rope attached; lift the finger or tap again to **release early**. |
| CTL-04 | One button for **melee**. |
| CTL-05 | One button to **fire** the held weapon, with light auto-aim toward the nearest enemy. |
| CTL-06 | **Rope aim assist:** snap slightly toward the nearest anchor, weapon or player near the tap point. |
| CTL-07 | Rope range shown as a faint circle around the player. |
| CTL-08 | **Haptic feedback** on rope connections and melee impacts. |

---

## 9. Game Feel and Polish

- Hitstop on every successful hit.
- Screen shake on strong impacts.
- Slow motion on the final kill of a round.
- Rope tension sound while pulling.
- Ragdoll-style knockback.
- Auto-generated **5-second clip of the final kill** that players can share.

---

## 10. Balance and Technical Risks

| Risk | Mitigation |
|------|------------|
| Infinite pull-and-punch loops | Short pull immunity after being pulled (CNT-03). |
| Rope spam | Rope cooldown (ROPE-11). |
| Players camping weapons | Weapon despawn timer (WPN-03) and legendary spawns in exposed spots (WPN-04). |
| Endless drifting / loss of control | Slight drag (PHY-02) and cling on arrival (PHY-03). |
| Online sync of rope physics | Plan netcode from day one (rollback or server-authoritative physics). Option to launch with bots and local play first. |

---

## 11. Progression and Monetization

- **Cosmetics only:** rope trails, hook shapes, character skins, kill effects, emotes. No pay-to-win.
- **Battle pass** for cosmetic rewards.
- **Ranked mode** for competitive players.
- **Daily challenges** that teach mechanics, e.g. "Pull 5 enemies into hazards" or "Win without picking up a weapon".

---

## 12. MVP / First Prototype Scope

The goal of the prototype is to prove the rope feels fun on its own.

**Include:**
1. One empty arena with walls and a few obstacles, including one rotating obstacle.
2. Tap-to-rope onto walls and obstacles.
3. Cling-and-kick-off on arrival at a surface.
4. Rope an enemy and pull them into a melee hit.
5. Orbiting / slingshot around an obstacle.

**Success test:** if flying around with only these mechanics is fun in an empty arena, proceed to weapons (start with pistol, shotgun and sword), hazards and game modes.
