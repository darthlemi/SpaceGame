# Star Systems and Jumping - Design

Date: 2026-11-04. Status: awaiting user approval.

Decisions marked "(my call)" were made by Claude while writing this up. The
user hasn't explicitly confirmed them. Everything else is the user's decision.

## Intent

The campaign is one hand-placed map: a home base, one Dominion base, one
Freehold base and seven fleets. That's too small for the bigger fleets and
factions planned next. Rather than grow the map behind a camera, the game grows
by adding **systems**. Each system is a map the size of today's, and fleets
**jump** between connected systems, FTL-style.

What success looks like: you open the jump map, pick a neighbouring system,
sit through a tense 3-second charge-up while a pirate closes in, and arrive
somewhere new. That place has its own stations and traffic, and it is more
dangerous the farther you are from home. Meanwhile, the systems you left keep
living: traders haul, pirates raid next door, and patrols chase them.

This is sub-project 1 of the "bigger world" thread. Later sub-projects build on
it, in this order:
1. Systems and jumping (this document).
2. More factions: 4-5 factions with a hostile one, a peacekeeper and neutrals.
3. AI economy and bigger fleets: treasuries, discounted costs, and 4-10 ship
   fleets.
4. A mysterious end-game faction: jump gates, cheaper or longer jumps, and
   better ships.
5. Big battles: 10 ships per side.

## Goals

### Galaxy
- One fixed galaxy, the same every game, with 20-30 systems branching out
  from the player's starting system. It is not random, because a random galaxy
  is hard to balance.
- Each system has the same size and fixed view as today's campaign map. There
  is no camera and no pan or zoom.
- Each system holds a couple of bases. Some systems are all pirate, some are
  all neutral, and some are mixed. Dominion and Freehold each own several bases
  spread across their own territory.
- Danger rises with distance from the starting system. Far systems are only
  more dangerous; there is no better pay or loot for going far in this
  sub-project.
- Life carries on in every system, not only the one the player is in.

### Jumping
- A **Jump** button next to **Fleet** in the fleet status bar, and the **J**
  key, both open the jump map.
- The jump map is a full-screen galaxy map (mockup A). The game pauses behind
  it while it is open.
- You pick a destination system on the map and press its Jump button.
- Jumping starts a **3-second warp countdown**. During it, the fleet can't
  move. A hostile fleet can still engage it, and that cancels the warp.
- **Fuel cost** comes from fuel consumption: the sum of each ship's
  `ShipType` `fuel_burn`, times a tuning factor. Bigger and heavier fleets pay
  more. A typical jump should take a large share of the tank.
- If you can't afford the jump, its Jump button is inactive, but you can still
  browse the map.
- **Arrival:** at a random point within a small radius of the edge point that
  faces the system you came from.
- **Discovery:** the map shows every system you have visited, plus the systems
  connected to them. It remembers everything it has shown.

### AI
- Fleets of every faction jump between systems to trade, raid, hunt and keep
  the peace.
- AI fleets follow the same jump rules as the player: the countdown, getting
  caught during it, per-ship fuel cost, and the arrival rule. This follows the
  earlier decision that the player and the AI play by the same rules.
- For now, every system is simulated in full. Abstract off-screen simulation
  is flagged as possible future work (see Constraints).

## Non-goals

- A campaign camera, pan or zoom, or bigger maps for individual systems.
- A random or procedurally generated galaxy.
- New factions, faction roles (hostile or peacekeeper), or the mysterious
  faction. Those are sub-projects 2 and 4. This sub-project uses today's
  factions: Dominion, Freehold, pirates, neutral traders and neutral patrols.
- AI treasuries, paid fleet growth, or fleets bigger than today's 3-ship cap.
  Those are sub-project 3.
- Jump gates and other ways to make jumps cheaper or longer.
- Better loot, shop stock or trade prices in far systems. Pricing comes later.
- New or different services at neutral or pirate stations. The user wants to
  revisit this later, and it is logged in the carry-forward.
- Attacking or capturing bases.
- Saving and loading. None exists today.
- Abstract off-screen simulation.
- AI fleets following the player through a jump (my call).

## Anti-goals (would be a failure even if it works)

- **A dead galaxy.** If you can jump into systems where nothing is moving, or
  return to find nothing happened while you were away, the feature has failed
  its purpose.
- **A free escape.** A jump you can trigger when an enemy is already on top
  of you, with no risk, defeats the countdown. The warp must be catchable.
- **Map clutter.** 20-30 systems on one screen must stay readable: names,
  links and "you are here" at a glance.
- **Hard-coded faction branches multiplying.** Today
  `DOMINION or FREEHOLD` checks are scattered through `campaign_scene.gd` and
  `campaign_state.gd`. Multi-base, multi-system logic must not add more of
  them. Sub-project 2 will need to add factions.
- **Combat or docking regressions.** Engaging, docking, trading, refitting,
  respawning and returning from combat must work exactly as today, inside
  whichever system you are in.

## Constraints

- Godot 4, GDScript. Tests run via `tests\run_tests.gd`; see the carry-forward
  for how to run Godot and its gotchas.
- The viewport is the project default 1152x648 (there are no display settings
  in `project.godot`). `CampaignFleetIcon.MAP_MIN`/`MAP_MAX` currently clamp to
  4000x2400, larger than what is shown. "Keep maps like they are" means a
  system is the visible area. Clamp fleets to the viewport, with a margin for
  HUD (my call).
- **Physics isolation:** fleets and bases are `Area2D`s, and engagement,
  skirmishes and docking all trigger on overlap. Systems simulated at the same
  time must never overlap one another's physics. One simple way is to place
  each system at its own large world offset and show only the current one. The
  builder picks the mechanism, but cross-system overlaps must be impossible.
- **Only the current system is interactive.** Clicks, the engage prompt,
  docking and the HUD only ever involve the player's current system.
- **The campaign scene is rebuilt after every battle**
  (`change_scene_to_file` into combat and back), from `CampaignState` data.
  All galaxy state must therefore live in data, not only in nodes. That covers
  which system each fleet is in, its warp countdown, its jump plan, its trade
  route, discovery, and base economies. This absorbs the parked backlog item
  "trader route reset after combat": route state must persist on
  `CampaignFleet`, not only on `CampaignFleetIcon._route_state`.
- **Performance:** every system runs all the time. The builder must measure
  frame time with the full galaxy populated, at 1x and at 5x speed. If it
  doesn't hold a smooth frame rate, stop and report rather than quietly
  building off-screen simulation. Off-screen simulation is a known possible
  follow-up.
- Existing conventions: credits are `int`; HUD panels drawn over the play area
  use `MOUSE_FILTER_STOP` backgrounds; UI uses the holo theme from
  `2026-11-04-holo-ui-chrome-design.md`.

## How it works

### Galaxy data (my call on format and layout)
- The whole galaxy lives in one hand-editable data definition. It lists:
  - each system's id, display name, jump-map position and danger tier;
  - the links between systems;
  - each system's bases: owner, in-system position, station art, economy
    roles and starting stock;
  - each base's starting fleets.
  The builder picks the file format by matching how the project already stores
  data. Today, campaign data is GDScript literals in `campaign_scene.gd`
  `_bootstrap_default_campaign`.
- I draft the first layout. The user adjusts it afterwards, so the data must
  be easy to read and edit. Draft shape: about 24 systems.
  - The start system holds the player's HomeBase and one neutral station.
  - The Freehold cluster is on one side of the start, and the Dominion cluster
    on the other, 3-5 systems each.
  - Neutral and mixed systems sit between and around them.
  - Pure pirate systems sit at the fringes and in a few pockets closer in.
  - Each system has 1-3 bases.
- **Danger tier** is the jump count from the start, capped at 5, unless the
  data overrides it. The data can override any system's tier.
- Every base is its own data object: owner, system, position, economy,
  catalogue and station art. `PowerFaction` keeps reputation, fines and
  hostility, but owns a list of bases instead of one `base_position` and one
  `economy`.
- **Station art:** each base uses one of the 16 renders in
  `assets\sprites\stations\`. The data fixes the choice so a base always
  looks the same. Faction is shown with a coloured ring like the fleet icons,
  replacing `dominion_base.png` and `freehold_base.png` (my call).

### Bases
- **Faction bases:** today's behaviour, with each base running its own
  economy.
- **Neutral stations:** they work like faction bases: trade, shipyard, repair,
  crew hire, and their own economy. They offer `HOME_CATALOG` parts and charge
  no fines (my call).
- **Pirate bases:** dockable and tradeable like every other base, with their
  own economy, so they produce fuel and grow a crew pool. The danger is the
  pirate fleets around them, which stay hostile and may attack you on the way
  in or out. Pirate fleets spawn, refuel and regain crew there. Like neutral
  stations, they offer `HOME_CATALOG` parts and charge no fines (my call).
- **Every base is dockable and tradeable.** So every system has somewhere to
  refuel, if you can survive getting there.
- **HomeBase** stays in the start system. Respawn still sends the player
  there.
- **Economy ticks** run for every base in the galaxy.

### Danger tiers (my call on what a tier changes)
A fleet spawned or regrown at a base uses that base's system tier. The tier
changes:
- **Ship mix:** mostly corvettes at tier 1, more capitals by tier 4-5.
- **Loadout quality:** the randomized loadout (`Ship.randomize_loadout` /
  `_assign_random_loadout`) draws from better catalogue parts as the tier
  rises.
- **Crew:** fuller crews at higher tiers.

Fleet size stays capped at 3 ships (`FleetAllocationPolicy.MAX_SHIPS_PER_FLEET`).
Sub-project 3 will make the tier feed fleet size too.

### Player jump flow
1. Press **Jump** or **J** to open the full-screen jump map. The game pauses.
   Closing it with J, Esc or Close restores the previous pause state, the same
   way the Fleet panel does today.
2. Pick a discovered system. The info strip shows:
   - its name;
   - its owner mix, for example "Freehold, pirates seen";
   - its base count;
   - its danger tier (my call);
   - the jump cost against your current fuel.
3. The Jump button is active only when all of these hold:
   - the system is directly connected to yours;
   - you can afford the jump;
   - no warp is already charging;
   - the engage prompt and respawn screen aren't open.
   Jumps go only to directly connected systems; longer trips are several jumps
   (my call).
4. Pressing Jump closes the map, unpauses, and starts the 3-second countdown.
   Jumping while docked undocks first (my call). The countdown is in game time,
   so it pauses with the game and speeds up at 3x and 5x (my call).
   A ring and a 3-2-1 label show on the player icon. The player can't move. A
   Cancel Warp button is shown (my call).
5. If a hostile fleet touches the player during the countdown, the warp is
   cancelled and the normal engage prompt opens. A cancelled warp costs no
   fuel (my call). Fuel is spent only when the countdown completes.
   - **Caught rule (my call; the user hasn't answered this one):** today a
     hostile fleet touching the player does nothing unless the player clicked
     it (`_on_player_area_entered` only fires for `_travel_target`). During a
     countdown, contact forces the engage prompt. Disengage stays available,
     but a new warp can't start while any hostile fleet overlaps the player,
     so being caught isn't a free escape. Outside a countdown, behaviour is
     unchanged from today.
   - "Hostile to the player" means fleets running pirate behaviour: pirates,
     plus Dominion or Freehold fleets below `HOSTILE_REPUTATION_THRESHOLD`, as
     `_behavior_for_fleet` decides today (my call).
6. When the countdown completes, the fuel is spent. The player leaves the
   current system and appears in the destination: at a random point within a
   small radius of the edge point that faces the origin system. A short
   warp-in effect plays. The destination and its neighbours are marked
   discovered.

### Distress signal
- When you can't afford any connected jump, you can send a distress signal
  for fuel, paid in credits. If you have neither the fuel nor the money, you
  are stuck: fight until you die, or get supplies by winning battles. There
  is no free tow home.
- **My calls on the details:**
  - The button sits on the jump map's info strip. It is shown only when no
    connected jump is affordable and you aren't docked.
  - It buys exactly the fuel you're short for the cheapest connected jump, at
    a premium: a tunable multiple, say 3x, of the commodity's base fuel price.
    The cost is an `int` in credits.
  - Delivery is instant.
  - It is unavailable, with the reason shown, when you lack the credits or
    the cargo room for the fuel. Jettison already exists for freeing room.

### AI jumping (my call on the decision rules)
- **Same mechanics as the player:** the countdown with a visible ring, being
  catchable, the fuel cost and the arrival rule.
  - AI fleets that start a skirmish mid-countdown lose the warp.
  - Fleets warping in show the same warp-in effect.
- **NPC fuel (my call):** NPC fleets carry fuel cargo for jumps only. Moving
  inside a system stays free for them, as today. They refuel free of charge
  at a friendly or neutral base from that base's FUEL stock. If the stock is
  empty, they wait. Charging them for fuel comes in sub-project 3.
- **Routes:** multi-jump trips use the shortest path through the link graph.
- **By role:**
  - **Faction traders** haul between their faction's bases and neutral
    stations within a few jumps of home. They pick destinations by today's
    surplus and need logic (`run_npc_trade_for_fleet`), generalised from "home
    base vs. player's HomeBase" to any pair of bases.
  - **Neutral traders** (`TRADER`) haul between neutral stations.
  - **Patrols** (Dominion, Freehold and `NEUTRAL`) keep the peace in their
    faction's systems. They wander, and they jump to an adjacent owned system
    where pirates are present. That is the "hunt".
  - **Pirates** wander their system. They raid by jumping into an adjacent
    system, preferring ones with traders, and head home when damaged or low on
    crew.
  - **Hostile behaviour toward the player** stays as today, but only in the
    player's current system.
- **Fleet counts and respawn:**
  - The galaxy data gives each base a fleet quota by role. This covers every
    base: faction, neutral and pirate.
  - A destroyed fleet respawns at its base, free, after a tunable delay. Its
    ships and loadouts come from the base's tier.
  - Today only Dominion and Freehold ever regrow, and only through
    `_apply_fleet_allocation`. Pirate, `TRADER` and `NEUTRAL` fleets are never
    replaced. Without respawn, the galaxy dies out.
  - `FleetAllocationPolicy`'s grow logic for Dominion and Freehold runs per
    base, capped by that base's quota.
  - **Threat** for a base is measured in its own system plus adjacent systems,
    not galaxy-wide. Today `_threat_ratio` sums pirates everywhere, so it would
    read as huge threat for every base.
  - Paid growth and a real fleet budget come in sub-project 3.
- **HomeBase** stays a trade stop for faction traders, as today, so the home
  economy keeps getting supplied.

### Jump map UI (mockup A)
- A full-screen panel under the fleet status bar.
- **Systems** are nodes coloured by their dominant owner. Unknown connected
  systems show as dim "unknown" nodes with no details.
- **Links** are lines between systems. "You are here" is highlighted, and the
  selected system has a ring.
- **Info strip:** the system details and the Jump button described above.
  When the button is disabled, the strip says why: "Not connected", or "Not
  enough fuel (need X, have Y)".
- **Visited systems** show what you saw on your last visit, not live
  information (my call).
- **Readability:** the layout must stay readable at 1152x648 with about 30
  systems.

## Left to the builder

- The galaxy data format, and the mechanism that keeps systems physically
  isolated.
- How `CampaignScene` is split up, for example a per-system container node.
  Don't keep growing `campaign_scene.gd`.
- These tuning constants:
  - the jump fuel factor: start so the starter fleet's jump costs about
    one-third of `PLAYER_STARTING_FUEL`;
  - the arrival radius and edge margin;
  - how often AI fleets jump, and how long they wait between jumps;
  - the per-tier ship mix and loadout tables.
- The warp-in and countdown visuals, kept simple.
- The test strategy, which must cover:
  - jump affordability;
  - cancel on engagement;
  - fuel spent only on completion;
  - arrival placement;
  - discovery;
  - state surviving a combat scene round-trip;
  - AI fleets completing multi-jump trips;
  - the frame-time measurement.

## Open idea (logged, not in scope)

What makes neutral stations and pirate bases different to visit, for example
black-market parts, bounties or smuggling. The user wants to come back to
this.
