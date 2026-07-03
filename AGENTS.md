# Dyna — AGENTS.md

## Project snapshot
Dyna is an early Godot 4.7 prototype of an autonomous dinosaur ecosystem inspired by Dyna Brothers. The target is an observable living world shaped by indirect player influence, not a normal RTS with direct unit control.

Current scope:
- a tile-based test world on `TileMapLayer`;
- one herbivore base species plus a temporary predator species;
- directional sprites and a right-facing walk animation for the stegosaurus;
- grass as the first renewable resource;
- egg laying, two egg stages, and hatching;
- autonomous grazing, predator hunting, and simple 1v1 duels;
- a first player influence action: lightning;
- debug UI for hover/selection, stats, FPS, performance counters, and simulation speed;
- removable F3 grid debug overlay for grid/path/occupancy inspection;
- F8 CSV performance logging;
- a free observer camera.

## Working rules
- Keep all changes inside `E:/dyna/Project` unless explicitly approved otherwise.
- Local Godot lives in `E:/Godot_v4.7/`; preferred headless CLI: `E:/Godot_v4.7/Godot_v4.7-stable_win64_console.exe`; short smoke test: `'/e/Godot_v4.7/Godot_v4.7-stable_win64_console.exe' --headless --path '/e/dyna' --quit-after 10`.
- Before risky or structural code changes, make a git backup commit.
- Keep code comments short and in English.
- Do not push the project toward a standard RTS.
- Do not edit `docs/design_roadmap.md` unless the user explicitly asks for roadmap/design-roadmap changes.
- When changing architecture, update `docs/project-map.md`, `docs/current-state.md`, and `docs/dependencies.md` together.

## Current architecture canon
- The world grid is the source of truth for walkability, terrain, occupancy, blockers, pathfinding, and grazing queries.
- Creatures make logical decisions in grid/anchor space but move smoothly in world space.
- Large creatures use `anchor_tile + footprint_size`; current creature footprint is `2x2`.
- Grass exists per tile, registers into the world, grows from stage 1 to adult stage 2, and only adult grass is edible.
- Eggs are world objects: stage 1 is non-blocking `1x2`; stage 2 expands to blocking `2x2`; stage 2 can be eaten and later hatches.
- Static creature stats, visuals, egg tuning, and species identity live in `.tres` species resources.
- `creature.gd` remains the runtime coordinator, while grazing, predator, reproduction, and visual details are split into helper scripts.
- UI should observe and trigger player actions, but long-term world/entity state should stay in world/entity logic.

## Key files
- `project.godot` — project entry, main scene `res://scenes/main/main.tscn`.
- `scenes/main/main.tscn` — top-level assembly: camera, UI, world, debug overlay.
- `scenes/world/world.tscn` — sandbox world with tilemap, grass, eggs, creatures, predator spawn marker.
- `scenes/creatures/creature.tscn` — base creature scene.
- `scenes/resources/grass.tscn` — grass resource scene.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/debug/grid_debug_overlay.tscn` — removable grid debug overlay scene.
- `scripts/world/world_grid.gd` — central world/grid manager.
- `scripts/creatures/creature.gd` — base creature runtime coordinator.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore grazing helper.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — predator targeting, chasing, and duel entry helper.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction and egg-spawn helper.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional sprites and walk animation helper.
- `scripts/creatures/creature_species_data.gd` — species resource schema.
- `scripts/combat/duel.gd` — isolated 1v1 duel loop.
- `scripts/resources/grass.gd` — grass lifecycle.
- `scripts/resources/egg.gd` — egg lifecycle and hatching.
- `scripts/ui/creature_stats_ui.gd` — stats UI, player lightning action, speed selector, debug status text.
- `scripts/debug/grid_debug_overlay.gd` — grid/path/occupancy debug drawing and info panel.
- `scripts/debug/performance_stats.gd` — performance counters and F8 CSV logging autoload.
- `scripts/camera/camera_controller.gd` — observer camera.
- `data/species/stegosaurus.tres` — herbivore species tuning and visuals.
- `data/species/predator.tres` — temporary predator species tuning and visuals.
- `data/animations/stegosaurus_walk_right_frames.tres` — stegosaurus right-facing walk animation frames.
- `docs/project-map.md` — structure and responsibilities.
- `docs/current-state.md` — live project snapshot.
- `docs/dependencies.md` — dependency graph and task file bundles.
- `docs/design_roadmap.md` — broader design vision and roadmap.

## Recommended read order for a new agent/session
1. `AGENTS.md`
2. `docs/current-state.md`
3. `docs/project-map.md`
4. `docs/dependencies.md`
5. `docs/design_roadmap.md` only when broader design intent matters
6. then inspect task-relevant scenes/scripts

## Fragile areas
- `world_grid.gd` <-> `creature.gd`: `anchor_tile`, `pending_anchor_tile`, `movement_target_position`, occupancy, movement, and grazing.
- Any change touching footprint placement or visual-vs-logical sync.
- Grazing target scoring, retargeting, and the rule that creatures should not eat until they reach the correct grazing anchor.
- Registration/unregistration of grass, creatures, and blockers in `world_grid`.
- Predator duel entry: side-contact-only combat should not become diagonal corner contact.
- Egg stage transition: stage 1 is non-blocking; stage 2 must register as a blocker and unregister before hatching/removal.

## Near-term project meaning
This stage is a simulation testbed for:
- creature movement and pathfinding;
- food search and renewable resources;
- reproduction and population growth;
- predator/prey pressure;
- observation through UI/debug tools;
- first indirect player actions;
- preparation for more species, richer terrain, player energy, and ecosystem depth.

## Original Dyna Brothers spirit
- Autonomous ecosystem strategy, not heavy micro RTS.
- Creatures should mostly act on their own.
- Combat and behaviour should grow from simple automatic states/roles.
- Readability should come from world behaviour more than heavy UI.
