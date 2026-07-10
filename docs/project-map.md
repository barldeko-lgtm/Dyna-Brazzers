# Dyna Project Map

## Project root

- `project.godot` — Godot project config. Startup scene is `scenes/ui/start_screen.tscn`; `SaveSystem` is registered as an autoload.
- `AGENTS.md` — short briefing for agents.
- `docs/project-map.md` — project structure and file ownership.
- `docs/current-state.md` — current implemented systems and prototype status.
- `docs/dependencies.md` — practical dependency/task map.
- `docs/design_roadmap.md` — broader design roadmap.

## Key scenes

- `scenes/ui/start_screen.tscn` — centered startup screen with New Game, three-slot Load, placeholder Menu, and Exit.
- `scenes/main/main.tscn` — camera, HUD, world instance, debug overlay, UI script wiring.
- `scenes/world/world.tscn` — active sandbox world: terrain TileMap, terrain TileSet sources, creatures, grass, eggs, world grid.
- `scenes/resources/grass.tscn` — grass resource scene with 4 growth-stage textures.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/creatures/creature.tscn` — base creature scene.
- `scenes/debug/grid_debug_overlay.tscn` — F3 grid/debug overlay scene.
- `scenes/effects/rain_cast_effect.tscn` — one-second, four-frame rain cast animation.

## Key scripts

- `scripts/world/world_grid.gd` — terrain/walkability, occupancy, blockers, pathfinding, grass lookup, grass consumption aggregation.
- `scripts/resources/grass.gd` — 4-stage grass lifecycle, consumption, spreading, rain/sun reactions, per-stage food value.
- `scripts/resources/egg.gd` — egg lifecycle, blocker handling, hatching.
- `scripts/creatures/creature.gd` — base creature runtime coordinator, including death/corpse cleanup and world-space interaction highlight overlay.
- `scripts/creatures/creature_species_data.gd` — species resource schema for stats, visuals, eggs, death texture, and corpse lifetime.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore grazing and quality-aware food targeting.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional sprites, walking/eating animations, and death-pose visual locking.
- `scripts/ui/start_screen.gd` — startup menu flow, three-slot loading, save date labels, and Exit.
- `scripts/ui/creature_stats_ui.gd` — creature info panel, hover/selection, empty-click deselection, lightning click bridge, and highlight coordination.
- `scripts/ui/player_ui.gd` — player side-panel counters and time speed controls.
- `scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed text debug.
- `scripts/ui/player_nature_ui.gd` — player energy and nature powers.
- `scripts/save/save_system.gd` — three-slot JSON persistence, in-game save/load menu integration, session reset, and runtime reconstruction.
- `scripts/debug/grid_debug_overlay.gd` — F3 grid overlay: blocked terrain, grass, occupancy, footprint, path.
- `scripts/effects/rain_cast_effect.gd` — real-time four-frame rain animation playback and cleanup.
- `scripts/effects/rain_target_preview.gd` — rain area preview and successful-cast visual trigger.

## Save files

Save slots are stored outside the project in Godot's `user://` directory:

- `user://dyna_save_slot_1.json`
- `user://dyna_save_slot_2.json`
- `user://dyna_save_slot_3.json`

On Windows this normally resolves to:

`%APPDATA%/Godot/app_userdata/Dyna/`

## Terrain assets

- `assets/sprites/terrain/ground.png` — ground tile.
- `assets/sprites/terrain/water_tiles_independent.png` — 9 manually selectable water variants.
- `assets/sprites/terrain/mountain_tiles_independent.png` — 9 manually selectable mountain variants.
- `assets/sprites/terrain/tree_tiles_independent.png` — tree atlas with 4 trees split into normal 128x128 TileMap tiles.
- `assets/sprites/terrain/grass_stage_1.png` ... `grass_stage_4.png` — grass growth-stage sprites.

## Effect assets

- `assets/sprites/effects/rain/rain_cast_01.png` ... `rain_cast_04.png` — four transparent 640x640 rain frames covering a 5x5-tile area.

## Creature and species assets

- `data/species/stegosaurus.tres` — stegosaurus stats, directional textures, animation resources, egg tuning, death texture, and corpse lifetime.
- `assets/sprites/creatures/stegosaurus/stegosaurus_dead.png` — stegosaurus defeated/death pose shown briefly before removal.
- `assets/ui/creature_selection_frame.png` — stone corner highlight frame used for creature hover/selection.

## Ownership summary

- World rules belong in `scripts/world/world_grid.gd`.
- Terrain TileSet setup lives in `scenes/world/world.tscn`.
- Terrain visual variants belong in `assets/sprites/terrain/`.
- Creature species stats and species-specific visual references belong in `data/species/*.tres`.
- Grass lifecycle and per-stage food value belong in `scripts/resources/grass.gd`.
- Grass consumption aggregation belongs in `scripts/world/world_grid.gd`.
- Grazing target ranking belongs in `scripts/creatures/behaviors/creature_grazing_logic.gd`.
- Creature runtime coordination, death state entry, corpse cleanup, and world-space selection frame setup belong in `scripts/creatures/creature.gd`.
- Creature visual selection/animation details belong in `scripts/creatures/behaviors/creature_visual_controller.gd`.
- Startup-screen presentation and button flow belong in `scripts/ui/start_screen.gd` and `scenes/ui/start_screen.tscn`.
- Save/load data collection, slot files, runtime reconstruction, and in-game save actions belong in `scripts/save/save_system.gd`.
- Creature info UI and hover/selection highlight coordination belong in `scripts/ui/creature_stats_ui.gd`.
- Player HUD counters and speed controls belong in `scripts/ui/player_ui.gd`.
- Always-visible compact debug and F4 detailed text debug belong in `scripts/ui/debug_status_ui.gd`.
- F3 grid visualization belongs in `scripts/debug/grid_debug_overlay.gd`.

## Removed / not used

Trees are not separate resource scenes.

Do not use:

- `scenes/resources/tree.tscn`
- `scripts/resources/tree.gd`
- `assets/sprites/terrain/trees/`
- `assets/sprites/terrain/tree_tiles_large.png`

Trees are TileMap terrain, like water and mountains.
