# Dyna — Dependencies

> Purpose: explain how important files depend on each other and which files to inspect for common tasks. This file may be more detailed than the other docs because it is a working guide for code changes.

---

## 1. Core dependency principles

### World grid is the physical source of truth

`res://scripts/world/world_grid.gd` owns:
- terrain lookup;
- walkability;
- footprint placement;
- pathfinding;
- grass lookup;
- creature occupancy;
- blocker occupancy.

If a task touches movement, standing position, blocked tiles, resource lookup, or pathing, inspect `world_grid.gd`.

### Creature script is the runtime coordinator

`res://scripts/creatures/creature.gd` owns high-level runtime state and delegates subsystem details to helpers.

Important linked helpers:
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`

### Resources own their lifecycle

Grass and eggs should manage their own internal state:
- `res://scripts/resources/grass.gd`
- `res://scripts/resources/egg.gd`

Other systems should call their public methods rather than duplicating lifecycle rules elsewhere.

### UI triggers actions but should not own simulation state

Player and observation UI live mostly in:
- `res://scripts/ui/player_nature_ui.gd`
- `res://scripts/ui/creature_stats_ui.gd`

UI can trigger actions and display data, but lasting world/entity/resource state should stay in world, creature, grass, egg, or species logic.

---

## 2. Scene links

### Main scene

`res://scenes/main/main.tscn`

Primary links:
- `res://scripts/camera/camera_controller.gd`
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scripts/ui/player_nature_ui.gd`
- `res://scenes/world/world.tscn`
- `res://scenes/debug/grid_debug_overlay.tscn`

Inspect this scene when changing top-level UI composition, camera node wiring, world instance wiring, or debug overlay placement.

### World scene

`res://scenes/world/world.tscn`

Primary links:
- `res://scripts/world/world_grid.gd`
- `res://scenes/creatures/creature.tscn`
- `res://scenes/resources/grass.tscn`
- `res://scenes/resources/egg.tscn`

Inspect this scene when changing sandbox layout, terrain setup, placed grass, placed creatures, egg container, creature container, or spawn markers.

### Creature scene

`res://scenes/creatures/creature.tscn`

Primary script:
- `res://scripts/creatures/creature.gd`

Important children:
- `BodySprite`
- `WalkRightSprite`
- `CollisionShape2D`
- `EatingTimer`
- `EggLayingTimer`
- `HoverArea`

Inspect this scene when changing creature node structure, collisions, timers, hover/click handling, or default species assignment.

### Grass scene

`res://scenes/resources/grass.tscn`

Primary script:
- `res://scripts/resources/grass.gd`

Inspect when changing grass timers, visual stages, node structure, or scene-level resource setup.

### Egg scene

`res://scenes/resources/egg.tscn`

Primary script:
- `res://scripts/resources/egg.gd`

Inspect when changing egg stages, timers, visuals, blocker shape, or hatching setup.

### Effect scenes

Lightning:
- `res://scenes/effects/lightning_strike_effect.tscn`
- `res://scripts/effects/lightning_strike_effect.gd`
- `res://data/animations/lightning_strike_frames.tres`

Rain preview:
- `res://scenes/effects/rain_target_preview.tscn`
- `res://scripts/effects/rain_target_preview.gd`

Sun preview:
- `res://scenes/effects/sun_target_preview.tscn`
- `res://scripts/effects/rain_target_preview.gd`

The rain preview script is currently a reusable square/tile-area preview helper used by more than one power.

---

## 3. System dependency blocks

### World / grid / terrain

Main files:
- `res://scripts/world/world_grid.gd`
- `res://scenes/world/world.tscn`
- `res://scripts/debug/grid_debug_overlay.gd`

Usually relevant:
- `res://scripts/creatures/creature.gd`
- `res://scripts/resources/grass.gd`
- `res://scripts/resources/egg.gd`

Important links:
- creatures register anchors and occupied footprint tiles in `world_grid.gd`;
- grass registers its tile in `world_grid.gd`;
- eggs register blocker footprints in `world_grid.gd`;
- debug overlay reads world-grid data for visualization.

High-risk areas:
- `grass_by_tile`
- `creature_anchors`
- `blocker_anchors`
- `occupied_by_tile`
- `can_place_footprint`
- movement registration/unregistration
- blocker registration/unregistration

### Creature runtime

Main files:
- `res://scripts/creatures/creature.gd`
- `res://scripts/creatures/creature_species_data.gd`
- `res://data/species/*.tres`

Helpers:
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`

Important links:
- `creature.gd` owns the high-level state machine and mutable runtime state;
- helper scripts read/write owner creature state;
- species resources provide static per-species configuration;
- UI/debug calls public getters on creatures.

High-risk areas:
- logical anchor vs visual position;
- movement path state;
- state transitions;
- death cleanup;
- helper delegation;
- runtime values vs species values.

### Grass and grazing

Main files:
- `res://scripts/resources/grass.gd`
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/world/world_grid.gd`

Usually relevant:
- `res://scripts/creatures/creature.gd`
- `res://scripts/debug/performance_stats.gd`
- `res://data/species/stegosaurus.tres`

Important links:
- grass registers in `world_grid.gd`;
- `world_grid.gd` counts edible grass under possible creature footprints;
- `creature_grazing_logic.gd` asks the world for targets and paths;
- `creature.gd` starts eating after movement reaches a valid anchor;
- `world_grid.gd` consumes edible grass under the footprint;
- `grass.gd` handles the consumed state.

High-risk areas:
- target anchor validity;
- retargeting;
- unreachable targets;
- repeated path rebuilds;
- map-wide scans;
- footprint grass count;
- eating before arrival.

### Eggs and reproduction

Main files:
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/resources/egg.gd`
- `res://scenes/resources/egg.tscn`
- `res://scripts/world/world_grid.gd`
- `res://scripts/creatures/creature_species_data.gd`

Usually relevant:
- `res://scripts/creatures/creature.gd`
- `res://scenes/creatures/creature.tscn`
- `res://data/species/*.tres`

Important links:
- reproduction helper checks creature/species conditions;
- reproduction helper chooses an egg anchor using world placement rules;
- egg scene handles stage timers;
- egg registers blockers through `world_grid.gd` when needed;
- egg unregisters blockers before hatching or removal;
- hatching instantiates a creature scene.

High-risk areas:
- stale blockers;
- invalid egg anchors;
- hatching placement;
- removal order;
- stage transition cleanup.

### Predator and combat

Main files:
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/combat/duel.gd`
- `res://scripts/creatures/creature.gd`
- `res://scripts/world/world_grid.gd`

Usually relevant:
- `res://data/species/predator.tres`
- `res://data/species/*.tres`

Important links:
- predator helper finds valid prey;
- world grid provides pathing and placement checks;
- predator helper seeks a side-contact position;
- duel helper resolves combat loop;
- creature death/cleanup is still handled by `creature.gd`.

High-risk areas:
- diagonal contact accidentally starting combat;
- stuck combat state;
- stale duel references;
- death during duel;
- predator hunger/combat aftermath behaviour.

### Player nature powers

Main files:
- `res://scripts/ui/player_nature_ui.gd`
- `res://scenes/main/main.tscn`

For grass-affecting powers:
- `res://scripts/resources/grass.gd`
- `res://scripts/world/world_grid.gd`
- `res://scripts/effects/rain_target_preview.gd`
- `res://scenes/effects/rain_target_preview.tscn`
- `res://scenes/effects/sun_target_preview.tscn`

For creature-targeted powers:
- `res://scripts/creatures/creature.gd`
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scenes/effects/lightning_strike_effect.tscn`
- `res://scripts/effects/lightning_strike_effect.gd`

Important links:
- `player_nature_ui.gd` owns energy and targeting;
- terrain-targeted powers use world-grid tile lookup;
- grass-affecting powers call public grass methods;
- creature-targeted powers use creature public damage hooks;
- creature click routing currently passes through prototype UI.

High-risk areas:
- UI bypassing resource lifecycle;
- scene-level exported overrides hiding script defaults;
- target preview mismatch;
- world registration after deleting resources;
- turning player powers into direct unit control.

### Creature visuals and animation

Main files:
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`
- `res://scripts/creatures/creature.gd`
- `res://scenes/creatures/creature.tscn`
- `res://data/species/*.tres`
- `res://data/animations/*.tres`

Usually relevant:
- creature sprites under `res://assets/sprites/creatures/`

Important links:
- species resources point to visual/animation data;
- visual helper switches sprites/animations based on direction and state;
- movement direction comes from creature runtime state.

High-risk areas:
- left/right mirroring;
- animation not matching movement;
- visual sprite position vs logical body;
- missing animation resources.

### UI and debug

Main files:
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scripts/ui/player_nature_ui.gd`
- `res://scripts/debug/grid_debug_overlay.gd`
- `res://scripts/debug/performance_stats.gd`
- `res://scenes/main/main.tscn`

Important links:
- creature hover/click uses the creature stats UI group;
- player powers use the player nature UI group;
- debug status reads performance counters and world state;
- grid debug overlay reads world/creature state but should not modify simulation.

Known debt:
- `creature_stats_ui.gd` currently mixes stats, debug text, and simulation speed;
- split into smaller UI scripts during UI cleanup.

### Performance and logs

Main files:
- `res://scripts/debug/performance_stats.gd`
- `res://scripts/ui/creature_stats_ui.gd`

Inspect the measured system too:
- grazing/pathing: `res://scripts/world/world_grid.gd`, `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- grass: `res://scripts/resources/grass.gd`
- creature ticks: `res://scripts/creatures/creature.gd`
- player powers: `res://scripts/ui/player_nature_ui.gd`

Important links:
- gameplay scripts add counters;
- `PerformanceStats` aggregates rates;
- debug UI displays status;
- F8 CSV logs are used for diagnosis.

High-risk areas:
- counters becoming misleading;
- logging too much;
- diagnosing symptoms without checking the linked system.

---

## 4. Task bundles

### If changing movement, walkability, or footprint placement

Read first:
- `res://scripts/world/world_grid.gd`
- `res://scripts/creatures/creature.gd`

Then, depending on issue:
- `res://scenes/world/world.tscn`
- `res://scripts/debug/grid_debug_overlay.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`

### If changing grazing or food search

Read first:
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/world/world_grid.gd`
- `res://scripts/resources/grass.gd`

Then, depending on issue:
- `res://scripts/creatures/creature.gd`
- `res://scripts/debug/performance_stats.gd`
- `res://data/species/stegosaurus.tres`

### If changing grass lifecycle or grass nature reactions

Read first:
- `res://scripts/resources/grass.gd`
- `res://scripts/world/world_grid.gd`

Then, depending on issue:
- `res://scripts/ui/player_nature_ui.gd`
- `res://scripts/effects/rain_target_preview.gd`
- `res://scenes/resources/grass.tscn`

### If changing player powers

Read first:
- `res://scripts/ui/player_nature_ui.gd`
- `res://scenes/main/main.tscn`

For grass effects:
- `res://scripts/resources/grass.gd`
- `res://scripts/world/world_grid.gd`
- `res://scripts/effects/rain_target_preview.gd`

For creature effects:
- `res://scripts/creatures/creature.gd`
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scripts/effects/lightning_strike_effect.gd`

### If changing reproduction or eggs

Read first:
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/resources/egg.gd`
- `res://scripts/world/world_grid.gd`

Then, depending on issue:
- `res://scenes/resources/egg.tscn`
- `res://scripts/creatures/creature_species_data.gd`
- `res://data/species/*.tres`

### If changing predator or combat

Read first:
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/combat/duel.gd`
- `res://scripts/creatures/creature.gd`

Then, depending on issue:
- `res://scripts/world/world_grid.gd`
- `res://data/species/predator.tres`

### If changing creature visuals or animation

Read first:
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`
- `res://scripts/creatures/creature.gd`
- `res://data/species/*.tres`
- `res://data/animations/*.tres`

Then, depending on issue:
- `res://scenes/creatures/creature.tscn`
- assets under `res://assets/sprites/creatures/`

### If changing UI architecture

Read first:
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scripts/ui/player_nature_ui.gd`
- `res://scenes/main/main.tscn`

Goal:
- keep player nature UI separate;
- split creature stats, debug status, and simulation speed when appropriate;
- avoid moving simulation rules into UI.

### If analyzing performance logs

Read first:
- `res://scripts/debug/performance_stats.gd`
- the CSV log;
- the system whose counters spike.

Common spike areas:
- grazing candidate checks;
- footprint queries;
- path calls;
- path expanded tiles;
- grass spread events;
- creature physics ticks;
- node/object counts.

---

## 5. Runtime flows that matter for dependencies

### Grazing

`creature.gd` detects hunger and delegates to `creature_grazing_logic.gd`. The grazing helper asks `world_grid.gd` for candidate anchors and paths. The creature moves to the chosen anchor. Eating uses `world_grid.gd` to consume grass, and `grass.gd` handles its own consumed state.

### Grass spread and recovery

`grass.gd` owns growth and spread. `world_grid.gd` only knows where grass exists and whether it can be found/consumed. Player powers should call grass hooks rather than duplicating growth/spread state in UI.

### Reproduction

`creature_reproduction_logic.gd` decides if and where an egg can be created. `egg.gd` owns its lifecycle after spawning. `world_grid.gd` validates placement and blocker state.

### Predator combat

`creature_predator_logic.gd` owns hunting and duel entry. `duel.gd` owns the combat loop. `creature.gd` owns health, death, and state cleanup.

### Player powers

`player_nature_ui.gd` owns energy and targeting. It should call into world, grass, creature, and effect scripts. The affected system should own lasting state changes.

---

## 6. Documentation update policy

Update this file when:
- a file responsibility changes;
- a new dependency is introduced;
- a scene/script link changes;
- a task bundle becomes misleading;
- a fragile rule changes.

Do not update this file for ordinary tuning changes:
- costs;
- radii;
- delays;
- counts;
- speed presets;
- damage values;
- other temporary balance numbers.
