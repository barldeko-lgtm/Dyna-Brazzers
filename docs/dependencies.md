# Dyna — Dependencies

## World grid

`res://scripts/world/world_grid.gd` owns:

- terrain lookup;
- walkability;
- footprint placement;
- pathfinding;
- grass lookup;
- creature occupancy;
- blocker occupancy;
- counting/consuming edible grass under creature footprints.

If a task touches movement, blocked tiles, tree blocking, grass consumption, corpse passability, or pathing, inspect `world_grid.gd`.

## UI ownership

`res://scenes/main/main.tscn` owns active gameplay UI node wiring.

Current UI scripts:

- `res://scripts/ui/start_screen.gd` — startup menu and three-slot startup loading;
- `res://scripts/ui/creature_stats_ui.gd` — creature info panel, selection, and hover/selection highlight coordination;
- `res://scripts/ui/player_ui.gd` — side-panel counters and time speed controls;
- `res://scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug text;
- `res://scripts/ui/player_nature_ui.gd` — energy and nature powers;
- `res://scripts/debug/grid_debug_overlay.gd` — F3 grid/debug overlay.

Expected gameplay scene wiring:

- `UI` uses `creature_stats_ui.gd`;
- `UI/FpsLabel` uses `debug_status_ui.gd`;
- `UI/PlayerSidePanel` uses `player_ui.gd`;
- `UI/PlayerSidePanel/.../PlayerNaturePanel` uses `player_nature_ui.gd`.

Rules:

- do not put counters or time speed controls back into `creature_stats_ui.gd`;
- do not put detailed debug text back into `creature_stats_ui.gd`;
- F3 grid overlay and F4 text debug are separate systems;
- creature click selection should stay compatible with lightning targeting and highlight updates;
- dead/corpse creatures should not remain selectable unless deliberately reworked later.

## Startup scene

Main files:

- `res://project.godot`;
- `res://scenes/ui/start_screen.tscn`;
- `res://scripts/ui/start_screen.gd`.

Runtime flow:

1. `project.godot` starts `start_screen.tscn`.
2. New Game changes to `res://scenes/main/main.tscn`.
3. Load queries `SaveSystem` for three slots.
4. Occupied slots show date/time; empty slots are disabled.
5. Selecting an occupied slot delegates loading to `SaveSystem`.
6. Exit calls `get_tree().quit()`.

The startup-screen `Menu` button is currently a placeholder for future settings/options.

## Save system

Main file:

- `res://scripts/save/save_system.gd`.

Registration:

- `SaveSystem` is an autoload in `project.godot`.

Slot files:

- `user://dyna_save_slot_1.json`;
- `user://dyna_save_slot_2.json`;
- `user://dyna_save_slot_3.json`.

In-game UI integration:

- the existing right-side `MainPlaceholder5` / `MENU` button opens SaveSystem content;
- do not add a second duplicate in-game menu button;
- opening the menu pauses simulation;
- closing it restores the previous simulation speed;
- actions are Save, Load, Main Menu, Close Game, and Back.

Saved dynamic data:

- creatures;
- grass;
- eggs;
- player energy;
- camera position/zoom;
- simulation speed;
- save timestamp.

Static terrain is loaded from `world.tscn`, not serialized.

Loading flow:

1. Read and validate JSON save version.
2. Ensure `main.tscn` is active.
3. Pause time during reconstruction.
4. Clear current creature, egg, and grass nodes.
5. Recreate grass and timer state.
6. Recreate eggs and blocker state.
7. Recreate creatures and mutable stats.
8. Restore player energy and camera.
9. Restore the saved simulation speed.

Main Menu flow:

1. Reset temporary SaveSystem menu/session references.
2. Restore `Engine.time_scale` to `1`.
3. Change to `start_screen.tscn`.
4. The old game scene is freed.
5. Save files remain untouched.

Rules:

- returning to Main Menu must produce a clean New Game session;
- returning to Main Menu must not delete slot files;
- dead temporary corpse nodes are not persisted;
- active animation frame/path/eating micro-state is not required to resume exactly;
- adding new runtime systems may require a save version bump and migration handling.

## Terrain source ids

`res://scenes/world/world.tscn` owns the active TileSet terrain sources.

Current source ids:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

Blocked terrain sources:

- water;
- mountain;
- tree.

## Trees

Trees are TileMap terrain, not separate scenes.

Main files:

- `res://scenes/world/world.tscn`;
- `res://scripts/world/world_grid.gd`;
- `res://assets/sprites/terrain/tree_tiles_independent.png`.

Do not use old object-tree files:

- `res://scenes/resources/tree.tscn`;
- `res://scripts/resources/tree.gd`;
- `res://assets/sprites/terrain/trees/`.

Do not use abandoned large-tile file:

- `res://assets/sprites/terrain/tree_tiles_large.png`.

Tree TileSet setup:

- source id `3`;
- texture: `res://assets/sprites/terrain/tree_tiles_independent.png`;
- `texture_region_size = Vector2i(128, 128)`;
- every tree piece is a normal 128x128 tile;
- each visual tree is assembled as a 2x2 block.

Atlas layout:

- Tree 1: `(0,0)`, `(1,0)`, `(0,1)`, `(1,1)`;
- Tree 2: `(2,0)`, `(3,0)`, `(2,1)`, `(3,1)`;
- Tree 3: `(4,0)`, `(5,0)`, `(4,1)`, `(5,1)`;
- Tree 4: `(6,0)`, `(7,0)`, `(6,1)`, `(7,1)`.

## Grass lifecycle

`res://scripts/resources/grass.gd` owns:

- 4-stage growth;
- stage visuals;
- whether grass is edible;
- per-stage food value;
- consumption reset to stage 1;
- rain/sun stage changes;
- stage-4 spread attempts;
- world-grid registration/unregistration.

Current grass stages:

- Stage 1 — not edible;
- Stage 2 — edible, restores 3 satiety;
- Stage 3 — edible, restores 5 satiety;
- Stage 4 — edible, restores 7 satiety and can spread.

## Grazing target ranking

Main file:

- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`.

Current score:

`score = total_food_value_under_footprint - estimated_distance * 2`

Rules:

- evaluate the full creature footprint;
- use grass food values `3 / 5 / 7` for stages `2 / 3 / 4`;
- stages 2 and 3 remain edible fallback targets;
- initial targeting and periodic retargeting must use the same formula;
- do not revert to counting all edible stages as equal-value grass tiles.

## Rain cast visual

Main files:

- `res://scripts/ui/player_nature_ui.gd`;
- `res://scripts/effects/rain_target_preview.gd`;
- `res://scripts/effects/rain_cast_effect.gd`;
- `res://scenes/effects/rain_target_preview.tscn`;
- `res://scenes/effects/rain_cast_effect.tscn`;
- `res://assets/sprites/effects/rain/rain_cast_01.png` ... `rain_cast_04.png`.

Rules:

- rain gameplay and rain visuals must remain separate;
- the visual effect must not apply grass changes itself;
- preserve the 640x640 source size because it matches 5 tiles at 128 pixels each;
- keep the animation duration independent of `Engine.time_scale`;
- retain real alpha transparency in all four PNG frames.

## Creature highlight frame

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/ui/creature_stats_ui.gd`;
- `res://assets/ui/creature_selection_frame.png`.

Rules:

- the frame asset may be authored larger than `256x256`; the script scales it down automatically;
- hover uses a softer modulate, selection uses a stronger modulate;
- do not leave the highlight at texture-native size;
- keep the highlight overlay above world resources/grass;
- keep highlight logic split: UI owns selection intent, creature owns visual overlay.

## Creature death and corpse visuals

Main files:

- `res://scripts/creatures/creature.gd`;
- `res://scripts/creatures/creature_species_data.gd`;
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`;
- `res://data/species/stegosaurus.tres`;
- `res://assets/sprites/creatures/stegosaurus/stegosaurus_dead.png`.

Rules:

- corpse visuals are not blockers;
- dead creatures must not keep stale creature occupancy in `world_grid.gd`;
- `death_texture` and `corpse_lifetime` belong to species data, not hard-coded per scene;
- do not delay world-grid unregistration until `queue_free()`.
