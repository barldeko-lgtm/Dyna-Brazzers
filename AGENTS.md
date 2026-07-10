# Dyna — AGENTS.md

## Project snapshot

Dyna is an early Godot 4.7 prototype of an autonomous dinosaur ecosystem inspired by Dyna Brothers. The project is built around an observable living world shaped by indirect player influence, not a standard RTS with direct unit orders.

The current prototype includes:
- a tile-based test world on `TileMapLayer`;
- autonomous herbivore creatures;
- a temporary predator species and simple one-on-one combat;
- grass as the first renewable resource;
- egg laying, egg stages, and hatching;
- basic terrain blocking with ground, water, mountains, and trees;
- creature death state with a short non-blocking corpse/death-pose visual;
- player nature powers: lightning, rain, and sun;
- hover/click observation UI;
- stone corner highlight frame for hover/selection;
- separated player UI, creature info UI, and debug status UI;
- debug/performance tools;
- a free observer camera.

## Working rules

- Keep the simulation-first architecture.
- Do not push the project toward direct unit control or normal RTS micro.
- Prefer small, safe changes.
- Keep code comments short and in English.
- Do not edit `docs/design_roadmap.md` unless the user explicitly asks.
- When architecture or file ownership changes, update `docs/project-map.md`, `docs/current-state.md`, and `docs/dependencies.md` together.
- Do not document temporary balance numbers unless they are architecture-critical.

## Documentation rule

The docs should explain architecture, ownership, runtime flows, and fragile areas. They should not try to mirror every temporary tuning value.

Costs, radii, damage values, timers, counts, speed presets, and similar balance values should be read from the current exported variables or resources in code.

Update docs when behaviour, ownership, file structure, or design intent changes. Do not update docs just because a temporary tuning number changed.

## Current architecture canon

- The world grid is the source of truth for terrain, walkability, occupancy, blockers, pathfinding, and resource lookup.
- Creatures make decisions in grid/anchor space but move smoothly in world space.
- Species stats, visuals, egg tuning, death texture, corpse lifetime, and species identity live in `.tres` resources.
- `creature.gd` is the creature runtime coordinator.
- Grazing, predator, reproduction, and visual logic are split into helper scripts.
- Grass owns its own lifecycle and registers itself with the world grid.
- Eggs are world objects and must correctly register/unregister blocking state.
- Dead creatures release world-grid occupancy immediately; corpse visuals are non-blocking.
- Player nature UI triggers powers and spends energy, but long-term simulation state should remain in world/entity/resource logic.
- Player powers should influence the ecosystem indirectly where possible.

## Key files

- `project.godot` — project entry and autoloads.
- `scenes/main/main.tscn` — top-level assembly: camera, UI, world, debug overlay.
- `scenes/world/world.tscn` — sandbox world with terrain, grass, eggs, and creatures.
- `scenes/creatures/creature.tscn` — base creature scene.
- `scenes/resources/grass.tscn` — grass resource scene.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/effects/lightning_strike_effect.tscn` — lightning visual effect.
- `scenes/effects/rain_target_preview.tscn` — rain targeting preview.
- `scenes/effects/sun_target_preview.tscn` — sun targeting preview.
- `scenes/debug/grid_debug_overlay.tscn` — optional grid debug overlay.
- `data/species/stegosaurus.tres` — stegosaurus species resource, including death texture/corpse lifetime.
- `assets/sprites/creatures/stegosaurus/stegosaurus_dead.png` — stegosaurus death-pose sprite.
- `assets/ui/creature_selection_frame.png` — stone corner creature selection frame.
- `scripts/world/world_grid.gd` — central grid/world authority.
- `scripts/creatures/creature.gd` — creature runtime coordinator, death/corpse cleanup, and world-space highlight overlay.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore grazing helper.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — predator targeting/chasing/combat-entry helper.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction and egg spawn helper.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional sprites, animation, and death visual handling.
- `scripts/creatures/creature_species_data.gd` — species resource schema.
- `scripts/combat/duel.gd` — isolated duel loop.
- `scripts/resources/grass.gd` — grass lifecycle and nature-power reactions.
- `scripts/resources/egg.gd` — egg lifecycle and hatching.
- `scripts/ui/creature_stats_ui.gd` — creature info panel, hover/selection, empty-click deselection, lightning click bridge, and highlight coordination.
- `scripts/ui/player_ui.gd` — player counters and time speed controls.
- `scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug text.
- `scripts/ui/player_nature_ui.gd` — player energy and nature powers.
- `scripts/debug/performance_stats.gd` — runtime counters and CSV logging.
- `scripts/debug/grid_debug_overlay.gd` — F3 grid overlay.
- `scripts/camera/camera_controller.gd` — observer camera.

## Recommended read order for a new agent/session

1. `AGENTS.md`
2. `docs/current-state.md`
3. `docs/project-map.md`
4. `docs/dependencies.md`
5. `docs/design_roadmap.md` only when broader design intent matters
6. task-relevant scenes/scripts

## Fragile areas

- Visual vs logical creature position: `anchor_tile`, `pending_anchor_tile`, `movement_target_position`, `global_position`, and world occupancy must stay consistent.
- Grazing target selection and retargeting must not let creatures eat before reaching a valid target anchor.
- Grass, creatures, eggs, and blockers must correctly register/unregister in `world_grid.gd`.
- Dead creatures must unregister creature occupancy immediately, before their corpse visual disappears.
- Predator combat should start from side contact, not diagonal corner contact.
- Egg stage transitions must not leave stale blockers.
- Player powers should not corrupt world registration or bypass resource lifecycle rules.
- UI ownership is split: do not move player counters, speed controls, or debug status back into `creature_stats_ui.gd`.
- The creature highlight overlay should stay above grass/world props and should be scaled to the intended footprint size rather than rendered at texture-native size.

## Project meaning

This stage is a simulation testbed for autonomous creatures, renewable resources, reproduction, predator pressure, indirect player powers, and debugging tools. The project should feel like a living ecosystem first and a game UI second.
