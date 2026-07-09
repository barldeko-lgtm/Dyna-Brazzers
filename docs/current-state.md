# Dyna — Current Project State

## Status

Dyna is an early Godot 4.7 simulation prototype.

Current prototype includes:
- tile-based 2D world;
- autonomous herbivore creatures;
- 4-stage renewable grass;
- eggs, hatching, and population growth;
- temporary predator and simple duel combat;
- player nature powers;
- right-side HUD with live creature/egg counters;
- manually selectable water and mountain variants;
- tree terrain tiles;
- debug/performance tools;
- free observer camera.

## Design direction

The player is not a direct unit commander. The game should feel like an ecosystem that runs mostly by itself while the player influences conditions from above.

Keep:
- autonomous creature behaviour;
- indirect player influence;
- world/resource/entity logic separate from UI;
- simulation-first design, not a standard RTS.

## Terrain

Terrain is source-id driven:

- source id `0` — ground;
- source id `1` — water;
- source id `2` — mountain;
- source id `3` — tree.

Water, mountains, and tree tiles are blocked terrain.

Trees are TileMap terrain. Each visual tree is 256x256, but it is stored as four normal 128x128 TileMap tiles in a 2x2 block.

## Trees

Current tree rules:
- trees are placed by hand in `scenes/world/world.tscn`;
- trees do not spawn during gameplay;
- trees are not separate `Node2D` objects;
- trees use TileMap source id `3`;
- each full tree is painted as a 2x2 block of normal 128x128 tiles;
- each tree tile is blocked terrain;
- grass should not grow on tree terrain;
- creatures should not path through tree terrain.

Tree atlas:
- `assets/sprites/terrain/tree_tiles_independent.png`

Atlas layout:
- Tree 1: `(0,0)`, `(1,0)`, `(0,1)`, `(1,1)`;
- Tree 2: `(2,0)`, `(3,0)`, `(2,1)`, `(3,1)`;
- Tree 3: `(4,0)`, `(5,0)`, `(4,1)`, `(5,1)`;
- Tree 4: `(6,0)`, `(7,0)`, `(6,1)`, `(7,1)`.

Recommended editor workflow:
- select the 2x2 tree block in the TileMap editor;
- save/use it as a TileMap Pattern;
- place trees using the pattern instead of four separate manual clicks.

## Grass

Grass has 4 stages:

- Stage 1 — young grass, not edible.
- Stage 2 — edible, restores 3 satiety.
- Stage 3 — edible, restores 5 satiety.
- Stage 4 — edible, restores 7 satiety and can spread.

Rules:
- growth advances by 1 stage every 5 seconds until stage 4;
- eating any edible grass resets it to stage 1;
- only stage 4 grass can spread;
- rain advances grass by 1 stage; stage 4 tries to spread;
- sun reduces grass by 2 stages, but never below stage 1;
- random sun-based grass removal remains separate.

## Fragile rules

- Water variants must remain in source id `1`.
- Mountain variants must remain in source id `2`.
- Tree terrain must remain in source id `3`.
- Trees should use normal 128x128 TileMap tiles, not large 256x256 TileMap tiles.
- Do not use `texture_origin` hacks for trees.
- Grass is edible from stage 2, but spreads only from stage 4.
- Grass food values are `3 / 5 / 7` for stages `2 / 3 / 4`.
