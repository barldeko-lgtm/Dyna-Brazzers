# Dyna Project Map

## Project root

- `project.godot` — Godot project config. Startup scene is `scenes/ui/start_screen.tscn`; `PerformanceStats`, `PlayerFlags`, and the flag-aware `SaveSystem` extension are autoloads.
- `AGENTS.md` — working rules and architecture briefing for agents.
- `docs/project-map.md` — project structure and file ownership.
- `docs/current-state.md` — current implemented systems and prototype status.
- `docs/dependencies.md` — practical dependency and fragile-flow map.
- `docs/design_roadmap.md` — broader design roadmap; do not edit unless explicitly requested.

## Key scenes

- `scenes/ui/start_screen.tscn` — centered semi-transparent startup menu over a full-screen illustrated Dyna Brazzers background, with New Game, three-slot Load, placeholder Menu, and Exit.
- `scenes/main/main.tscn` — camera, right-side HUD with terrain minimap and creature markers, world instance, debug overlay, and UI wiring.
- `scenes/world/world.tscn` — only active gameplay world: 85x85 terrain TileMap, initial grass, an empty creature container, eggs container, camera marker, and world grid.
- `scenes/world/player_base.tscn` — fixed 2x2 player nature base, spawned at the authored `CameraStart` marker and used as the origin for player-created eggs.
- `scenes/resources/grass.tscn` — grass resource scene with four growth-stage textures.
- `scenes/resources/egg.tscn` — shared two-stage egg scene used by all reproducing species.
- `scenes/creatures/creature.tscn` — shared base creature scene.
- `scenes/debug/grid_debug_overlay.tscn` — F3 grid/debug overlay.
- `scenes/effects/lightning_strike_effect.tscn` — lightning effect.
- `scenes/effects/rain_target_preview.tscn` — rain targeting preview.
- `scenes/effects/rain_cast_effect.tscn` — four-frame rain cast animation.
- `scenes/effects/sun_target_preview.tscn` — sun targeting preview.

## Key scripts

### World and camera

- `scripts/world/world_grid.gd` — terrain lookup, walkability, occupancy, blockers, pathfinding, grass lookup, and footprint queries.
- `scripts/world/start_map_world_grid.gd` — extends the base grid for the authored start map, spawns the player base at `CameraStart`, protects its footprint from grass spreading, and exposes world bounds to the camera.
- `scripts/world/player_base.gd` — scales the base sprite, registers its static 2x2 blocker footprint, finds nearby valid egg positions, and creates configured species eggs.
- `scripts/world/start_map_layout.gd` — builds the initial 85x85 terrain only when the `Ground` TileMap is empty; chooses matching water and mountain edge variants.
- `scripts/camera/camera_controller.gd` — camera movement, wheel zoom, new-game start marker, and map-bound clamping.

### Creatures and resources

- `scripts/creatures/creature.gd` — creature runtime coordinator, movement state, death cleanup, and world-space shadow/highlight overlays.
- `scripts/creatures/creature_species_data.gd` — shared species resource schema, including per-species egg texture fields.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore food search and target ranking.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — temporary predator targeting and combat-entry logic.
- `scripts/creatures/behaviors/creature_egg_eater_logic.gd` — stage-2 egg targeting and consumption logic.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction and egg spawning.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional visuals, animations, and death pose.
- `scripts/combat/duel.gd` — temporary one-on-one combat loop.
- `scripts/resources/grass.gd` — grass growth, consumption, spread, and nature-power reactions.
- `scripts/resources/egg.gd` — egg stages, species texture application, blocker handling, and hatching.

### UI, effects, saving, and debug

- `scripts/ui/start_screen.gd` — startup menu and slot loading.
- `scripts/ui/creature_stats_ui.gd` — creature information, hover, selection, and lightning click bridge.
- `scripts/ui/player_ui.gd` — interactive terrain minimap generation, creature-marker overlay layer, camera viewport display and click navigation, creature/egg counters, time-speed controls, and egg-controller bootstrap.
- `scripts/ui/player_egg_creation_ui.gd` — runtime egg submenu, temporary species energy prices, button availability, and base purchase requests.
- `scripts/flags/player_flag_system.gd` — `PlayerFlags` autoload; owns all-species flag submenu, map placement, saved state, target distribution, and soft attraction.
- `scripts/flags/player_flag_visual.gd` — non-blocking world-space flag, 11x11 area, and placement-preview drawing.
- `scripts/ui/player_nature_ui.gd` — spell buttons, targeting, and previews.
- `scripts/player/player_energy.gd` — session energy reserve, spending API, and living-dinosaur income.
- `scripts/world/nature_effects_system.gd` — world-side lightning, rain, sun, grass effects, and spell VFX application.
- `scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug.
- `scripts/save/save_system.gd` — base three-slot JSON persistence, in-game menu integration, and runtime reconstruction.
- `scripts/save/save_system_with_flags.gd` — small `SaveSystem` extension that adds player species flags without duplicating the base save logic.
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

Static terrain and the fixed player base are not included in these files. Active species flags are stored as lightweight tile records inside the selected save slot.

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

The terrain minimap reads these source ids directly from the active `Ground` TileMapLayer, generates its display texture at runtime, overlays the active camera viewport, draws 6x6 creature-category triangle markers on a separate overlay layer (light green herbivores, red predators, blue egg eater), and translates minimap clicks into observer-camera world positions.

## UI assets

- `assets/ui/start_screen_background.png` — 1920x1080 illustrated background used by the startup scene.

## Effect assets

- `assets/sprites/effects/rain/rain_cast_01.png` ... `rain_cast_04.png` — transparent rain animation frames.
- `assets/ui/creature_selection_frame.png` — world-space creature hover/selection frame.

## Player-base asset

- `assets/sprites/world/player_base.png` — 512x512 transparent source sprite displayed at 256x256 in world space with mipmapped linear filtering.

## Creature and species assets

- `data/species/stegosaurus.tres` — stegosaurus stats, visuals, animations, egg data, and death settings.
- `data/species/triceratops.tres` — triceratops stats, directional visuals, and custom egg textures.
- `data/species/predator.tres` — temporary predator species resource.
- `data/species/tyrannosaurus.tres` — tyrannosaurus stats, visuals, and custom egg textures.
- `data/species/raptor.tres` — raptor stats, visuals, and custom egg textures.
- `data/species/pterodactyl.tres` — pterodactyl stats, visuals, and custom egg textures.
- `data/species/egg_eater.tres` — egg-eater stats, visuals, and custom egg textures.
- `assets/sprites/creatures/stegosaurus/` — stegosaurus sprites, animations, and egg sprites.
- `assets/sprites/creatures/triceratops/` — triceratops directional, animation, and egg sprites.
- `assets/sprites/creatures/tyrannosaurus/` — tyrannosaurus directional, idle, and egg sprites.
- `assets/sprites/creatures/raptor/` — raptor directional, idle, and egg sprites.
- `assets/sprites/creatures/pterodactyl/` — pterodactyl directional and egg sprites.
- `assets/sprites/creatures/egg_eater/` — egg-eater directional and egg sprites.

The current species resources assign their stage-1 and stage-2 egg textures directly. `egg.tscn` remains shared and supplies defaults for future incomplete species.

## Ownership summary

- Authored terrain and initial world contents belong in `scenes/world/world.tscn`.
- The player-base scene owns its visual scaling, blocker registration, nearby egg-placement search, and species egg creation; `start_map_world_grid.gd` owns spawning it at the authored camera-start point.
- Empty-map bootstrap and terrain edge selection belong in `scripts/world/start_map_layout.gd`.
- Terrain, movement permissions, occupancy, blockers, pathfinding, and resource lookup belong in world-grid scripts.
- Camera movement and visual boundary clamping belong in `scripts/camera/camera_controller.gd`.
- Species stats, species visuals, and species-specific egg texture references belong in `data/species/*.tres`.
- Creature runtime coordination belongs in `scripts/creatures/creature.gd`.
- Specialized creature behaviour belongs in `scripts/creatures/behaviors/`.
- Grass and egg lifecycles belong in their own resource scripts.
- Startup flow belongs in `start_screen.gd`; startup layout, background presentation, and menu transparency belong in `start_screen.tscn`.
- Save collection, reconstruction, slot files, and in-game save menu belong in `save_system.gd`.
- Creature observation and selection belong in `creature_stats_ui.gd`.
- Terrain minimap generation, creature-marker overlay updates, camera-frame updates, minimap click navigation, counters, speed controls, and egg-controller startup belong in `player_ui.gd`.
- Egg submenu presentation, temporary egg prices, purchase validation, and base requests belong in `player_egg_creation_ui.gd`.
- Species-flag UI, targeting, world visuals, target distribution, and soft order behaviour belong to the `PlayerFlags` autoload and `scripts/flags/`.
- The base save system stays in `save_system.gd`; flag serialization is layered through `save_system_with_flags.gd`.
- Spell controls, targeting, and previews belong in `player_nature_ui.gd`. Player energy belongs in `player_energy.gd`; egg purchases and spell UI use its public API. World-side spell results belong in `nature_effects_system.gd`.
- Text and grid diagnostics belong in their dedicated debug scripts.

## Removed / not used

Do not use:

- `scenes/world/world_triceratops.tscn`;
- species-specific duplicate egg scenes;
- `scenes/resources/tree.tscn`;
- `scripts/resources/tree.gd`;
- `assets/sprites/terrain/trees/`;
- `assets/sprites/terrain/tree_tiles_large.png`.

Trees are TileMap terrain, and species should not require separate copies of the world or egg scenes.
