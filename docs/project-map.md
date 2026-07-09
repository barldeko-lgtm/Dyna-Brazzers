# Dyna Project Map

## Project root

- `project.godot` — Godot project config.
- `AGENTS.md` — short briefing for agents.
- `docs/project-map.md` — project structure and file ownership.
- `docs/current-state.md` — current implemented systems and prototype status.
- `docs/dependencies.md` — practical dependency/task map.
- `docs/design_roadmap.md` — broader design roadmap.

## Key scenes

- `scenes/main/main.tscn` — camera, HUD, world instance, debug overlay.
- `scenes/world/world.tscn` — active sandbox world: terrain TileMap, terrain TileSet sources, creatures, grass, eggs, world grid.
- `scenes/resources/grass.tscn` — grass resource scene with 4 growth-stage textures.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/creatures/creature.tscn` — base creature scene.

## Key scripts

- `scripts/world/world_grid.gd` — terrain/walkability, occupancy, blockers, pathfinding, grass lookup, grass consumption aggregation.
- `scripts/resources/grass.gd` — 4-stage grass lifecycle, consumption, spreading, rain/sun reactions, per-stage food value.
- `scripts/resources/egg.gd` — egg lifecycle, blocker handling, hatching.
- `scripts/creatures/creature.gd` — base creature runtime coordinator.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore grazing and food targeting.
- `scripts/ui/player_nature_ui.gd` — player energy and nature powers.
- `scripts/ui/creature_stats_ui.gd` — stats, selection, debug status, speed UI, live counters.

## Terrain assets

- `assets/sprites/terrain/ground.png` — ground tile.
- `assets/sprites/terrain/water_tiles_independent.png` — 9 manually selectable water variants.
- `assets/sprites/terrain/mountain_tiles_independent.png` — 9 manually selectable mountain variants.
- `assets/sprites/terrain/tree_tiles_independent.png` — tree atlas with 4 trees split into normal 128x128 TileMap tiles.
- `assets/sprites/terrain/grass_stage_1.png` ... `grass_stage_4.png` — grass growth-stage sprites.

## Ownership summary

- World rules belong in `scripts/world/world_grid.gd`.
- Terrain TileSet setup lives in `scenes/world/world.tscn`.
- Terrain visual variants belong in `assets/sprites/terrain/`.
- Grass lifecycle and per-stage food value belong in `scripts/resources/grass.gd`.
- Grass consumption aggregation belongs in `scripts/world/world_grid.gd`.
- Creature runtime coordination belongs in `scripts/creatures/creature.gd`.

## Removed / not used

Trees are not separate resource scenes.

Do not use:
- `scenes/resources/tree.tscn`
- `scripts/resources/tree.gd`
- `assets/sprites/terrain/trees/`
- `assets/sprites/terrain/tree_tiles_large.png`

Trees are TileMap terrain, like water and mountains.
