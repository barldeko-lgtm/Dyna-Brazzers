# Dyna Project Map

This document is the repository path and ownership index.

Implemented behaviour belongs in `docs/current-state.md`. Fragile contracts and cross-file rules belong in `docs/dependencies.md`. Tunable values should be read from their owning scripts/resources.

## Project root

- `project.godot` — Godot configuration, startup scene, and autoload registration.
- `default_bus_layout.tres` — shared audio-bus layout.
- `AGENTS.md` — working rules for agents.
- `docs/current-state.md` — implemented gameplay and player-visible behaviour.
- `docs/project-map.md` — file, scene, resource, and asset ownership.
- `docs/dependencies.md` — runtime flows, stable contracts, and refactor safety.
- `docs/design_roadmap.md` — broader design roadmap; do not edit unless explicitly requested.

## Main scenes

- `scenes/ui/start_screen.tscn` — startup menu, level selection, load slots, settings, and exit.
- `scenes/main/main.tscn` — small gameplay compositor for camera, HUD, simulation root, world, and debug overlays.
- `scenes/ui/player_hud.tscn` — gameplay HUD, minimap, counters, and nature-menu instance.
- `scenes/ui/creature_info_panel.tscn` — selected/hovered creature information.
- `scenes/ui/nature_menu.tscn` — player energy, spells, time controls, and host area for runtime submenus.
- `scenes/world/world.tscn` — active authored world, terrain, DryGround, initial grass, creature/egg containers, and world grid.
- `scenes/world/player_base.tscn` — fixed player nature base.
- `scenes/world/enemy_base.tscn` — fixed enemy base.
- `scenes/resources/grass.tscn` — shared grass nodes and textures; timing is owned by `grass.gd`.
- `scenes/resources/egg.tscn` — shared egg scene.
- `scenes/creatures/creature.tscn` — shared creature scene.
- `scenes/debug/grid_debug_overlay.tscn` — F3 world diagnostics.
- `scenes/debug/enemy_ai_debug_overlay.tscn` — F5 enemy-AI/rain diagnostics.
- `scenes/effects/lightning_strike_effect.tscn` — lightning effect.
- `scenes/effects/rain_target_preview.tscn` — player rain preview.
- `scenes/effects/rain_cast_effect.tscn` — rain cast animation.
- `scenes/effects/sun_target_preview.tscn` — sun preview.
- `scenes/effects/earthquake_target_preview.tscn` — earthquake preview.

## World and camera scripts

- `scripts/world/world_grid.gd` — terrain queries, DryGround state, walkability, pathfinding, grass registry, footprints, blockers, creature occupancy, and movement reservations.
- `scripts/world/start_map_world_grid.gd` — start-map bootstrap; creates both bases, enemy runtime controllers, enemy rally objectives, energy nodes, and world bounds.
- `scripts/world/start_map_layout.gd` — preserves authored level 1 and builds registered pixel-map levels before world-grid initialization.
- `scripts/world/pixel_map_parser.gd` — exact-color map decoding and 2x2 base/tree marker validation.
- `scripts/world/faction_base.gd` — shared base blocker, scaling, faction assignment, and nearby egg placement.
- `scripts/world/player_base.gd` — player wrapper exposing `create_player_egg()`.
- `scripts/world/enemy_base.gd` — enemy wrapper exposing `create_enemy_egg()`.
- `scripts/world/nature_effects_system.gd` — successful lightning, rain, sun, and earthquake gameplay plus cast VFX/sounds. Rain uses a pre-cast grass snapshot.
- `scripts/camera/camera_controller.gd` — camera movement, zoom limits, save normalization, start position, and map clamping.

## Creature and resource scripts

- `scripts/creatures/creature.gd` — creature FSM/survival coordinator and public facade.
- `scripts/creatures/creature_species_data.gd` — biological species schema.
- `scripts/creatures/creature_faction.gd` — validated runtime ownership.
- `scripts/creatures/behaviors/creature_movement_controller.gd` — queued routes, grid steps, reservations, and indirect-order route API.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — pasture cache, food candidate ranking, route search, and grazing target lifecycle.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — prey selection, approach routing, engagement, and combat handoff.
- `scripts/creatures/behaviors/creature_egg_eater_logic.gd` — edible-egg targeting and consumption.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction and natural egg spawning.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional visuals, animations, shadows, and death poses.
- `scripts/creatures/behaviors/creature_interaction_controller.gd` — hover/selection visual and mouse bridge.
- `scripts/combat/duel.gd` — current one-on-one combat loop.
- `scripts/resources/grass.gd` — grass lifecycle, food value, spreading, registry sync, and nature-power reactions.
- `scripts/resources/egg.gd` — egg lifecycle, expansion/blocker state, hatching, and edible/destruction API.

## Catalogs, energy, and enemy strategy

- `scripts/catalogs/player_species_catalog.gd` — ordered player roster, egg economy, player income, and flag presentation.
- `scripts/catalogs/enemy_species_catalog.gd` — enemy resource roster and enemy economy values.
- `scripts/player/player_energy.gd` — player reserve and income from eligible living player creatures.
- `scripts/enemies/enemy_energy.gd` — enemy reserve and income from eligible living enemy creatures.
- `scripts/enemies/enemy_egg_production_controller.gd` — disabled legacy producer retained only for save compatibility.
- `scripts/enemies/enemy_ai_controller.gd` — periodic enemy population/satiety snapshot and egg-production decisions.
- `scripts/enemies/enemy_spell_controller.gd` — enemy spell triggers, rain target search/cost, world-space diagnostic contours, and public F5/F8 data.

## Flag systems

Player flags:

- `scripts/flags/player_flag_system.gd` — facade, placed data, scene attachment, and save/debug API.
- `scripts/flags/player_flag_system_with_catalog.gd` — active catalog-backed autoload and placement revisions.
- `scripts/flags/player_flag_ui_controller.gd` — menu, input, preview, and status text.
- `scripts/flags/player_flag_assignment_service.gd` — eligibility, batching, commitments, retries, completion, and route application.
- `scripts/flags/player_flag_target_allocator.gd` — destination candidates, pasture preference, reservations, and retry rotation.
- `scripts/flags/player_flag_visual.gd` — world-space flag and area drawing.
- `scripts/flags/raptor_guard_policy.gd` — shared player/enemy raptor leash rules.

Enemy objectives:

- `scripts/flags/enemy_flag_system.gd` — runtime persistent rally-objective facade.
- `scripts/flags/enemy_flag_assignment_service.gd` — enemy faction/resource eligibility and persistent-rally semantics.
- `scripts/flags/enemy_flag_visual.gd` — player-base attack objective and enemy-base raptor guard drawing.

## UI, audio, save, and debug scripts

- `scripts/ui/start_screen.gd` — startup UI, level selection, slot loading, and settings.
- `scripts/ui/player_ui.gd` — minimap, counters, base focus, time controls, and egg-controller bootstrap.
- `scripts/ui/creature_stats_ui.gd` — creature information, selection state, and lightning-target bridge.
- `scripts/ui/player_egg_creation_ui.gd` — player egg submenu and purchases.
- `scripts/ui/player_nature_ui.gd` — spell buttons, targeting/previews, named menu controls, and stable nested-UI access API.
- `scripts/ui/debug_status_ui.gd` — compact FPS/status line and F4 text diagnostics.
- `scripts/debug/grid_debug_overlay.gd` — F3 terrain/occupancy/path/flag diagnostics.
- `scripts/debug/enemy_ai_debug_overlay.gd` — read-only F5 enemy strategy/rain panel.
- `scripts/debug/performance_stats.gd` — runtime counters and F8 CSV recording.
- `scripts/audio/audio_manager.gd` — global music, one-shot sounds, UI clicks, bus setup, fades, and settings.
- `scripts/save/save_system.gd` — level routing, base slot persistence, and reconstruction.
- `scripts/save/save_system_with_flags.gd` — faction, player-flag, completion, and audio-setting extensions.
- `scripts/save/save_system_with_enemy.gd` — active final save layer for enemy energy and strategic timing/legacy state.
- `scripts/effects/` — target previews and one-shot effect playback.

## Data resources

Player species:

- `data/species/stegosaurus.tres`
- `data/species/triceratops.tres`
- `data/species/tyrannosaurus.tres`
- `data/species/raptor.tres`
- `data/species/pterodactyl.tres`
- `data/species/egg_eater.tres`

Enemy variants:

- `data/species/enemy/stegosaurus.tres`
- `data/species/enemy/triceratops.tres`
- `data/species/enemy/tyrannosaurus.tres`
- `data/species/enemy/raptor.tres`
- `data/species/enemy/pterodactyl.tres`
- `data/species/enemy/egg_eater.tres`

Enemy and player variants share biological `species_id` values but use distinct resource paths and runtime faction ids.

## Important assets

Terrain:

- `assets/maps/start_map_layout.png` — map-layout reference, not runtime terrain input.
- `assets/maps/level_2_map.png` — exact-color 90x60 runtime layout for level 2.
- `assets/sprites/terrain/ground.png`
- `assets/sprites/terrain/water_tiles_independent.png`
- `assets/sprites/terrain/mountain_tiles_independent.png`
- `assets/sprites/terrain/tree_tiles_independent.png`
- `assets/sprites/terrain/grass_stage_1.png` ... `grass_stage_4.png`
- `assets/sprites/terrain/dry_ground/dry_ground_01.png` ... `dry_ground_03.png`

Stable terrain source ids in `world.tscn`:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

World/UI:

- `assets/sprites/world/player_base.png`
- `assets/sprites/world/enemy_base.png`
- `assets/ui/start_screen_background.png`
- `assets/ui/creature_selection_frame.png`
- `assets/sprites/effects/rain/`

Audio:

- `assets/audio/music/gameplay_theme.mp3`
- `assets/audio/sfx/lightning_strike.wav`
- `assets/audio/sfx/rain_cast.wav`
- `assets/audio/sfx/sun_cast.wav`
- `assets/audio/sfx/earthquake_cast.wav`
- `assets/audio/ui/button_click.wav`

Player creature visuals live under `assets/sprites/creatures/<species>/`.
Enemy visuals live under `assets/sprites/creatures/enemy/<species>/`; their `.tres` resources select faction-specific directional and egg textures.
Generic egg fallback textures live under `assets/sprites/eggs/`; species-specific stage textures stay beside that species' player visuals.

## Save files

Gameplay slots:

- `user://dyna_save_slot_1.json`
- `user://dyna_save_slot_2.json`
- `user://dyna_save_slot_3.json`

Audio settings:

- `user://audio_settings.cfg`

On Windows, `user://` normally resolves under `%APPDATA%/Godot/app_userdata/Dyna/`.

## Removed or unused

Do not use:

- `scenes/world/world_triceratops.tscn`;
- species-specific duplicate egg scenes;
- `scenes/resources/tree.tscn`;
- `scripts/resources/tree.gd`;
- `assets/sprites/terrain/trees/`;
- `assets/sprites/terrain/tree_tiles_large.png`;
- `data/species/predator.tres`;
- `assets/sprites/creatures/predator/`.

Trees are TileMap terrain. New species/factions must not require duplicate world, creature, egg, movement, or survival scenes.
