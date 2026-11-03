# Crew Mechanic - Design

Date: 2026-11-03. Status: awaiting user approval.

Decisions marked "(my call)" were made by Claude while writing this up. The
user hasn't explicitly confirmed them. Everything else is the user's decision.

## Intent

Crew today is a display-only number (`ShipType.BASE_STATS["crew"]`, summed by
`CampaignFleet.crew_total()`). This makes crew a real resource that the player
spends, loses and has to replace. Damage costs crew as well as hull, a fleet
that loses too many people can't fight well, and keeping crew costs money
every tick.

What success looks like: after a rough battle you have to decide between
spreading the survivors so every ship can fight, holding a ship back, and
scuttling it. Hiring at a base is a real stop. Running out of money hurts but
never soft-locks the game, and losing everything sends you back to your home
base instead of ending the game.

## Goals

- Crew lives on ships. Each ship holds 0..its class complement. The fleet's
  crew is the sum. There is no reserve or pool outside the ships.
- Ships lose crew as they take hull damage in combat.
- Under 30% crew, a ship can't be deployed, except that every fleet always
  deploys at least one ship.
- Crew too low mid-battle: the ship is disabled (no firing, no thrust) and
  drifts. A side whose remaining ships are all disabled loses.
- Any ship at 0 crew makes the whole fleet crawl at 25% speed on the map.
- A Fleet Management panel (mockup layout A, a row list): per ship, a flagship
  star, the label, a crew slider, the crew count, a Deploy checkbox and a
  Scuttle button. Below the rows are a Balance button, a Jettison button and
  a Hire strip when docked.
- A Jettison dialog with sliders for dumping chosen cargo, parts and crew.
- Hire crew at bases from a per-base hire pool that refills based on
  population. The player pays a one-time fee per head.
- Wages: the player pays per crew per economy tick. Unpaid crew desert until
  the wage bill fits what the player can pay.
- The flagship (picked by the player) never deserts below a floor.
- Enemy and NPC ships follow the same crew rules, and their crew never drops
  to 0.
- After a won battle, the player can take a small share of the defeated
  fleet's surviving crew.
- Losing the whole fleet respawns the player at HomeBase (no game over). The
  player either buys a ship or takes a free basic one with minimum crew.

## Non-goals

- Crew skill, experience, morale or individual crew members.
- Crew affecting anything except deployability, disabling and map speed.
- NPC wages or NPC desertion.
- Tying NPC fleet growth (`CampaignState._grow_fleet`) to the base hire pool.
  New NPC ships spawn fully crewed, as they do today.
- Hiring reducing base population. The hire pool is its own number.
- Buying ships at the Shipyard during normal play. Ship purchase exists only
  on the respawn screen (my call; flagged as a natural follow-up).

## Anti-goals (would be a failure even if it works)

- Any soft-lock: in combat (a battle that can never end), on the map (broke
  and unable to fight or move), or after a total loss.
- Crew spawning from nowhere. Every new crew member comes from a hire pool or
  a battle capture. The only exceptions are new NPC ships, the NPC crew floor,
  pirate regen and the free respawn ship's minimum crew.
- A crash on the hand-written compositions in
  `campaign_scene._bootstrap_default_campaign`, which lack most keys. This
  repeats the 2026-11-02 refit Critical bug. All crew reads must default
  safely.

## Data model

- Crew per ship: an int `"crew"` key in each `ship_compositions` dict. When
  the key is missing, the ship is treated as fully crewed (its class
  complement). `ShipType.new_composition()` sets it to the full complement.
- Complement: `ShipType.crew_for(kind)` (existing: corvette 12, freighter 6,
  capital 40).
- Thresholds are fractions of the complement, rounded up to whole crew:
  - `DEPLOY_MIN_CREW_FRACTION = 0.3` (user). Gives freighter 2, corvette 4,
    capital 12.
  - `DISABLE_CREW_FRACTION = 0.1` (my call; the user didn't give a number).
- `CampaignFleet.crew_total()` becomes the sum of actual crew. Add
  `crew_capacity()` (sum of complements).
- Deploy flag: per ship, persists between battles (my call), defaults to true.
- Flagship: the player fleet has exactly one while it has any ships. The
  default at campaign start is the largest class (capital), my call. If the
  flagship is destroyed or scuttled, the role passes to the largest
  remaining ship (my call; scuttling the flagship is blocked anyway). It must
  survive `combat_scene._collect_survivor_data`, which rebuilds every
  composition dict from scratch.

## Combat

- Who deploys: ships with the deploy flag set and crew >= the deploy
  minimum. If that selects none, the ship with the highest crew deploys
  anyway (user: "a fleet has to deploy at least 1 ship"). For the player,
  this is the highest-crew ship that has the deploy flag. If no ship has the
  flag, it's the flagship (my call). Enemy fleets use the same rule, with
  every flag set.
- Crew loss: proportional to the fraction of current hull lost, so crew
  reaches 0 only when hull does (my call). An under-crewed ship gets disabled
  sooner, which is intended.
- NPC crew floor: an NPC ship's crew never drops below `NPC_CREW_FLOOR`
  (user: enemies should "never run out of crew all the way"). This applies
  in combat, in skirmishes and on the map. Combat crew loss on NPC ships
  clamps at the floor. Because the floor is below the disable threshold, NPC
  ships can still be disabled.
- Disabled: crew < `DISABLE_CREW_FRACTION` x complement. The ship stops
  firing and thrusting and drifts. It is still targetable and destructible.
- End of battle (user, answer 1): a side loses when every one of its deployed
  ships is destroyed or disabled. This needs a "disabled" signal feeding the
  existing end check in `combat_scene._on_ship_destroyed`, which today counts
  only destroyed ships. If both sides reach that state in the same frame, the
  player loses (my call; it can't stall).
- Results:
  - Winner: surviving ships (disabled included) keep the crew they have
    left. Destroyed ships lose all crew.
  - Player wins: the enemy fleet is defeated entirely. Its disabled and
    held-back ships are lost with it (my call). Reputation loss, fine, loot,
    the crew offer and removing the fleet from the map all happen.
    `resolve_engagement` therefore needs a victory path that doesn't depend
    on `CampaignFleet.is_destroyed()`.
  - Player loses: deployed ships that were destroyed or disabled are lost.
    Held-back ships return unchanged and the fleet continues. If nothing is
    left, the player respawns (see Respawn).
  - The survivor-collection code must merge held-back ships back. It maps by
    array index today, which breaks once spawned ships are a subset.

## On the campaign map

- Speed: if any ship in a fleet has 0 crew, the fleet moves at
  `EMPTY_FUEL_SPEED_FACTOR` (0.25) of its speed. This does not stack with the
  empty-fuel penalty (my call). It applies to all fleets, but NPC fleets
  never hit 0 because of the floor.
- Status bar: the crew label shows `crew / capacity` and the wage bill per
  tick. A "Fleet" button opens Fleet Management.

## Fleet Management panel

The layout is mockup A: a row list in a ScrollContainer, following the
existing `Layout` VBox and ScrollContainer convention, covered by
`tests/ui_layout_check.gd`. It can be opened on the map and while docked.
Opening it pauses the game, matching the other panels (my call).

Per row:
- Flagship star: click to make this ship the flagship.
- Ship label: class + index, since ships have no names.
- Crew slider: 0..complement, with a marker at the deploy minimum.
- `crew/complement`.
- Deploy checkbox: shows "Too few" under the minimum.
- Scuttle button: disabled on the flagship and on the last ship.

Behavior:
- Slider: the fleet total never changes here. Raising a ship takes crew from
  the ship with the highest crew % first, and lowering gives to the lowest
  crew % first (my call).
- Balance: every ship goes to (as near as integers allow) the same crew % of
  its complement. Remainders go to the flagship, then the largest class.
- Header: `Crew X / Y`, `Wages Z cr/tick`, `Credits N`.
- Hire strip (docked only): pool available, price per head, a -/+ count and
  a Hire button with the total cost. The count is capped by the pool, free
  berths and credits. Hired crew fill the ship with the lowest crew % first
  (my call).
- Scuttle: removes the ship permanently, with no refund (my call). Its crew
  move into free berths on other ships, and any who don't fit are lost. A
  confirmation shows what will be lost: crew that don't fit, and cargo/parts
  above the new capacity (user: warn that excess is lost). If cargo would
  overflow, the confirm step opens Jettison with the minimum to dump
  pre-set, so the player chooses what goes (my call). Scuttle completes only
  once cargo fits.

## Jettison dialog

The user asked for this ("jettison on cargo and crew ... use sliders like the
fleet management").
- One slider row per held commodity (0..amount held), one row per spare part
  in `part_inventory` (a checkbox is fine, since parts are single items), and
  one crew slider per ship (0..that ship's crew).
- Jettison confirms and removes everything selected. Dumped items are gone
  and are not dropped on the map (my call).
- Crew jettisoned from the flagship can't take it below the flagship floor
  (my call, keeps the anti-soft-lock guarantee).

## Hiring and base hire pools

- `BaseEconomy` gains a hire pool (float, shown floored). Each economy tick
  it refills by `population * CREW_POOL_REGEN_RATE`, capped at
  `population * CREW_POOL_CAP_FRACTION`. All bases have one.
- Flat `CREW_HIRE_COST` per head (my call).
- Hiring is available at any base the player can dock at.

## Wages and desertion (player only)

- Each economy tick, the player pays `WAGE_PER_CREW` x payable crew. Payable
  crew is total crew minus the flagship floor. Floor crew are wage-exempt (my
  call, so the player can't spiral into debt).
- If the player can't afford the full bill, they pay for as many crew as
  credits allow, and `DESERTION_RATE` of the unpaid crew (at least 1) desert.
  Credits never go negative.
- Desertion comes from the non-flagship ship with the lowest crew % first
  (my call). The flagship only loses crew down to its floor.
- Flagship floor: the deploy minimum of its complement (my call).

## NPC rules

- The same thresholds apply in player battles, plus the NPC crew floor.
- After any battle or skirmish, NPC fleets auto-balance crew across their
  ships.
- NPC-vs-NPC skirmishes (`CampaignState._resolve_skirmish`): the winner loses
  crew in proportion to `winner_damage_fraction`, clamped at the floor, then
  auto-balances. The loser is removed, as today.
- Dominion and Freehold fleets draw from their faction base's hire pool each
  economy tick to fill empty berths. There is no proximity check (my call).
- Each pirate fleet regains `PIRATE_CREW_REGEN` crew per economy tick, up to
  capacity.

## Crew from battles

- After a player victory, the player is offered `CAPTURED_CREW_FRACTION` x
  the crew aboard the enemy's disabled and held-back ships at battle end.
  Destroyed ships have 0 crew by the crew-loss rule. Disabling enemies
  instead of destroying them pays off, which is intended.
- Offered in the existing LootPanel next to cargo, capped by free berths.
  LootPanel opens today only when `cargo_total() > 0`, and must also open
  when there is crew to capture.

## Respawn (replaces game over on a total loss)

The user decided this.
- Trigger: the player fleet has no ships left after a battle (today this
  goes to `scenes/ui/game_over.tscn`).
- Kept: reputation and fines.
- Lost: all cargo, spare parts and crew (user: "everything in cargo/crew
  should be lost"; parts are part of cargo capacity). Credits are reduced by
  `RESPAWN_CREDIT_PENALTY` (user: amount TBD).
- The player appears docked at HomeBase on a respawn screen with two
  choices:
  - Buy a ship: any class at `SHIP_PRICE[kind]`, if affordable after the
    penalty. It arrives with the deploy minimum of crew (my call, matching
    the free ship). The rest are hired normally.
  - Take a free basic ship: a corvette (my call) with the deploy minimum of
    crew.
- The new ship is the flagship. Fuel is 0, since cargo was lost, so the
  fleet crawls until the player buys fuel (my call: respects "everything
  lost"; a small free fuel stipend is an easy change if crawling out of
  HomeBase feels bad).
- Whether `game_over.tscn` is kept for anything else is the builder's call.

## Placeholder numbers (all tuning guesses)

| Constant | Value | Note |
|---|---|---|
| `CAPTURED_CREW_FRACTION` | 0.2 | user: "should be lower" than hiring |
| `CREW_HIRE_COST` | 40 cr | |
| `CREW_POOL_CAP_FRACTION` | 0.05 | of population |
| `CREW_POOL_REGEN_RATE` | 0.005 | of population per tick |
| `DEPLOY_MIN_CREW_FRACTION` | 0.3 | user |
| `DESERTION_RATE` | 0.2 | of unpaid crew per tick |
| `DISABLE_CREW_FRACTION` | 0.1 | |
| `NPC_CREW_FLOOR` | 1 | per ship |
| `PIRATE_CREW_REGEN` | 1 | per fleet per tick |
| `RESPAWN_CREDIT_PENALTY` | 0.25 | fraction of credits lost; user: TBD |
| `SHIP_PRICE` | corvette 400, freighter 500, capital 2000 | |
| `WAGE_PER_CREW` | 0.1 cr | per tick; starting fleet (58 crew) about 70 cr/min at 1x |

## Constraints

- Godot 4 / GDScript, existing headless test harness (`tests/run_tests.gd`).
- New `class_name`s need the `--headless --editor --quit` warm pass.
- Assigning literals to typed arrays through the untyped autoload: use
  `.assign()`.
- UI panels follow the `Layout` VBox and ScrollContainer convention and are
  checked by `tests/ui_layout_check.gd`.

## Left to the builder

- Where flagship and deploy state are stored.
- How the disabled state is represented on `Ship`.
- Where crew loss hooks in, as long as every hull-damage path is covered
  (debug `KillAll` included).
- Slider widget choice, and the layout of Jettison and the respawn screen.
- Build order. Suggested stages: (1) data + combat rules, (2) Fleet
  Management + hire + wages, (3) Scuttle/Jettison, (4) respawn, (5) NPC
  refill/regen.
