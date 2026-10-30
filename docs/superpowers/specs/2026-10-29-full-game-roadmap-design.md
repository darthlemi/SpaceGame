# Full Game Roadmap — Design Spec

## Vision

(Unchanged from the original combat-core spec.) A Starsector-inspired
tactical space game built in Godot: real-time ship combat layered under a
persistent campaign map with factions, territory, and ship customization.
The signature hook is a **rift system**: large battles have a chance to
tear open rifts — anomalies tied to dormant precursor tech — offering a
tiered, decaying risk/reward payoff to players who investigate.

## Purpose of This Document

This is a **roadmap, not a spec**. It lists the game's major systems in
build order with a one-line description and the dependency reasoning
behind the ordering. It does not design any system in detail — each
milestone gets its own brainstorming → spec → plan cycle when it's picked
up.

## Milestones

1. **Combat core** — ✅ Done. Real-time ship-to-ship combat: Hull/Shield/
   Engine/WeaponMounts composition, pluggable weapon behaviors, a unified
   `Order` interface for player (direct-pilot or RTS) and AI control,
   scaled from a 1v1 duel to N-vs-M fleet battles with formations.

2. **Campaign map** — Strategic layer: map nodes, fleet travel between
   them, time progression, persistence of fleet/ship state between
   battles. This is the skeleton everything else hangs off of; territory,
   markets, and missions all need a place to exist before they can be
   designed.

3. **Factions & territory** — Ownership of map nodes, reputation with the
   player, basic AI faction behavior (expansion, conflict with rivals).
   Depends on the campaign map existing.

4. **Economy & trading** — Markets, commodities, prices, trade routes
   anchored to map nodes. Depends on the campaign map; feeds ship refit
   (buying parts) and the rift system (a sink/source for rare currency).

5. **Ship refit/customization** — Hull slots, swappable weapons/parts,
   buying and selling. Deepens the existing combat loop. Depends on the
   economy to be meaningful — otherwise parts are free and refit choices
   carry no weight.

6. **Crew/progression** — Officers, crew skills, leveling. Layers onto
   ships and the campaign. Lowest dependency risk of the remaining
   systems, so it has flexibility in exact timing within this range.

7. **Rift system** — The signature hook: anomalies spawned
   probabilistically from large battles, offering a tiered, decaying
   risk/reward payoff (hazard → exploitable resource → combat power-up).
   Deliberately *not* built first despite being the differentiator: it
   needs battles with real stakes (campaign), a currency sink/source
   (economy), and something to spend the payoff on (refit) to actually
   mean anything to the player.

8. **Narrative + meta/UI shell** — Missions and story beats layered on top
   of factions with agendas, plus the non-gameplay wrapper (main menu,
   save/load, settings). Save/load has no creative dependencies and can
   move earlier if it becomes a practical blocker for playtesting; story
   content depends on factions existing to have agendas worth writing
   about.

## Explicitly Out of Scope

No multiplayer. No systems beyond the eight milestones above — this list
was confirmed as the complete remaining scope for the game.

## Next Step

Pick up Milestone 2 (Campaign Map) and run it through its own
brainstorming → spec → plan cycle when ready to build it.
