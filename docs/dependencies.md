# Dyna — Dependencies

## World grid

`res://scripts/world/world_grid.gd` owns:

- terrain lookup;
- DryGround overlay state, deterministic visual variants, rain-hit tracking, and cleared-cell reporting for recovery;
- walkability;
- footprint placement;
- pathfinding;
- grass lookup;
- creature occupancy;
- blocker occupancy;
- counting and consuming edible grass under creature footprints.

`res://scripts/world/start_map_world_grid.gd` extends the base grid for the authored start map, spawns the fixed player base, excludes its footprint from grass spreading, and provides world bounds used by the camera.

The active world and map bootstrap are:

- `res://scenes/world/world.tscn`;
- `res://scripts/world/start_map_layout.gd`;
- `res://scripts/world/start_map_world_grid.gd`;
- `res://scripts/camera/camera_controller.gd`.

Map flow:

1. `world.tscn` creates the `Ground` TileMap and its terrain sources.
2. `start_map_layout.gd` checks whether the TileMap already has cells.
3. If the TileMap is empty, the initial 85x85 map is created.
4. If the TileMap is non-empty, the script does nothing.
5. Godot saves later manual TileMap edits in `world.tscn`.
6. The world grid initializes terrain and occupancy.
7. `start_map_world_grid.gd` places the fixed player base at `CameraStart` and reserves its 2x2 footprint.
8. The camera reads authored bounds through the world grid.

Rules:

- never clear or rebuild a non-empty map during scene startup;
- never hand-generate serialized `tile_map_data`;
- preserve terrain source ids;
- keep initial creatures, grass, eggs container, camera marker, and predator marker on valid terrain;
- keep the player-base spawn point on a valid 2x2 ground footprint;
- after major map edits, recreate saves or add migration/version handling.

If a task touches movement, blocked tiles, map dimensions, camera bounds, grass placement, the player base, corpse passability, or pathing, inspect these files together.

## Player base

Main files:

- `res://scenes/world/player_base.tscn`;
- `res://scripts/world/player_base.gd`;
- `res://scripts/world/start_map_world_grid.gd`;
- `res://scripts/world/world_grid.gd`;
- `res://assets/sprites/world/player_base.png`.

Runtime flow:

1. `start_map_world_grid.gd` instantiates one player base at the existing `CameraStart` marker.
2. `player_base.gd` converts that world position into a 2x2 anchor.
3. The base registers through `world_grid.register_blocker()`.
4. Its 512x512 texture is scaled to a 256x256 world visual with linear mipmapped filtering.
5. Pathfinding and creature placement automatically avoid the four reserved cells.
6. `can_host_grass()` rejects cells occupied by the `player_base` group.
7. The base is static setup and is not collected or reconstructed by `SaveSystem`.

Rules:

- only one node named `PlayerBase` should be spawned;
- the base remains stationary and non-passable;
- its logical footprint remains 2x2 even if the source texture resolution changes;
- moving `CameraStart` also moves the fresh-game base spawn and camera start;
- future egg-creation UI or logic should find the base through the `player_base` group rather than hard-coded node paths;
- do not add the base to dynamic save groups such as `creatures`, `eggs`, or `grass`.

## UI ownership

`res://scenes/main/main.tscn` owns active gameplay UI node wiring.

Current UI scripts:

- `res://scripts/ui/start_screen.gd` — startup menu and three-slot startup loading;
- `res://scripts/ui/creature_stats_ui.gd` — creature information, selection, and highlight coordination;
- `res://scripts/ui/player_ui.gd` — terrain minimap, diet/faction markers, player-only counters, and time-speed controls;
- `res://scripts/flags/player_flag_system.gd` — mature species-flag placement, area/candidate, and route-application helpers;
- `res://scripts/flags/player_flag_system_with_catalog.gd` — active `PlayerFlags` autoload that reads the fixed player catalog, filters non-player factions, batches route work, caches reserved targets, and tracks one-shot arrival revisions;
- `res://scripts/flags/player_flag_visual.gd` — non-blocking world-space flag and influence-area rendering;
- `res://scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug text;
- `res://scripts/ui/player_nature_ui.gd` — spell buttons, targeting, and previews;
- `res://scripts/player/player_energy.gd` — session energy reserve, spending API, and catalog-defined income from living player-faction dinosaurs;
- `res://scripts/world/nature_effects_system.gd` — world-side lightning, rain, sun, earthquake, grass effects, DryGround clearing, adjacent mature-grass timer restarts, and spell VFX application;
- `res://scripts/debug/performance_stats.gd` — F8 CSV performance logging, including separate flag scan/path counters;
- `res://scripts/debug/grid_debug_overlay.gd` — F3 grid/debug overlay.

Expected gameplay scene wiring:

- `UI` uses `creature_stats_ui.gd`;
- `UI/FpsLabel` uses `debug_status_ui.gd`;
- `UI/PlayerSidePanel` uses `player_ui.gd`;
- the nature panel uses `player_nature_ui.gd`.
- the active world owns `PlayerEnergy`; UI, egg purchases, and `SaveSystem` query it through the `player_energy` group.

Rules:

- do not put counters or speed controls back into `creature_stats_ui.gd`;
- do not put detailed debug text back into `creature_stats_ui.gd`;
- F3 grid overlay and F4 text debug are separate systems;
- creature selection must remain compatible with nature-power targeting;
- dead/corpse creatures should not remain selectable.


## Species catalog and faction ownership

Main files:

- `res://scripts/creatures/creature_species_data.gd`;
- `res://data/species/*.tres`;
- `res://scripts/creatures/creature_faction.gd`;
- `res://scripts/catalogs/player_species_catalog.gd`;
- `res://scripts/ui/player_egg_creation_ui.gd`;
- `res://scripts/player/player_energy.gd`;
- `res://scripts/flags/player_flag_system_with_catalog.gd`;
- `res://scripts/ui/player_ui.gd`;
- `res://scripts/save/save_system_with_flags.gd`;
- `res://scripts/debug/performance_stats.gd`.

Ownership layers:

1. `CreatureSpeciesData` describes the dinosaur itself: identity, diet, stats, visuals, survival, combat, and reproduction.
2. `CreatureFaction` describes runtime ownership independently: `player`, `enemy`, `alien`, or `neutral`. Untagged current entities and old save records default to `player`.
3. `PlayerSpeciesCatalog` is the single ordered fixed roster for player-only values: egg purchase cost, player energy income, flag text/tooltips, and current `PASTURE`/`GATHER` flag behaviour.
4. A future six-species enemy roster should use its own enemy catalog and may reuse the same biological species resources without inheriting player economy or player orders.

Rules:

- all current dinosaurs keep the shared 2x2 logical footprint; do not duplicate footprint size into catalogs;
- bought eggs are assigned to the player faction; naturally laid eggs inherit their parent faction; hatchlings inherit the egg faction;
- only living player-faction creatures whose species exists in `PlayerSpeciesCatalog` generate player energy;
- player flags affect only player-faction creatures in the fixed player catalog;
- changing one species flag cancels only that species routes and retry timers; other species flag work remains intact;
- flag target/path work is processed in batches of at most five creatures per 0.5-second update, and a single flag path is capped at 500 expanded tiles;
- target reservations use a tile-to-creature dictionary plus a creature-to-tiles cache instead of all-pairs target comparison;
- entering the flag area completes the current flag revision for that creature; it resumes autonomous wandering and ignores that placement after leaving until the species flag is moved or replaced;
- active flag revisions and per-creature completed revisions are optional save fields; older saves remain valid and creatures without completion data may answer an existing flag once;
- minimap category comes from `diet_type`, never from resource path text; faction selects the marker palette;
- current HUD counts only player creatures and player eggs;
- creature and egg faction ids are optional save fields, so old version-1 saves remain valid and restore missing values as player;
- `PerformanceStats` writes `flag_creatures_scanned_per_sec`, `flag_path_requests_per_sec`, and `flag_path_failures_per_sec` to new F8 CSV logs;
- future enemy spawners must assign `enemy` before the entity enters active gameplay.

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

The startup-screen `Settings` button opens Music and Sounds sliders backed by `AudioManager`.

## Audio system

Main files:

- `res://project.godot`;
- `res://default_bus_layout.tres`;
- `res://scripts/audio/audio_manager.gd`;
- `res://scripts/ui/start_screen.gd`;
- `res://scripts/save/save_system_with_flags.gd`;
- `res://scripts/world/nature_effects_system.gd`;
- `res://assets/audio/music/gameplay_theme.mp3`;
- `res://assets/audio/sfx/lightning_strike.wav`;
- `res://assets/audio/sfx/rain_cast.wav`;
- `res://assets/audio/sfx/sun_cast.wav`;
- `res://assets/audio/sfx/earthquake_cast.wav`;
- `res://assets/audio/ui/button_click.wav`.

Registration and storage:

- `AudioManager` is an autoload in `project.godot`;
- the autoload uses `PROCESS_MODE_ALWAYS` so menu pauses do not stop music fades or one-shot playback;
- the default bus layout defines `Master`, `Music`, `Sounds`, `Ambient`, `SFX`, and `UI`;
- `Ambient`, `SFX`, and `UI` send into `Sounds`;
- user-selected Music and Sounds values are stored in `user://audio_settings.cfg`, not in gameplay save slots.

Runtime flow:

1. `AudioManager` ensures the required buses and routing exist.
2. It loads saved Music and Sounds values and applies them before playback.
3. It creates one global music player, loads the gameplay MP3 once, and enables its native loop flag.
4. Entering `res://scenes/main/main.tscn` starts or fades in the gameplay track.
5. Returning to the startup screen fades the track out and stops it.
6. Startup and in-game Settings pages call the same `AudioManager` getters and setters.
7. Successful lightning, rain, sun, and earthquake casts ask `AudioManager` to create temporary `SFX` one-shot players.
8. Each one-shot player frees itself when its sound ends.
9. `AudioManager` watches scene-tree additions, connects every existing or runtime-created `BaseButton`, and plays the shared click on `button_down` through the `UI` bus.

Rules:

- do not add another gameplay-music player or audio manager to gameplay/UI scenes;
- route background music through `Music`, all player-facing non-music volume through `Sounds`, ambient loops through `Ambient`, world effects through `SFX`, and menu feedback through `UI`;
- trigger cast sounds only after gameplay validation and successful energy spending;
- earthquake audio must play only when `apply_earthquake()` actually destroys at least one egg;
- keep audio playback independent from simulation speed and save reconstruction;
- use `AudioManager.play_sfx()` or `play_ui_sfx()` for short shared sounds instead of permanent players;
- keep the shared button click global; do not attach duplicate click players or click callbacks to individual button scenes;
- replace audio files at their documented paths or update the corresponding preload/path constants;
- settings UI must call `AudioManager` rather than manipulating `AudioServer` or scene players directly.

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
- the action menu includes a `Settings` page with Music and Sounds sliders;
- do not add a second duplicate in-game menu button;
- opening the menu pauses simulation;
- closing it restores the previous simulation speed;
- actions are Save, Load, Main Menu, Close Game, and Back.

Saved dynamic data includes creatures, grass, eggs, optional creature/egg faction ids, optional per-creature completed-flag revisions, player energy, rain-cleared DryGround cells and partial hit counts, active species flags with placement revisions, camera state, simulation speed, and save timestamp. `save_system_with_flags.gd` layers these optional fields over the base `SaveSystem`; older saves without them load entities as player-owned, with no active flags, and without completed revisions.

Static base terrain and the fixed player base are loaded from start-map setup and are not serialized. Authored DryGround loads with the map; only cleared-cell and partial-hit deltas are saved.

Loading flow:

1. Read and validate the JSON schema and save version before changing the active scene.
2. Ensure `main.tscn` is active.
3. Pause time during reconstruction.
4. Clear current creature, egg, and grass nodes.
5. Restore rain-cleared DryGround cells and partial hit state.
6. Recreate grass and timer state.
7. Recreate eggs and blocker state.
8. Recreate creatures and mutable stats using saved species resource paths.
9. Preserve the already spawned static player base and its blocker registration.
10. Restore player energy, camera, and simulation speed.
11. The save extension reapplies creature/egg factions and completed-flag revisions, defaulting missing faction fields to player, before restoring player flags and their active revisions.

Rules:

- returning to Main Menu must produce a clean New Game session;
- returning to Main Menu must not delete slot files;
- temporary corpse nodes are not persisted;
- the player base is not a dynamic save entity;
- exact animation and short-lived behaviour micro-state do not need to resume, but completed flag revisions are persistent gameplay state and must resume;
- save writes must verify a temporary JSON file before replacing the live slot and retain a recoverable backup during replacement;
- invalid slots remain visible as damaged but cannot be loaded;
- adding optional faction fields must not invalidate existing version-1 saves;
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

The player base is not another terrain source. It uses world-grid blocker occupancy so its sprite can remain a separate future-interactive structure.

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

- grass may exist and spread only on normal walkable terrain and not on occupied DryGround;
- grass must not spread onto the fixed player-base footprint;
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

## Egg lifecycle and species visuals

Main files:

- `res://scenes/resources/egg.tscn`;
- `res://scripts/resources/egg.gd`;
- `res://scripts/creatures/creature_species_data.gd`;
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`;
- species resources under `res://data/species/`;
- species egg PNGs under `res://assets/sprites/creatures/<species>/`.

Current custom egg sets exist for:

- stegosaurus;
- triceratops;
- tyrannosaurus;
- raptor;
- pterodactyl;
- egg eater.

Rules:

- use the shared egg scene and lifecycle for all species;
- store stage-1 and stage-2 texture references in the species `.tres`;
- do not duplicate `egg.tscn` per species;
- when a species provides custom textures, assign both stages;
- when custom textures are absent, preserve the defaults from `egg.tscn` rather than assigning `null`;
- stage changes, blocking, hatching, saving/restoration of the hatch scene and species visuals, faction inheritance, egg-eater targeting, and earthquake destruction must remain independent of the selected visuals;
- naturally laid eggs inherit the parent faction, player-base eggs are explicitly player-owned, and hatchlings inherit the egg faction;
- earthquake destroys both egg stages through the egg lifecycle so a stage-2 blocker is released normally;
- renaming or moving species egg assets requires updating their `.tres` references.

## Rain cast visual

Main files:

- `res://scripts/ui/player_nature_ui.gd`;
- `res://scripts/world/nature_effects_system.gd`;
- `res://scripts/effects/rain_target_preview.gd`;
- `res://scripts/effects/rain_cast_effect.gd`;
- `res://scenes/effects/rain_target_preview.tscn`;
- `res://scenes/effects/rain_cast_effect.tscn`;
- rain frame assets under `res://assets/sprites/effects/rain/`.

Rules:

- `player_nature_ui.gd` owns rain targeting and preview, while `nature_effects_system.gd` owns successful rain gameplay and cast VFX;
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
- they consume an adjacent egg and restore hunger;
- changing egg visuals must not change egg stage identity or targeting rules.

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
- saves restore species through their resource paths;
- species-specific egg visuals remain data references and do not require separate creature or egg scenes.
