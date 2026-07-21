# Dyna Project Map

This document is the repository path and ownership index. It is intentionally descriptive enough for a new agent to locate systems without searching the whole project.
Implemented behaviour belongs in `docs/current-state.md`; fragile contracts belong in `docs/dependencies.md`.

## Project root

- `project.godot` — Godot project config. Startup scene is `scenes/ui/start_screen.tscn`; `AudioManager`, `PerformanceStats`, the catalog-backed `PlayerFlags`, and the enemy-state-aware `SaveSystem` extension are autoloads.
- `default_bus_layout.tres` — shared `Master`, `Music`, `Sounds`, `Ambient`, `SFX`, and `UI` audio-bus layout.
- `AGENTS.md` — working rules and architecture briefing for agents.
- `docs/project-map.md` — project structure and file ownership.
- `docs/current-state.md` — current implemented systems and prototype status.
- `docs/dependencies.md` — practical dependency and fragile-flow map.
- `docs/design_roadmap.md` — broader design roadmap; do not edit unless explicitly requested.

## Key scenes

- `scenes/ui/start_screen.tscn` — centered semi-transparent startup menu over a full-screen illustrated Dyna Brazzers background, with New Game, three-slot Load, audio Settings, and Exit.
- `scenes/main/main.tscn` — small gameplay compositor containing the camera, `player_hud.tscn` instance, simulation root, world instance, and grid debug overlay.
- `scenes/ui/player_hud.tscn` — gameplay CanvasLayer with the creature-info instance, FPS/debug label, right-side minimap, entity counters, and nature-menu instance.
- `scenes/ui/creature_info_panel.tscn` — self-contained selected/hovered creature information panel with health and hunger templates.
- `scenes/ui/nature_menu.tscn` — self-contained player energy, time controls, named main-menu buttons, spell buttons, and host area used by runtime egg, flag, and save menus.
- `scenes/world/world.tscn` — only active gameplay world: 85x85 base terrain TileMap, a DryGround overlay with three variants, initial grass, an empty creature container, eggs container, camera marker, and world grid.
- `scenes/world/player_base.tscn` — fixed 2x2 player nature base, spawned at the authored `CameraStart` marker and used as the origin for player-created eggs.
- `scenes/world/enemy_base.tscn` — fixed 2x2 enemy base using its dedicated `enemy_base.png` visual; it is spawned near the opposite map edge or at an authored `EnemyBaseStart` marker and serves the temporary five-second egg producer.
- `scenes/resources/grass.tscn` — grass resource scene with four growth-stage textures.
- `scenes/resources/egg.tscn` — shared two-stage egg scene used by all reproducing species.
- `scenes/creatures/creature.tscn` — shared base creature scene.
- `scenes/debug/grid_debug_overlay.tscn` — F3 grid/debug overlay.
- `scenes/effects/lightning_strike_effect.tscn` — lightning effect.
- `scenes/effects/rain_target_preview.tscn` — rain targeting preview.
- `scenes/effects/rain_cast_effect.tscn` — four-frame rain cast animation.
- `scenes/effects/sun_target_preview.tscn` — sun targeting preview.
- `scenes/effects/earthquake_target_preview.tscn` — earthquake targeting preview.

## Key scripts

### World and camera

- `scripts/world/world_grid.gd` — terrain lookup, DryGround overlay/rain-hit state, walkability, occupancy, blockers, pathfinding, grass lookup, and footprint queries.
- `scripts/world/start_map_world_grid.gd` — extends the base grid for the authored start map, spawns the player and enemy bases, protects both footprints from grass spreading, and exposes world bounds to the camera. The enemy base uses `EnemyBaseStart` when present and otherwise chooses a deterministic valid fallback near the opposite map edge without rewriting `world.tscn`.
- `scripts/world/faction_base.gd` — shared stationary 2x2 base foundation: faction assignment, blocker registration, visual scaling, nearby egg-footprint search, and faction-owned egg creation plumbing.
- `scripts/world/player_base.gd` — thin player wrapper over `FactionBase`; preserves the existing `create_player_egg()` API used by the player egg menu.
- `scripts/world/enemy_base.gd` — thin enemy wrapper over `FactionBase`; exposes `create_enemy_egg()` to the temporary enemy production controller while keeping strategic decisions outside the base.
- `scripts/world/start_map_layout.gd` — builds the initial 85x85 terrain only when the `Ground` TileMap is empty; chooses matching water and mountain edge variants.
- `scripts/camera/camera_controller.gd` — single owner of the 0.3–2.0 zoom limits, real-time observer movement independent of simulation speed, loaded-zoom normalization, new-game start marker, and map-bound clamping; `main.tscn` stores only the starting zoom.

### Creatures and resources

- `scripts/creatures/creature.gd` — creature runtime coordinator and public facade for FSM state, survival, movement, combat, reproduction, death cleanup, visuals, and interaction.
- `scripts/creatures/creature_species_data.gd` — shared biological species resource schema; `diet_type` is the sole stored nutrition category and helper methods classify herbivores, predators, and egg eaters.
- `scripts/creatures/creature_faction.gd` — validated runtime faction ownership helper (`player`, `enemy`, `neutral`) kept separate from species identity. Untagged current entities default to player; unknown or removed non-empty faction ids normalize to neutral.
- `scripts/catalogs/player_species_catalog.gd` — ordered fixed catalog of the six player species with player-only egg prices, energy income, flag text, and current flag behaviour category.
- `scripts/catalogs/enemy_species_catalog.gd` — fixed six-species enemy roster with enemy-specific resources, mirrored egg costs, and per-creature enemy-energy income; strategic population priorities remain future work.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore food search and target ranking.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — shared carnivore targeting and combat-entry logic.
- `scripts/creatures/behaviors/creature_egg_eater_logic.gd` — stage-2 egg targeting, periodic retargeting, and consumption logic.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction and egg spawning.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional visuals, animations, contour-ground-shadow creation/synchronization, and death pose. Enemy resources currently omit animation frame resources and therefore use static directional sprites.
- `scripts/creatures/behaviors/creature_interaction_controller.gd` — world-space hover/selection frame, `HoverArea` mouse signals, and the creature-to-UI click bridge.
- `scripts/creatures/behaviors/creature_movement_controller.gd` — grid-step execution, route clearing, wandering-step selection, and the creature-owned API used by indirect external orders.
- `scripts/combat/duel.gd` — temporary one-on-one combat loop.
- `scripts/resources/grass.gd` — grass growth, consumption, spread, and nature-power reactions.
- `scripts/resources/egg.gd` — egg stages, species texture application, blocker handling, hatching, and the single shared 5/1/10-second incubation schedule used by every species and faction.

### Audio

- `scripts/audio/audio_manager.gd` — global gameplay-music playback, one-shot sound playback, automatic existing/runtime button-click wiring, scene-based fades, audio-bus bootstrap, persistent audio settings, and public Music/Sounds controls.

### UI, effects, saving, and debug

- `scripts/ui/start_screen.gd` — startup menu, slot loading, and runtime-built Music/Sounds settings controls.
- `scripts/ui/creature_stats_ui.gd` — script owned by the root `PanelContainer` of `creature_info_panel.tscn`; handles creature information, hover, selection, and the lightning click bridge.
- `scripts/ui/player_ui.gd` — script on `player_hud.tscn`'s right-side panel; handles interactive terrain minimap generation, diet/faction markers, player-only counters, camera viewport display/click navigation, time controls, and egg-controller bootstrap.
- `scripts/ui/player_egg_creation_ui.gd` — runtime egg submenu presentation, button availability, and base purchase requests using the player species catalog; nested host controls come from the nature-menu API.
- `scripts/flags/player_flag_system.gd` — compact flag facade for gameplay-scene attachment, placed-flag data, visual synchronization, and stable save/debug entry points.
- `scripts/flags/player_flag_system_with_catalog.gd` — active `PlayerFlags` autoload layer that supplies player-catalog menu entries and placement revisions, then delegates UI and creature assignment to dedicated services.
- `scripts/flags/player_flag_ui_controller.gd` — runtime flag submenu, mouse placement/removal targeting, preview updates, and status text.
- `scripts/flags/player_flag_assignment_service.gd` — player-faction filtering, five-new-route batching, immediate committed-route resume, retries, completion revisions, and F3 status data.
- `scripts/flags/player_flag_target_allocator.gd` — target selection within the 11x11 area, pasture preference, per-creature tile reservation, and retry destination rotation.
- `scripts/flags/player_flag_visual.gd` — non-blocking world-space flag, 11x11 area, and placement-preview drawing.
- `scripts/ui/player_nature_ui.gd` — script on `nature_menu.tscn`; owns spell controls, targeting, previews, named menu-button lookup, and the stable access API used by dynamic menus and time controls.
- `scripts/player/player_energy.gd` — session energy reserve, spending API, and catalog-defined income from living player-faction dinosaurs only.
- `scripts/enemies/enemy_energy.gd` — session enemy reserve starting at 5000, spending API, and catalog-defined income from living enemy-faction creatures.
- `scripts/enemies/enemy_egg_production_controller.gd` — temporary five-second round-robin enemy egg producer; strategic AI will replace this deterministic scaffold later.
- `scripts/world/nature_effects_system.gd` — world-side lightning, rain, sun, earthquake, grass effects, DryGround clearing, adjacent mature-grass timer restarts, spell VFX application, and successful-cast sound triggers.
- `scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem/Enemy Enka line and F4 detailed debug.
- `scripts/save/save_system.gd` — base three-slot JSON persistence with temporary-write verification, backup recovery, in-game menu integration, and runtime reconstruction.
- `scripts/save/save_system_with_flags.gd` — save extension for creature/egg factions, flag revisions, player species flags, and in-game audio settings.
- `scripts/save/save_system_with_enemy.gd` — final active save layer that adds optional enemy energy and temporary egg-production cursor/timer state.
- `scripts/debug/performance_stats.gd` — runtime counters and F8 CSV logging, including separate player-flag scan, path-request, and path-failure columns.
- `scripts/debug/grid_debug_overlay.gd` — F3 visualization of terrain, occupancy, footprints, paths, and the selected creature's current flag state/target.
- `scripts/effects/` — effect playback and target-preview scripts.

## Save files

Save slots are stored outside the project in Godot's `user://` directory:

- `user://dyna_save_slot_1.json`
- `user://dyna_save_slot_2.json`
- `user://dyna_save_slot_3.json`

Audio settings are stored separately in `user://audio_settings.cfg`.

On Windows this normally resolves to:

`%APPDATA%/Godot/app_userdata/Dyna/`

Static base terrain and both fixed faction bases are not included in these files. The authored DryGround overlay loads with the map; rain-cleared cells and partial hit counts are stored as deltas. Creature and egg factions are optional save fields, so older saves load them as player-owned. Active species flags remain lightweight tile records. Enemy energy plus the temporary production cursor and remaining timer are optional saved state.

## Terrain assets

- `assets/maps/start_map_layout.png` — original map-layout reference; it is not read as runtime terrain.
- `assets/sprites/terrain/ground.png` — ground tile.
- `assets/sprites/terrain/water_tiles_independent.png` — water and shore variants.
- `assets/sprites/terrain/mountain_tiles_independent.png` — mountain interior, edge, and corner variants.
- `assets/sprites/terrain/tree_tiles_independent.png` — four trees split into normal 128x128 TileMap pieces.
- `assets/sprites/terrain/grass_stage_1.png` ... `grass_stage_4.png` — grass growth-stage sprites.
- `assets/sprites/terrain/dry_ground/dry_ground_01.png` ... `dry_ground_03.png` — 128x128 DryGround overlay variants.

Terrain source ids in `world.tscn`:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

The world scene has source-id base terrain plus a DryGround overlay. The minimap reads terrain ids, displays DryGround separately, overlays the camera viewport, and draws 6x6 markers from each creature's `diet_type` and faction. Current player colours remain light green/red/blue; a separate enemy palette is prepared. HUD counters remain player-only.

## UI assets

- `assets/ui/start_screen_background.png` — 1920x1080 illustrated background used by the startup scene.

## Audio assets

- `assets/audio/music/gameplay_theme.mp3` — first looping gameplay background track, played globally through the `Music` bus.
- `assets/audio/sfx/lightning_strike.wav` — lightning cast sound, played as a one-shot through the `SFX` bus.
- `assets/audio/sfx/rain_cast.wav` — successful rain-cast sound, played as a one-shot through the `SFX` bus.
- `assets/audio/sfx/sun_cast.wav` — successful sun-cast sound, played as a one-shot through the `SFX` bus.
- `assets/audio/sfx/earthquake_cast.wav` — successful earthquake sound, played once after at least one egg is destroyed.
- `assets/audio/ui/button_click.wav` — short generated menu click, played automatically through the `UI` bus for every enabled button.

## Effect assets

- `assets/sprites/effects/rain/rain_cast_01.png` ... `rain_cast_04.png` — transparent rain animation frames.
- `assets/ui/creature_selection_frame.png` — world-space creature hover/selection frame.

## Faction-base assets

- `assets/sprites/world/player_base.png` — 512x512 transparent player-base source sprite displayed at 256x256 in world space with mipmapped linear filtering.
- `assets/sprites/world/enemy_base.png` — 512x512 transparent enemy-base source sprite displayed at 256x256 through the same shared base-scaling logic.

## Creature and species assets

Player resources:

- `data/species/stegosaurus.tres` — stegosaurus stats, visuals, animations, egg data, and death settings.
- `data/species/triceratops.tres` — triceratops stats, directional visuals, and custom egg textures.
- `data/species/tyrannosaurus.tres` — tyrannosaurus stats, visuals, and custom egg textures.
- `data/species/raptor.tres` — raptor stats, visuals, and custom egg textures.
- `data/species/pterodactyl.tres` — pterodactyl stats, visuals, and custom egg textures.
- `data/species/egg_eater.tres` — egg-eater stats, visuals, and custom egg textures.

Enemy resources:

- `data/species/enemy/stegosaurus.tres`;
- `data/species/enemy/triceratops.tres`;
- `data/species/enemy/tyrannosaurus.tres`;
- `data/species/enemy/raptor.tres`;
- `data/species/enemy/pterodactyl.tres`;
- `data/species/enemy/egg_eater.tres`.

The six enemy resources currently copy the effective player balance values and reuse the existing directional and two-stage egg PNGs. They intentionally do not reference walk/eat animation frame resources; static directional sprites are used until enemy-specific art is supplied. Enemy and player resources keep the same biological `species_id`, while their distinct resource paths and runtime faction ids keep save restoration and ownership separate.

Current visual folders:

- `assets/sprites/creatures/stegosaurus/` — stegosaurus sprites, animations, and egg sprites.
- `assets/sprites/creatures/triceratops/` — triceratops directional, animation, and egg sprites.
- `assets/sprites/creatures/tyrannosaurus/` — tyrannosaurus directional, idle, and egg sprites.
- `assets/sprites/creatures/raptor/` — raptor directional, idle, and egg sprites.
- `assets/sprites/creatures/pterodactyl/` — pterodactyl directional and egg sprites.
- `assets/sprites/creatures/egg_eater/` — egg-eater directional and egg sprites.

The species resources assign their stage-1 and stage-2 egg textures directly. `egg.tscn` remains shared and supplies defaults for future incomplete species.

## Removed / not used

Do not use:

- `scenes/world/world_triceratops.tscn`;
- species-specific duplicate egg scenes;
- `scenes/resources/tree.tscn`;
- `scripts/resources/tree.gd`;
- `assets/sprites/terrain/trees/`;
- `assets/sprites/terrain/tree_tiles_large.png`;
- `data/species/predator.tres` and `assets/sprites/creatures/predator/` — obsolete generic predator prototype removed after the dedicated carnivore species became active.

Trees are TileMap terrain, and species should not require separate copies of the world or egg scenes.
