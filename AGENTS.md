# Dyna — AGENTS.md

## Project snapshot

Dyna is an early Godot 4.7 prototype of an autonomous dinosaur ecosystem inspired by Dyna Brothers. The project is built around an observable living world shaped by indirect player influence, not a standard RTS with direct unit orders.

The current prototype includes:

- an editable 85x85 tile-based world on `TileMapLayer`;
- six species available through player-created eggs: stegosaurus, triceratops, tyrannosaurus, raptor, pterodactyl, and egg eater; fresh games start without adult creatures;
- grass as the first renewable resource;
- egg laying, egg stages, and hatching;
- terrain blocking with ground, water, mountains, and trees;
- creature death with a short non-blocking corpse/death-pose visual;
- player nature powers: lightning, rain, sun, and earthquake;
- a first all-species flag pass: non-blocking 11x11 influence areas;
- a local four-frame rain cast VFX;
- hover/click observation UI and creature highlighting;
- separated player UI, creature info UI, debug status UI, and save system;
- debug/performance tools;
- a free observer camera constrained to the authored world.

Automatic predator spawning is currently disabled.

## Working rules

- Keep the simulation-first architecture.
- Do not push the project toward direct unit control or normal RTS micro.
- Prefer small, safe changes.
- Keep code comments short and in English.
- Do not edit `docs/design_roadmap.md` unless the user explicitly asks.
- Before code changes, read `docs/project-map.md`, `docs/current-state.md`, and `docs/dependencies.md`.
- When architecture, file ownership, or runtime flows change, update those three documents together.
- Do not document temporary balance values unless they are architecture-critical.
- Do not manually reconstruct or rewrite Godot `tile_map_data`; edit and save the TileMap through Godot.
- Do not create species-specific copies of the whole world scene. Assign species resources directly to creature instances or spawning logic.

## Documentation rule

The docs should explain architecture, ownership, runtime flows, current implemented behaviour, and fragile areas. They should not mirror every exported number or temporary tuning value.

Use each document for its intended purpose:

- `docs/project-map.md` — where files and responsibilities live;
- `docs/current-state.md` — what the current prototype actually does;
- `docs/dependencies.md` — which files and systems must be inspected together;
- `docs/design_roadmap.md` — broader future design, only when explicitly requested.

Update docs when behaviour, ownership, file structure, or design intent changes. Do not update docs only because a temporary cost, timer, radius, stat, or speed value changed.

## Current architecture canon

- `scenes/world/world.tscn` is the only active gameplay world.
- The `Ground` TileMap is the authored base terrain source of truth once saved in Godot; the optional `DryGround` overlay marks dynamic non-walkable, non-growable cells, uses three deterministic visual variants, and needs three rain hits per cell to clear.
- `start_map_layout.gd` may populate only a completely empty TileMap and must never overwrite an existing edited map.
- The world grid is the source of truth for terrain, walkability, occupancy, blockers, pathfinding, map bounds, and resource lookup.
- Creatures make decisions in grid/anchor space but move smoothly in world space.
- Species stats, visuals, egg tuning, death texture, corpse lifetime, and species identity live in `.tres` resources.
- `creature.gd` is the creature runtime coordinator.
- Grazing, predator, egg-eater, reproduction, and visual logic are split into helper scripts.
- Grass owns its lifecycle and registers itself with the world grid.
- Grass may spread across normal walkable ground; initial grass placements are not growth boundaries.
- Eggs are world objects and must correctly register and unregister blocking state.
- Dead creatures release world-grid occupancy immediately; corpse visuals are non-blocking.
- Player nature UI owns spell controls and targeting; `PlayerEnergy` owns the player reserve and dinosaur-driven income.
- Player powers should influence the ecosystem indirectly where possible.

## Key files

- `project.godot` — project entry and autoloads.
- `scenes/ui/start_screen.tscn` — startup screen.
- `scenes/main/main.tscn` — top-level assembly: camera, UI, world, and debug overlay.
- `scenes/world/world.tscn` — active world with terrain, initial grass, creatures, eggs container, and camera marker.
- `scripts/world/start_map_layout.gd` — one-time empty-map bootstrap and terrain-edge selection.
- `scripts/world/start_map_world_grid.gd` — authored-map extension of the base world grid, including camera bounds.
- `scripts/world/world_grid.gd` — central grid/world authority.
- `scripts/camera/camera_controller.gd` — observer camera, start marker, zoom, and world clamping.
- `scenes/creatures/creature.tscn` — shared creature scene.
- `scripts/creatures/creature.gd` — creature runtime coordinator.
- `scripts/creatures/creature_species_data.gd` — species resource schema.
- `scripts/creatures/behaviors/` — grazing, predator, reproduction, and visual helpers.
- `data/species/stegosaurus.tres` — stegosaurus species resource.
- `data/species/triceratops.tres` — triceratops species resource.
- `data/species/predator.tres` — temporary predator species resource.
- `data/species/tyrannosaurus.tres` — tyrannosaurus species resource.
- `data/species/raptor.tres` — raptor species resource.
- `data/species/pterodactyl.tres` — pterodactyl species resource.
- `data/species/egg_eater.tres` — egg-eater species resource.
- `scenes/resources/grass.tscn` and `scripts/resources/grass.gd` — grass scene and lifecycle.
- `scenes/resources/egg.tscn` and `scripts/resources/egg.gd` — egg scene and lifecycle.
- `scripts/ui/creature_stats_ui.gd` — creature information and selection.
- `scripts/ui/player_ui.gd` — counters and time-speed controls.
- `scripts/ui/player_egg_creation_ui.gd` — egg submenu, temporary species prices, and base purchase requests.
- `scripts/flags/player_flag_system.gd` — `PlayerFlags` autoload for all-species flag UI, placement, save state, and soft attraction.
- `scripts/flags/player_flag_visual.gd` — non-blocking world-space flag and 11x11 area visual.
- `scripts/save/save_system_with_flags.gd` — flag-aware extension of the base save system.
- `scripts/ui/player_nature_ui.gd` — spell buttons, targeting, and previews.
- `scripts/player/player_energy.gd` — session-owned player energy, spending API, and living-dinosaur income.
- `scripts/world/nature_effects_system.gd` — world-side lightning, rain, sun, and spell VFX application.
- `scripts/ui/debug_status_ui.gd` — compact and detailed text debug.
- `scripts/save/save_system.gd` — save/load persistence and in-game menu integration.
- `scripts/debug/performance_stats.gd` and `grid_debug_overlay.gd` — diagnostics.

## Recommended read order for a new agent/session

1. `AGENTS.md`
2. `docs/current-state.md`
3. `docs/project-map.md`
4. `docs/dependencies.md`
5. task-relevant scenes, scripts, and species resources
6. `docs/design_roadmap.md` only when broader design intent matters

## Fragile areas

- Visual vs logical creature position: `anchor_tile`, pending movement, target position, `global_position`, and world occupancy must stay consistent.
- Grazing target selection and retargeting must not let creatures eat before reaching a valid target anchor.
- Grass, creatures, eggs, and blockers must correctly register and unregister in the world grid.
- New grass must receive its intended position before `add_child()`, because `_ready()` immediately synchronizes it with the grid.
- Dead creatures must release occupancy before their corpse visual disappears.
- Predator combat should begin from valid side contact, not diagonal corner contact.
- Egg stage transitions must not leave stale blockers.
- The map bootstrap must return immediately when `Ground` already contains cells.
- Do not hand-edit serialized TileMap byte data outside Godot.
- Static terrain is not stored in saves; major map edits can invalidate old saved entity positions.
- UI ownership is split: do not move counters, speed controls, or debug status back into `creature_stats_ui.gd`.
- The creature highlight must stay above world props and scale to the intended footprint.

## Project meaning

This stage is a simulation testbed for autonomous creatures, renewable resources, reproduction, species variety, future predator pressure, indirect player powers, saving, and debugging tools. The project should feel like a living ecosystem first and a game UI second.
