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

If a task touches movement, blocked tiles, tree blocking, grass consumption, or pathing, inspect `world_grid.gd`.

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
