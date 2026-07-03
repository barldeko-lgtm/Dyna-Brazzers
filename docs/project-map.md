# Dyna Project Map

Fast entry point for a new session: what lives where, what each part owns, and where to look first.

---

## 1. High-level structure

### Project root
- `project.godot` — Godot project config; main scene is `res://scenes/main/main.tscn`; `PerformanceStats` is registered as an autoload.
- `AGENTS.md` — short working rules and project canon for agents.
- `docs/project-map.md` — this file: structure, responsibilities, and where to look first.
- `docs/current-state.md` — live prototype snapshot.
- `docs/dependencies.md` — dependency graph, system links, and task-based file bundles.
- `docs/design_roadmap.md` — broader design vision and roadmap. Do not edit unless asked.
- `logs/` — CSV performance logs created by F8 recording.

### `scenes/`
Scene assemblies and placed nodes.

- `scenes/main/main.tscn` — top-level project assembly.
- `scenes/world/world.tscn` — active test world.
- `scenes/creatures/creature.tscn` — base creature scene.
- `scenes/resources/grass.tscn` — grass resource scene.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/debug/grid_debug_overlay.tscn` — removable debug grid overlay and info panel.

### `scripts/`
Main gameplay logic by subsystem.

- `scripts/world/world_grid.gd` — central world/grid authority.
- `scripts/creatures/creature.gd` — base creature runtime coordinator.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore food search, grazing scoring, path rebuild, and retargeting helper.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — predator prey search, chase pathing, side-contact checks, and duel start helper.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction checks and egg spawning helper.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — directional visuals, mirroring, and walk-animation helper.
- `scripts/creatures/creature_species_data.gd` — species resource schema.
- `scripts/combat/duel.gd` — isolated 1v1 duel loop.
- `scripts/resources/grass.gd` — grass lifecycle.
- `scripts/resources/egg.gd` — egg lifecycle and hatching.
- `scripts/ui/creature_stats_ui.gd` — creature HUD, selection UI, player lightning action, speed selector, debug status text.
- `scripts/debug/grid_debug_overlay.gd` — removable grid/path/occupancy debug drawing and info panel.
- `scripts/debug/performance_stats.gd` — performance counters, elapsed time, memory/node/object counts, and F8 CSV logging.
- `scripts/camera/camera_controller.gd` — observer camera movement and zoom.

### `data/`
Configurable game data resources.

- `data/species/stegosaurus.tres` — herbivore species stats, visuals, egg settings, and walk-animation config.
- `data/species/predator.tres` — temporary predator species stats, visuals, and hunt tuning.
- `data/animations/stegosaurus_walk_right_frames.tres` — 6-frame right-facing stegosaurus walk animation.

### `assets/`
Sprites and placeholders.

- `assets/sprites/terrain/ground.png` — ground tile.
- `assets/sprites/terrain/water_placeholder.png` — temporary water tile.
- `assets/sprites/terrain/mountain_placeholder.png` — temporary mountain tile.
- `assets/sprites/terrain/grass_stage_1.png` — small grass.
- `assets/sprites/terrain/grass_stage_2.png` — adult grass.
- `assets/sprites/creatures/stegosaurus/` — stegosaurus directional sprites and right-facing walk frames.
- `assets/sprites/creatures/predator/` — temporary predator directional sprite set.
- `assets/sprites/creatures/eggs/` — egg sprites for both stages.

---

## 2. Scene startup flow

### `project.godot`
Project entry point. Launches `res://scenes/main/main.tscn`. Also registers the `PerformanceStats` autoload from `scripts/debug/performance_stats.gd`.

### `scenes/main/main.tscn`
Top-level scene. Currently contains:
- `Camera2D` — camera using `camera_controller.gd`.
- `UI` — creature stats, FPS/debug text, lightning action button, and simulation speed controls.
- `Simulation` — currently an empty technical node.
- `World` — an instance of `scenes/world/world.tscn`.
- `GridDebugOverlay` — optional removable grid debug overlay.

### `scenes/world/world.tscn`
Active simulation sandbox. Contains:
- `World` (`Node2D`) with `world_grid.gd`.
- `Creatures` — test creatures plus `PredatorSpawn` marker.
- `Grasses` — grass instances.
- `Eggs` — creature eggs.
- `Ground` (`TileMapLayer`) — map geometry and terrain types.

Important: `World` with `world_grid.gd` is the logic center. Most gameplay entities find it by walking up the scene tree.

---

## 3. Key scenes

### `scenes/main/main.tscn`
**Role:** top-level project assembly.

**Owns:** bootstrapping the prototype, observer camera, UI layer, optional grid overlay, and world scene attachment.

**Keep in mind:** do not turn this into a heavy gameplay-logic scene. World/entity logic belongs in `world_grid.gd`, creature/resource scripts, and their helpers.

### `scenes/world/world.tscn`
**Role:** active gameplay sandbox.

**Owns:** placed map, terrain, test creatures, grass patches, eggs container, and predator spawn marker.

**Keep in mind:** the map currently uses large `128x128` tiles. This is still a mechanics sandbox, not final world structure.

### `scenes/creatures/creature.tscn`
**Role:** base creature scene.

**Structure:**
- `CharacterBody2D`
- `BodySprite`
- `WalkRightSprite`
- `CollisionShape2D`
- `EatingTimer`
- `EggLayingTimer`
- `HoverArea` with its own collision shape for hover/click UI

**Keep in mind:** the scene pulls stats, visuals, animation, and egg setup from `species_data`. Left-facing visuals are mirrored from right-facing sprites. Current logical footprint is `2x2`.

### `scenes/resources/grass.tscn`
**Role:** base grass scene.

**Structure:** `Node2D`, `BodySprite`, `GrowthTimer`, `SpreadTimer`.

**Keep in mind:** grass exists on tiles, registers into `world_grid`, grows from stage 1 to adult stage 2, adult grass is edible, and grass tries to spread only once.

### `scenes/resources/egg.tscn`
**Role:** base creature egg scene.

**Structure:** `Node2D`, `BodySprite`, `Stage1Timer`, `ExpandRetryTimer`, `HatchTimer`.

**Keep in mind:** stage 1 is a non-blocking vertical `1x2` egg. Stage 2 expands to blocking `2x2`, can be eaten, and later hatches a new creature.

### `scenes/debug/grid_debug_overlay.tscn`
**Role:** optional debug overlay.

**Structure:** `Node2D`, `CanvasLayer`, `DebugInfoPanel`, `DebugInfoLabel`.

**Keep in mind:** should stay removable and observational.

---

## 4. Key scripts

### `scripts/world/world_grid.gd`
**Role:** central world/grid manager and source of truth.

**Owns:**
- `Ground` lookup/cache;
- tile size and map bounds;
- world/tile/anchor conversion;
- terrain type lookup for ground, water, and mountain;
- blocked terrain rules;
- footprint placement;
- grass registration by tile;
- creature anchor and occupied-tile registration;
- blocker registration for objects like eggs;
- neighbor lookup with diagonal corner-cut prevention;
- A*-style pathfinding;
- grazing-target queries and scoring;
- counting and consuming adult grass under a footprint;
- optional delayed predator spawn, currently controlled by `PREDATOR_SPAWN_ENABLED`.

**Fragile areas:** creature registration/movement, footprint placement, `anchor_tile` vs visual position, blocker registration, grazing selection.

### `scripts/creatures/creature.gd`
**Role:** base autonomous creature runtime coordinator.

**Owns:**
- states `IDLE`, `WALK`, `SEEK_FOOD`, `EATING`, `LAYING_EGG`, `COMBAT`, `DEAD`;
- age, hunger, starvation damage, well-fed regeneration, death;
- high-level state transitions;
- smooth movement between tile anchors;
- path following;
- species data application;
- helper object wiring for grazing, predator, reproduction, and visuals;
- eating timer and consumption callback;
- duel attach/detach/damage hooks;
- hover/click selection hooks;
- public getters used by UI/debug.

**Keep in mind:** this file is still the central creature coordinator. Add new systems carefully; prefer helpers when a subsystem can be isolated.

### `scripts/creatures/behaviors/creature_grazing_logic.gd`
**Role:** herbivore grazing helper.

**Owns:** local recheck, global fallback, target scoring/retargeting, target validity, path rebuilding toward grazing anchor, and deciding when eating can start.

### `scripts/creatures/behaviors/creature_predator_logic.gd`
**Role:** predator behaviour helper.

**Owns:** nearest-prey search, prey validation, side-contact combat range, pathing to prey-adjacent anchors, and duel creation.

### `scripts/creatures/behaviors/creature_reproduction_logic.gd`
**Role:** reproduction helper.

**Owns:** reproduction condition checks, egg anchor choice, egg spawning, and egg parameter transfer from species data.

### `scripts/creatures/behaviors/creature_visual_controller.gd`
**Role:** creature visual helper.

**Owns:** directional sprite selection, horizontal mirroring, right-facing walk animation setup, and animation/static sprite switching.

### `scripts/creatures/creature_species_data.gd`
**Role:** species resource schema.

**Owns:** species identity, predator/herbivore flags, hunt tuning, directional visuals, optional walk animation, survival/combat stats, hunger tuning, egg lifecycle tuning, reproduction thresholds/costs, and hatchling starting stats.

### `scripts/combat/duel.gd`
**Role:** isolated 1v1 duel loop.

**Owns:** fighter references, initiator-first turn order, 1-second alternating turns, `max(1, attack - defense)` damage, and duel finish signal.

### `scripts/resources/grass.gd`
**Role:** grass lifecycle.

**Owns:** two growth stages, timers, world registration, single spread attempt, spreading to 4 cardinal neighbors, fallback to stage 1 after consumption.

### `scripts/resources/egg.gd`
**Role:** creature egg lifecycle.

**Owns:** stage 1 placement, repeated expansion attempts, stage 2 blocker registration, bool-based edibility, hatching a configured creature scene.

### `scripts/ui/creature_stats_ui.gd`
**Role:** creature HUD and lightweight player interaction UI.

**Owns:** hover preview, click-to-pin selection, name/age/health/hunger display, health/hunger bars, FPS/debug text, lightning target mode, simulation speed switching.

### `scripts/debug/grid_debug_overlay.gd`
**Role:** removable world-grid debug overlay.

**Owns:** F3 toggle, drawing blocked terrain/grass/occupied tiles/footprints/targets/paths, and bottom-left selected/hovered creature debug text.

### `scripts/debug/performance_stats.gd`
**Role:** performance instrumentation autoload.

**Owns:** elapsed time, counters/rates, static memory, node/object counts, F8 CSV recording, and log file creation under `logs/`.

### `scripts/camera/camera_controller.gd`
**Role:** observer camera control.

**Owns:** WASD movement, mouse-wheel zoom, and zoom range limits.

---

## 5. Current system links

### World -> Creatures
Creatures find `world_grid` through the scene tree. The world tells creatures where they can stand, move, path, and find food. The world stores real anchor/occupancy data.

### World -> Grass
Grass registers into the world by tile. The world uses the grass registry for food search, adult-count scoring, and consumption.

### World -> Eggs
Eggs use the world to resolve anchors, placement, blocking, and hatch placement. Stage 2 egg occupancy is tracked through blocker registration.

### Creature -> Helper scripts
`creature.gd` creates helper objects and delegates grazing, predator, reproduction, and visual details while keeping high-level state ownership.

### Creature -> UI
`HoverArea` talks to the `creature_stats_ui` group. The UI asks creatures for name, age, health, hunger, and max values. Lightning applies direct damage through creature methods.

### Debug systems -> World/Creature
The debug overlay and performance stats read world/creature state but should not become owners of gameplay state.

---

## 6. What already works in practice

The current code already provides:
- startup through `scenes/main/main.tscn`;
- camera movement and zoom;
- a tile-based world with ground, water, and mountain terrain;
- blocked water/mountain tiles;
- several test herbivores;
- directional creature sprites plus stegosaurus right-walk animation;
- age, hunger, health, starvation damage, well-fed healing, and death;
- hover and click creature selection;
- grid-based grass search and pathfinding;
- adult grass eating and grass regrowth;
- grass spreading once to cardinal neighbors;
- egg laying, egg growth, stage 2 blocking, and hatching;
- simple predator species data and predator behaviour helper;
- isolated 1v1 duel loop;
- first player action: lightning damage;
- stats panel, FPS/debug text, simulation speed control;
- F3 grid overlay;
- F8 CSV performance recording.

---

## 7. Where to look first for new tasks

### Movement / path / footprint / stuck behaviour
1. `scripts/world/world_grid.gd`
2. `scripts/creatures/creature.gd`
3. `scripts/creatures/behaviors/creature_visual_controller.gd` if the issue is visual sync
4. `scenes/world/world.tscn`

### Grass / food / grazing
1. `scripts/creatures/behaviors/creature_grazing_logic.gd`
2. `scripts/resources/grass.gd`
3. `scripts/world/world_grid.gd`
4. `scripts/creatures/creature.gd`

### Egg / reproduction / hatching
1. `scripts/creatures/behaviors/creature_reproduction_logic.gd`
2. `scripts/resources/egg.gd`
3. `scripts/creatures/creature.gd`
4. `data/species/stegosaurus.tres`

### Predator / combat
1. `scripts/creatures/behaviors/creature_predator_logic.gd`
2. `scripts/combat/duel.gd`
3. `scripts/creatures/creature.gd`
4. `data/species/predator.tres`
5. `scripts/world/world_grid.gd`

### Creature UI / player lightning / speed controls
1. `scripts/ui/creature_stats_ui.gd`
2. `scripts/creatures/creature.gd`
3. `scenes/main/main.tscn`

### Debug / performance logging
1. `scripts/debug/performance_stats.gd`
2. `scripts/debug/grid_debug_overlay.gd`
3. `scripts/ui/creature_stats_ui.gd`
4. `logs/`

### Camera / world observation
1. `scripts/camera/camera_controller.gd`
2. `scenes/main/main.tscn`

---

## 8. Places to avoid touching blindly

- `anchor_tile`, `pending_anchor_tile`, and `movement_target_position` logic in `creature.gd`.
- `register_creature`, `move_creature`, `can_place_footprint`, and blocker functions in `world_grid.gd`.
- grazing target scoring and retarget logic.
- predator side-contact duel entry.
- egg stage 2 blocker registration/unregistration.
- consistency between visual motion and logical creature position.

If these areas are changed carelessly, a creature can visually stand in one place while logically eating, occupying, or fighting elsewhere.

---

## 9. Design context worth preserving

The project direction is:
- a living autonomous ecosystem;
- indirect player control;
- a world that exists on its own;
- gradual growth in species, resources, and player influence.

This is not “a normal RTS with dinosaurs”. It is an observable simulation shaped by outside player influence.
