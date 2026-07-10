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

`res://scenes/main/main.tscn` owns active UI node wiring.

Current UI scripts:
- `res://scripts/ui/creature_stats_ui.gd` — creature info panel, selection, and hover/selection highlight coordination.
- `res://scripts/ui/player_ui.gd` — side-panel counters and time speed controls.
- `res://scripts/ui/debug_status_ui.gd` — compact FPS/Time/Mem line and F4 detailed debug text.
- `res://scripts/ui/player_nature_ui.gd` — energy and nature powers.
- `res://scripts/debug/grid_debug_overlay.gd` — F3 grid/debug overlay.

Expected scene wiring:
- `UI` uses `creature_stats_ui.gd`.
- `UI/FpsLabel` uses `debug_status_ui.gd`.
- `UI/PlayerSidePanel` uses `player_ui.gd`.
- `UI/PlayerSidePanel/.../PlayerNaturePanel` uses `player_nature_ui.gd`.

Rules:
- do not put counters or time speed controls back into `creature_stats_ui.gd`;
- do not put detailed debug text back into `creature_stats_ui.gd`;
- F3 grid overlay and F4 text debug are separate systems;
- creature click selection should stay compatible with lightning targeting and highlight updates;
- dead/corpse creatures should not remain selectable unless deliberately reworked later.

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
- `res://scenes/world/world.tscn`
- `res://scripts/world/world_grid.gd`
- `res://assets/sprites/terrain/tree_tiles_independent.png`

Do not use old object-tree files:
- `res://scenes/resources/tree.tscn`
- `res://scripts/resources/tree.gd`
- `res://assets/sprites/terrain/trees/`

Do not use abandoned large-tile file:
- `res://assets/sprites/terrain/tree_tiles_large.png`

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

Why this setup:
- it avoids large TileMap tile alignment issues;
- it avoids `texture_origin` artifacts;
- it keeps tree blocking identical to water/mountain blocking;
- it lets grass placement reject tree terrain through normal walkability checks;
- trees can still be placed quickly by using Godot TileMap Patterns.

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

## Creature highlight frame

Main files:
- `res://scripts/creatures/creature.gd`
- `res://scripts/ui/creature_stats_ui.gd`
- `res://assets/ui/creature_selection_frame.png`

Runtime flow:
1. `creature_stats_ui.gd` tracks hovered and selected creatures.
2. It toggles hover/selected highlight flags on the creature node.
3. `creature.gd` shows `InteractionHighlight` using the shared stone frame texture.
4. The highlight sprite scales the source texture to `256x256`.
5. The highlight sprite uses a high absolute z-index so it renders above grass and other world props.
6. On death, the creature clears highlight state and hides the overlay.

Rules:
- the frame asset may be authored larger than `256x256`; the script scales it down automatically;
- hover uses a softer modulate, selection uses a stronger modulate;
- do not leave the highlight at texture-native size;
- keep the highlight overlay above world resources/grass;
- keep highlight logic split: UI owns selection intent, creature owns visual overlay.

## Creature death and corpse visuals

Main files:
- `res://scripts/creatures/creature.gd`
- `res://scripts/creatures/creature_species_data.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`
- `res://data/species/stegosaurus.tres`
- `res://assets/sprites/creatures/stegosaurus/stegosaurus_dead.png`

Runtime flow:
1. `creature.gd` enters `State.DEAD`.
2. Any active duel is notified.
3. Timers, current pathing, grazing target, and creature input picking are stopped.
4. The creature unregisters itself from `world_grid.gd` immediately.
5. Collision/Area2D picking is disabled recursively.
6. The species `death_texture` is shown as the corpse visual.
7. After `corpse_lifetime`, the creature is removed.

Rules:
- corpse visuals are not blockers;
- dead creatures must not keep stale creature occupancy in `world_grid.gd`;
- `death_texture` and `corpse_lifetime` belong to species data, not hard-coded per scene;
- do not delay world-grid unregistration until `queue_free()`.

## Task bundle: trees or terrain blocking

Read first:
- `res://scenes/world/world.tscn`
- `res://scripts/world/world_grid.gd`
- `res://assets/sprites/terrain/tree_tiles_independent.png`

Rules:
- trees stay in TileSet source id `3`;
- trees are blocked terrain;
- trees are painted as 2x2 blocks of normal 128x128 tiles;
- do not re-add `tree.gd` or `tree.tscn`;
- do not use large 256x256 TileMap tiles for trees;
- do not use `texture_origin` hacks for tree alignment;
- use Godot TileMap Patterns if placing trees by hand becomes tedious.

## Runtime flow: tree blocking

Trees are terrain tiles. `world_grid.gd` reads the TileMap source id from `Ground`. If a tile belongs to tree source id `3`, it is treated as blocked terrain. This prevents creature pathing and grass placement on tree terrain.
