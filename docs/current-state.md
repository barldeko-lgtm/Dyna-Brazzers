# Dyna — Current Project State

> Live project snapshot. Update after meaningful architecture, world-logic, scene-structure, or prototype-scope changes.

---

## 1. Short status

The project is still an early working prototype.

Current scope:
- a tile-based world built on `TileMapLayer`;
- a herbivore base species plus a temporary predator species;
- egg laying, a two-stage egg lifecycle, and hatching;
- grass as the first renewable resource;
- autonomous food search;
- a simple 1v1 duel layer with predator hunting;
- a debug UI for hover/selection and creature stats;
- a free observer camera.

For local runs use Godot from `E:/Godot_v4.7/`; preferred headless CLI: `E:/Godot_v4.7/Godot_v4.7-stable_win64_console.exe`; short smoke test: `'/e/Godot_v4.7/Godot_v4.7-stable_win64_console.exe' --headless --path '/e/dyna' --quit-after 10`.

This is still a simulation sandbox, not a full game.

---

## 2. What currently works

### World
- The project starts from `scenes/main/main.tscn`.
- The world scene is `scenes/world/world.tscn`.
- Ground is `Ground` (`TileMapLayer`).
- The world caches tile size and map bounds.
- The world owns walkability, occupancy, grass lookup, blocker lookup, and grazing queries.

### Creatures
- The world contains several test creatures of the same base species.
- The creature uses directional sprites by movement direction.
- Left-facing views are mirrored from right-facing sprites.
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
- Food search uses a two-step flow: local recheck first, then global fallback.
- The creature eats grass under its footprint.
- Static species stats and visuals are loaded from `species_data` resources.
- The current species data lives in `data/species/stegosaurus.tres` and `data/species/predator.tres`.
- There is now a separate 1v1 duel loop with alternating 1-second turns, initiator-first order, and `max(1, attack - defense)` damage.
- A simple predator species now exists as a temporary hunter placeholder.
- Only 1 predator is spawned, and it appears `10` seconds after world start.
- Predators spawn with full health and full hunger.
- Predators start hunting only when hunger drops to `60` or lower.
- Predators chase the nearest living non-predator and start duels only on side contact, not diagonal corner contact.
- Fighters turn to face each other when the duel starts.
- Predator duel wins restore `+50` hunger without a separate eating system yet.
- When reproduction conditions pass, the creature enters egg-laying for `5` seconds.
- Egg stage 1 appears at the creature position as a non-blocking vertical `1x2` object.
- The egg then tries to expand right into blocking stage 2 `2x2`.
- Egg stage 2 is an edible living object with bool logic and no HP system.
- After stage 2, a new creature hatches with `100 hp` and `50` hunger.

### Grass
- Grass has 2 growth stages.
- Adult grass is edible.
- After being eaten, grass falls back to stage 1.
- Grass spreads in the 4 cardinal directions.
- Grass registers itself into the world by tile.

### UI and observation
- The camera moves with WASD.
- Mouse wheel controls zoom.
- The UI shows hover preview and click-to-pin selection.
- The UI shows name, age, health, and hunger.
- Clicking the same creature again or empty space clears selection.
- There is an FPS label.
- There is a simulation speed selector with `x1`, `x2`, `x3`.

---

## 3. Current project core

1. `world_grid.gd` owns the grid, occupancy, and resource queries.
2. `scripts/creatures/creature.gd` runs autonomous creature decisions on top of that grid.
3. `scripts/combat/duel.gd` provides the current 1v1 duel loop.
4. `grass.gd` provides the first renewable resource loop.
5. `creature_stats_ui.gd` lets the user observe creature state.
6. `camera_controller.gd` lets the user observe the simulation.

---

## 4. What is still prototype-level

- Only two prototype species are data-driven so far, and the predator is still a temporary combat placeholder.
- The broader art pipeline for future species is not standardized.
- The world still has few entity types.
- There is no full player-as-nature system yet.
- There is no player energy economy.
- There are no actions like rain or lightning yet.
- There is no general combat entry/targeting system yet beyond the simple predator placeholder.
- There is no broader herbivore/predator ecosystem split yet.
- There are no water or mountain biomes yet.
- There is no full gameplay HUD beyond the debug panel.
- There is no save/load system.

---

## 5. Most important current files

### Entry
- `project.godot`
- `scenes/main/main.tscn`

### World simulation
- `scenes/world/world.tscn`
- `scripts/world/world_grid.gd`
- `scripts/combat/duel.gd`

### Creatures
- `scenes/creatures/Creature.tscn`
- `scripts/creatures/creature.gd`
- `scripts/creatures/creature_species_data.gd`
- `data/species/stegosaurus.tres`
- `data/species/predator.tres`

### Resources
- `scenes/resources/grass.tscn`
- `scripts/resources/grass.gd`
- `scenes/resources/egg.tscn`
- `scripts/resources/egg.gd`

### UI and view
- `scripts/ui/creature_stats_ui.gd`
- `scripts/camera/camera_controller.gd`

### Docs
- `AGENTS.md`
- `docs/project-map.md`
- `docs/design_roadmap.md`
- `docs/current-state.md`

---

## 6. Main current risks

### 1. Logical vs visual creature sync
The fragile zone is the relationship between:
- `anchor_tile`
- `pending_anchor_tile`
- visual `global_position`
- occupancy in `world_grid`

If edited carelessly, a creature can stand in one place visually while logically eating or occupying tiles elsewhere.

### 2. Grazing target selection and retargeting
Food logic is already non-trivial:
- the creature chooses a grazing target;
- it can re-evaluate nearby alternatives;
- it should not start eating before reaching the real target anchor.

This is easy to break with a “cleaner” but wrong simplification.

### 3. World registration of entities
Grass, creatures, and blockers all depend on registration inside `world_grid`.
If the tile registry breaks, the simulation quickly becomes dishonest.

### 4. Future file growth
`creature.gd` is still large even after moving species data out.
Combat should be added carefully so the file does not become the next blob.

---

## 7. Logical next directions

### Option A — clean up the current combat layer
- corpse / eating aftermath instead of raw `+50 hunger`;
- better combat entry polish and stop-distance visuals;
- keep combat logic isolated from wider creature logic.

### Option B — expand the creature loop
- more species resources;
- better reproduction/population behaviour;
- cleaner handling of death outcomes.

### Option C — strengthen the world as a system
- water;
- mountains;
- blocked zones;
- stronger obstacle handling.

### Option D — start opening the player role
- player energy;
- a first player-facing HUD;
- the first indirect world action;
- creature/world reaction to that action.

---

## 8. What new sessions should remember

- This is not a normal RTS.
- The player is an external force, not a unit commander.
- The world grid is the source of truth.
- Creatures should feel alive and autonomous.
- Species data should live in `.tres` resources, not one giant creature script.
- The project direction is already clear even if the code is still prototype-grade.

---

## 9. When to update this file

Update `docs/current-state.md` when:
- the set of key scenes changes;
- a major system appears;
- the architecture canon changes;
- a meaningful roadmap milestone is reached;
- the prototype enters a new version phase.

Even short updates save future sessions from unnecessary archaeology.
