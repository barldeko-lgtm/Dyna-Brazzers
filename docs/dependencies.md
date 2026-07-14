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
- counting and consuming edible grass under creature footprints.

`res://scripts/world/start_map_world_grid.gd` extends the base grid for the authored start map and provides world bounds used by the camera. Grass-host checks remain based on normal walkable terrain.

The active world and map bootstrap are:

- `res://scenes/world/world.tscn`;
- `res://scripts/world/start_map_layout.gd`;
- `res://scripts/camera/camera_controller.gd`.

Map flow:

1. `world.tscn` creates the `Ground` TileMap and its terrain sources.
2. `start_map_layout.gd` checks whether the TileMap already has cells.
3. If the TileMap is empty, the initial 85x85 map is created.
4. If the TileMap is non-empty, the script does nothing.
5. Godot saves later manual TileMap edits in `world.tscn`.
6. The camera reads authored bounds through the world grid.

Rules:

- never clear or rebuild a non-empty map during scene startup;
- never hand-generate serialized `tile_map_data`;
- preserve terrain source ids;
- keep initial creatures, grass, eggs container, camera marker, and predator marker on valid terrain;
- after major map edits, recreate saves or add migration/version handling.

If a task touches movement, blocked tiles, map dimensions, camera bounds, grass placement, corpse passability, or pathing, inspect these files together.

## UI ownership

`res://scenes/main/main.tscn` owns active gameplay UI node wiring.

Current UI scripts:

- `res://scripts/ui/start_screen.gd` — startup menu and three-slot startup loading;
- `res://scripts/ui/creature_stats_ui.gd` — creature information, selection, and highlight coordination;
- `res://scripts/ui/player_ui.gd` — side-panel counters and time-speed controls;
- `res://scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug text;
- `res://scripts/ui/player_nature_ui.gd` — energy and nature powers;
- `res://scripts/debug/grid_debug_overlay.gd` — F3 grid/debug overlay.

Expected gameplay scene wiring:

- `UI` uses `creature_stats_ui.gd`;
- `UI/FpsLabel` uses `debug_status_ui.gd`;
- `UI/PlayerSidePanel` uses `player_ui.gd`;
- the nature panel uses `player_nature_ui.gd`.

Rules:

- do not put counters or speed controls back into `creature_stats_ui.gd`;
- do not put detailed debug text back into `creature_stats_ui.gd`;
- F3 grid overlay and F4 text debug are separate systems;
- creature selection must remain compatible with nature-power targeting;
- dead/corpse creatures should not remain selectable.

## Startup scene

Main files:

- `res://project.godot`;
- `res://scenes/ui/start_screen.tscn`;
- `res://scripts/ui/start_screen.gd`.

Runtime flow:

1. `project.godot` starts `start_screen.tscn`.
2. New Game changes to `res://scenes/main/main.tscn`.
3. `main.tscn` instances `res://scenes/world/world.tscn`.
4. Load queries `SaveSystem` for three slots.
5. Occupied slots show date/time; empty slots are disabled.
6. Selecting a slot delegates loading to `SaveSystem`.
7. Exit closes the application.

The startup-screen `Menu` button remains a placeholder for future settings/options.

## Save system

Main file:

- `res://scripts/save/save_system.gd`.

Registration:

- `SaveSystem` is an autoload in `project.godot`.

Slot files:

- `user://dyna_save_slot_1.json`;
- `user://dyna_save_slot_2.json`;
- `user://dyna_save_slot_3.json`.

In-game UI integration:

- the existing right-side `MENU` button opens SaveSystem content;
- do not add a second duplicate in-game menu button;
- opening the menu pauses simulation;
- closing it restores the previous simulation speed;
- actions are Save, Load, Main Menu, Close Game, and Back.

Saved dynamic data includes creatures, grass, eggs, player energy, camera state, simulation speed, and save timestamp.

Static terrain is loaded from `world.tscn` and is not serialized.

Loading flow:

1. Read and validate JSON save version.
2. Ensure `main.tscn` is active.
3. Pause time during reconstruction.
4. Clear current creature, egg, and grass nodes.
5. Recreate grass and timer state.
6. Recreate eggs and blocker state.
7. Recreate creatures and mutable stats using saved species resource paths.
8. Restore player energy and camera.
9. Restore simulation speed.

Rules:

- returning to Main Menu must produce a clean New Game session;
- returning to Main Menu must not delete slot files;
- temporary corpse nodes are not persisted;
- exact animation and short-lived behaviour micro-state do not need to resume;
- changing map layout, saved schema, or species resource paths may require new saves or a version migration.

## Terrain source ids

`res://scenes/world/world.tscn` owns the active TileSet terrain sources.

Current source ids:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

Blocked terrain sources:

- water;
- mountain;
- tree.

`start_map_layout.gd` chooses water and mountain atlas variants from neighbouring terrain when it creates an empty map. Later manual edits are saved by Godot and must not be regenerated at runtime.

## Trees

Trees are TileMap terrain, not separate scenes.

Main files:

- `res://scenes/world/world.tscn`;
- `res://scripts/world/world_grid.gd`;
- `res://assets/sprites/terrain/tree_tiles_independent.png`.

Tree TileSet rules:

- source id `3`;
- normal tile region size is 128x128;
- each visual tree is assembled as a 2x2 block;
- all four occupied cells are blocked;
- grass and creatures treat tree cells as unavailable.

Do not use old object-tree files or abandoned large-tree tile assets.

## Grass lifecycle

`res://scripts/resources/grass.gd` owns:

- four-stage growth;
- stage visuals;
- edibility and stage-dependent food value;
- consumption reset;
- rain and sun reactions;
- mature-grass spreading;
- world-grid registration and unregistration.

Dependencies:

- `res://scripts/world/world_grid.gd`;
- `res://scripts/world/start_map_world_grid.gd`;
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`;
- `res://scenes/resources/grass.tscn`.

Rules:

- grass may exist and spread only on normal walkable terrain;
- initial grass nodes do not define an allowed-growth region;
- spread checks cardinal neighbouring tiles;
- prevent duplicate grass registration on the same tile;
- set a newly instantiated grass node's target position before `add_child()`;
- consumption and nature powers must use the grass lifecycle rather than bypassing it.

## Grazing target ranking

Main file:

- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`.

Rules:

- evaluate food under the full creature footprint;
- compare food quality/value with estimated travel distance;
- allow lower-stage edible grass as fallback;
- initial targeting and periodic retargeting must use the same ranking;
- do not allow consumption before the creature reaches a valid eating anchor.

## Rain cast visual

Main files:

- `res://scripts/ui/player_nature_ui.gd`;
- `res://scripts/effects/rain_target_preview.gd`;
- `res://scripts/effects/rain_cast_effect.gd`;
- `res://scenes/effects/rain_target_preview.tscn`;
- `res://scenes/effects/rain_cast_effect.tscn`;
- rain frame assets under `res://assets/sprites/effects/rain/`.

Rules:

- rain gameplay and rain visuals remain separate;
- the visual effect must not apply grass changes itself;
- playback remains independent of `Engine.time_scale`;
- preserve real alpha transparency;
- spend energy only for a valid successful cast.

## Creature highlight frame

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/ui/creature_stats_ui.gd`;
- `res://assets/ui/creature_selection_frame.png`.

Rules:

- UI owns selection intent;
- the creature owns its world-space visual overlay;
- scale the authored frame to the intended footprint;
- keep the overlay above normal world props;
- clear hover/selection state when the creature dies or disappears.

## Egg-eater behavior

Main files:

- `res://scripts/creatures/behaviors/creature_egg_eater_logic.gd`;
- `res://scripts/resources/egg.gd`;
- `res://data/species/egg_eater.tres`.

Rules:

- egg eaters are a separate diet category, not predators;
- they reuse predator-style pathing but never start duels;
- only `STAGE_2` eggs are valid targets;
- they consume an adjacent egg and restore hunger.

## Creature ground shadows

Main file:

- `res://scripts/creatures/creature.gd`.

Rules:

- a dark semi-transparent contour shadow mirrors the active static texture or animated frame below the body sprite and above terrain;
- contour shadows synchronize their animation frame and apply the horizontal correction from the active upward-diagonal texture or frame set;
- shadows are static because the game has no day/night cycle;
- predator and herbivore offsets are configured separately to fit their art;
- shadows must not affect collision, occupancy, selection, or pathfinding.

## Creature death and corpse visuals

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/creatures/creature_species_data.gd`;
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`;
- species resources under `res://data/species/`.

Rules:

- corpse visuals are non-blocking;
- dead creatures must release world-grid occupancy immediately;
- collision and picking are disabled for corpses;
- death texture and corpse lifetime belong to species data;
- do not delay occupancy release until `queue_free()`.

Species dependencies:

- the shared creature scene must remain species-agnostic;
- new species, including the pterodactyl, are added through `.tres` data and visual assets;
- do not create a separate copy of the world scene solely to assign a species;
- saves restore species through their resource paths.
- tyrannosaurus uses the shared egg lifecycle; when a species has no custom egg textures, preserve `egg.tscn`'s default textures rather than assigning `null`.
