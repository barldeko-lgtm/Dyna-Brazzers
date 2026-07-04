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
- `docs/design_roadmap.md` — broader design vision and roadmap.
- `logs/` — CSV performance logs created by F8 recording.

### `scenes/`
Scene assemblies and placed nodes.

- `scenes/main/main.tscn` — top-level project assembly.
- `scenes/world/world.tscn` — active test world.
- `scenes/creatures/creature.tscn` — base creature scene.
- `scenes/resources/grass.tscn` — grass resource scene.
- `scenes/resources/egg.tscn` — egg resource scene.
- `scenes/effects/lightning_strike_effect.tscn` — short visual lightning strike effect.
- `scenes/effects/rain_target_preview.tscn` — 3x3 rain target preview overlay.
- `scenes/effects/sun_target_preview.tscn` — 5x5 sun target preview overlay.
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
- `scripts/resources/grass.gd` — grass lifecycle plus rain/sun reaction hooks.
- `scripts/resources/egg.gd` — egg lifecycle and hatching.
- `scripts/ui/creature_stats_ui.gd` — creature HUD, selection UI, debug status text, and simulation speed selector.
- `scripts/ui/player_nature_ui.gd` — player nature HUD, energy economy, lightning targeting, rain targeting, sun targeting, and nature action costs.
- `scripts/effects/lightning_strike_effect.gd` — plays the lightning animation and removes the effect after its lifetime.
- `scripts/effects/rain_target_preview.gd` — draws the configurable square target area for rain and sun previews.
- `scripts/debug/grid_debug_overlay.gd` — removable grid/path/occupancy debug drawing and info panel.
- `scripts/debug/performance_stats.gd` — performance counters, elapsed time, memory/node/object counts, and F8 CSV logging.
- `scripts/camera/camera_controller.gd` — observer camera movement and zoom.

### `data/`
Configurable game data resources.

- `data/species/stegosaurus.tres` — herbivore species stats, visuals, egg settings, and walk-animation config.
- `data/species/predator.tres` — temporary predator species stats, visuals, and hunt tuning.
- `data/animations/stegosaurus_walk_right_frames.tres` — right-facing stegosaurus walk animation.
- `data/animations/stegosaurus_walk_up_frames.tres` — up-facing stegosaurus walk animation.
- `data/animations/lightning_strike_frames.tres` — lightning strike animation frames.

### `assets/`
Sprites and placeholders.

- `assets/sprites/terrain/ground.png` — ground tile.
- `assets/sprites/terrain/water_placeholder.png` — temporary water tile.
- `assets/sprites/terrain/mountain_placeholder.png` — temporary mountain tile.
- `assets/sprites/terrain/grass_stage_1.png` — small grass.
- `assets/sprites/terrain/grass_stage_2.png` — adult grass.
- `assets/sprites/creatures/stegosaurus/` — stegosaurus directional sprites and walk frames.
- `assets/sprites/creatures/predator/` — temporary predator directional sprite set.
- `assets/sprites/creatures/eggs/` — egg sprites for both stages.
- `assets/sprites/effects/lightning/` — lightning strike source frames.

---

## 2. Scene startup flow

### `project.godot`
Project entry point. Launches `res://scenes/main/main.tscn`. Also registers the `PerformanceStats` autoload from `scripts/debug/performance_stats.gd`.

### `scenes/main/main.tscn`
Top-level scene. Currently contains:
- `Camera2D` — camera using `camera_controller.gd`.
- `UI` — creature stats panel, FPS/debug text, player nature panel, and simulation speed controls.
- `PlayerNaturePanel` under `UI` — player energy, lightning, rain, and sun controls using `player_nature_ui.gd`.
- `Simulation` — currently an empty technical node.
- `World` — an instance of `scenes/world/world.tscn`.
- `GridDebugOverlay` — optional removable grid debug overlay.

Important: balance values for player nature actions are kept in `scripts/ui/player_nature_ui.gd`. `main.tscn` should not duplicate these exported values unless there is a deliberate scene-specific override.

### `scenes/world/world.tscn`
Active simulation sandbox. Contains:
- `World` (`Node2D`) with `world_grid.gd`.
- `Creatures` — test creatures plus `PredatorSpawn` marker.
- `Grasses` — grass instances.
- `Eggs` — creature eggs.
- `Ground` (`TileMapLayer`) — map geometry and terrain types.

Important: `World` with `world_grid.gd` is the logic center. Most gameplay entities find it by walking up the scene tree or through the `world_grid` group.

---

## 3. Key scenes

### `scenes/main/main.tscn`
**Role:** top-level project assembly.

**Owns:** bootstrapping the prototype, observer camera, UI layer, optional grid overlay, and world scene attachment.

**Keep in mind:** do not turn this into a heavy gameplay-logic scene. World/entity logic belongs in `world_grid.gd`, creature/resource scripts, and helpers. Player nature UI may call world/resource methods, but it should not become the owner of ecosystem rules.

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

**Keep in mind:** grass exists on tiles, registers into `world_grid`, grows from stage 1 to adult stage 2, adult grass is edible, and grass normally tries to spread only once. Nature powers can force or reset parts of this lifecycle.

### `scenes/resources/egg.tscn`
**Role:** base creature egg scene.

**Structure:** `Node2D`, `BodySprite`, `Stage1Timer`, `ExpandRetryTimer`, `HatchTimer`.

**Keep in mind:** stage 1 is a non-blocking vertical `1x2` egg. Stage 2 expands to blocking `2x2`, can be eaten, and later hatches a new creature.

### `scenes/effects/lightning_strike_effect.tscn`
**Role:** short-lived visual lightning strike.

**Structure:** `Node2D`, `AnimatedSprite2D`.

**Keep in mind:** this is purely visual. Actual damage is applied by `player_nature_ui.gd`.

### `scenes/effects/rain_target_preview.tscn`
**Role:** lightweight visual target helper for rain.

**Structure:** `Node2D` with `rain_target_preview.gd`.

**Keep in mind:** this is a removable visual overlay only. It follows the mouse-selected tile while rain targeting is armed and draws the affected area. It should not own grass or world rules.

### `scenes/effects/sun_target_preview.tscn`
**Role:** lightweight visual target helper for sun.

**Structure:** `Node2D` using the same configurable preview script as rain, but with sun colors and radius `2`.

**Keep in mind:** this is a removable visual overlay only. It shows the 5x5 sun target area. The separate 7x7 spread-reset area is gameplay logic, not necessarily previewed.

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

### `scripts/resources/grass.gd`
**Role:** grass lifecycle.

**Owns:** two growth stages, timers, world registration, single spread attempt, spreading to 4 cardinal neighbors, fallback to stage 1 after consumption, rain reaction hooks, sun reaction hooks, and spread-attempt reset support.

**Rain behaviour:** rain does not create grass directly. Stage 1 grass immediately becomes stage 2; stage 2 grass triggers the existing one-time spread logic and stops the spread timer so the forced spread does not double-fire.

**Sun behaviour:** sun can revert adult stage 2 grass to stage 1, then selected grass nodes can be removed by the player nature UI. A separate reset hook clears `has_tried_to_spread` so sun-hit areas can recover and spread again instead of becoming sterile.

### `scripts/ui/creature_stats_ui.gd`
**Role:** creature HUD and lightweight observation/debug UI.

**Owns:** hover preview, click-to-pin selection, name/age/health/hunger display, health/hunger bars, FPS/debug text, and simulation speed switching.

### `scripts/ui/player_nature_ui.gd`
**Role:** player-facing nature powers HUD.

**Owns:** nature energy, energy regeneration, spell button enable/disable states, lightning targeting/damage/effect spawn, rain targeting, sun targeting, nature action costs, and calling grass reactions in tile areas.

**Current balance defaults live here:**
- `max_energy := 500.0`
- `starting_energy := 0.0`
- `energy_regen_per_second := 1.0`
- `lightning_damage := 50.0`
- `lightning_energy_cost := 50.0`
- `rain_energy_cost := 25.0`
- `rain_radius_tiles := 1` (`3x3`)
- `sun_energy_cost := 100.0`
- `sun_radius_tiles := 2` (`5x5`)
- `sun_spread_reset_radius_tiles := 3` (`7x7`)
- `sun_remove_grass_count := 8`

**Keep in mind:** player powers should stay indirect. Rain accelerates grass lifecycle through existing grass logic. Sun reduces/clears grass and resets spread opportunity in the local area, but should not become direct creature control.

### `scripts/effects/rain_target_preview.gd`
**Role:** configurable square targeting preview helper.

**Owns:** drawing the highlighted tile area under the cursor while a tile-targeted nature power is armed.

**Used by:** rain preview and sun preview scenes.

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
`HoverArea` talks to the `creature_stats_ui` group. The UI asks creatures for name, age, health, hunger, and max values. Player nature UI can apply lightning damage through creature methods.

### PlayerNatureUI -> Grass/World
`player_nature_ui.gd` finds the `world_grid` group, converts mouse position to a tile, scans tile areas for grass, and calls grass methods such as `apply_rain()`, `apply_sun()`, and `reset_spread_attempt()`. It should remain a caller of world/resource logic, not the owner of grass rules.

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
- directional creature sprites plus stegosaurus right/up walk animation;
- age, hunger, health, starvation damage, well-fed healing, and death;
- hover and click creature selection;
- grid-based grass search and pathfinding;
- adult grass eating and grass regrowth;
- grass spreading once to cardinal neighbors;
- rain accelerating grass growth/spread in a 3x3 area;
- sun reverting/removing grass in a 5x5 area and resetting spread opportunity in a 7x7 area;
- egg laying, egg growth, stage 2 blocking, and hatching;
- simple predator species data and predator behaviour helper;
- isolated 1v1 duel loop;
- player nature energy economy;
- lightning damage with energy cost and visual strike effect;
- rain action with energy cost and 3x3 target preview;
- sun action with energy cost and 5x5 target preview;
- stats panel, FPS/debug text, simulation speed control;
- F3 grid overlay;
- F8 CSV performance recording.

---

## 7. Where to look first for new tasks

### Movement / path / footprint / stuck behaviour
1. `scripts/world/world_grid.gd`
2. `scripts/creatures/creature.gd`
3. `scripts/creatures/behaviors/creature_visual_controller.gd`

### Grazing / grass search / eating
1. `scripts/creatures/behaviors/creature_grazing_logic.gd`
2. `scripts/world/world_grid.gd`
3. `scripts/resources/grass.gd`

### Grass lifecycle / nature effects on grass
1. `scripts/resources/grass.gd`
2. `scripts/ui/player_nature_ui.gd`
3. `scripts/effects/rain_target_preview.gd`
4. `scenes/effects/rain_target_preview.tscn`
5. `scenes/effects/sun_target_preview.tscn`

### Player powers / energy / targeting
1. `scripts/ui/player_nature_ui.gd`
2. `scenes/main/main.tscn`
3. `scripts/effects/lightning_strike_effect.gd`
4. `scripts/effects/rain_target_preview.gd`

### Predator / combat
1. `scripts/creatures/behaviors/creature_predator_logic.gd`
2. `scripts/combat/duel.gd`
3. `scripts/creatures/creature.gd`

### Eggs / reproduction
1. `scripts/creatures/behaviors/creature_reproduction_logic.gd`
2. `scripts/resources/egg.gd`
3. `scripts/creatures/creature_species_data.gd`

### UI / selection / debug
1. `scripts/ui/creature_stats_ui.gd`
2. `scripts/ui/player_nature_ui.gd`
3. `scripts/debug/grid_debug_overlay.gd`
4. `scripts/debug/performance_stats.gd`
