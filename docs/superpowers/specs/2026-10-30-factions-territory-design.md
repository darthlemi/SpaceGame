# Factions & Territory — Design Spec

## Vision

(From the full-game roadmap, Milestone 3.) Ownership and conflict layered
onto the campaign map: two rival power factions, each holding territory
(a base), with a reputation relationship to the player that gates whether
their fleets are hostile. Rival factions can skirmish with each other
(and with pirates) without the player's involvement, resolved
abstractly rather than through a full combat scene.

## Goals for This Milestone

- Two power factions ("Dominion" and "Freehold"), each with a fixed base
  on the map (territory) and a reputation value toward the player.
- Reputation gates whether a faction's fleets are hostile to the player,
  reusing the existing patrol/pirate behavior split rather than adding a
  third behavior class.
- Defeating a power faction's fleet in combat lowers that faction's
  reputation. Nothing raises it this milestone (no missions/trade yet).
- The two power factions are at war with each other by default; both are
  always hostile to the existing stateless pirates. When two non-player
  hostile fleets meet, an abstracted "skirmish" resolves over time
  (duration based on how evenly matched they are) instead of an instant
  outcome or a full `CombatScene` battle.
- Player-vs-fleet combat is completely unchanged — still always a real
  `CombatScene` battle, exactly as today.

## Architecture

**`Faction`** (Resource): `faction_id: StringName`, `display_name:
String`, `reputation: float`, `base_position: Vector2`. Two instances are
created at campaign bootstrap, one per power faction. Pirates remain
exactly as they are today (`CampaignFleet.Faction.PIRATE` tag, no
`Faction` resource, no reputation) — they are not a "power faction" and
are always mutually hostile with both power factions and (per the
existing `PirateBehavior`) with the player.

**`FactionBase`** (scene): visually and structurally identical to the
existing `HomeBase` pattern (an `Area2D` at a fixed map point) but tagged
with its owning `faction_id`. It marks territory and is a future target
for capture/attack — this milestone does not implement capture; the base
is a static landmark only. Docking there for repair is explicitly out of
scope (per your choice: reputation gates combat hostility, not docking
access).

**Reputation → behavior:** each power faction's fleets pick their
movement/aggression behavior from their faction's current `reputation`
against a single exported threshold (`HOSTILE_REPUTATION_THRESHOLD =
40.0`, on a `0.0`–`100.0` scale, starting at `60.0` for both power
factions). Below the threshold, a faction's fleet icons use the existing
`PirateBehavior` (intercept the player if stronger); at or above it, they
use `PatrolBehavior` (ignore the player). This is a per-fleet behavior
selection recomputed whenever `CampaignScene` spawns or re-evaluates a
fleet icon — no new behavior class, reusing what Tasks 2 and 4 already
built.

**Reputation decay:** `CampaignState.resolve_engagement()` (already the
bridge from `CombatScene`) gains a `defeated_faction_id` parameter. When
the player wins a battle against a power faction's fleet, the matching
`Faction.reputation` drops by a fixed `REPUTATION_LOSS_PER_DEFEAT = 15.0`,
clamped at `0.0`.

**Skirmish (NPC-vs-NPC conflict):** a `Skirmish` (plain data, held in a
new `CampaignState.active_skirmishes: Array[Skirmish]`) pairs two
non-player `CampaignFleetIcon`s once `CampaignScene` detects they're
hostile and overlapping (mirroring the existing player-overlap
`area_entered` wiring, but for icon-vs-icon pairs that exclude the player
icon). Hostility rule: a power-faction fleet and a pirate fleet are
always hostile to each other; two power-faction fleets are hostile only
while their factions are at war (a single `CampaignState.factions_at_war:
bool`, `true` by default — with only two power factions, one flag fully
describes their relationship).

Starting a skirmish freezes both icons (they skip their normal behavior
dispatch in `_physics_process` for the skirmish's duration) and computes:

```
imbalance = abs(strength_a - strength_b) / (strength_a + strength_b)   # in [0, 1)
duration = lerp(MAX_SKIRMISH_TIME, MIN_SKIRMISH_TIME, imbalance)       # MAX=30.0s, MIN=3.0s
```

At expiry, the stronger fleet wins: the loser's `CampaignFleet` is
removed from `CampaignState` (same removal path as a pirate destroyed by
the player today), and the winner takes proportional damage via a new
`CampaignFleet.apply_fractional_damage(fraction: float)` method — scaling
every ship's `current_hp`/`current_shield` down by `fraction` (clamped at
0), where `fraction = (1.0 - imbalance) * MAX_WINNER_DAMAGE_FRACTION`
(`MAX_WINNER_DAMAGE_FRACTION = 0.5`). An even fight costs the winner up
to half their strength; a lopsided stomp costs them almost nothing. The
surviving icon unfreezes and resumes its normal behavior.

If the player engages either participant in an active skirmish (triggers
the existing `CombatScene` flow), that skirmish is simply cancelled — the
engaged fleet is now in a real battle; the other combatant (if any) just
unfreezes and resumes normal behavior. No special-casing beyond that.

## Components

- **`Faction`** (Resource): as above.
- **`FactionBase`** (scene): as above.
- **`Skirmish`** (Resource or plain inner class): `fleet_a: CampaignFleet`,
  `fleet_b: CampaignFleet`, `icon_a: CampaignFleetIcon`, `icon_b:
  CampaignFleetIcon`, `remaining_time: float`.
- **`CampaignState`** gains: `factions: Array[Faction]`,
  `factions_at_war: bool`, `active_skirmishes: Array[Skirmish]`. Gains
  methods `start_skirmish(icon_a, icon_b)`, `tick_skirmishes(delta)`
  (called from `CampaignScene._physics_process`), and extends
  `resolve_engagement` with the reputation-decay parameter described
  above.
- **`CampaignFleetIcon`** gains: a `frozen: bool` flag checked at the top
  of `_physics_process` (skip behavior dispatch and movement while
  frozen), and a faction-aware behavior pick for power-faction fleets
  (replacing the fixed `behavior_type` assignment at spawn time for those
  fleets only — pirates/neutral/trader fleets are unaffected).
- **`CampaignFleet`** gains: `apply_fractional_damage(fraction: float) ->
  void`.

## Data Flow

1. `CampaignScene._bootstrap_default_campaign()` creates the two `Faction`
   resources (`Dominion`, `Freehold`), each starting at `reputation =
   60.0`, and spawns one `FactionBase` per faction at a fixed, on-screen
   position distinct from the player's `HomeBase`. `factions_at_war`
   starts `true`.
2. Power-faction fleets are spawned the same way other non-player fleets
   are today, but their `behavior_type` is chosen from their faction's
   current reputation (hostile vs. ignore) rather than a fixed tag.
3. `CampaignScene` detects icon-vs-icon overlaps for non-player pairs
   (new wiring, parallel to the existing player-overlap wiring) and calls
   `CampaignState.start_skirmish()` when the pair is hostile per the
   rules above.
4. Each physics frame, `CampaignState.tick_skirmishes(delta)` counts down
   active skirmishes and resolves any that expire (remove loser, damage
   winner, unfreeze survivor).
5. If the player engages a fleet, any skirmish involving that fleet is
   cancelled (the other participant unfreezes) before the normal
   `CombatScene` hand-off proceeds unchanged.
6. On `CombatScene` resolution, if the defeated enemy fleet belonged to a
   power faction, `CampaignState.resolve_engagement` drops that faction's
   reputation by `REPUTATION_LOSS_PER_DEFEAT`, clamped at 0.

## Explicitly Out of Scope

Territory capture (bases never change ownership this milestone), docking
at a faction base, reputation recovery (no mechanism raises it yet — that
needs missions/trade, both later milestones), more than two power
factions, any UI displaying reputation/faction state to the player
(reputation exists as data only this milestone; a later milestone can
surface it).

## Testing

Following the existing `tests/` pattern (`Formation`-style pure static
methods tested via synchronous `run()`, scene-tree behavior tested via
`run_async(tree)`):

- Unit tests for the imbalance/duration/damage formulas as pure static
  functions (e.g. on a `SkirmishResolution` helper class), covering the
  even-fight and lopsided-fight ends of the range.
- Unit tests for `CampaignFleet.apply_fractional_damage` (partial and
  zero-clamped cases).
- Unit tests for the reputation-threshold behavior pick and for
  `resolve_engagement`'s reputation decay (including the clamp-at-0 case).
- A scene-tree integration test driving two hostile icons through a full
  skirmish via physics frames, asserting the loser is removed from
  `CampaignState` and the winner's fleet took the expected fractional
  damage.
- A scene-tree integration test confirming an in-progress skirmish is
  correctly cancelled when the player engages one of its participants.
