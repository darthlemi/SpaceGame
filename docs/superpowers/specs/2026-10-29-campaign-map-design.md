# Campaign Map — Design Spec

## Vision

(From the full-game roadmap, Milestone 2.) The strategic layer that sits
above the combat core: a persistent map the player's fleet moves through
in real time, encountering other fleets, fighting or avoiding them, and
returning to a home base to repair. This is the skeleton later milestones
(factions, economy, refit, rifts) will hang off of.

## Goals for This Milestone

- A free 2D plane (not a node graph) that the player's fleet moves across
  in real time by setting a heading/destination.
- A single player fleet, a single fixed home base for repair.
- Non-player fleets with distinct behaviors: patrol/wander (neutral),
  trader (routes to/from base, flees danger), pirate (wanders, but
  intercepts the player if it judges itself stronger).
- Engaging a fleet transitions into the existing `CombatScene`; the
  outcome (damage, losses) persists back onto the campaign map.
- Player fleet wiped out → game over. Docking at the home base fully
  repairs the fleet.

## Architecture

Campaign-map fleets are **not** full `Ship` scenes. They're lightweight
2D icons driven by a `CampaignFleet` data resource (composition + current
HP/shield + position/heading/speed). Instantiating full weapon/collision/
visual `Ship` components for every roaming fleet would waste performance
and couple the strategic layer to combat internals for no benefit, since
most map fleets never fight.

An autoload `CampaignState` singleton is the single source of truth that
survives the scene swap between `CampaignScene` and `CombatScene`. It
holds the player's `CampaignFleet`, the list of non-player fleets, and
the home base reference.

Engaging a fleet: `CampaignState.start_engagement(player_fleet,
enemy_fleet)` hands both `CampaignFleet` compositions to `CombatScene`,
which instantiates real `Ship` scenes at their current HP/shield for the
fight — reusing the existing combat core unchanged. On battle end,
`CombatScene` reports results back to `CampaignState.resolve_engagement`,
which writes final HP/shield/destroyed-ship state onto the
`CampaignFleet` resources and swaps back to `CampaignScene`.

## Components

- **`CampaignFleet`** (Resource): `fleet_id`, `faction` (player / pirate /
  trader / neutral — a tag only, no faction logic this milestone), ship
  compositions (hull type + current HP/shield), position, heading, speed.
- **`CampaignFleetIcon`** (scene): visual map node driven by a
  `CampaignFleet` reference; position/heading only, no combat components.
- **`HomeBase`** (scene): single fixed map point. Player fleet docking
  (proximity/button trigger) resets all its ships' HP/shield to max.
- **`CampaignState`** (autoload): holds player fleet, non-player fleet
  list, home base reference. Exposes `start_engagement()` and
  `resolve_engagement(result)`.
- **Fleet behavior strategies** — one independent script per type, not a
  shared state machine, so adding a new type later doesn't touch others:
  - *Patrol/neutral*: wanders within a radius of its spawn point, never
    initiates engagement.
  - *Trader*: moves point-to-point toward the home base and back; flees
    if a hostile fleet comes within range.
  - *Pirate*: wanders like patrol; when the player fleet is within
    detection range, compares total fleet strength (sum of HP+shield
    across ships, as a simple proxy) and moves to intercept if it judges
    itself stronger, otherwise avoids.

## Data Flow

1. `CampaignScene` ticks fleet positions (player input for the player
   fleet; behavior-strategy scripts for others) in real time.
2. Overlap between the player fleet and a hostile fleet triggers an
   engage/disengage prompt (pirates intercept; traders/patrols only
   trigger if the player moves into them). Disengage is only offered if
   not already overlapping — once overlapping, the fight happens.
3. Confirming engage calls `CampaignState.start_engagement`, swapping to
   `CombatScene` built from both fleets' current compositions.
4. `CombatScene` resolves the fight using existing combat-core logic
   unchanged, then reports surviving ships (with final HP/shield) and
   destroyed ships back to `CampaignState.resolve_engagement`.
5. `resolve_engagement` writes results onto the `CampaignFleet`
   resources, removes a destroyed enemy fleet's icon, and swaps back to
   `CampaignScene`.
6. If the player fleet has zero surviving ships, show a game-over screen
   instead of returning to `CampaignScene`.
7. Docking at `HomeBase` resets the player `CampaignFleet`'s ship
   HP/shield to max; no other effect this milestone.

## Explicitly Out of Scope

Faction ownership/reputation and AI faction behavior beyond the three
fleet-behavior strategies above, markets/trading economy (traders follow
a route but carry no actual goods/prices), ship refit/buying, multiple
player fleets, rift spawning. These are later roadmap milestones.

## Testing

Following the existing `tests/` pattern:
- Unit tests for `CampaignFleet` state changes (damage application,
  repair-to-max).
- Unit tests per fleet-behavior strategy: patrol stays within its wander
  radius; trader follows its route and flees on threat proximity; pirate
  correctly compares strength and only intercepts when stronger.
- Unit tests for `CampaignState.start_engagement` / `resolve_engagement`
  data handoff (correct fleets passed in, correct state written back).
- A scene-tree integration test (like the existing combat ones) covering
  a full campaign → combat → campaign round-trip, asserting fleet
  HP/shield and destroyed-ship state is preserved correctly across the
  transition.
