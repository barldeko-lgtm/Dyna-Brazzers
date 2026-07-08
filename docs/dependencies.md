# Dyna — Dependencies

> Purpose: explain how important files depend on each other and which files to inspect for common tasks.

## Core dependency principles

### World grid is the physical source of truth

`res://scripts/world/world_grid.gd` owns:
- terrain lookup;
- walkability;
- footprint placement;
- pathfinding;
- grass lookup;
- creature occupancy;
- blocker occupancy.

If a task touches movement, standing position, blocked tiles, resource lookup, or pathing, inspect `world_grid.gd`.

### Terrain TileSet source ids are gameplay rules

`res://scenes/world/world.tscn` owns the active terrain TileSet sources.

Current terrain source ids:
- source id `0` — ground, walkable;
- source id `1` — water, blocked;
- source id `2` — mountain, blocked.

`world_grid.gd` reads source ids to decide walkability. Visual variants of the same terrain type must stay inside the same source id.

Current visual variant atlases:
- `res://assets/sprites/terrain/water_tiles_independent.png`;
- `res://assets/sprites/terrain/mountain_tiles_independent.png`.


### Creature script is the runtime coordinator

`res://scripts/creatures/creature.gd` owns high-level runtime state and delegates subsystem details to helpers:
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`

### Resources own their lifecycle

Grass and eggs should manage their own internal state:
- `res://scripts/resources/grass.gd`
- `res://scripts/resources/egg.gd`

### UI triggers actions but should not own simulation state

Player and observation UI live mostly in:
- `res://scripts/ui/player_nature_ui.gd`
- `res://scripts/ui/creature_stats_ui.gd`

UI can trigger actions and display data, but lasting world/entity/resource state should stay in world, creature, grass, egg, or species logic.

## Scene links

### Main scene

`res://scenes/main/main.tscn`

Primary links:
- `res://scripts/camera/camera_controller.gd`
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scripts/ui/player_nature_ui.gd`
- `res://scenes/world/world.tscn`
- `res://scenes/debug/grid_debug_overlay.tscn`

### World scene

`res://scenes/world/world.tscn`

Primary links:
- `res://scripts/world/world_grid.gd`
- `res://scenes/creatures/creature.tscn`
- `res://scenes/resources/grass.tscn`
- `res://scenes/resources/egg.tscn`
- `res://assets/sprites/terrain/*.png`

Terrain setup in this scene should preserve:
- source id `1` for all functional water variants;
- source id `2` for all functional mountain variants;
- already-painted `tile_map_data`.

## System dependency blocks

### World / grid / terrain

Main files:
- `res://scripts/world/world_grid.gd`
- `res://scenes/world/world.tscn`
- `res://scripts/debug/grid_debug_overlay.gd`

Usually relevant:
- `res://scripts/creatures/creature.gd`
- `res://scripts/resources/grass.gd`
- `res://scripts/resources/egg.gd`
- `res://assets/sprites/terrain/`

Important links:
- creatures register anchors and occupied footprint tiles in `world_grid.gd`;
- grass registers its tile in `world_grid.gd`;
- eggs register blocker footprints in `world_grid.gd`;
- terrain walkability is based on TileSet source ids;
- water and mountain visual variants are manually selectable but functionally identical inside their source id.

High-risk areas:
- source id `1` must remain water;
- source id `2` must remain mountain;
- moving visual variants between sources changes gameplay;
- preserving `tile_map_data` when editing `world.tscn`.

### UI and debug

Main files:
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scripts/ui/player_nature_ui.gd`
- `res://scripts/debug/grid_debug_overlay.gd`
- `res://scripts/debug/performance_stats.gd`
- `res://scenes/main/main.tscn`

Known debt:
- `creature_stats_ui.gd` currently mixes stats, debug text, simulation speed, and counters;
- split into smaller UI scripts during UI cleanup.

## Task bundles

### If changing movement, walkability, footprint placement, or terrain blocking

Read first:
- `res://scripts/world/world_grid.gd`
- `res://scenes/world/world.tscn`

Rules:
- keep water variants in source id `1`;
- keep mountain variants in source id `2`;
- do not create new source ids for visual-only variants unless `world_grid.gd` is deliberately updated.

### If changing terrain visuals or adding tile variants

Read first:
- `res://scenes/world/world.tscn`
- `res://assets/sprites/terrain/`

Rules:
- visual variants of water should stay in water source id `1`;
- visual variants of mountains should stay in mountain source id `2`;
- keep atlas coordinates predictable;
- preserve existing `tile_map_data`;
- keep `0:0` as the safest default for already-painted tiles.

### If changing grazing or food search

Read first:
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/world/world_grid.gd`
- `res://scripts/resources/grass.gd`

### If changing player powers

Read first:
- `res://scripts/ui/player_nature_ui.gd`
- `res://scenes/main/main.tscn`

### If changing reproduction or eggs

Read first:
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/resources/egg.gd`
- `res://scripts/world/world_grid.gd`

### If changing predator or combat

Read first:
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/combat/duel.gd`
- `res://scripts/creatures/creature.gd`

### If changing creature visuals or animation

Read first:
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`
- `res://scripts/creatures/creature.gd`
- `res://data/species/*.tres`
- `res://data/animations/*.tres`

## Runtime flows that matter for dependencies

### Terrain walkability

`world_grid.gd` reads the source id of a tile from the `Ground` TileMapLayer. Water source id `1` and mountain source id `2` are blocked. Individual atlas coordinates inside those sources are visual variants and should not affect gameplay.

### Player powers

`player_nature_ui.gd` owns energy and targeting. It should call into world, grass, creature, and effect scripts. The affected system should own lasting state changes.

## Documentation update policy

Update this file when:
- a file responsibility changes;
- a new dependency is introduced;
- a scene/script link changes;
- a task bundle becomes misleading;
- a fragile rule changes.

Do not update this file for ordinary tuning changes:
- costs;
- radii;
- delays;
- counts;
- speed presets;
- damage values.
