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
- calling world/resource methods for nature effects.

Helper scripts own subsystem details, but they operate through the owning creature and world grid.

---

## 2. High-level dependency graph

```text
project.godot
└── scenes/main/main.tscn
    ├── Camera2D -> scripts/camera/camera_controller.gd
    ├── UI -> scripts/ui/creature_stats_ui.gd
    ├── PlayerNaturePanel -> scripts/ui/player_nature_ui.gd
    │   ├── LightningStrikeEffect -> scenes/effects/lightning_strike_effect.tscn -> scripts/effects/lightning_strike_effect.gd
    │   └── RainTargetPreview -> scenes/effects/rain_target_preview.tscn -> scripts/effects/rain_target_preview.gd
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

### `scripts/creatures/behaviors/creature_grazing_logic.gd`
**Owns:** herbivore grazing detail logic.

**Depends on:**
- owner `creature.gd`
- owner `world_grid`
- `world_grid.find_best_grazing_targets()`
- `world_grid.count_adult_grass_under_footprint()`
- `world_grid.find_path()`

**Used by:** `creature.gd`.

**Touch when:** herbivore food search, target selection, retargeting, path-to-food, or eating eligibility breaks.

---

### `scripts/creatures/behaviors/creature_predator_logic.gd`
**Owns:** predator detail logic.

**Depends on:**
- owner `creature.gd`
- `scripts/combat/duel.gd`
- owner `world_grid`
- `world_grid.creature_anchors`
- `world_grid.find_path()` and `world_grid.estimate_path_steps()`
- `species_data` flags/tuning such as `is_predator`, `predator_target_radius`, `hunger_search_threshold`

**Used by:** `creature.gd`.

**Touch when:** predator target choice, chase path, duel range, or side-contact rules break.

---

### `scripts/creatures/behaviors/creature_reproduction_logic.gd`
**Owns:** reproduction detail logic.

**Depends on:**
- owner `creature.gd`
- owner `world_grid`
- `species_data` egg scene/textures/timing/hatchling stats/reproduction thresholds
- `scenes/resources/egg.tscn`
- `Eggs` container in world scene

**Used by:** `creature.gd`.

**Touch when:** reproduction conditions, egg placement, egg tuning transfer, or egg spawning breaks.

---

### `scripts/creatures/behaviors/creature_visual_controller.gd`
**Owns:** creature visual detail logic.

**Depends on:**
- owner `creature.gd`
- owner `species_data` directional textures and walk frames
- `BodySprite`
- `WalkRightSprite`

**Used by:** `creature.gd`.

**Touch when:** sprite direction, mirroring, animation/static switching, or walk animation setup breaks.

---

### `scripts/creatures/creature_species_data.gd`
**Owns:** species resource schema.

**Used by:**
- `data/species/stegosaurus.tres`
- `data/species/predator.tres`
- `creature.gd`
- behaviour helpers
- `egg.gd` through hatch species configuration

**Touch when:** adding new species-wide stat fields, visuals, animation fields, hunger tuning, reproduction tuning, or predator tuning.

**Important:** changing this schema can require updating every `.tres` species resource.

---

### `data/species/stegosaurus.tres`
**Owns:** current herbivore tuning and visuals.

**Depends on:**
- `creature_species_data.gd`
- stegosaurus directional textures
- walk animation resources
- `scenes/resources/egg.tscn`
- egg textures

**Used by:** creature scene default, hatched creatures, and balancing.

**Touch when:** changing herbivore stats, visuals, hunger, reproduction, egg timings, or walk animation.

---

### `data/species/predator.tres`
**Owns:** current temporary predator tuning and visuals.

**Depends on:**
- `creature_species_data.gd`
- predator directional textures
- egg scene/textures, although reproduction is effectively disabled through very high thresholds

**Used by:** optional predator spawn and predator balancing.

**Touch when:** changing predator stats, hunger threshold, target radius, combat numbers, or visuals.

---

### `scripts/combat/duel.gd`
**Owns:** isolated duel loop.

**Depends on:** fighters exposing methods/properties:
- `attach_duel()`
- `detach_duel()`
- `can_continue_duel()`
- `take_duel_damage()`
- `get_attack()` / `get_defense()` or species data fallback

**Used by:**
- `creature.gd`
- `creature_predator_logic.gd`

**Touch when:** turn order, duel timing, damage formula, or finish behaviour changes.

---

### `scenes/resources/grass.tscn`
**Owns:** grass scene node structure.

**Depends on:**
- `scripts/resources/grass.gd`
- `assets/sprites/terrain/grass_stage_1.png`
- `assets/sprites/terrain/grass_stage_2.png`

**Used by:**
- `scenes/world/world.tscn`
- `grass.gd` self-spread instancing

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
- `player_nature_ui.gd` indirectly through rain calling `apply_rain()` on grass in the targeted 3x3 area

**Touch when:** growth timing, spreading, edibility, consumption, blocked-terrain handling, rain reaction, or grass visual stage changes.

---

### `scenes/resources/egg.tscn`
**Owns:** egg scene node structure.

**Depends on:**
- `scripts/resources/egg.gd`
- egg stage textures

**Used by:**
- `scenes/world/world.tscn`
- species data resources and reproduction helper

**Touch when:** egg node structure or default resource setup changes.

---

### `scripts/resources/egg.gd`
**Owns:** egg lifecycle and hatching.

**Depends on:**
- `world_grid.gd` found through scene tree
- `BodySprite`, `Stage1Timer`, `ExpandRetryTimer`, `HatchTimer`
- `hatch_species_data`
- `hatch_creature_scene`
- `Creatures` container in world scene

**Used by:** reproduction system and predator/creature food logic if eggs are treated as edible targets later.

**Touch when:** egg placement, expansion, blocker registration, edibility, hatching, or hatchling setup changes.

---

### `scripts/ui/creature_stats_ui.gd`
**Owns:** prototype creature/debug UI.

**Depends on:**
- UI node paths in `scenes/main/main.tscn`
- creature public methods and properties
- `PerformanceStats` autoload
- `world_grid` group for debug status
- camera node for mouse world position

**Used by:** creature hover/click callbacks and player input.

**Touch when:** stats panel, selection, speed controls, FPS/debug status, or creature UI input changes.

---

### `scripts/ui/player_nature_ui.gd`
**Owns:** player-facing nature powers HUD.

**Depends on:**
- UI node paths in `scenes/main/main.tscn` under `PlayerNaturePanel`
- `world_grid` group for mouse tile conversion and grass lookup
- creature public direct-damage method for lightning
- `scripts/resources/grass.gd` exposing `apply_rain()`
- `scenes/effects/lightning_strike_effect.tscn`
- `scenes/effects/rain_target_preview.tscn`
- `PerformanceStats` autoload for rain counters

**Used by:** player input and creature click forwarding.

**Touch when:** player energy, spell costs, lightning targeting, rain targeting, rain area size, or player nature UI changes.

---

### `scenes/effects/lightning_strike_effect.tscn`
**Owns:** lightning visual effect instance.

**Depends on:**
- `scripts/effects/lightning_strike_effect.gd`
- `data/animations/lightning_strike_frames.tres`

**Used by:** `player_nature_ui.gd`.

---

### `scripts/effects/lightning_strike_effect.gd`
**Owns:** lightning visual effect lifecycle.

**Depends on:**
- `AnimatedSprite2D`
- `SpriteFrames` on the scene instance

**Used by:** `scenes/effects/lightning_strike_effect.tscn`.

---

### `scenes/effects/rain_target_preview.tscn`
**Owns:** visual rain target preview instance.

**Depends on:**
- `scripts/effects/rain_target_preview.gd`

**Used by:** `player_nature_ui.gd`.

---

### `scripts/effects/rain_target_preview.gd`
**Owns:** drawing the 3x3 rain target highlight.

**Depends on:**
- `world_grid.map_to_world_center()` called through the world grid reference
- `world_grid.tile_size` for drawing tile-sized rectangles

**Used by:** `scenes/effects/rain_target_preview.tscn`.

**Touch when:** rain targeting visuals, highlight colours, tile preview sizing, or preview placement changes.

---

### `scripts/debug/grid_debug_overlay.gd`
**Owns:** optional visual debug overlay.

**Depends on:**
- `world_grid` group
- creature selection/hover state from UI or groups
- world dictionaries and creature path/target properties

**Used by:** `scenes/debug/grid_debug_overlay.tscn`.

**Touch when:** debug visualization, F3 toggle, or debug info panel changes.

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

### `scripts/camera/camera_controller.gd`
**Owns:** observer camera.

**Depends on:** Camera2D node in main scene.

**Used by:** `scenes/main/main.tscn`.

**Touch when:** camera movement, zoom, bounds, or future observer camera behaviour changes.

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
-> SpreadTimer starts
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

### Player lightning flow
```text
PlayerNaturePanel/player_nature_ui.gd
-> player spends 50 energy after clicking a valid creature
-> lightning effect scene is instanced at target position
-> creature.take_direct_damage(50)
-> creature may die and unregister from world_grid
```

### Reproduction flow
```text
creature meets reproduction thresholds
-> creature_reproduction_logic picks available egg anchor
-> creature enters LAYING_EGG
-> egg scene spawns into Eggs container
-> stage 1 egg is non-blocking
-> stage 2 expansion registers blocker
-> hatch timer spawns new creature and unregisters blocker
```

### Predator combat flow
```text
predator hunger reaches hunt threshold
-> creature_predator_logic finds prey
-> path to side-adjacent anchor
-> side-contact check passes
-> duel starts
-> duel alternates attacks
-> loser dies
-> winner detaches
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
