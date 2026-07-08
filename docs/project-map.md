# Dyna Project Map

> Purpose: show where project parts live. This is a map of folders, scenes, and key files.

## Project root

- `project.godot` — Godot project config.
- `AGENTS.md` — short briefing for agents.
- `docs/project-map.md` — project structure and file ownership.
- `docs/current-state.md` — current implemented systems and prototype status.
- `docs/dependencies.md` — practical dependency/task map.
- `docs/design_roadmap.md` — broader design roadmap.

## Scenes

- `scenes/main/main.tscn` — top-level assembly: camera, right-side player HUD, creature stats/debug UI, world instance, and debug overlay.
- `scenes/world/world.tscn` — active sandbox world: terrain TileMapLayer, terrain TileSet sources, creatures, grass, eggs, and world-grid node.
- `scenes/creatures/creature.tscn` — base creature scene.
- `scenes/resources/grass.tscn` — grass resource scene.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/effects/lightning_strike_effect.tscn` — lightning visual effect.
- `scenes/effects/rain_target_preview.tscn` — rain target preview.
- `scenes/effects/sun_target_preview.tscn` — sun target preview.
- `scenes/debug/grid_debug_overlay.tscn` — optional grid/path/occupancy debug overlay.

## Scripts

- `scripts/world/world_grid.gd` — central world/grid authority: terrain, walkability, occupancy, blockers, pathfinding, and resource lookup.
- `scripts/creatures/creature.gd` — base creature runtime coordinator.
- `scripts/creatures/creature_species_data.gd` — species resource schema.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore grazing and food targeting.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — predator search, chase, and duel entry.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction checks and egg spawning.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — creature directional visuals and walk/eating-animation switching.
- `scripts/combat/duel.gd` — isolated one-on-one duel loop.
- `scripts/resources/grass.gd` — grass lifecycle, consumption, spread, world registration, and nature-power reactions.
- `scripts/resources/egg.gd` — egg lifecycle, blocker handling, and hatching.
- `scripts/ui/creature_stats_ui.gd` — prototype creature stats, selection, debug status, simulation speed UI, and live creature/egg counters.
- `scripts/ui/player_nature_ui.gd` — player energy and nature-power targeting/effects.
- `scripts/ui/spell_menu_toggle.gd` — spell submenu helper.
- `scripts/debug/grid_debug_overlay.gd` — grid/path/occupancy debug drawing.
- `scripts/debug/performance_stats.gd` — runtime counters and CSV logging.
- `scripts/camera/camera_controller.gd` — observer camera movement and zoom.

## Assets

### Terrain

- `assets/sprites/terrain/ground.png` — ground tile.
- `assets/sprites/terrain/water_tiles_independent.png` — atlas of 9 manually selectable water variants.
- `assets/sprites/terrain/water_center.png`, `water_north.png`, `water_south.png`, `water_west.png`, `water_east.png`, `water_north_west.png`, `water_north_east.png`, `water_south_west.png`, `water_south_east.png` — individual water source sprites.
- `assets/sprites/terrain/mountain_tiles_independent.png` — atlas of 9 manually selectable mountain variants.
- `assets/sprites/terrain/mountain_01.png` … `mountain_09.png` — individual mountain source sprites.

### Creatures and resources

- `assets/sprites/creatures/stegosaurus/` — stegosaurus sprites and walk/eating frames.
- `assets/sprites/creatures/predator/` — temporary predator sprites.
- `assets/sprites/creatures/eggs/` — egg sprites.
- `assets/sprites/effects/lightning/` — lightning effect frames.
- `assets/ui/nature_energy_icon.png` — nature energy icon.

## Ownership summary

- World rules belong in `scripts/world/world_grid.gd`.
- Terrain TileSet setup lives in `scenes/world/world.tscn`.
- Terrain visual variants belong in `assets/sprites/terrain/`.
- Terrain source-id meaning is documented in `docs/dependencies.md`.
- Creature runtime coordination belongs in `scripts/creatures/creature.gd`.
- Creature subsystem details belong in `scripts/creatures/behaviors/`.
- Species identity and static tuning belong in `data/species/*.tres`.
- Grass lifecycle belongs in `scripts/resources/grass.gd`.
- Egg lifecycle belongs in `scripts/resources/egg.gd`.
- Player powers belong in `scripts/ui/player_nature_ui.gd`.
- Debug and performance tooling belongs in `scripts/debug/`.
