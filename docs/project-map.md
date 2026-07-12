# Dyna Project Map

## Project root

- `project.godot` — Godot project config. Startup scene is `scenes/ui/start_screen.tscn`; `PerformanceStats` and `SaveSystem` are autoloads.
- `AGENTS.md` — working rules and architecture briefing for agents.
- `docs/project-map.md` — project structure and file ownership.
- `docs/current-state.md` — current implemented systems and prototype status.
- `docs/dependencies.md` — practical dependency and fragile-flow map.
- `docs/design_roadmap.md` — broader design roadmap; do not edit unless explicitly requested.

## Key scenes

- `scenes/ui/start_screen.tscn` — centered startup screen with New Game, three-slot Load, placeholder Menu, and Exit.
- `scenes/main/main.tscn` — camera, HUD, world instance, debug overlay, and UI wiring.
- `scenes/world/world.tscn` — only active gameplay world: 85x85 terrain TileMap, initial grass, two stegosauruses, four triceratops, one tyrannosaurus, one raptor, eggs container, camera marker, and world grid.
- `scenes/resources/grass.tscn` — grass resource scene with four growth-stage textures.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/creatures/creature.tscn` — shared base creature scene.
- `scenes/debug/grid_debug_overlay.tscn` — F3 grid/debug overlay.
- `scenes/effects/lightning_strike_effect.tscn` — lightning effect.
- `scenes/effects/rain_target_preview.tscn` — rain targeting preview.
- `scenes/effects/rain_cast_effect.tscn` — four-frame rain cast animation.
- `scenes/effects/sun_target_preview.tscn` — sun targeting preview.

## Key scripts

### World and camera

- `scripts/world/world_grid.gd` — terrain lookup, walkability, occupancy, blockers, pathfinding, grass lookup, and footprint queries.
- `scripts/world/start_map_world_grid.gd` — extends the base grid for the authored start map and exposes world bounds to the camera.
- `scripts/world/start_map_layout.gd` — builds the initial 85x85 terrain only when the `Ground` TileMap is empty; chooses matching water and mountain edge variants.
- `scripts/camera/camera_controller.gd` — camera movement, wheel zoom, new-game start marker, and map-bound clamping.

### Creatures and resources

- `scripts/creatures/creature.gd` — creature runtime coordinator, movement state, death cleanup, and world-space shadow/highlight overlays.
- `scripts/creatures/creature_species_data.gd` — shared species resource schema.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore food search and target ranking.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — temporary predator targeting and combat-entry logic.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction and egg spawning.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional visuals, animations, and death pose.
- `scripts/combat/duel.gd` — temporary one-on-one combat loop.
- `scripts/resources/grass.gd` — grass growth, consumption, spread, and nature-power reactions.
- `scripts/resources/egg.gd` — egg stages, blocker handling, and hatching.

### UI, effects, saving, and debug

- `scripts/ui/start_screen.gd` — startup menu and slot loading.
- `scripts/ui/creature_stats_ui.gd` — creature information, hover, selection, and lightning click bridge.
- `scripts/ui/player_ui.gd` — creature/egg counters and time-speed controls.
- `scripts/ui/player_nature_ui.gd` — player energy and nature powers.
- `scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug.
- `scripts/save/save_system.gd` — three-slot JSON persistence, in-game menu integration, and runtime reconstruction.
- `scripts/debug/performance_stats.gd` — runtime counters and CSV logging.
- `scripts/debug/grid_debug_overlay.gd` — F3 visualization of terrain, occupancy, footprints, and paths.
- `scripts/effects/` — effect playback and target-preview scripts.

## Save files

Save slots are stored outside the project in Godot's `user://` directory:

- `user://dyna_save_slot_1.json`
- `user://dyna_save_slot_2.json`
- `user://dyna_save_slot_3.json`

On Windows this normally resolves to:

`%APPDATA%/Godot/app_userdata/Dyna/`

Static terrain is not included in these files.

## Terrain assets

- `assets/maps/start_map_layout.png` — original map-layout reference; it is not read as runtime terrain.
- `assets/sprites/terrain/ground.png` — ground tile.
- `assets/sprites/terrain/water_tiles_independent.png` — water and shore variants.
- `assets/sprites/terrain/mountain_tiles_independent.png` — mountain interior, edge, and corner variants.
- `assets/sprites/terrain/tree_tiles_independent.png` — four trees split into normal 128x128 TileMap pieces.
- `assets/sprites/terrain/grass_stage_1.png` ... `grass_stage_4.png` — grass growth-stage sprites.

Terrain source ids in `world.tscn`:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

## Effect assets

- `assets/sprites/effects/rain/rain_cast_01.png` ... `rain_cast_04.png` — transparent rain animation frames.
- `assets/ui/creature_selection_frame.png` — world-space creature hover/selection frame.

## Creature and species assets

- `data/species/stegosaurus.tres` — stegosaurus stats, visuals, animations, egg data, and death settings.
- `data/species/triceratops.tres` — triceratops stats and directional visuals.
- `data/species/predator.tres` — temporary predator species resource.
- `data/species/tyrannosaurus.tres` — tyrannosaurus species resource.
- `data/species/raptor.tres` — raptor species resource.
- `assets/sprites/creatures/stegosaurus/` — stegosaurus sprites and animation resources.
- `assets/sprites/creatures/triceratops/` — triceratops directional sprites.
- `assets/sprites/creatures/tyrannosaurus/` — tyrannosaurus directional and idle sprites.
- `assets/sprites/creatures/raptor/` — raptor directional sprites; the right-facing sprite is also used as temporary idle.

The third starting creature in `world.tscn` references `triceratops.tres` directly; `Tyrannosaurus` and `Raptor` reference their species resources. A separate `world_triceratops.tscn` is not part of the active structure.

## Ownership summary

- Authored terrain and initial world contents belong in `scenes/world/world.tscn`.
- Empty-map bootstrap and terrain edge selection belong in `scripts/world/start_map_layout.gd`.
- Terrain, movement permissions, occupancy, blockers, pathfinding, and resource lookup belong in world-grid scripts.
- Camera movement and visual boundary clamping belong in `scripts/camera/camera_controller.gd`.
- Species stats and species-specific visual references belong in `data/species/*.tres`.
- Creature runtime coordination belongs in `scripts/creatures/creature.gd`.
- Specialized creature behaviour belongs in `scripts/creatures/behaviors/`.
- Grass and egg lifecycles belong in their own resource scripts.
- Startup flow belongs in `start_screen.gd` and `start_screen.tscn`.
- Save collection, reconstruction, slot files, and in-game save menu belong in `save_system.gd`.
- Creature observation and selection belong in `creature_stats_ui.gd`.
- Counters and speed controls belong in `player_ui.gd`.
- Nature energy and powers belong in `player_nature_ui.gd`.
- Text and grid diagnostics belong in their dedicated debug scripts.

## Removed / not used

Do not use:

- `scenes/world/world_triceratops.tscn`;
- `scenes/resources/tree.tscn`;
- `scripts/resources/tree.gd`;
- `assets/sprites/terrain/trees/`;
- `assets/sprites/terrain/tree_tiles_large.png`.

Trees are TileMap terrain, and species should not require separate copies of the world scene.
