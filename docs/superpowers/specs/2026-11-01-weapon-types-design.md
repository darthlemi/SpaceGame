# Weapon Types Design

## Goal

Expand the single flat `Weapon` resource (damage/fire_rate/range) into five
weapon families — Kinetic, Missile, Beam, Point Defense, Drone — each with
3-4 role-differentiated variants, balanced against current ship stats:

- Corvette: 60 HP / 20 shield (80 EHP)
- Freighter: 80 HP / 20 shield (100 EHP)
- Capital: 220 HP / 80 shield (300 EHP)

Component damage (engine/weapon disables) is assumed to exist as a design
concept even though it is not implemented yet; this spec defines the model
needed to implement it.

## Damage model

Additive fields on `Weapon`, defaulting to no-ops so existing content
(the current default Kinetic Cannon) is unaffected:

- `shield_mult: float = 1.0` — shield absorbs `damage * shield_mult` first.
- `hull_mult: float = 1.0` — overflow (or, for pierced damage, raw damage)
  applies `damage * hull_mult` to hull.
- `pierce_pct: float = 0.0` — this fraction of damage skips the shield
  entirely and hits hull directly. Used sparingly (Railgun, Lance).
- `component_damage: float = 0.0` — applies to a component pool (see below)
  in addition to the normal shield/hull split. Nonzero only on
  EMP/ion-flavored weapons.
- `mount_type: enum {FIXED, TURRET}` + `fire_arc_degrees: float` — Fixed
  weapons fire straight along the ship's forward axis only (no tracking,
  hull must face the target). Turreted weapons traverse within an arc
  (60°-140° typical; PD turrets get near-full traversal since their job is
  intercepting threats from any direction). Weapons never fire through the
  ship — arc is always centered on the mount's facing, not omnidirectional
  by default.
- `rarity: enum {COMMON, UNCOMMON, RARE, EPIC}` — tracks DPM and
  specialization, not raw power alone. Common = safe generalist. Uncommon =
  clear tradeoff/niche. Rare = high alpha or a narrow-but-powerful disable
  niche. Epic = breaks its own type's usual rule. Spawn/loot rules using
  this tag are out of scope for this spec.

### Component pools

Each ship has independent small HP pools per disable-able subsystem (e.g.
`engine_hp = 30`, `weapons_hp = 30`), separate from hull/shield. A hit with
nonzero `component_damage` applies to a random-weighted component pool.
Reaching 0 disables that subsystem for a duration, then it repairs/resets.
Targeting a *specific* component is a later feature — out of scope here.

Missiles/drones use cooldown-only firing (`fire_rate`), same as existing
weapons — no finite ammo/magazine layer.

## Kinetic (ballistic — strong vs hull, weak vs shield, cheap/reliable)

| Weapon | Mount/Arc | Dmg | Rate | DPS | Range | Shield× | Hull× | Pierce | Rarity | Role |
|---|---|---|---|---|---|---|---|---|---|---|
| Autocannon | Turret 100° | 10 | 1.0 | 10 | 300 | 0.7 | 1.1 | — | Common | Workhorse generalist |
| Mass Driver | Turret 120° | 14 | 0.8 | 11.2 | 400 | 1.0 | 1.0 | — | Common | Neutral all-rounder |
| Flak Cannon | Turret 140° | 4 | 4.0 | 16 | 200 | 0.6 | 0.6 | — | Uncommon | Anti-swarm splash, weak single-target |
| Railgun | Fixed | 35 | 0.25 | 8.8 | 500 | 0.5 | 1.3 | 25% | Rare | Long-range sniper, punishes stationary targets |

## Missile (ordnance — flexible alpha, countered by PD)

| Weapon | Mount/Arc | Dmg | Rate | Range | Shield× | Hull× | Special | Rarity | Role |
|---|---|---|---|---|---|---|---|---|---|
| Seeker Missile | Turret, homing | 18 | 0.5 | 350 | 1.1 | 0.9 | Always hits unless intercepted | Common | Reliable chip damage vs mobile targets |
| Swarm Missile | Turret, volley | 5×4 submissiles | 0.33 | 300 | 1.2 | 0.7 | Saturates PD | Uncommon | Punishes PD-less fleets, dies to PD |
| Torpedo | Fixed, slow straight-line | 60 | 0.2 | 450 | 1.0 | 1.2 | Slow travel — interceptable | Rare | Capital-killer burst |
| EMP Missile | Turret, homing, short rng | 6 | 0.4 | 250 | 0.8 | 0.5 | +15 component dmg/hit | Rare | Disables a subsystem, low DPS |

## Beam (energy — strong vs shield, weak vs hull except Lance; instant-hit)

| Weapon | Mount/Arc | Dmg | Rate | DPS | Range | Shield× | Hull× | Special | Rarity | Role |
|---|---|---|---|---|---|---|---|---|---|---|
| Pulse Laser | Turret 110° | 9 | 1.2 | 10.8 | 280 | 1.4 | 0.75 | — | Common | Shield-stripper generalist |
| Heavy Beam | Turret 90° | 16 | 1.0 | 16 | 220 | 1.3 | 0.85 | — | Uncommon | Close-range shield-melter |
| Disruptor (Ion) | Turret 100° | 5 | 1.0 | 5 | 260 | 1.0 | 0.4 | +10 component dmg/hit, pauses shield regen 2s | Rare | Lockdown utility, weak raw dmg |
| Lance/Graser | Fixed | 30 | 0.4 | 12 | 450 | 0.6 | 1.3 | 20% pierce | Epic | Sniper that breaks Beam's usual hull weakness |

## Point Defense (2 variants, short range, wide/full traversal turret, weak dual-use vs ships)

| Weapon | Dmg | Rate | Range | vs Missile/Drone | vs Ship (Shield×/Hull×) | Rarity | Role |
|---|---|---|---|---|---|---|---|
| PD Flak Turret | 3 | 6.0 | 120 | Splash, best vs clustered swarms | 0.3 / 0.3 | Common | Counters Swarm Missile/drone volleys |
| PD Laser Turret | 6 | 3.0 | 150 | Hitscan, best vs single fast targets | 0.3 / 0.3 | Uncommon | Counters Torpedo/Seeker/solo Interceptor |

## Drone (launched autonomous craft — own HP, no mount arc; countered by enemy PD/flak)

| Drone | HP | Dmg | Rate | Special | Rarity | Role |
|---|---|---|---|---|---|---|
| Attack Drone | 15 | 4 | 1.5 | — | Common | Generalist DPS add-on |
| Interceptor Drone | 8 | 2 | 2.0 | ×3 vs missiles/drones, ×0.3 vs ships | Uncommon | Mobile PD escort |
| Bomber Drone | 10 | 40 (one-shot) | — | Kamikaze payload, self-expends | Rare | High-risk anti-hull strike |
| EW Drone | 6 | — (no weapon) | — | -50% target shield regen while in range | Epic | Pure debuff support, no DPS |

## Balance / counter-play summary

- **Kinetic vs Beam** is the core damage-type tension: Kinetic chews
  through hull but bounces off shields; Beam melts shields but underwhelms
  once hull is bare (except Lance, which deliberately breaks this rule at
  Epic rarity).
- **Missiles** trade reliability for burst, but every variant is
  vulnerable to PD — Torpedo's slow travel and Swarm's multiple weak
  bodies both get eaten by PD before impact; Seeker is the safest pick.
- **Point Defense is a pure opportunity-cost pick**: strong vs
  missiles/drones, nearly dead weight vs ships directly. Fleets choose it
  only when expecting missile/drone-heavy opposition.
- **Drones** add flexible DPS but create their own rock-paper-scissors:
  Interceptor Drones and PD/Flak counter enemy drones and Swarm Missiles;
  Bomber Drones share Torpedo's counters.
- **The "disable" sub-economy"** (EMP Missile, Disruptor Beam, EW Drone)
  deals low direct damage but sets up kills for high-alpha weapons
  (Torpedo, Railgun, Lance) by knocking out a target's weapon/engine or
  shield regen — most valuable in capital duels where raw DPS races are
  slow.

## Out of scope

- Ammo/magazine limits (missiles/drones use cooldown only, per decision).
- Component-specific targeting (which component gets hit is
  random-weighted for now).
- Rarity-driven spawn/loot tables.
- Mount size restrictions (small/medium/large hardpoints).
