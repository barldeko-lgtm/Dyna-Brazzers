# Dyna — Current Project State

## Status

Dyna is an early Godot 4.7 simulation prototype.

Current prototype includes:
- tile-based 2D world;
- autonomous herbivore creatures;
- 4-stage renewable grass;
- eggs, hatching, and population growth;
- temporary predator and simple duel combat;
- player nature powers;
- right-side HUD with live creature/egg counters;
- manually selectable water and mountain variants;
- debug/performance tools;
- free observer camera.

## Design direction

The player is not a direct unit commander. The game should feel like an ecosystem that runs mostly by itself while the player influences conditions from above.

Keep:
- autonomous creature behaviour;
- indirect player influence;
- world/resource/entity logic separate from UI;
- simulation-first design, not a standard RTS.

## Terrain

Terrain is source-id driven:

- source id `0` — ground;
- source id `1` — water;
- source id `2` — mountain.

Water and mountain variants are manual visual variants, not autotiles and not separate gameplay types.

## Grass

Grass now has 4 stages:

- Stage 1 — young grass, not edible.
- Stage 2 — edible, restores 3 satiety.
- Stage 3 — edible, restores 5 satiety.
- Stage 4 — edible, restores 7 satiety and can spread.

Rules:
- growth advances by 1 stage every 5 seconds until stage 4;
- eating any edible grass resets it to stage 1;
- only stage 4 grass can spread;
- rain advances grass by 1 stage; stage 4 tries to spread;
- sun reduces grass by 2 stages, but never below stage 1;
- random sun-based grass removal remains separate.

## Known technical debt

- `creature_stats_ui.gd` still mixes stats, selection, debug status, simulation speed UI, and counters.
- `creature.gd` is still a central coordinator.
- Creature animation coverage is still partial.
- Grass food value now belongs to grass stages; avoid duplicating food values in creature code.

## Fragile rules

- World-grid registration for grass, creatures, and blockers must stay honest.
- Water variants must remain in source id `1`.
- Mountain variants must remain in source id `2`.
- Grass is edible from stage 2, but spreads only from stage 4.
- Grass food values are `3 / 5 / 7` for stages `2 / 3 / 4`.
- UI buttons should trigger powers or future actions, not directly command autonomous creatures.
