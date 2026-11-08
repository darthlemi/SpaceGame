# Systems and Stations menu - design

## Intent
The player has no way to review what they've seen across the galaxy without flying back to each
station. This adds a menu that remembers what the player saw at every station they've docked at,
and shows it in a browsable list: systems on the left, one station's remembered detail on the right.
Mockup (final, signed off): `docs\superpowers\mockups\station-menu-final-v24.html`.

## Goals
- Left: scrollable tree of visited systems, expandable to their stations.
- Right: detail panel for the selected station — header, three stat boxes, two sortable
  PRODUCES/CONSUMES tables.
- Data shown is a snapshot taken on docking ("as last seen"), not live.
- New button on the campaign HUD opens the menu.

## Non-goals
- No live/current data — the whole point is "as you last saw it."
- No systems that haven't been visited (discovered-only jump-map systems do not appear).
- No save-game concerns beyond flagging that this snapshot state needs to survive whenever saving
  is eventually built (it doesn't exist yet for anything else either).
- No new station services (black-market, bounties, etc.) — that's a separate open idea.
- No Security stat (doesn't exist in the campaign scripts).

## Decisions (made with the user)
- **Which systems appear:** visited only — a system is listed once the player has docked at one of
  its stations. Not shown: discovered-but-unvisited systems (visible on the jump map, not here).
- **Entry point:** a new button on the campaign HUD, always available, not nested in the jump map.
- **Snapshot vs. live:** build a real per-station snapshot now. This is the data the whole menu
  reads; nothing in it is computed live from the current economy.
- **Day counter:** add a real elapsed-days counter to `CampaignState`, derived from the existing
  tick timer, and stamp it into each station snapshot so the header can show
  `Visited: Day 42 (13 days ago)` for real.
- **Layout:** one screen, 16:9 reference stage (1280x720) scaled to fit the window, per the mockup.
  - Left: scrollable tree, scrollbar on the left edge. Systems show a small `[+]`/`[-]` toggle,
    name, and "Stations - x" under it. Expanded systems list their stations with a faction-coloured
    round dot. Long names wrap.
  - Right: scrollable detail panel for the selected station:
    - header: station name, "System: <name>", faction badge (hugs its text, no stretch), "Visited:
      Day N (M days ago)";
    - three one-line stat boxes spanning the row: Population, Wealth, Reputation;
    - Population is a signed number: green `+` growing, red `-` declining, plain white and no sign
      when stable;
    - market split into two tables, PRODUCES and CONSUMES, fixed-width columns (Commodity 34%,
      Stock, Buy, Sell 22% each), every header and cell centred;
    - Stock is signed and coloured against `Commodity.TARGET_STOCK`: green `+n` over target, red
      `-n` short of it;
    - no status tags (no Surplus/Deficit words), no Role column.
  - Sorting: click a column header to sort that table only, independent of the other table. First
    click ascending (up arrow), second click descending (down arrow); the arrow sits outside the
    header text so it never shifts the centring. No sort applied when the panel first opens.

## My calls (the user hasn't confirmed these)
- **Snapshot trigger:** taken in the same place `record_visit` already fires for the per-system jump
  map snapshot (`CampaignState.record_visit`, `campaign_state.gd:210`) — i.e. on arrival in a system,
  snapshot every station in that system the player can currently see data for. Simpler than trying to
  hook every possible docking path, and keeps one snapshot event per system visit rather than one per
  station interaction.
- **Day counter semantics:** 1 game-day = a fixed number of economy ticks (reuse
  `ECONOMY_TICK_INTERVAL` scaling; exact day length is a builder constant, not user-specified).
  Starts at Day 0 at campaign start. Pure elapsed-time counter, not tied to any other mechanic.
- **Sort state does not persist** between menu closes/reopens or between stations — matches "No sort
  on open" already in the mockup notes; re-selecting a station or reopening the menu always starts
  unsorted.
- **HUD button placement:** wherever the existing HUD has room near other panel-opening buttons
  (e.g. next to the jump map button) — left to the builder, no mockup for the HUD chrome itself.
- **Reputation:** `BaseOverviewPanel` already shows a reputation number when docked; the snapshot
  copies that same value verbatim. No new reputation logic.
- **Wealth:** snapshot `BaseEconomy.wealth_level()` verbatim, same as the existing overview panel.

## Constraints
- Godot 4.7, GDScript, tabs, CRLF in the working tree (patch `.gd` files with Python `newline=''`,
  not `sed -i`).
- Implemented directly on `main`; do not push.
- UI follows `assets\ui\theme.tres`; any panel drawn over the play area uses `MOUSE_FILTER_STOP`.
- No save games exist yet — snapshot and day-counter state live only in the running `CampaignState`,
  same as everything else today.

## Left to the builder
- Scene/node structure for the tree and detail panel; whether the tree reuses any existing list
  control or is built from scratch.
- Exact snapshot data structure on `CampaignState` (e.g. `station_snapshots: Dictionary[station_id]
  -> Dictionary`) and the day-counter field name/placement.
- Scrollbar-on-the-left implementation (Godot's default is right-aligned).
- Test layout (mirror `tests\` structure, register in `run_tests.gd`).

## Verification
- Unit test: docking/visiting a system populates a snapshot per station with the right fields
  (stock sign vs. target, population sign vs. trend, day number).
- Unit test: day counter advances correctly against known tick counts, survives pause/speed changes
  (reuses whatever `tick_warps`/economy tick already does for pause-awareness).
- Unit test: sort toggles ascending/descending per table independently; selecting a different
  station resets sort state.
- Manual: open the menu after visiting 2-3 systems, confirm tree/detail panel match the mockup
  layout, confirm revisiting a station updates its snapshot (day count and days-ago refresh).
- Full suite clean except the known long-run-sim flake; 0 `SCRIPT ERROR`.

## Builder-check answers (settled from the project or my calls)
- **Snapshot source fields:** `BaseEconomy.stock`, `price_for`, `sell_price_for`, `net_commodities()`
  (splits a station's goods into PRODUCES/CONSUMES by sign), `population`, `population_trend`,
  `wealth_level()`, plus whatever `BaseOverviewPanel` reads today for reputation. No new economy
  computation — this feature only captures and displays existing values at visit time.
- **Faction colour/badge:** reuse whatever `campaign_fleet_icon.gd` / the jump map already use for
  faction colouring, for visual consistency with the rest of the campaign UI.
- **Mockup alignment caveat carried over:** the HTML mockup rescales in-browser, so pixel alignment
  (toggle boxes, `+` centring) is only truly settled once built in Godot controls; SVG toggles were
  the scale-proof approach used in the mockup and should carry over.
