# Dyna — Current Project State

> Live project snapshot. Update after meaningful architecture, world-logic, scene-structure, or prototype-scope changes.

---

## 1. Short status

The project is an early working Godot 4.7 simulation prototype.

Current scope:
- a tile-based world built on `TileMapLayer`;
- terrain types: ground, water, and mountain;
- a herbivore base species plus a temporary predator species;
- species data in `.tres` resources;
- directional creature sprites and a right-facing walk animation for the stegosaurus;
- egg laying, a two-stage egg lifecycle, and hatching;
- grass as the first renewable resource;
- autonomous herbivore grazing;
- temporary predator hunting;
- a simple 1v1 duel layer;
- first player influence action: lightning;
- debug UI for hover/selection and creature stats;
- an FPS/debug status display with cursor/world/tile/time/performance data;
- simulation speed control (`x1`, `x2`, `x3`);
- F3 removable grid debug overlay;
- F8 CSV performance logging;
- a free observer camera.

For local runs use Godot from `E:/Godot_v4.7/`; preferred headless CLI: `E:/Godot_v4.7/Godot_v4.7-stable_win64_console.exe`; short smoke test: `'/e/Godot_v4.7/Godot_v4.7-stable_win64_console.exe' --headless --path '/e/dyna' --quit-after 10`.

This is still a simulation sandbox, not a full game.

---

## 2. What currently works

### World
- The project starts from `scenes/main/main.tscn`.
- The world scene is `scenes/world/world.tscn`.
- Ground is `Ground` (`TileMapLayer`).
- The world uses three prototype terrain types: normal ground, water, and mountain.
- Water and mountain tiles currently replace ground directly and both act as blocked terrain.
- The world caches tile size and map bounds.
- The world owns walkability, terrain lookup, occupancy, blockers, pathfinding, and grazing queries.
- The world can contain a `PredatorSpawn` marker.
- Predator delayed spawning code exists but is currently controlled by `PREDATOR_SPAWN_ENABLED`, which is set to `false`.

### Creatures
- The world contains several test herbivore creatures of the same base species.
- Static species stats and visuals are loaded from `species_data` resources.
- Current species data lives in `data/species/stegosaurus.tres` and `data/species/predator.tres`.
- The creature uses directional sprites by movement direction.
- Left-facing views are mirrored from right-facing sprites.
- The stegosaurus has a 6-frame right-facing walk animation resource.
- Logical position uses `anchor_tile`.
- Current footprint is `2x2`.
- Current states: `IDLE`, `WALK`, `SEEK_FOOD`, `EATING`, `LAYING_EGG`, `COMBAT`, `DEAD`.
- Hunger drains over time.
- At zero hunger, health starts to decay.
- Above `70` satiety, the creature regenerates `1 hp/sec`.
- At `0 hp`, the creature enters `DEAD` and leaves the world.
- Creatures start at age `0`.
- Age increases by `1` every `30` seconds.
- At age `10`, the creature enters `DEAD` and leaves the world.
- The creature can search for grazing targets and build a grid path.
- Food search uses a helper flow: local recheck first, then global fallback.
- The creature eats adult grass under its footprint only after reaching a valid grazing anchor.
- Reproduction logic is split into `creature_reproduction_logic.gd`.
- Predator logic is split into `creature_predator_logic.gd`.
- Visual selection and walk-animation logic is split into `creature_visual_controller.gd`.

### Predator and combat
- A temporary predator species exists in `data/species/predator.tres`.
- Predator behaviour searches for living non-predator prey.
- Predators start hunting at their hunger search threshold (`60` in the predator resource).
- Predators path toward side-adjacent contact anchors.
- Predators start duels only on side contact, not diagonal corner contact.
- Fighters turn to face each other when a duel starts.
- The duel loop alternates turns every `1` second.
- Damage is currently `max(1, attack - defense)`.
- Predator duel wins restore hunger using species hunger tuning, without a separate corpse/eating aftermath yet.

### Grass
- Grass has 2 growth stages.
- Adult grass is edible.
- After being eaten, grass falls back to stage 1.
- Grass spreads in the 4 cardinal directions.
- Grass tries to spread only once.
- Grass registers itself into the world by tile.
- Grass cannot exist on blocked terrain tiles like water or mountains.

### Eggs and reproduction
- When reproduction conditions pass, the creature enters egg-laying for the species-configured duration.
- Egg stage 1 appears at the chosen egg anchor as a non-blocking vertical `1x2` object.
- The egg then tries to expand right into blocking stage 2 `2x2`.
- Egg stage 2 is an edible living object with bool logic and no HP system.
- After stage 2, a new creature hatches with species-configured starting health and hunger.

### UI, observation, and debug
- The camera moves with WASD.
- Mouse wheel controls zoom.
- The UI shows hover preview and click-to-pin selection.
- The UI shows creature name, age, health, hunger, and bars.
- Clicking the same creature again or empty space clears selection.
- There is an FPS/debug label.
- Debug label includes cursor screen/world position, tile position, elapsed run time, memory, node/object counts, grass/creature counts, and performance rates.
- There is a lightning button: press it, then left-click a creature to deal `50` damage.
- Pressing the lightning button again or right-clicking cancels armed lightning targeting.
- There is a simulation speed selector with `x1`, `x2`, and `x3`.
- There is an F3 removable grid debug overlay with blocked terrain, grass, occupied tiles, selected creature footprint, pending footprint, grazing target, path, and a bottom-left debug text panel.
- `PerformanceStats` is an autoload and can record CSV logs with F8 into `logs/`.

---

## 3. Current project core

1. `world_grid.gd` owns the grid, terrain, occupancy, blockers, pathfinding, and resource queries.
2. `creature.gd` runs autonomous creature state on top of that grid.
3. `creature_grazing_logic.gd` owns herbivore grazing search/retarget details.
4. `creature_predator_logic.gd` owns predator prey search/chase/duel entry details.
5. `creature_reproduction_logic.gd` owns reproduction checks and egg spawning details.
6. `creature_visual_controller.gd` owns directional sprite and walk-animation details.
7. `duel.gd` provides the current 1v1 duel loop.
8. `grass.gd` provides the first renewable resource loop.
9. `egg.gd` provides the current reproduction object lifecycle.
10. `creature_stats_ui.gd` lets the user observe creature state and trigger lightning.
11. `performance_stats.gd` provides runtime counters and CSV logging.
12. `camera_controller.gd` lets the user observe the simulation.

---

## 4. What is still prototype-level

- Only two species resources exist so far, and the predator is still a temporary combat placeholder.
- Predator spawning code exists but is currently disabled by constant.
- Combat aftermath is still placeholder-like: predator wins restore hunger directly instead of using corpse/eating logic.
- The broader art pipeline for future species is not standardized.
- The world still has few entity types.
- There is no full player-as-nature system yet.
- There is no player energy economy yet.
- Lightning exists, but rain and other nature actions do not yet exist.
- There is no general combat targeting system beyond the temporary predator workflow.
- Water and mountain exist as prototype blocked terrain, but there are no deeper biome-specific rules yet.
- There is no full gameplay HUD beyond debug/prototype UI.
- There is no save/load system.

---

## 5. Most important current files

### Entry and docs
- `project.godot`
- `AGENTS.md`
- `docs/project-map.md`
- `docs/current-state.md`
- `docs/dependencies.md`
- `docs/design_roadmap.md`

### Scenes
- `scenes/main/main.tscn`
- `scenes/world/world.tscn`
- `scenes/creatures/creature.tscn`
- `scenes/resources/grass.tscn`
- `scenes/resources/egg.tscn`
- `scenes/debug/grid_debug_overlay.tscn`

### World simulation
- `scripts/world/world_grid.gd`
- `scripts/combat/duel.gd`

### Creatures
- `scripts/creatures/creature.gd`
- `scripts/creatures/creature_species_data.gd`
- `scripts/creatures/behaviors/creature_grazing_logic.gd`
- `scripts/creatures/behaviors/creature_predator_logic.gd`
- `scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `scripts/creatures/behaviors/creature_visual_controller.gd`
- `data/species/stegosaurus.tres`
- `data/species/predator.tres`
- `data/animations/stegosaurus_walk_right_frames.tres`

### Resources
- `scripts/resources/grass.gd`
- `scripts/resources/egg.gd`

### UI, debug, and view
- `scripts/ui/creature_stats_ui.gd`
- `scripts/debug/grid_debug_overlay.gd`
- `scripts/debug/performance_stats.gd`
- `scripts/camera/camera_controller.gd`

---

## 6. Main current risks

### 1. Logical vs visual creature sync
The fragile zone is the relationship between:
- `anchor_tile`
- `pending_anchor_tile`
- visual `global_position`
- `movement_target_position`
- occupancy in `world_grid`

If edited carelessly, a creature can stand in one place visually while logically eating, blocking, or fighting elsewhere.

### 2. Grazing target selection and retargeting
Food logic is already non-trivial:
- the creature chooses a grazing target;
- it can re-evaluate nearby alternatives;
- it should not start eating before reaching the real target anchor;
- grazing queries depend on `world_grid` adult grass counts under `2x2` footprints.

This is easy to break with a “cleaner” but wrong simplification.

### 3. World registration of entities
Grass, creatures, and blockers all depend on registration inside `world_grid`.
If tile registry or unregister flow breaks, the simulation quickly becomes dishonest.

### 4. Predator/duel contact rules
Predator combat should start from side contact, not diagonal corner contact.
Path-to-prey logic and duel range checks are easy to accidentally loosen.

### 5. Egg blockers
Stage 2 eggs must register as blockers and must unregister before hatching/removal.
Leaving stale blockers will corrupt walkability.

### 6. Future file growth
`creature.gd` is smaller than before thanks to helpers, but it is still the coordinator for many systems.
Add new systems carefully so it does not become the next blob.

---

## 7. Logical next directions

### Option A — clean up the current combat layer
- corpse/eating aftermath instead of raw hunger restore;
- better combat entry polish and stop-distance visuals;
- keep combat logic isolated from wider creature logic.

### Option B — expand the creature loop
- more species resources;
- better reproduction/population behaviour;
- cleaner handling of death outcomes.

### Option C — strengthen the world as a system
- richer terrain visuals beyond placeholder water/mountain tiles;
- biome-specific rules instead of one shared blocked-terrain rule;
- stronger obstacle handling and terrain reactions.

### Option D — continue opening the player role
- player energy;
- proper player-facing HUD;
- rain and other indirect world actions;
- creature/world reaction to player actions.

### Option E — keep improving instrumentation
- use F8 CSV logs during performance issues;
- add counters around expensive world/creature/resource searches as needed;
- keep debug tools removable.

---

## 8. What new sessions should remember

- This is not a normal RTS.
- The player is an external force, not a unit commander.
- The world grid is the source of truth.
- Creatures should feel alive and autonomous.
- Species data should live in `.tres` resources, not one giant creature script.
- Helper scripts should reduce blob growth, not hide unclear ownership.
- Documentation should stay synchronized: update map/state/dependencies together when architecture changes.
- The project direction is already clear even if the code is still prototype-grade.

---

## 9. Main runtime flows

### Herbivore grazing flow
`Creature.gd` notices hunger/search state -> `CreatureGrazingLogic` finds or rechecks a grazing target -> `WorldGrid` scores adult grass under possible footprints -> creature builds a path -> creature moves anchor-by-anchor -> creature reaches target anchor -> eating timer runs -> `WorldGrid.consume_adult_grass_under_footprint()` consumes adult grass -> grass falls back to stage 1 -> creature restores hunger.

### Reproduction flow
`Creature.gd` updates reproduction cooldown/state -> `CreatureReproductionLogic` checks health, hunger, age, cooldown, and available egg anchor -> creature enters `LAYING_EGG` -> egg timer completes -> helper spawns `egg.tscn` into `Eggs` -> egg stage 1 starts non-blocking -> egg expands to stage 2 and registers blocker -> hatch timer completes -> blocker unregisters -> new creature spawns.

### Predator combat flow
Predator hunger reaches search threshold -> `CreaturePredatorLogic` finds nearest valid non-predator prey -> helper builds path to a side-adjacent anchor -> predator moves -> side-contact check passes -> helper creates `Duel` -> both fighters enter combat -> duel alternates attacks -> loser dies/leaves world -> winner detaches and predator restores hunger.

### Player lightning flow
UI arms lightning mode -> player clicks a creature -> UI calls creature direct damage -> creature health may reach zero -> creature enters `DEAD` and unregisters from the world.

### Performance logging flow
`PerformanceStats` autoload tracks elapsed time and counters -> UI displays current rates/status -> F8 toggles CSV recording -> samples are appended to `logs/perf_log_*.csv`.

---

## 10. When to update this file

Update `docs/current-state.md` when:
- the set of key scenes changes;
- a major system appears;
- an existing system is disabled/enabled in a meaningful way;
- the architecture canon changes;
- a meaningful roadmap milestone is reached;
- the prototype enters a new version phase.

Even short updates save future sessions from unnecessary archaeology.
