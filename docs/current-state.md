# Dyna — Current Project State

> Purpose: describe what the prototype currently is and what systems already work.

## Status

Dyna is an early Godot 4.7 simulation prototype.

The project currently has:
- a tile-based 2D world;
- autonomous herbivore creatures;
- grass as a renewable resource;
- eggs, hatching, and population growth;
- a temporary predator and simple duel combat;
- player nature powers;
- a structured right-side player HUD;
- live player-side creature/egg counters;
- manually selectable water and mountain terrain visual variants;
- debug/performance tools;
- a free observer camera.

The project is still a simulation sandbox, not a finished game.

## Design direction

The player is not a direct unit commander. The intended feel is an ecosystem that mostly runs by itself while the player influences conditions from above.

Important direction rules:
- keep creature behaviour autonomous;
- prefer indirect influence over unit commands;
- keep world/resource/entity logic separate from UI;
- avoid turning the project into a standard RTS.

## Implemented systems

### World

The prototype has a tile-based world using `TileMapLayer`.

The world currently supports:
- walkable terrain;
- blocked terrain types;
- map bounds caching;
- footprint placement;
- occupancy tracking;
- blocker tracking;
- pathfinding;
- grass/resource lookup.

Terrain is source-id driven:
- source id `0` is ground;
- source id `1` is water;
- source id `2` is mountain.

Water and mountain tiles now have multiple manually selectable visual variants. These variants are not autotiles and are not separate gameplay types.

### Terrain visuals

Current terrain visual work includes:
- a water atlas with 9 independent manually selectable water variants;
- a mountain atlas with 9 independent manually selectable mountain variants.

These visual variants are meant for hand-painting nicer water and mountain shapes in the editor. They do not change terrain logic by themselves.

### Creatures

The world contains autonomous creatures with:
- species-driven stats and visuals;
- logical tile anchors;
- smooth visual movement;
- hunger;
- health;
- aging;
- death;
- wandering;
- food seeking;
- eating;
- egg laying;
- combat state;
- directional walking animations.

Creature logic is split between the main creature coordinator and helper scripts for grazing, predator behaviour, reproduction, and visuals.

### Grass

Grass supports:
- growth stages;
- edible adult state;
- consumption;
- spreading;
- tile registration in the world grid;
- reaction hooks for player nature powers.

### Eggs and reproduction

Eggs support:
- staged lifecycle;
- blocker registration when needed;
- vulnerability rules;
- hatching into a creature.

### UI, debug, and performance

The prototype currently includes:
- a persistent right-side player HUD panel;
- a minimap placeholder area;
- live player-side herbivore and egg counters;
- placeholder/enemy-side counter slots for future use;
- a nature-energy icon and numeric energy display;
- simulation speed buttons;
- a 2x3 main action button grid;
- a collapsible spell submenu for lightning, rain/cloud, and sun;
- creature hover/selection;
- creature stats display;
- debug status text;
- grid/path/occupancy debug overlay;
- runtime counters;
- CSV performance logging;
- observer camera movement and zoom.

## Known technical debt

- `creature_stats_ui.gd` still mixes stats, selection, debug status, simulation speed UI, and counters.
- `creature.gd` is still a central coordinator.
- Creature animation coverage is still partial.
- Terrain logic depends on TileSet source ids, so source-id meaning must stay documented and consistent.
- Current powers work, but the system is not yet a general reusable action framework.

## Fragile rules

- Creature logical anchors, pending anchors, visual position, and world occupancy must stay synchronized.
- World-grid registration for grass, creatures, and blockers must stay honest.
- Terrain TileSet source ids must stay aligned with `world_grid.gd` constants.
- Water variants must remain in source id `1` if they should behave as water.
- Mountain variants must remain in source id `2` if they should behave as mountains/blockers.
- UI buttons should trigger powers or future actions, not directly command autonomous creatures.

## Useful next directions

Possible near-term work:
- build the actual minimap;
- compact UI cleanup;
- better visual feedback for nature powers;
- paint nicer water/mountain forms using the new visual variants;
- richer terrain and resource interactions;
- additional species.
