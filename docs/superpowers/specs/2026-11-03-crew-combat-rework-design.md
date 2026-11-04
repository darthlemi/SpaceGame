# Crew Combat Rework - Design

Date: 2026-11-03. Status: awaiting user approval (builder check done).
Amends: `docs/superpowers/specs/2026-11-03-crew-mechanic-design.md` (shipped,
commits up to `35ab62e`). Where the two disagree, this document wins.

Decisions marked "(my call)" were made by Claude while writing this up and
haven't been confirmed by the user. Everything else is the user's decision.

## Intent

The user doesn't want stalemates, or ships that sit disabled, in combat.
Instead:
- Crew losses make a ship progressively worse.
- Losing a battle means the losing side tries to run.
- Ships that fail to escape are captured, with their crew.
- Credits are whole numbers everywhere, because anything below 1 is
  effectively 0 for the player.

Prior art (researched 2026-11-03):
- FTL: crew manning a system gives a bonus to weapon charge, shield
  recharge and evasion.
- Starsector: a skeleton-crew shortage lowers Combat Readiness, and low
  readiness causes malfunctions. Each side chooses engage or disengage,
  and the winner can pursue a ship that's slower than it.

What we take from them: a continuous crew penalty rather than a hard off
switch, and escape odds driven by speed. We don't take Starsector's
post-battle random damage chase, which its developer called a problem.

## Goals

1. **Crew efficiency.** Each ship has an efficiency driven by its crew
   fraction. It scales fire rate, shield regen, top speed and turn rate.
2. **No disabled state.** Ships fight until the hull is destroyed. Crew still
   reaches 0 only when the hull does (unchanged proportional loss).
3. **Losing a battle.** A side loses when it has no active armed ship left.
   "Active armed" means not destroyed, with at least one weapon mount that
   isn't destroyed and has a weapon. Unarmed ships, such as freighters,
   can't keep a side in the fight. This replaces both "all deployed ships
   destroyed or disabled" and the stalemate.
4. **Escape rolls (both sides).** When a side loses, every one of its
   surviving ships rolls to escape, deployed and held back alike. A faster
   ship escapes more often. Speed is the ship's effective speed, so lost
   crew and engine damage reduce it.
5. **Capture.** Ships that fail the roll are captured by the winner, with
   their crew.
   - Player wins: captured ships are offered in the loot window.
   - Enemy wins: your caught ships join the enemy fleet.
6. **Loot window.** It offers:
   - captured ships, each with a Keep checkbox;
   - one crew slider, for the crew aboard captured ships;
   - cargo, as today.

   The slider max is the player fleet's free berths, including the berths
   of kept ships. Ticking a ship raises the max and auto-sets the slider to
   the new max. This replaces the old "20% of crew" capture offer.
7. **Whole credits.** `credits` and every price, sell price, fee, fine,
   repair cost, hire cost, ship price, wage and penalty are ints. Wages are
   1 credit per 10 payable crew per economy tick, rounded down.

## Non-goals

- Crew skill or experience. FTL's skill bonus is not included.
- Boarding actions. Capture only happens through the post-battle roll.
- A playable chase battle (Starsector's "escape scenario").
- A player fleet size cap. None for now (my call).
- Making cargo amounts integer. Fuel stays fractional; only credits change.

## Anti-goals

- A battle that can never end. Removing the stalemate must not bring back
  the unarmed soft-lock.
- Capture creating crew from nowhere. Crew only moves with ships or from
  the captured pool.
- Any fractional credit value visible to the player.

## Crew efficiency

- `efficiency = lerp(MIN_CREW_EFFICIENCY, 1.0, crew / complement)`, with
  `MIN_CREW_EFFICIENCY = 0.5` (my call).
  - Full crew gives 1.0. Half crew gives 0.75.
  - Ships with untracked crew (complement 0: drones, debug ships) are always
    1.0.
- Applied live in combat, every time crew changes:
  - **Fire rate:** cooldown = `1 / (fire_rate * efficiency)`.
  - **Shield regen:** multiplied by efficiency. It must combine with the EW
    drone's existing per-frame `Shield.regen_multiplier` debuff, not
    overwrite it.
  - **Top speed and turn rate:** multiplied by efficiency. This stacks with
    the existing engine-health scaling in `ShipEngine.effective_max_speed`.
- Removed: `Ship.disabled`, `Ship.is_disabled()`,
  `CrewRules.DISABLE_CREW_FRACTION` and `disable_threshold_for`, plus every
  disabled branch in combat_scene and its tests.
- `DEPLOY_MIN_CREW_FRACTION` (0.3) and the deploy rules stay, with one
  change. When no ship meets the normal rule, the "at least one ship
  deploys" fallback picks the first match from this list (my call):
  1. The highest-crew armed ship with the deploy flag.
  2. The highest-crew armed ship regardless of the flag.
  3. The existing order: highest-crew flagged ship, then the flagship, then
     the highest-crew ship.
- The campaign-map rule stays: any ship at 0 crew means a 25% crawl.

## Battle end

- After setup, and whenever a hull or weapon mount is destroyed, check each
  side for active armed ships.
- The player side is checked first: if the player has none, Defeat.
  Otherwise, if the enemy has none, Victory. Both sides having none at once
  is therefore a Defeat. That case can only arise mid-battle from mutual
  destruction.
- Before combat starts: if neither side's deploy set contains an armed
  ship, Engage is disabled with the reason "Neither fleet can fight" (my
  call). Disengage still works.
- An unarmed player deploy set against an armed enemy is allowed. It is an
  immediate Defeat followed by escape rolls. The fallback above makes this
  rare.

## Escape rolls

- **Who rolls:** every surviving ship on the losing side. That means deployed
  ships still alive and every held-back comp.
- **Pursuer speed:** the highest effective top speed among the winner's
  surviving deployed ships.
- **Escaper speed:**
  - Deployed ship: its effective top speed at battle end, with crew
    efficiency and engine damage applied.
  - Held-back comp: computed from its comp (class base speed, or engine
    item, times crew efficiency times engine hp fraction).
- **Chance (my call):**
  `p = clamp(0.5 + ESCAPE_SPEED_WEIGHT * (escaper / pursuer - 1.0), ESCAPE_MIN, ESCAPE_MAX)`,
  with `ESCAPE_SPEED_WEIGHT = 1.0`, `ESCAPE_MIN = 0.1` and `ESCAPE_MAX = 0.9`.
  - Equal speed gives 50%.
  - A pursuer speed of 0 means every ship escapes.
- **Determinism:** the roll uses an RNG that tests can seed or inject. No
  global `randf()` in the decision path.
- **Escaped ships:** they stay with their own fleet, with their current
  hull, crew and damage.
  - Enemy escapers: the enemy fleet stays on the map with only those ships.
    No reputation loss, because it wasn't destroyed (my call).
  - Player escapers: they stay in the player fleet. If none escape and none
    were left, the player respawns as today.
- **Reputation:** the faction takes the existing reputation loss and fine
  once per player victory in which any of its ships were destroyed or
  captured, even if others escaped. This follows the user's earlier "fines
  are per kill"; once per battle is my call.
- **Cargo on a partial escape** (user): the defeated fleet's cargo splits by
  cargo capacity.
  - The captured ships' share, `captured capacity / total fleet capacity` of
    each commodity and of `part_inventory`, goes to the loot window.
  - The rest stays with the escaping fleet.
  - Parts are allocated whole, rounded down, to the loot share (my call).
  - If no ships escape, all the cargo goes to the loot window, as today.
- **Fleets left together after a battle** do not re-engage automatically.
  Arrival still requires the player to click the fleet
  (`campaign_scene._on_player_area_entered` only acts on `_travel_target`).
  No cooldown is added.
- **Player left with only unarmed ships** after a partial escape: allowed.
  The player keeps them and can trade. Respawn happens only when the fleet
  has no ships (my call).

## Capture

- **Enemy captured by the player:** each caught comp, with its current
  crew, goes to the loot window as a captured-ship offer.
  - Kept ships are appended to the player fleet.
  - Unkept ships are scuttled, and their crew go into the slider pool.
  - The slider pool is the total crew aboard all captured ships. Crew on a
    kept ship stay on it by default. The slider shows the movable crew plus
    the kept ships' crew, capped by free berths.
- **Player ships captured by an NPC:** caught comps are appended to the
  winning NPC fleet.
  - If that would exceed `FleetAllocationPolicy.MAX_SHIPS_PER_FLEET`, the
    extras are scuttled (my call).
  - Captured ships keep their crew, then the NPC fleet auto-balances.
  - Captured flagship: the flagship flag is cleared on the comp.
    `ensure_flagship()` picks a new flagship for the player if the player
    still has ships.

## Loot window

- **Sections:** cargo (unchanged), Captured Ships, Crew.
- **Captured Ships:** one row per ship with class, hull %, crew/complement
  and a Keep checkbox. Ticking it:
  - adds the ship's complement to the free-berth calculation;
  - auto-sets the crew slider to its new max.
- **Crew pool** (my call, resolving the builder check): the sum of the crew
  aboard all captured ships, kept or not.
- **Crew slider:** from 0 to
  `min(pool, free_berths(player fleet) + sum of complements of kept ships)`.
  - Kept ships count at their full complement, because they join empty.
  - Its label shows the count and the added wages per tick.
- **Take:** a single confirm (my call; today's per-row Take buttons stay for
  cargo).
  - Appends each kept ship with crew 0.
  - Then distributes the slider's crew with `CrewRules.add_crew`, which fills
    the lowest crew fraction first, so new ships fill first.
  - Untaken crew and unkept ships are lost.
- **Closing without Take:** nothing is taken (my call). The panel's Close
  button is labelled "Leave".
- **Opening condition:** the window opens when there is cargo, a captured
  ship or captured crew.

## Whole credits

- `CampaignState.credits: int`. Every API that charges or pays credits takes
  or returns int:
  - buy and sell (`BaseEconomy.price_for` returns `int`, rounded to
    nearest, minimum 1)
  - sell price (my call), derived from the rounded buy price:
    `clampi(floori(buy * SELL_SPREAD), 1, maxi(1, buy - 1))`. Selling never
    meets or beats the buy price when buy >= 2, so there's no buy-resell
    profit.
  - part buy and sell (`PartRarity` prices)
  - fines (`FINE_PER_KILL`)
  - `REPAIR_COST`
  - `CREW_HIRE_COST`
  - `ShipType.SHIP_PRICE`
  - the respawn penalty (`floori`)
- **Wages:** `wage_bill = floori(payable_crew / 10) * WAGE_PER_10_CREW`,
  with `WAGE_PER_10_CREW = 1`.
- **Desertion:** when credits are short, groups of 10 that can't be paid
  are unpaid. `DESERTION_RATE` applies to the crew in those groups, and the
  existing minimum of 1 deserter per unpaid tick stays. Credits never go
  negative.
- **Display:** every credit label uses `%d` of an int. No float formatting
  of credits anywhere.

## Constraints

- Godot 4 / GDScript and the existing headless test runner.
- Crew reads keep using `CrewRules.crew_of` (missing-key defaults).
- Panels follow the existing `Layout` VBox and ScrollContainer convention,
  checked by `tests/ui_layout_check.gd`.
- Existing tests that assert disabled, stalemate, the 20% capture or float
  credits are updated or replaced, not deleted without a replacement that
  covers the new behavior.

## Left to the builder

- Where efficiency is stored on `Ship`: a cached value refreshed in the
  crew-change handler, or computed on read.
- How the escape RNG is injected.
- The loot window's internal layout.
- Build order.
