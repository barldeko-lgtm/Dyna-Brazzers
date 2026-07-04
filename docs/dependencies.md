# Dyna — Dependency Map

> Practical dependency graph for agents and future sessions. Use this when deciding which files to inspect or send for a task.

---

## 1. Core principle

`world_grid.gd` is the source of truth for the physical simulation grid:
- terrain;
- walkability;
- occupancy;
- blockers;
- paths;
- grass lookup;
- grazing target queries.

`creature.gd` is the source of truth for creature runtime state:
- current state;
- health/hunger/age;
- anchor and movement state;
- current path and targets;
- duel attachment;
- helper coordination.

`player_nature_ui.gd` owns the current player-facing nature action surface:
- energy;
- spell button states;
- lightning targeting;
- rain targeting;
- sun targeting;
- calling world/resource methods for nature effects.

Helper scripts own subsystem details, but they operate through the owning creature and world grid.

Balance values for player nature actions currently live in `scripts/ui/player_nature_ui.gd`. Do not duplicate those exported values in `scenes/main/main.tscn` unless a deliberate per-scene override is needed.

---

## 2. High-level dependency graph

```text
project.godot
└── scenes/main/main.tscn
    ├── Camera2D -> scripts/camera/camera_controller.gd
    ├── UI -> scripts/ui/creature_stats_ui.gd
    ├── PlayerNaturePanel -> scripts/ui/player_nature_ui.gd
    │   ├── LightningStrikeEffect -> scenes/effects/lightning_strike_effect.tscn -> scripts/effects/lightning_strike_effect.gd
    │   ├── RainTargetPreview -> scenes/effects/rain_target_preview.tscn -> scripts/effects/rain_target_preview.gd
    │   └── SunTargetPreview -> scenes/effects/sun_target_preview.tscn -> scripts/effects/rain_target_preview.gd
    ├── World -> scenes/world/world.tscn
    │   └── World -> scripts/world/world_grid.gd
    │       ├── Creatures -> scenes/creatures/creature.tscn -> scripts/creatures/creature.gd
    │       ├── Grasses -> scenes/resources/grass.tscn -> scripts/resources/grass.gd
    │       ├── Eggs -> scenes/resources/egg.tscn -> scripts/resources/egg.gd
    │       └── Ground -> TileMapLayer terrain source
    └── GridDebugOverlay -> scripts/debug/grid_debug_overlay.gd

PerformanceStats autoload -> scripts/debug/performance_stats.gd
```

---

## 3. File-by-file dependencies

### `project.godot`
**Owns:** main scene and autoload registration.

**Depends on:**
- `scenes/main/main.tscn`
- `scripts/debug/performance_stats.gd` as `PerformanceStats`

**Touch when:** changing startup scene or autoloads.

---

### `scenes/main/main.tscn`
**Owns:** top-level scene assembly.

**Depends on:**
- `scenes/world/world.tscn`
- `scenes/debug/grid_debug_overlay.tscn`
- `scripts/camera/camera_controller.gd`
- `scripts/ui/creature_stats_ui.gd`
- `scripts/ui/player_nature_ui.gd`

**Used by:** `project.godot`.

**Touch when:** adding/removing top-level UI, camera, world instance, debug overlay, global scene nodes, or player nature HUD nodes.

**Important:** avoid scene-level overrides for player nature balance values unless intentional. Defaults should usually stay in `scripts/ui/player_nature_ui.gd`.

---

### `scenes/world/world.tscn`
**Owns:** world node layout and placed sandbox objects.

**Depends on:**
- `scripts/world/world_grid.gd`
- `scenes/creatures/creature.tscn`
- `scenes/resources/grass.tscn`
- terrain sprites in `assets/sprites/terrain/`

**Used by:** `scenes/main/main.tscn`.

**Important child nodes:**
- `Creatures`
- `PredatorSpawn`
- `Grasses`
- `Eggs`
- `Ground`

**Touch when:** changing test map, placed creatures/grass, terrain tile setup, spawn markers, or world containers.

---

### `scripts/world/world_grid.gd`
**Owns:** grid authority.

**Depends on:**
- `Ground` child from `scenes/world/world.tscn`
- `scenes/creatures/creature.tscn` for optional predator spawn
- `data/species/predator.tres` for optional predator spawn
- grass/creature/egg nodes calling registration methods

**Used by:**
- `scripts/creatures/creature.gd`
- `scripts/creatures/behaviors/creature_grazing_logic.gd`
- `scripts/creatures/behaviors/creature_predator_logic.gd`
- `scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `scripts/resources/grass.gd`
- `scripts/resources/egg.gd`
- `scripts/debug/grid_debug_overlay.gd`
- `scripts/debug/performance_stats.gd`
- `scripts/ui/creature_stats_ui.gd`
- `scripts/ui/player_nature_ui.gd`
- `scripts/effects/rain_target_preview.gd`

**Critical data dictionaries:**
- `grass_by_tile`
- `creature_anchors`
- `blocker_anchors`
- `occupied_by_tile`

**Touch when:** movement/pathing/terrain/occupancy/grass-search/blocker bugs appear.

**Do not change blindly:** `register_creature`, `move_creature`, `unregister_creature`, `register_blocker`, `unregister_blocker`, `can_place_footprint`, pathfinding, and grazing scoring.

---

### `scenes/creatures/creature.tscn`
**Owns:** base creature node structure.

**Depends on:**
- `scripts/creatures/creature.gd`
- `data/species/stegosaurus.tres` by default

**Used by:**
- `scenes/world/world.tscn`
- `scripts/world/world_grid.gd` optional predator spawn
- `scripts/resources/egg.gd` hatching

**Important child nodes:**
- `BodySprite`
- `WalkRightSprite`
- `CollisionShape2D`
- `EatingTimer`
- `EggLayingTimer`
- `HoverArea`

**Touch when:** creature node structure, collisions, hover area, timers, or default species data change.

---

### `scripts/creatures/creature.gd`
**Owns:** base creature runtime coordination.

**Depends on:**
- `scripts/combat/duel.gd`
- `scripts/creatures/behaviors/creature_grazing_logic.gd`
- `scripts/creatures/behaviors/creature_predator_logic.gd`
- `scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `scripts/creatures/behaviors/creature_visual_controller.gd`
- `scripts/creatures/creature_species_data.gd`
- `world_grid.gd` found through scene tree
- `creature_stats_ui` group for hover/click UI
- `player_nature_ui` group for player nature targeting, when creature clicks are forwarded to active player powers

**Used by:**
- `scenes/creatures/creature.tscn`
- helper scripts through owner callbacks and owner state access
- `duel.gd` through combat hooks
- UI/debug scripts through public getters
- `player_nature_ui.gd` for direct lightning damage

**Main state:**
- `state`
- `health`, `hunger`, `age`
- `anchor_tile`, `pending_anchor_tile`, `movement_target_position`
- `current_path`
- `grazing_target_anchor`, `has_grazing_target`, `grazing_candidate_queue`
- `current_duel`

**Touch when:** high-level creature lifecycle/state changes are needed.

**Do not change blindly:** movement sync, eating entry, duel attach/detach, death/unregister flow, helper delegation.

---

### `scripts/resources/grass.gd`
**Owns:** grass lifecycle.

**Depends on:**
- `world_grid.gd` found through scene tree
- own scene path for spreading new grass
- `BodySprite`, `GrowthTimer`, `SpreadTimer`

**Used by:**
- `world_grid.gd` through registration and consumption calls
- creatures indirectly through grazing/world queries
- `player_nature_ui.gd` through rain calling `apply_rain()`
- `player_nature_ui.gd` through sun calling `apply_sun()`, random removal, and `reset_spread_attempt()`

**Touch when:** growth timing, spreading, edibility, consumption, blocked-terrain handling, rain reaction, sun reaction, spread-reset behaviour, or grass visual stage changes.

---

### `scripts/ui/player_nature_ui.gd`
**Owns:** player-facing nature powers HUD.

**Depends on:**
- UI node paths in `scenes/main/main.tscn` under `PlayerNaturePanel`
- `world_grid` group for mouse tile conversion and grass lookup
- creature public direct-damage method for lightning
- `scripts/resources/grass.gd` exposing `apply_rain()`, `apply_sun()`, and `reset_spread_attempt()`
- `scenes/effects/lightning_strike_effect.tscn`
- `scenes/effects/rain_target_preview.tscn`
- `scenes/effects/sun_target_preview.tscn`
- `PerformanceStats` autoload for nature-action counters

**Used by:** player input and creature click forwarding.

**Touch when:** player energy, spell costs, lightning targeting, rain targeting, sun targeting, sun grass removal count, target area sizes, or player nature UI changes.

---

### `scenes/effects/lightning_strike_effect.tscn`
**Owns:** lightning visual effect instance.

**Depends on:**
- `scripts/effects/lightning_strike_effect.gd`
- `data/animations/lightning_strike_frames.tres`

**Used by:** `player_nature_ui.gd`.

---

### `scenes/effects/rain_target_preview.tscn`
**Owns:** visual rain target preview instance.

**Depends on:**
- `scripts/effects/rain_target_preview.gd`

**Used by:** `player_nature_ui.gd`.

---

### `scenes/effects/sun_target_preview.tscn`
**Owns:** visual sun target preview instance.

**Depends on:**
- `scripts/effects/rain_target_preview.gd`

**Used by:** `player_nature_ui.gd`.

---

### `scripts/effects/rain_target_preview.gd`
**Owns:** drawing configurable square target highlights.

**Depends on:**
- `world_grid.map_to_world_center()` called through the world grid reference
- `world_grid.tile_size` for drawing tile-sized rectangles

**Used by:**
- `scenes/effects/rain_target_preview.tscn`
- `scenes/effects/sun_target_preview.tscn`

**Touch when:** tile targeting visuals, highlight colours, tile preview sizing, or preview placement changes.

---

### `scripts/debug/performance_stats.gd`
**Owns:** performance counters and CSV logging.

**Depends on:**
- autoload registration in `project.godot`
- `world_grid` group for grass/creature counts
- `logs/` folder creation/access

**Used by:**
- `creature_stats_ui.gd`
- `player_nature_ui.gd`
- `grass.gd`
- any script that calls `PerformanceStats.add_counter()`

**Touch when:** changing counters, CSV columns, sample frequency, log path, or F8 behaviour.

---

## 4. Runtime flow maps

### Startup flow
```text
project.godot
-> main.tscn
-> UI ready / player nature UI ready / camera ready / world instance ready / debug overlay ready
-> world_grid._ready()
-> world caches Ground tile size and map bounds
-> placed grass/creatures/eggs find world_grid and register/sync
```

### Creature movement flow
```text
creature state chooses movement/path
-> world_grid.find_path()
-> creature reserves/moves anchor through world_grid
-> visual position interpolates toward anchor world position
```

### Herbivore grazing flow
```text
creature hunger reaches search threshold
-> creature_grazing_logic finds/scans targets
-> world_grid counts adult grass under candidate footprints
-> creature paths to selected anchor
-> eating timer completes
-> world_grid.consume_adult_grass_under_footprint()
-> grass.consume()
-> grass returns to stage 1 and restarts growth timer
```

### Grass growth/spread flow
```text
grass starts at stage 1
-> GrowthTimer completes
-> grass becomes stage 2
-> SpreadTimer starts if has_tried_to_spread is false
-> spread tick triggers one-time cardinal spread
-> spread timer stops
```

### Player rain flow
```text
PlayerNaturePanel/player_nature_ui.gd
-> player spends 25 energy after clicking a valid ground tile
-> rain preview is hidden
-> UI scans the 3x3 tile area through world_grid tile/grass lookup
-> grass.apply_rain()
-> stage 1 grass becomes stage 2
-> stage 2 grass triggers existing one-time cardinal spread logic
```

### Player sun flow
```text
PlayerNaturePanel/player_nature_ui.gd
-> player spends 100 energy after clicking a valid ground tile
-> sun preview is hidden
-> UI scans the 5x5 tile area through world_grid tile/grass lookup
-> adult grass.apply_sun()
-> adult grass returns to stage 1
-> up to sun_remove_grass_count grass nodes are randomly queue_free()'d from the 5x5 area
-> UI scans the 7x7 spread-reset area
-> remaining grass.reset_spread_attempt()
-> mature remaining grass can start spread timer again
-> young remaining grass can spread after growing up again
```

### Player lightning flow
```text
PlayerNaturePanel/player_nature_ui.gd
-> player spends 50 energy after clicking a valid creature
-> lightning effect scene is instanced at target position
-> creature.take_direct_damage(50)
-> creature may die and unregister from world_grid
```

---

## 5. Task-based file bundles

### Add/change a player nature action
Read first:
- `docs/project-map.md`
- `docs/current-state.md`
- `docs/dependencies.md`
- `scripts/ui/player_nature_ui.gd`
- `scenes/main/main.tscn`

Often related:
- `scripts/world/world_grid.gd`
- target resource script, e.g. `scripts/resources/grass.gd`
- visual helper scene/script if the action needs targeting or effect feedback

### Change player nature balance
Read first:
- `scripts/ui/player_nature_ui.gd`

Rule:
- keep default balance values in `player_nature_ui.gd`;
- avoid duplicating exported values in `scenes/main/main.tscn` unless a scene override is intentional.

### Change rain
Read first:
- `scripts/ui/player_nature_ui.gd`
- `scripts/resources/grass.gd`
- `scripts/effects/rain_target_preview.gd`
- `scenes/main/main.tscn`

Rules:
- rain should not spawn grass directly;
- stage 1 grass should use the existing growth/stage logic;
- stage 2 grass should use the existing one-time spread logic;
- timers should not double-fire after forced rain spread.

### Change sun
Read first:
- `scripts/ui/player_nature_ui.gd`
- `scripts/resources/grass.gd`
- `scenes/effects/sun_target_preview.tscn`
- `scripts/effects/rain_target_preview.gd`
- `scenes/main/main.tscn`

Rules:
- visible sun target area is 5x5 (`sun_radius_tiles := 2`);
- spread-reset area is 7x7 (`sun_spread_reset_radius_tiles := 3`);
- grass removal count is `sun_remove_grass_count`;
- sun should spend energy on valid ground click even if little/no grass is affected;
- deleted grass should be removed with `queue_free()` so `_exit_tree()` unregisters it from `world_grid`;
- sun should not leave areas permanently unable to spread.

### Change lightning
Read first:
- `scripts/ui/player_nature_ui.gd`
- `scenes/effects/lightning_strike_effect.tscn`
- `scripts/effects/lightning_strike_effect.gd`
- `data/animations/lightning_strike_frames.tres`

### Change grass lifecycle
Read first:
- `scripts/resources/grass.gd`
- `scenes/resources/grass.tscn`
- `scripts/world/world_grid.gd`

### Change creature movement/pathing
Read first:
- `scripts/world/world_grid.gd`
- `scripts/creatures/creature.gd`
- `scripts/creatures/behaviors/creature_grazing_logic.gd`

### Change predator/combat
Read first:
- `scripts/creatures/behaviors/creature_predator_logic.gd`
- `scripts/combat/duel.gd`
- `scripts/creatures/creature.gd`

### Change reproduction/eggs
Read first:
- `scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `scripts/resources/egg.gd`
- `scenes/resources/egg.tscn`
- `scripts/creatures/creature_species_data.gd`

### Change UI/debug
Read first:
- `scripts/ui/creature_stats_ui.gd`
- `scripts/ui/player_nature_ui.gd`
- `scripts/debug/grid_debug_overlay.gd`
- `scripts/debug/performance_stats.gd`
