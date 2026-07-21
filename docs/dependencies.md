# Dyna — Dependencies and Invariants

This is the detailed change-safety map for a new agent: runtime flows, ownership boundaries, stable IDs, compatibility rules, and invariants that must survive refactoring.
Some critical facts intentionally repeat `current-state.md` or `project-map.md`; this redundancy is defensive and should not be removed merely to reduce line count.

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

`res://scripts/world/start_map_world_grid.gd` extends the base grid for the authored start map, spawns both fixed faction bases, excludes both footprints from grass spreading, and provides world bounds used by the camera.

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
8. The same script places the fixed enemy base at an optional `EnemyBaseStart` child marker; until that marker is authored in Godot, it resolves a deterministic nearest-valid 2x2 anchor near the opposite map edge.
9. The camera reads authored bounds through the world grid and compensates for `Engine.time_scale`, so observer movement remains real-time at every simulation speed.

Rules:

- never clear or rebuild a non-empty map during scene startup;
- never hand-generate serialized `tile_map_data`;
- preserve terrain source ids;
- keep authored grass, the eggs container, the camera marker, and both base spawn regions on valid terrain;
- keep the player-base spawn point on a valid 2x2 ground footprint;
- when an authored `EnemyBaseStart` marker is later added in Godot, keep it on a valid 2x2 ground footprint;
- the runtime enemy fallback must search existing terrain only and must never modify the TileMap;
- after major map edits, recreate saves or add migration/version handling;
- do not multiply camera movement by simulation speed or remove its time-scale compensation.

If a task touches movement, blocked tiles, map dimensions, camera bounds, grass placement, either faction base, corpse passability, or pathing, inspect these files together.

## Faction bases

Main files:

- `res://scenes/world/player_base.tscn`;
- `res://scenes/world/enemy_base.tscn`;
- `res://scripts/world/faction_base.gd`;
- `res://scripts/world/player_base.gd`;
- `res://scripts/world/enemy_base.gd`;
- `res://scripts/world/start_map_world_grid.gd`;
- `res://scripts/world/world_grid.gd`;
- `res://assets/sprites/world/player_base.png`.

Shared runtime flow:

1. `start_map_world_grid.gd` instantiates one player base and one enemy base.
2. Each faction-specific wrapper sets its faction before the inherited `_ready()` runs.
3. `faction_base.gd` converts the requested world position into a 2x2 anchor.
4. If the requested footprint is blocked, it asks the world grid for a nearby valid anchor.
5. The base registers through `world_grid.register_blocker()`.
6. Its current 512x512 texture is scaled to a 256x256 world visual with linear mipmapped filtering.
7. Pathfinding and creature placement automatically avoid the four reserved cells.
8. `can_host_grass()` rejects cells occupied by any node in the `faction_base` group.
9. Both bases are static setup and are not collected or reconstructed by `SaveSystem`.

Player-specific flow:

- `player_base.gd` preserves the stable `create_player_egg()` API used by `player_egg_creation_ui.gd`;
- the inherited common method searches a free stage-1 footprint, creates the shared egg scene, assigns the selected player resource, and marks the egg as `player` before adding it to the world.

Enemy-specific flow:

- `enemy_base.gd` exposes `create_enemy_egg()` as a thin wrapper over the same safe common placement method;
- nothing calls that method automatically yet;
- enemy energy, production timers, population choices, priorities, attack plans, and all other strategic AI belong to a later system rather than `FactionBase`.

Rules:

- only one node named `PlayerBase` and one node named `EnemyBase` should be spawned;
- both bases remain stationary and non-passable;
- both logical footprints remain 2x2 even if either source texture resolution changes;
- moving `CameraStart` also moves the fresh-game player base and camera start;
- prefer an authored `EnemyBaseStart` marker for final map composition, but add or move it only through Godot rather than hand-editing TileMap serialization;
- player egg UI must continue finding the player base through the `player_base` group and using `create_player_egg()`;
- future enemy production logic must find the enemy base through the `enemy_base` group and use `create_enemy_egg()` or the inherited `create_faction_egg()` API;
- shared blocker, visual, and nearby egg-placement changes belong in `faction_base.gd`, not duplicated in both wrappers;
- do not add either base to dynamic save groups such as `creatures`, `eggs`, or `grass`;
- do not add strategic decision-making to the base scene.

## UI ownership

`res://scenes/main/main.tscn` only instances the gameplay HUD. Physical gameplay UI ownership is split across `res://scenes/ui/player_hud.tscn`, `res://scenes/ui/creature_info_panel.tscn`, and `res://scenes/ui/nature_menu.tscn`.

Current UI scripts:

- `res://scripts/ui/start_screen.gd` — startup menu and three-slot startup loading;
- `res://scripts/ui/creature_stats_ui.gd` — creature information, selection, and highlight coordination;
- `res://scripts/ui/player_ui.gd` — terrain minimap, diet/faction markers, player-only counters, and time-speed controls;
- `res://scripts/flags/player_flag_system.gd` — compact facade for scene attachment, placed flag records, visual sync, and stable save/debug entry points;
- `res://scripts/flags/player_flag_system_with_catalog.gd` — active `PlayerFlags` autoload layer that supplies the player catalog and placement revisions;
- `res://scripts/flags/player_flag_ui_controller.gd` — flag submenu, targeting input, preview, and status text;
- `res://scripts/flags/player_flag_assignment_service.gd` — creature eligibility, first-route batching, commitment resume, retries, completion, and F3 status;
- `res://scripts/flags/player_flag_target_allocator.gd` — 11x11 target selection, pasture preference, reservations, and retry rotation;
- `res://scripts/flags/player_flag_visual.gd` — non-blocking world-space flag and influence-area rendering;
- `res://scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug text;
- `res://scripts/ui/player_nature_ui.gd` — spell buttons, targeting, previews, and the stable access API for nested nature-menu controls;
- `res://scripts/player/player_energy.gd` — session energy reserve, spending API, and catalog-defined income from living player-faction dinosaurs;
- `res://scripts/world/nature_effects_system.gd` — world-side lightning, rain, sun, earthquake, grass effects, DryGround clearing, adjacent mature-grass timer restarts, and spell VFX application;
- `res://scripts/debug/performance_stats.gd` — F8 CSV performance logging, including separate flag scan/path counters;
- `res://scripts/debug/grid_debug_overlay.gd` — F3 grid/debug overlay with selected-creature flag status and assigned flag destination.

Expected gameplay scene wiring:

- `main.tscn/UI` is an instance of `player_hud.tscn`;
- `player_hud.tscn/CreatureStatsPanel` is an instance of `creature_info_panel.tscn`, whose root uses `creature_stats_ui.gd`;
- `player_hud.tscn/FpsLabel` uses `debug_status_ui.gd`;
- `player_hud.tscn/PlayerSidePanel` uses `player_ui.gd`;
- `player_hud.tscn/.../PlayerNaturePanel` is an instance of `nature_menu.tscn`, whose root uses `player_nature_ui.gd`;
- the active world owns `PlayerEnergy`; UI, egg purchases, and `SaveSystem` query it through the `player_energy` group.

Rules:

- do not put counters or speed controls back into `creature_stats_ui.gd`;
- do not put detailed debug text back into `creature_stats_ui.gd`;
- F3 grid overlay and F4 text debug are separate systems; F3 may query `PlayerFlags` through its public debug-data method but must not own flag behaviour;
- creature selection must remain compatible with nature-power targeting;
- SaveSystem, player flags, egg creation, and player time controls must resolve nested nature-menu controls through the `player_nature_ui` group API, not paths through `UI/PlayerSidePanel/MarginContainer/...`;
- keep `main.tscn` as a compositor rather than moving HUD styles or deep UI node trees back into it;
- preserve the root instance names `UI`, `CreatureStatsPanel`, and `PlayerNaturePanel` when rearranging the split scenes so old diagnostic paths remain readable;
- dead/corpse creatures should not remain selectable.

## Player species flags

Main files:

- `res://scripts/flags/player_flag_system.gd`;
- `res://scripts/flags/player_flag_system_with_catalog.gd`;
- `res://scripts/flags/player_flag_ui_controller.gd`;
- `res://scripts/flags/player_flag_assignment_service.gd`;
- `res://scripts/flags/player_flag_target_allocator.gd`;
- `res://scripts/flags/player_flag_visual.gd`.

Ownership rules:

- the base facade owns placed flag data, scene attachment, world-visual synchronization, and public save/debug methods;
- the catalog wrapper owns player-species validation and per-placement revisions;
- the UI controller owns menu controls, mouse targeting, placement/removal input, preview, and user-facing status text;
- the assignment service owns creature scanning, five-new-route batching, commitments, pauses, retries, arrival completion, and F3 status data;
- the target allocator owns destination candidates, 11x11 bounds, pasture preference, tile reservations, and retry destination rotation;
- only the creature indirect-order API may mutate creature routes or FSM-related movement fields;
- save files keep the same flag records and completion-revision metadata; this split does not change save format.

## Creature movement and indirect orders

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/creatures/behaviors/creature_movement_controller.gd`;
- `res://scripts/flags/player_flag_system_with_catalog.gd`.

Rules:

- `creature.gd` remains the public facade for route and state transitions;
- `creature_movement_controller.gd` owns grid-step execution, queued-route mutation, and indirect-order route apply/pause/cancel operations;
- active flag code must call the creature indirect-order API instead of setting `current_path`, `state_timer`, `state`, `has_grazing_target`, `food_recheck_timer`, or `grazing_candidate_queue`;
- survival, food, reproduction, and combat remain higher priority than indirect orders;
- enemy creatures use the same movement controller and autonomous FSM; do not create an enemy-only movement or survival copy.

## Creature visual and interaction boundaries

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`;
- `res://scripts/creatures/behaviors/creature_interaction_controller.gd`;
- `res://scripts/ui/creature_stats_ui.gd`.

Rules:

- `creature.gd` remains the public facade and owns FSM state plus the ordered death-cleanup sequence;
- `creature_visual_controller.gd` owns directional sprites, animation playback, contour-shadow nodes/frame synchronization, and applying the species death pose;
- resources with no valid animation frames automatically fall back to static directional textures; enemy resource scaffolds intentionally rely on this path until their animation assets exist;
- `creature_interaction_controller.gd` owns the highlight sprite and `HoverArea` signal handling, but forwards selection and lightning intent to `creature_stats_ui.gd` rather than owning UI state;
- UI callers continue using `set_hover_highlighted()`, `set_selected_highlighted()`, and `clear_interaction_highlights()` on the creature facade;
- neither controller may change survival, combat, reproduction, occupancy, or pathfinding rules.

## Species catalog and faction ownership

Main files:

- `res://scripts/creatures/creature_species_data.gd`;
- player resources under `res://data/species/*.tres`;
- enemy resources under `res://data/species/enemy/*.tres`;
- `res://scripts/creatures/creature_faction.gd`;
- `res://scripts/catalogs/player_species_catalog.gd`;
- `res://scripts/catalogs/enemy_species_catalog.gd`;
- `res://scripts/ui/player_egg_creation_ui.gd`;
- `res://scripts/player/player_energy.gd`;
- `res://scripts/flags/player_flag_system_with_catalog.gd`;
- `res://scripts/ui/player_ui.gd`;
- `res://scripts/save/save_system_with_flags.gd`;
- `res://scripts/debug/performance_stats.gd`.

Ownership layers:

1. `CreatureSpeciesData` describes one biological/resource variant: identity, diet, stats, visuals, survival, combat, and reproduction. `diet_type` is the single stored nutrition source; systems query it through `is_herbivore()`, `is_predator()`, and `is_egg_eater()`.
2. `CreatureFaction` describes runtime ownership independently and validates exactly `player`, `enemy`, or `neutral`. Untagged current entities and old save records default to `player`; unknown non-empty ids normalize to `neutral`.
3. `PlayerSpeciesCatalog` is the single ordered fixed roster for player-only values: egg purchase cost, player energy income, flag text/tooltips, and current `PASTURE`/`GATHER` flag behaviour.
4. `EnemySpeciesCatalog` is the fixed six-species enemy roster and selects enemy-specific resource paths only. Enemy economy, population goals, production priorities, production cadence, and strategic AI do not belong in this catalog and are not implemented yet.
5. Player and enemy variants deliberately keep the same biological `species_id`; the distinct `.tres` resource path chooses the visuals/stats variant, while `CreatureFaction` chooses ownership.

Current enemy resource rules:

- every enemy species has a separate resource under `data/species/enemy/`;
- its effective balance values currently match the corresponding player resource;
- it currently reuses the player's directional sprites and two egg textures;
- it does not reference walk or eating `SpriteFrames`, so the shared visual controller uses static directional poses;
- it uses the shared `creature.tscn`, `egg.tscn`, movement, survival, reproduction, combat, saving, and UI-observation paths;
- later art/stat changes should edit only the relevant enemy resource and asset paths rather than branching creature code.

Rules:

- all current dinosaurs keep the shared 2x2 logical footprint; do not duplicate footprint size into catalogs;
- bought eggs are assigned to the player faction; naturally laid eggs inherit their parent faction; hatchlings inherit the egg faction;
- a future enemy-base-created egg must be assigned `enemy` before it is added to active gameplay; `FactionBase` already performs this when called through the enemy wrapper;
- only living player-faction creatures whose species exists in `PlayerSpeciesCatalog` generate player energy;
- player flags affect only player-faction creatures in the fixed player catalog;
- player flags may read creature navigation/species data, but route application, food interruption, route cancellation, and related FSM mutations must go through the creature indirect-order API;
- changing one species flag cancels only that species routes and retry timers; other species flag work remains intact;
- first-time flag target/path work is processed in batches of at most five creatures per 0.5-second update, while creatures already committed to the current placement resume after food, reproduction, or combat outside that initial batch; a single flag path is capped at 1800 expanded tiles, and failed attempts rotate through alternative valid destinations instead of retrying the same tile forever;
- target reservations use a tile-to-creature dictionary plus a creature-to-tiles cache instead of all-pairs target comparison;
- the first successful route marks an in-session commitment to the current flag revision; temporary higher-priority behaviour pauses the route without discarding that commitment, and entering the flag area completes the revision so the creature resumes autonomous wandering and ignores that placement after leaving until the species flag is moved or replaced;
- active flag revisions and per-creature completed revisions are optional save fields; older saves remain valid and creatures without completion data may answer an existing flag once;
- minimap category comes from `diet_type`, never from resource path text; faction selects the marker palette;
- current HUD counts only player creatures and player eggs;
- creature and egg faction ids are optional save fields, so old version-1 saves remain valid and restore missing values as player;
- a removed or otherwise unknown non-empty faction id restores as neutral;
- `PerformanceStats` writes `flag_creatures_scanned_per_sec`, `flag_path_requests_per_sec`, and `flag_path_failures_per_sec` to new F8 CSV logs;
- do not introduce a fourth faction id without an explicit architecture change and matching save/UI/combat review.

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

Static base terrain and both fixed faction bases are loaded from start-map setup and are not serialized. Authored DryGround loads with the map; only cleared-cell and partial-hit deltas are saved. The enemy base currently has no health, energy, production timer, or other mutable state to persist.

Loading flow:

1. Read and validate the JSON schema and save version before changing the active scene.
2. Ensure `main.tscn` is active.
3. Pause time during reconstruction.
4. Clear current creature, egg, and grass nodes.
5. Restore rain-cleared DryGround cells and partial hit state.
6. Recreate grass and timer state.
7. Recreate eggs and blocker state.
8. Recreate creatures and mutable stats using saved species resource paths.
9. Preserve the already spawned static player and enemy bases and their blocker registrations.
10. Restore player energy, camera, and simulation speed.
11. The save extension reapplies creature/egg factions and completed-flag revisions, defaulting missing faction fields to player and unknown non-empty ids to neutral, before restoring player flags and their active revisions.

Rules:

- returning to Main Menu must produce a clean New Game session;
- returning to Main Menu must not delete slot files;
- temporary corpse nodes are not persisted;
- neither faction base is a dynamic save entity at this stage;
- exact animation and short-lived behaviour micro-state do not need to resume, but completed flag revisions are persistent gameplay state and must resume;
- save writes must verify a temporary JSON file before replacing the live slot and retain a recoverable backup during replacement;
- invalid slots remain visible as damaged but cannot be loaded;
- adding optional faction fields must not invalidate existing version-1 saves;
- changing map layout, saved schema, or species resource paths may require new saves or a version migration;
- enemy species resources must keep stable paths after saves begin containing enemy creatures or require a migration;
- when mutable base health or enemy production state is later added, update save collection/restoration explicitly rather than putting bases into generic creature/egg groups.

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

Faction bases are not terrain sources. They use world-grid blocker occupancy so their sprites can remain separate future-interactive structures.

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
- grass must not spread onto either fixed faction-base footprint;
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
- `res://scripts/world/faction_base.gd`;
- player species resources under `res://data/species/`;
- enemy species resources under `res://data/species/enemy/`;
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
- use the same 5-second stage 1, 1-second expansion retry, and 10-second stage 2 for every species and faction;
- keep those three timing values only in `scripts/resources/egg.gd`; species resources may define egg textures and hatchling biology but never incubation speed;
- store stage-1 and stage-2 texture references in the species `.tres`;
- do not duplicate `egg.tscn` per species or faction;
- when a species provides custom textures, assign both stages;
- when custom textures are absent, preserve the defaults from `egg.tscn` rather than assigning `null`;
- stage changes, blocking, hatching, saving/restoration of the hatch scene and species visuals, faction inheritance, egg-eater targeting, and earthquake destruction must remain independent of the selected visuals;
- naturally laid eggs inherit the parent faction, player-base eggs are explicitly player-owned, future enemy-base eggs are explicitly enemy-owned, and hatchlings inherit the egg faction;
- the shared `FactionBase` creation method must assign faction and species data before `add_child()` starts the egg lifecycle;
- earthquake destroys both egg stages through the egg lifecycle so a stage-2 blocker is released normally;
- renaming or moving species egg assets requires updating both player and enemy `.tres` references that use them.

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
- spend energy only for a valid successful cast; if `apply_*()` still returns `false` after the pre-check, immediately refund the exact cost through the existing `add_energy()` API; do not add reservation state for spell casts.

## Creature highlight frame

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/creatures/behaviors/creature_interaction_controller.gd`;
- `res://scripts/ui/creature_stats_ui.gd`;
- `res://assets/ui/creature_selection_frame.png`.

Rules:

- UI owns selection intent;
- `creature_interaction_controller.gd` owns the world-space overlay and mouse signal bridge;
- `creature.gd` preserves the public highlight methods used by UI;
- scale the authored frame to the intended footprint;
- keep the overlay above normal world props;
- clear hover/selection state when the creature dies or disappears.

## Egg-eater behavior

Main files:

- `res://scripts/creatures/behaviors/creature_egg_eater_logic.gd`;
- `res://scripts/resources/egg.gd`;
- `res://data/species/egg_eater.tres`;
- `res://data/species/enemy/egg_eater.tres`.

Rules:

- egg eaters are a separate diet category, not predators;
- they reuse predator-style pathing but never start duels;
- only `STAGE_2` eggs are valid targets;
- they consume an adjacent egg and restore hunger;
- while hungry, they recheck valid egg targets every 0.5 seconds and switch only if another target is at least two tile steps closer; switching clears queued old-route steps but never interrupts the active grid step;
- hunger overrides a player species flag, while a satiated player egg eater keeps its independent flag route;
- enemy egg eaters use the same food logic but never receive player flag routes;
- changing egg visuals must not change egg stage identity or targeting rules.

## Creature ground shadows

Main file:

- `res://scripts/creatures/behaviors/creature_visual_controller.gd`.

Rules:

- a dark semi-transparent contour shadow mirrors the active static texture or animated frame below the body sprite and above terrain;
- contour shadows synchronize their animation frame and apply the horizontal correction from the active upward-diagonal texture or frame set;
- shadows are static because the game has no day/night cycle;
- predator and herbivore offsets are configured separately to fit their art;
- enemy resources without animations must still synchronize shadows from the active static directional texture;
- shadows must not affect collision, occupancy, selection, or pathfinding.

## Creature death and corpse visuals

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/creatures/creature_species_data.gd`;
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`;
- player and enemy species resources under `res://data/species/`.

Rules:

- corpse visuals are non-blocking;
- dead creatures must release world-grid occupancy immediately;
- collision and picking are disabled for corpses;
- death texture and corpse lifetime belong to species data;
- when no death texture exists, the visual controller may fall back to the species right-facing texture;
- `creature.gd` owns death sequencing and occupancy/collision cleanup, while `creature_visual_controller.gd` owns only the displayed death pose and its synchronized shadow;
- do not delay occupancy release until `queue_free()`.

Species dependencies:

- the shared creature scene must remain species- and faction-agnostic;
- new player or enemy variants are added through `.tres` data and visual assets;
- do not create a separate creature scene, egg scene, movement script, survival script, or world copy solely for the enemy roster;
- saves restore the exact player/enemy resource variant through its resource path and ownership through the faction field;
- species-specific egg visuals remain data references and do not require separate creature or egg scenes;
- changing enemy art later should replace enemy resource references, not alter the shared player resource or common behaviour code.
