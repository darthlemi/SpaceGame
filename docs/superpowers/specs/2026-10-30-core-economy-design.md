# Core Economy — Design Spec

## Purpose

Milestone 4a (split from "Economy & trading" in the roadmap). Gives map
bases a production/consumption economy that drives local commodity prices,
and lets the player haul cargo between bases to buy low / sell high.
Autonomous NPC trade-route hauling is deliberately deferred to a follow-up
milestone ("Trade Routes") once this base economy is proven.

## Commodities

Six commodities, two tiers:

- Raw: `ORE`, `FOOD`, `FUEL`
- Manufactured: `HULL_PARTS` (from Ore), `WEAPONS` (from Ore + Fuel),
  `LUXURY_GOODS` (from Food)

Only `ORE`, `FOOD`, `FUEL`, `WEAPONS` are wired into an actual economy role
this milestone (see below). `HULL_PARTS` and `LUXURY_GOODS` exist in the
enum and have a base price for completeness/future use but no base
produces or consumes them yet — avoids building roles nobody uses.

## Data Model

### `Commodity` (enum, likely on a new `scripts/campaign/economy.gd` or similar)

```
enum Commodity { ORE, FOOD, FUEL, HULL_PARTS, WEAPONS, LUXURY_GOODS }
```

Each commodity has a fixed `base_price` (a const dictionary/lookup).

### `EconomyRole` (Resource)

```
enum RoleType { MINING, AGRICULTURE, INDUSTRIAL, POPULATION, TRADE_HUB }
@export var role_type: RoleType
@export var produces: Dictionary  # Commodity -> float, amount per tick
@export var consumes: Dictionary  # Commodity -> float, amount per tick
```

Fixed catalog of roles used this milestone:

| Role | Produces | Consumes |
|---|---|---|
| MINING | Ore | — |
| AGRICULTURE | Food | — |
| INDUSTRIAL | Weapons | Ore, Fuel |
| POPULATION | — | Food |
| TRADE_HUB | — | — |

### `BaseEconomy` (Resource), held by `HomeBase` and `FactionBase`

```
@export var slots: Array[EconomyRole] = []
@export var max_slots: int = 2       # cap raises to 3-4 in a later milestone
var stock: Dictionary = {}           # Commodity -> float
var deficit_streaks: Dictionary = {} # slot index (int) -> int, one streak per slot
```

Starting assignments (bootstrap, same place `CampaignScene._bootstrap_default_campaign`
currently sets up factions):

- **HomeBase**: `slots = [TRADE_HUB]`. Never decays (no consumption, so no
  deficit possible). Always has a market; starting stock for every
  commodity at a comfortable baseline so the player always has somewhere
  to sell.
- **Dominion**: `slots = [INDUSTRIAL, POPULATION]`. Imports Ore/Fuel/Food,
  exports Weapons.
- **Freehold**: `slots = [MINING, AGRICULTURE]`. Exports Ore and Food, no
  manufacturing.

### Currency and cargo

- `CampaignState.credits: float`, starts at `500.0`.
- `CampaignFleet.cargo: Dictionary` (Commodity -> float).
- `const CARGO_CAPACITY_PER_SHIP := 20.0` on `CampaignFleet`;
  `cargo_capacity() -> float` returns `ship_compositions.size() * CARGO_CAPACITY_PER_SHIP`.
  Buying is capped so total cargo never exceeds capacity.

## Simulation Tick

`CampaignState` runs an economy tick on a fixed real-time interval
(`ECONOMY_TICK_INTERVAL := 5.0` seconds — a lightweight stand-in for a
"day", independent of the physics-delta skirmish ticking that already
exists). Each tick, per base:

1. For each slot, add `produces` amounts to `stock`.
2. For each slot (identified by its index in `slots`), attempt to
   subtract `consumes` amounts from `stock`.
   - If `stock[commodity] < consumes[commodity]` for any one of that
     slot's inputs, every one of that slot's inputs is drawn down to 0
     (deficit) and that slot's deficit streak (`deficit_streaks[slot_index]`)
     increments by 1.
   - If all of that slot's inputs were fully available, its streak
     resets to 0.
3. If any slot's deficit streak reaches `DEFICIT_STREAK_THRESHOLD := 5`,
   the base's lowest-priority slot (last in `slots`) is removed — the
   base permanently shrinks by one economy slot — and all streaks reset
   to 0. (Recovery/regrowth is out of scope; a future milestone can add
   it.)
4. `TRADE_HUB` and any base with zero slots left are skipped (nothing to
   produce/consume).

## Pricing

Each commodity at each base has a price derived from that base's stock
via fixed tiered bands, relative to a per-commodity `target_stock`
baseline:

| Band | Stock vs. target | Multiplier |
|---|---|---|
| Critical | < 20% | 1.6x |
| Low | 20-60% | 1.3x |
| Normal | 60-140% | 1.0x |
| High | 140-180% | 0.8x |
| Surplus | > 180% | 0.6x |

`buy_price = base_price * multiplier`. `sell_price = buy_price * 0.8`
(fixed spread so buying then immediately selling back always loses
money). The same band table is reused for every commodity — only
`target_stock` varies per commodity/base.

## Player Trading

- Docking at `HomeBase` or a `FactionBase` auto-opens a new `TradePanel`
  Control (mirrors the structure of the existing `EngagePrompt`: hidden by
  default, shown via a signal from the base's `area_entered`, hidden again
  on undock or a Close button).
- `TradePanel` lists the docked base's commodities with current stock, buy
  price, sell price, and Buy/Sell buttons (fixed quantity per click, e.g.
  1 unit — matches the granularity of existing UI interactions; no
  quantity slider this milestone).
- **Buy**: requires `credits >= buy_price` and `fleet.cargo total + 1 <=
  cargo_capacity()`; on success, `credits -= buy_price`,
  `base.stock[commodity] -= 1`, `fleet.cargo[commodity] += 1`.
- **Sell**: requires `fleet.cargo[commodity] >= 1`; on success,
  `credits += sell_price`, `base.stock[commodity] += 1`,
  `fleet.cargo[commodity] -= 1`.
- Buy/Sell buttons disable themselves when the corresponding condition
  isn't met (not enough credits/cargo/capacity/stock).

## Testing

New GUT-style tests under `tests/`, following existing patterns
(`test_campaign_state.gd` etc.):

- `test_economy_tick.gd`: production adds to stock, consumption subtracts,
  partial-stock consumption deficits correctly, deficit streak increments
  and resets, slot removal fires after threshold streaks.
- `test_economy_pricing.gd`: each stock-ratio band maps to the correct
  price multiplier, sell price is 80% of buy price.
- `test_campaign_fleet_cargo.gd`: `cargo_capacity()` scales with ship
  count, buy is rejected/capped at capacity, sell is rejected with
  insufficient cargo.
- `test_campaign_state_credits.gd`: buy rejected without sufficient
  credits, credits never go negative, sell increases credits correctly.

## Out of Scope (this milestone)

- NPC trader fleets hauling real cargo ("Trade Routes" follow-up
  milestone).
- Base slot *growth* / recovery after shrinking.
- More than 2 starting slots per base, or raising `max_slots` above 2.
- `HULL_PARTS` / `LUXURY_GOODS` production roles.
- Quantity sliders / bulk buy-sell in the UI.
- Per-ship-class cargo capacity variation (flat per-ship for now; refit
  milestone can differentiate).
