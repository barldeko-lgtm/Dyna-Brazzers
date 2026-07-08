# Dyna — Dependencies

## World grid

`res://scripts/world/world_grid.gd` owns:
- terrain lookup;
- walkability;
- footprint placement;
- pathfinding;
- grass lookup;
- creature occupancy;
- blocker occupancy;
- counting/consuming edible grass under creature footprints.

If a task touches movement, blocked tiles, grass consumption, or pathing, inspect `world_grid.gd`.

## Grass lifecycle

`res://scripts/resources/grass.gd` owns:
- 4-stage growth;
- stage visuals;
- whether grass is edible;
- per-stage food value;
- consumption reset to stage 1;
- rain/sun stage changes;
- stage-4 spread attempts;
- world-grid registration/unregistration.

Current grass stages:
- Stage 1 — not edible;
- Stage 2 — edible, restores 3 satiety;
- Stage 3 — edible, restores 5 satiety;
- Stage 4 — edible, restores 7 satiety and can spread.

`world_grid.gd` should ask grass through public methods like `can_be_eaten()`, `consume()`, and `get_last_consumed_food_value()` instead of duplicating stage rules.

## Creature runtime

`res://scripts/creatures/creature.gd` owns high-level runtime state and delegates subsystem details to helpers:
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`

Creature hunger restore should not hardcode grass stages. The grass/world-grid path should provide the consumed satiety value.

## Grass scene

`res://scenes/resources/grass.tscn`

Primary links:
- `res://scripts/resources/grass.gd`
- `res://assets/sprites/terrain/grass_stage_1.png`
- `res://assets/sprites/terrain/grass_stage_2.png`
- `res://assets/sprites/terrain/grass_stage_3.png`
- `res://assets/sprites/terrain/grass_stage_4.png`

Inspect this scene when changing grass visual stages, timer nodes, or exported texture wiring.

## Task bundle: grass lifecycle or grass balance

Read first:
- `res://scripts/resources/grass.gd`
- `res://scenes/resources/grass.tscn`
- `res://scripts/world/world_grid.gd`

Then check:
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/creatures/creature.gd`
- `res://scripts/ui/player_nature_ui.gd`
- `res://data/species/stegosaurus.tres`

Rules:
- stage 1 is not edible;
- stages 2/3/4 restore 3/5/7 satiety;
- eating resets grass to stage 1;
- only stage 4 spreads;
- growth tick is 5 seconds;
- rain is +1 stage;
- sun is -2 stages, minimum stage 1.

## Terrain visual variants

Rules:
- water variants stay in source id `1`;
- mountain variants stay in source id `2`;
- preserve existing `tile_map_data` when editing `world.tscn`.

## Runtime flow: grass consumption

`grass.gd` advances stages, applies visuals, handles rain/sun changes, and resets itself to stage 1 after being eaten. `world_grid.gd` finds edible grass under creature footprints, calls `consume()`, and returns the restored satiety value to the creature.
