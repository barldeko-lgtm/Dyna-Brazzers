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

Helper scripts own subsystem details, but they operate through the owning creature and world grid.

---

## 2. High-level dependency graph

```text
project.godot
└── scenes/main/main.tscn
    ├── Camera2D -> scripts/camera/camera_controller.gd
    ├── UI -> scripts/ui/creature_stats_ui.gd
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

**Used by:** `project.godot`.

**Touch when:** adding/removing top-level UI, camera, world instance, debug overlay, or global scene nodes.

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

**Used by:**
- `scenes/creatures/creature.tscn`
- helper scripts through owner callbacks and owner state access
- `duel.gd` through combat hooks
- UI/debug scripts through public getters

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
- `data/animations/stegosaurus_walk_right_frames.tres`
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

### `data/animations/stegosaurus_walk_right_frames.tres`
**Owns:** stegosaurus right-facing walk animation frames.

**Depends on:**
- `assets/sprites/creatures/stegosaurus/stegosaurus_walk_right_01.png` through `_06.png`

**Used by:** `data/species/stegosaurus.tres` and `creature_visual_controller.gd`.

**Touch when:** changing walk frames, animation speed source, or animation resource path.

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

**Touch when:** growth timing, spreading, edibility, consumption, blocked-terrain handling, or grass visual stage changes.

---

### `scenes/resources/egg.tscn`
**Owns:** egg scene node structure.

**Depends on:**
- `scripts/resources/egg.gd`
- egg stage textures

**Used by:** species data resources and reproduction helper.

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
**Owns:** prototype UI and player action surface.

**Depends on:**
- UI node paths in `scenes/main/main.tscn`
- creature public methods and properties
- `PerformanceStats` autoload
- `world_grid` group for debug status
- camera node for mouse world position

**Used by:** creature hover/click callbacks and player input.

**Touch when:** stats panel, selection, lightning, speed controls, FPS/debug status, or UI input changes.

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
-> UI ready / camera ready / world instance ready / debug overlay ready
-> world_grid._ready()
-> world caches Ground tile size and map bounds
-> placed grass/creatures/eggs find world_grid and register/sync
```

### Creature movement flow
```text
creature.gd state update
-> decide next anchor/path step
-> world_grid.move_creature() reserves new footprint
-> creature stores pending_anchor_tile and movement_target_position
-> visual position moves smoothly
-> anchor_tile commits when movement reaches target
```

### Herbivore food flow
```text
hunger reaches search threshold
-> creature enters SEEK_FOOD
-> creature_grazing_logic requests candidates from world_grid
-> world_grid scores adult grass under possible footprints
-> creature builds path to selected anchor
-> creature reaches anchor
-> eating timer starts
-> world_grid.consume_adult_grass_under_footprint()
-> grass.consume() returns grass to stage 1
-> creature restores hunger
```

### Grass lifecycle flow
```text
grass.tscn ready
-> grass finds world_grid
-> syncs tile position
-> registers grass_by_tile
-> growth timer turns stage 1 into stage 2
-> spread timer tries cardinal spread once
-> adult grass can be consumed and returns to stage 1
```

### Reproduction and egg flow
```text
creature.gd reproduction update
-> creature_reproduction_logic checks species thresholds/cooldown
-> creature enters LAYING_EGG
-> egg timer timeout
-> reproduction helper spawns egg.tscn in Eggs container
-> egg stage 1 starts non-blocking 1x2
-> egg tries to register stage 2 blocker 2x2
-> hatch timer timeout
-> egg unregisters blocker
-> egg spawns creature.tscn into Creatures container
```

### Predator combat flow
```text
predator hunger reaches threshold
-> creature_predator_logic finds nearest valid non-predator prey
-> builds path to side-adjacent approach anchor
-> side-contact check passes
-> helper creates Duel
-> fighters attach duel and enter COMBAT
-> duel alternates attacks each second
-> loser dies / unregisters
-> winner detaches; predator restores hunger
```

### Lightning flow
```text
UI lightning button toggled on
-> next left-click on creature HoverArea
-> creature_stats_ui.try_apply_lightning_to_creature()
-> creature.take_direct_damage(50)
-> creature may enter DEAD and unregister from world_grid
```

### Performance logging flow
```text
PerformanceStats autoload runs
-> UI displays current status/rates
-> F8 toggles CSV recording
-> PerformanceStats writes samples to logs/perf_log_*.csv
```

---

## 5. Task-based file bundles

Use these bundles when the user does not know which files to provide.

### Movement, stuck creatures, wrong position, ghost occupancy
Send/check:
1. `scripts/world/world_grid.gd`
2. `scripts/creatures/creature.gd`
3. `scripts/creatures/behaviors/creature_visual_controller.gd`
4. `scenes/world/world.tscn`
5. `scenes/creatures/creature.tscn`

### Grass search, eating, food retargeting, herbivore starvation
Send/check:
1. `scripts/creatures/behaviors/creature_grazing_logic.gd`
2. `scripts/creatures/creature.gd`
3. `scripts/world/world_grid.gd`
4. `scripts/resources/grass.gd`
5. `scenes/resources/grass.tscn`
6. `data/species/stegosaurus.tres`

### Grass growth/spread/performance spam
Send/check:
1. `scripts/resources/grass.gd`
2. `scripts/world/world_grid.gd`
3. `scripts/debug/performance_stats.gd`
4. `scripts/ui/creature_stats_ui.gd`
5. recent `logs/perf_log_*.csv` if available

### Eggs, reproduction, hatching, blocker bugs
Send/check:
1. `scripts/creatures/behaviors/creature_reproduction_logic.gd`
2. `scripts/resources/egg.gd`
3. `scripts/creatures/creature.gd`
4. `scripts/world/world_grid.gd`
5. `scenes/resources/egg.tscn`
6. `data/species/stegosaurus.tres`

### Predator hunting, combat entry, duel bugs
Send/check:
1. `scripts/creatures/behaviors/creature_predator_logic.gd`
2. `scripts/combat/duel.gd`
3. `scripts/creatures/creature.gd`
4. `scripts/world/world_grid.gd`
5. `data/species/predator.tres`
6. `data/species/stegosaurus.tres`

### Creature visuals, animation, facing direction
Send/check:
1. `scripts/creatures/behaviors/creature_visual_controller.gd`
2. `scripts/creatures/creature.gd`
3. `scripts/creatures/creature_species_data.gd`
4. `data/species/stegosaurus.tres`
5. `data/animations/stegosaurus_walk_right_frames.tres`
6. relevant sprite files under `assets/sprites/creatures/`

### Creature stats and balancing
Send/check:
1. `scripts/creatures/creature_species_data.gd`
2. `data/species/stegosaurus.tres`
3. `data/species/predator.tres`
4. `scripts/creatures/creature.gd`
5. relevant behaviour helper script

### UI, selection, lightning, speed controls
Send/check:
1. `scripts/ui/creature_stats_ui.gd`
2. `scenes/main/main.tscn`
3. `scripts/creatures/creature.gd`
4. `scripts/debug/performance_stats.gd` if debug status is involved

### Debug overlay and visual diagnostics
Send/check:
1. `scripts/debug/grid_debug_overlay.gd`
2. `scenes/debug/grid_debug_overlay.tscn`
3. `scripts/world/world_grid.gd`
4. `scripts/creatures/creature.gd`
5. `scripts/ui/creature_stats_ui.gd`

### Performance logging / CSV / counters
Send/check:
1. `scripts/debug/performance_stats.gd`
2. `scripts/ui/creature_stats_ui.gd`
3. `project.godot`
4. recent `logs/perf_log_*.csv`
5. system scripts suspected of high activity, usually `grass.gd`, `creature.gd`, or `world_grid.gd`

### Camera controls
Send/check:
1. `scripts/camera/camera_controller.gd`
2. `scenes/main/main.tscn`

### Terrain / water / mountains / path blocking
Send/check:
1. `scripts/world/world_grid.gd`
2. `scenes/world/world.tscn`
3. terrain sprites/imports under `assets/sprites/terrain/`
4. any creature/pathing script affected by the issue

---

## 6. Documentation dependency rules

When code changes, update docs as follows:

### Update `docs/current-state.md` when:
- a feature starts working;
- a feature is disabled/enabled in a meaningful way;
- a major prototype limitation changes;
- debug/performance tooling changes;
- the real current behaviour no longer matches the snapshot.

### Update `docs/project-map.md` when:
- files/scenes are added, renamed, removed, or responsibilities move;
- a subsystem is split into a helper script;
- a new important data resource appears;
- startup or scene structure changes.

### Update `docs/dependencies.md` when:
- a script starts calling another script/resource;
- a new task bundle is useful;
- ownership of a system moves;
- fragile dependency links change.

### Update `AGENTS.md` when:
- agent rules change;
- read order changes;
- architecture canon changes;
- fragile areas change.

### Do not update `docs/design_roadmap.md` unless:
- the user explicitly asks to edit roadmap/design vision;
- roadmap milestones themselves change.
