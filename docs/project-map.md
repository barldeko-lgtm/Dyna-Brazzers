# Dyna Project Map

> Purpose: show where project parts live. This is a map of folders, scenes, and key files. It should not duplicate current feature status or detailed dependency/task guidance.

---

## 1. Project root

- `project.godot` — Godot project config, main scene, and autoload registration.
- `AGENTS.md` — short briefing for agents.
- `docs/project-map.md` — project structure and file ownership.
- `docs/current-state.md` — current implemented systems and prototype status.
- `docs/dependencies.md` — practical dependency/task map.
- `docs/design_roadmap.md` — broader design roadmap.
- `logs/` — CSV performance logs.

---

## 2. Scenes

### `scenes/main/`

- `scenes/main/main.tscn` — top-level assembly: camera, right-side player HUD, creature stats/debug UI, world instance, and debug overlay.

### `scenes/world/`

- `scenes/world/world.tscn` — active sandbox world: terrain, creatures, grass, eggs, and world-grid node.

### `scenes/creatures/`

- `scenes/creatures/creature.tscn` — base creature scene.

### `scenes/resources/`

- `scenes/resources/grass.tscn` — grass resource scene.
- `scenes/resources/egg.tscn` — egg resource scene.

### `scenes/effects/`

- `scenes/effects/lightning_strike_effect.tscn` — lightning visual effect.
- `scenes/effects/rain_target_preview.tscn` — rain target preview.
- `scenes/effects/sun_target_preview.tscn` — sun target preview.

### `scenes/debug/`

- `scenes/debug/grid_debug_overlay.tscn` — optional grid/path/occupancy debug overlay.

---

## 3. Scripts

### World

- `scripts/world/world_grid.gd` — central world/grid authority: terrain, walkability, occupancy, blockers, pathfinding, and resource lookup.

### Creatures

- `scripts/creatures/creature.gd` — base creature runtime coordinator.
- `scripts/creatures/creature_species_data.gd` — species resource schema.
- `scripts/creatures/behaviors/creature_grazing_logic.gd` — herbivore grazing and food targeting.
- `scripts/creatures/behaviors/creature_predator_logic.gd` — predator search, chase, and duel entry.
- `scripts/creatures/behaviors/creature_reproduction_logic.gd` — reproduction checks and egg spawning.
- `scripts/creatures/behaviors/creature_visual_controller.gd` — creature directional visuals and walk/eating-animation switching.

### Combat

- `scripts/combat/duel.gd` — isolated one-on-one duel loop.

### Resources

- `scripts/resources/grass.gd` — grass lifecycle, consumption, spread, world registration, and nature-power reactions.
- `scripts/resources/egg.gd` — egg lifecycle, blocker handling, and hatching.

### UI

- `scripts/ui/creature_stats_ui.gd` — prototype creature stats, selection, debug status, and simulation speed UI.
- `scripts/ui/player_nature_ui.gd` — player energy and nature-power targeting/effects.
- `scripts/ui/spell_menu_toggle.gd` — small helper for opening/closing the right-side spell submenu.

### Effects

- `scripts/effects/lightning_strike_effect.gd` — lightning effect playback/lifetime.
- `scripts/effects/rain_target_preview.gd` — configurable tile-area preview used by rain and sun.

### Debug and camera

- `scripts/debug/grid_debug_overlay.gd` — grid/path/occupancy debug drawing.
- `scripts/debug/performance_stats.gd` — runtime counters and CSV logging.
- `scripts/camera/camera_controller.gd` — observer camera movement and zoom.

---

## 4. Data

### Species

- `data/species/stegosaurus.tres` — current herbivore species resource.
- `data/species/predator.tres` — temporary predator species resource.

### Animations

- `data/animations/stegosaurus_walk_right_frames.tres` — stegosaurus right-facing walk animation frames.
- `data/animations/stegosaurus_walk_up_frames.tres` — stegosaurus up-facing walk animation frames.
- `data/animations/stegosaurus_walk_up_right_frames.tres` — stegosaurus up-right walk animation frames, mirrored for up-left movement.
- `data/animations/stegosaurus_eating_right_frames.tres` — stegosaurus right-facing eating animation frames, mirrored for left-facing eating.
- `data/animations/lightning_strike_frames.tres` — lightning effect animation frames.

---

## 5. Assets

### Terrain

- `assets/sprites/terrain/` — ground, water, mountain, and grass sprites.

### Creatures

- `assets/sprites/creatures/stegosaurus/` — stegosaurus sprites and walk/eating frames.
- `assets/sprites/creatures/predator/` — temporary predator sprites.
- `assets/sprites/creatures/eggs/` — egg sprites.

### Effects

- `assets/sprites/effects/lightning/` — lightning effect frames.

### UI

- `assets/ui/nature_energy_icon.png` — nature energy icon used by the right-side player HUD.

---

## 6. Ownership summary

- World rules belong in `scripts/world/world_grid.gd`.
- Creature runtime coordination belongs in `scripts/creatures/creature.gd`.
- Creature subsystem details belong in `scripts/creatures/behaviors/`.
- Species identity and static tuning belong in `data/species/*.tres`.
- Grass lifecycle belongs in `scripts/resources/grass.gd`.
- Egg lifecycle belongs in `scripts/resources/egg.gd`.
- Player powers belong in `scripts/ui/player_nature_ui.gd`.
- Debug and performance tooling belongs in `scripts/debug/`.
- The current right-side HUD layout lives in `scenes/main/main.tscn`.

---

## 7. What this file should not contain

Do not use this file for:
- current feature status;
- task-specific dependency bundles;
- temporary balance values;
- detailed runtime flows;
- roadmap planning.

Use:
- `docs/current-state.md` for what currently works;
- `docs/dependencies.md` for which files to read/change for a task;
- `docs/design_roadmap.md` for future design direction.
