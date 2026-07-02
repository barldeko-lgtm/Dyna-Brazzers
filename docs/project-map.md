# Dyna Project Map

Fast entry point for a new session: what lives where, what each part owns, and where to look first.

---

## 1. High-level structure

### Project root
- `project.godot` — Godot project config; main scene `res://scenes/main/main.tscn`
- `AGENTS.md` — short working rules and project canon
- `docs/design_roadmap.md` — overall game vision, player role, progression, and roadmap
- `docs/project-map.md` — this file
- `docs/current-state.md` — live prototype snapshot

### `scenes/`
Scene assemblies and placed nodes.

- `scenes/main/main.tscn` — top-level project assembly
- `scenes/debug/grid_debug_overlay.tscn` — removable debug grid overlay and info panel
- `scenes/world/world.tscn` — test world
- `scenes/creatures/Creature.tscn` — base creature scene
- `scenes/resources/grass.tscn` — grass resource scene
- `scenes/resources/egg.tscn` — egg scene with two stages and hatching

### `scripts/`
Main gameplay logic by subsystem.

- `scripts/world/world_grid.gd` — world/grid authority and delayed predator spawn
- `scripts/combat/duel.gd` — 1v1 duel loop
- `scripts/creatures/creature.gd` — base creature runtime logic
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore food search and grazing retarget helper
- `scripts/debug/grid_debug_overlay.gd` — removable grid debug drawing and bottom-left debug info panel
- `scripts/creatures/creature_species_data.gd` — species resource schema
- `scripts/resources/grass.gd` — grass lifecycle
- `scripts/resources/egg.gd` — egg lifecycle and hatching
- `data/species/stegosaurus.tres` — herbivore species data
- `data/species/predator.tres` — temporary predator species data
- `scripts/camera/camera_controller.gd` — observer camera
- `scripts/ui/creature_stats_ui.gd` — creature HUD, selection UI, and first player action button

### `assets/`
Sprites and placeholders.

- `assets/sprites/terrain/ground.png` — ground tile
- `assets/sprites/terrain/water_placeholder.png` — temporary water tile
- `assets/sprites/terrain/mountain_placeholder.png` — temporary mountain tile
- `assets/sprites/terrain/grass_stage_1.png` — small grass
- `assets/sprites/terrain/grass_stage_2.png` — adult grass
- `assets/sprites/creatures/stegosaurus/` — directional sprite set for the herbivore test creature
- `assets/sprites/creatures/predator/` — temporary directional sprite set for the predator
- `assets/sprites/creatures/eggs/` — egg sprites for both stages
- `assets/sprites/creatures/stegosaurus_placeholder.png` — old stegosaurus placeholder
- `assets/sprites/creatures/debug_square_256.png` — old debug sprite kept as a tech reference

### `data/`
Configurable game data resources.

- `data/species/stegosaurus.tres` — herbivore species stats, visuals, and egg settings
- `data/species/predator.tres` — predator species stats, visuals, and hunt tuning

---

## 2. Scene startup flow

### `project.godot`
Project entry point. Launches `res://scenes/main/main.tscn`.

### `scenes/main/main.tscn`
Top-level scene. Currently contains:
- `Camera2D` — camera using `camera_controller.gd`
- `UI` — creature stats, FPS, lightning action button, and simulation speed controls
- `Simulation` — currently an empty technical node
- `World` — an instance of `scenes/world/world.tscn`
- `GridDebugOverlay` — optional removable grid debug overlay

### `scenes/world/world.tscn`
Active simulation sandbox. Contains:
- `World` (`Node2D`) with `world_grid.gd`
- `Creatures` — test creatures
- `Grasses` — grass instances
- `Eggs` — creature eggs
- `Ground` (`TileMapLayer`) — map geometry and walkable area

Important: `World` with `world_grid.gd` is the logic center. Other entities find it by walking up the scene tree.

---

## 3. Key scenes

### `scenes/main/main.tscn`
**Role:** top-level project assembly.

**Owns:**
- bootstrapping the prototype;
- camera;
- debug UI;
- optional debug overlay instance;
- world scene attachment.

**Keep in mind:**
- do not turn this into a heavy gameplay-logic scene;
- world logic belongs in `world_grid.gd` and related entities.

### `scenes/world/world.tscn`
**Role:** test gameplay world.

**Owns:**
- ground, grass, eggs, and creatures;
- running the simulation;
- serving as the main behaviour sandbox.

**Keep in mind:**
- the map currently uses large `128x128` tiles;
- the scene already contains several test creatures and grass patches;
- this is a mechanics sandbox, not final world structure.

### `scenes/creatures/Creature.tscn`
**Role:** base creature scene.

**Structure:**
- `CharacterBody2D`
- `BodySprite`
- `EatingTimer`
- `EggLayingTimer`
- `HoverArea` for hover UI and click selection

**Keep in mind:**
- the scene pulls base stats, visuals, and egg setup from `species_data`;
- left-facing visuals are mirrored from right-facing sprites;
- the scene is tied to `2x2` footprint logic in `creature.gd`.

### `scenes/resources/grass.tscn`
**Role:** base grass scene.

**Structure:**
- `Node2D`
- `BodySprite`
- `GrowthTimer`
- `SpreadTimer`

**Keep in mind:**
- grass exists on tiles;
- only adult grass is edible;
- grass spreads in the 4 cardinal directions.

### `scenes/resources/egg.tscn`
**Role:** base creature egg scene.

**Structure:**
- `Node2D`
- `BodySprite`
- `Stage1Timer`
- `ExpandRetryTimer`
- `HatchTimer`

**Keep in mind:**
- egg stage 1 is vertical and non-blocking, conceptually `1x2`;
- after a free expansion right, the egg becomes stage 2 `2x2`;
- stage 2 blocks world tiles and later hatches a new creature.

---

## 4. Key scripts

### `scripts/world/world_grid.gd`
**Role:** central world/grid manager.

**Owns:**
- `Ground` lookup/cache;
- tile size and map bounds;
- world/grid conversion;
- `anchor_tile` and footprint helpers;
- grass registration by tile;
- creature occupied-tile registration;
- blocker registration for objects like eggs;
- walkability checks;
- terrain-type lookup for ground / water / mountain tiles;
- neighbor lookup with diagonal corner-cut prevention;
- A*-style pathfinding;
- grazing-target queries;
- counting and consuming adult grass under a footprint.

**Source of truth for:**
- world walkability;
- tile occupancy;
- real grass locations;
- real creature logical position.

**Fragile areas:**
- creature registration/movement;
- `anchor_tile` vs actual body position;
- grazing selection for `2x2` footprints.

### `scripts/creatures/creature.gd`
**Role:** base autonomous creature runtime logic.

**Owns:**
- states `IDLE`, `WALK`, `SEEK_FOOD`, `EATING`, `LAYING_EGG`, `COMBAT`, `DEAD`;
- age, hunger, starvation damage, and well-fed regen;
- death from old age and at `0 hp`;
- high-level food state transitions and eating entry;
- smooth movement between tile anchors;
- directional sprite choice;
- eating adult grass under the footprint;
- reproduction checks and egg-laying;
- spawning egg stage 1 at the current creature location;
- hover UI and click selection hooks;
- applying `species_data` for stats, visuals, and egg setup;
- predator prey search and delayed hunt behaviour;
- duel start checks with side-contact-only combat entry;
- facing the opponent on duel start.

**Keep in mind:**
- logical position is stored as `anchor_tile`;
- visual motion is separate from logical decisions;
- the creature should not start eating just because it crossed a good tile on the way;
- current footprint is `2x2`;
- grazing target logic now lives in `creature_grazing_logic.gd`;
- this file is still large, so future systems should be added carefully.

### `scripts/creatures/behaviors/creature_grazing_logic.gd`
**Role:** herbivore grazing helper.

**Owns:**
- two-step grazing search: local recheck, then global fallback;
- target scoring and retargeting;
- target validity checks;
- path rebuilding toward the current grazing anchor;
- deciding when a herbivore can start eating at the current anchor.

**Keep in mind:**
- this helper reads and writes creature runtime state through the owning creature;
- world queries and pathfinding still come from `world_grid.gd`.

**Useful public methods for UI:**
- `get_creature_name()`
- `get_age()`
- `get_health_percent()`
- `get_hunger_percent()`

### `scripts/combat/duel.gd`
**Role:** isolated 1v1 duel loop.

**Owns:**
- fighter A / fighter B references;
- initiator-first turn order;
- 1-second alternating turns;
- `max(1, attack - defense)` damage;
- duel finish when one fighter dies.

**Keep in mind:**
- this is only the internal duel loop;
- combat entry/targeting logic still belongs elsewhere.

### `scripts/creatures/creature_species_data.gd`
**Role:** species resource schema.

**Owns:**
- species identity fields;
- predator/herbivore flags;
- directional visuals;
- survival/combat stats;
- hunger tuning;
- egg lifecycle tuning;
- reproduction thresholds and costs;
- starting stats for spawned and hatched creatures.

**Keep in mind:**
- this is where species-level balancing should grow;
- the current concrete setup lives in `data/species/stegosaurus.tres` and `data/species/predator.tres`.

### `scripts/resources/grass.gd`
**Role:** grass lifecycle as the first renewable resource.

**Owns:**
- growth stages `STAGE_1` and `STAGE_2`;
- growth timer until the adult stage;
- spread timer;
- world registration through `world_grid`;
- spreading to 4 neighboring tiles;
- falling back to stage 1 after being eaten.

**Keep in mind:**
- grass is edible only in stage 2;
- the node syncs its own tile with the world;
- grass cannot stay or spread onto blocked terrain tiles;
- new grass is spawned by instantiating the same scene again.

### `scripts/resources/egg.gd`
**Role:** creature egg lifecycle.

**Owns:**
- the first vertical egg stage `1x2`;
- repeated checks for expansion into `2x2`;
- registering stage 2 as a blocking world object;
- bool-based egg edibility without an HP system;
- hatching a creature through the configured creature scene.

**Keep in mind:**
- egg stage 1 does not block tiles;
- stage 2 expands right and blocks `2x2`;
- egg visuals and the hatched creature scene are data-driven.

### `scripts/ui/creature_stats_ui.gd`
**Role:** creature HUD and lightweight player interaction UI.

**Owns:**
- temporary hover display;
- click-to-pin and clear selection;
- showing name, age, health, and hunger;
- arming/canceling the first lightning player action;
- FPS display;
- simulation speed switching between `x1`, `x2`, and `x3`.

**Keep in mind:**
- this UI can arm player actions, but action effects should still resolve in world/entity logic;
- the UI queries creature methods but should not own creature state.

### `scripts/debug/grid_debug_overlay.gd`
**Role:** removable world-grid debug overlay.

**Owns:**
- F3 toggle for debug visibility;
- drawing blocked terrain, grass, occupied tiles, creature footprint, pending footprint, target, and path;
- bottom-left debug text for the selected or hovered creature.

**Keep in mind:**
- this layer only reads state from `world_grid` and creatures;
- it should stay optional and easy to remove after testing.

### `scripts/camera/camera_controller.gd`
**Role:** basic observer camera control.

**Owns:**
- WASD movement;
- mouse-wheel zoom;
- zoom range limits.

**Keep in mind:**
- this is still a simple debug camera;
- later it may become a fuller observer camera.

---

## 5. Current system links

### World -> Creatures
- Creatures find `world_grid` through the scene tree.
- The world tells them where they can stand, move, and find food.
- The world stores real occupancy.

### World -> Grass
- Grass registers into the world by tile.
- The world uses the grass registry for food search and consumption.

### World -> Eggs
- Eggs use the world to resolve anchors, blocking, and hatch placement.
- Stage 2 egg occupancy is tracked through blocker registration.

### Creature -> UI
- On hover, `HoverArea` talks to the `creature_stats_ui` group.
- On click, `HoverArea` pins or clears selection.
- The UI asks the creature for name, age, health, and hunger.

### `TileMapLayer` -> All grid logic
- `Ground` defines the map, tile size, and effective world area.
- All grid calculations depend on it.

---

## 6. What already works in practice

The current code already provides:
- world startup through the main scene;
- camera movement and zoom;
- several test creatures on the map;
- directional creature sprites;
- age, hunger, death from old age, and death at `0 hp`;
- hover and click creature selection;
- grid-based grass search;
- eating adult grass;
- grass growth and spreading;
- egg laying, egg growth, and hatching;
- a separate 1v1 duel loop with alternating 1-second turns;
- a temporary predator species that spawns once after 10 seconds and hunts at hunger <= 60;
- the creature stats panel;
- an FPS label;
- simulation speed control.

---

## 7. Where to look first for new tasks

### Movement / path / footprint / stuck behaviour
1. `scripts/world/world_grid.gd`
2. `scripts/creatures/creature.gd`
3. `scenes/world/world.tscn`

### Grass / food / resource regeneration
1. `scripts/resources/grass.gd`
2. `scripts/world/world_grid.gd`
3. `scenes/resources/grass.tscn`

### Egg / reproduction / hatching
1. `scripts/resources/egg.gd`
2. `scripts/creatures/creature.gd`
3. `scenes/resources/egg.tscn`
4. `data/species/stegosaurus.tres`

### Creature UI
1. `scripts/ui/creature_stats_ui.gd`
2. `scripts/creatures/creature.gd`
3. `scenes/main/main.tscn`

### Camera / world observation
1. `scripts/camera/camera_controller.gd`
2. `scenes/main/main.tscn`

---

## 8. Places to avoid touching blindly

- `anchor_tile`, `pending_anchor_tile`, and `movement_target_position` logic in `creature.gd`
- `register_creature`, `move_creature`, and `can_place_footprint` in `world_grid.gd`
- grazing-target selection and retarget logic
- consistency between visual motion and logical creature position

If these areas are changed carelessly, a creature can visually stand in one place while logically eating and occupying tiles elsewhere.

---

## 9. Design context worth preserving

The project direction is:
- a living autonomous ecosystem;
- indirect player control;
- a world that exists on its own;
- gradual growth in species, resources, and player influence.

This is not “a normal RTS with dinosaurs”. It is an observable simulation shaped by outside player influence.
