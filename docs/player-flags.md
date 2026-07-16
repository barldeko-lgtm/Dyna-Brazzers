# Dyna — Player Species Flags

## Purpose

Species flags are indirect player orders. They influence where autonomous creatures prefer to operate without turning Dyna into a direct-control RTS.

The first implementation supports one stegosaurus pasture flag. The structure is intentionally species-based so triceratops, tyrannosaurus, raptor, pterodactyl, and egg-eater roles can be added later without replacing the system.

## Current player flow

1. The existing `⚑` button opens the species-flag submenu.
2. `Стегозавр — поставить` enables world targeting.
3. The cursor previews the flag tile and its 11x11 influence area.
4. Left-click on walkable terrain places or moves the flag.
5. Right-click cancels placement.
6. `Удалить флаг` removes the active stegosaurus flag.

Flags do not cost nature energy.

## Behaviour priority

A flag is weaker than the creature's survival and lifecycle behaviour.

Current effective priority:

1. death and active combat;
2. hunger and feeding;
3. egg laying and reproduction;
4. species flag;
5. ordinary idle wandering.

Only fed stegosauruses in `IDLE` or `WALK` may receive a flag route. Every eligible stegosaurus receives an independent destination, including creatures already completing an ordinary movement step. Crossing the hunger-search threshold immediately removes the queued flag route and switches the creature back to normal grass seeking. A hungry, eating, fighting, laying, or dead creature is never forced toward the flag.

## Area and target distribution

- The flag is stored on one map tile.
- Its influence area is 11x11 tiles, centered exactly on the flag tile: five tiles to each side plus the flag tile itself.
- The flag visual and area overlay do not reserve grid occupancy.
- A creature is considered to have arrived when the center of its footprint enters the area.
- Mature-grass anchors inside the area are preferred.
- A free walkable anchor is used when no suitable mature grass is available.
- Runtime target reservations spread multiple stegosauruses across different footprint anchors instead of sending all of them to the flag tile.
- On arrival, the creature returns to its normal autonomous logic. If it later wanders outside while fed, the flag can attract it again.

## Files and ownership

- `project.godot`
  - registers the `PlayerFlags` autoload;
  - points `SaveSystem` to the lightweight flag-aware extension.
- `scripts/flags/player_flag_system.gd`
  - attaches to the current game scene;
  - owns the flag submenu and targeting mode;
  - stores active species flag tiles;
  - distributes creature destinations;
  - applies the current soft stegosaurus order.
- `scripts/flags/player_flag_visual.gd`
  - draws the placed flag;
  - draws the 11x11 area;
  - draws valid/invalid placement previews;
  - never changes terrain or occupancy.
- `scripts/save/save_system_with_flags.gd`
  - extends the existing save system;
  - adds `player_flags` to save data;
  - restores flag state after the normal simulation restore;
  - cancels flag targeting when the save/load menu opens.
- `scripts/save/save_system.gd`
  - remains the source of truth for all pre-existing save, load, slot, menu, creature, grass, egg, energy, and camera behaviour.

## Save compatibility

The base save version remains unchanged. The new `player_flags` field is optional:

- new saves include active species flag tile records;
- old saves without the field load normally with no active flags;
- moving or deleting a flag is reflected on the next normal save.

## Extension rules

When adding another species flag:

- keep one active flag per species during the first implementation phase;
- add a species-specific role rather than copying generic movement blindly;
- keep survival and lifecycle states above flag behaviour;
- reuse the same tile record and world visual infrastructure;
- do not make flags blockers;
- do not spend energy unless the design is explicitly changed later;
- avoid direct target-click commands on individual dinosaurs.

Planned role direction:

- stegosaurus and triceratops: pasture / resource area;
- tyrannosaurus: attack and hunting area;
- raptor: defence area around eggs and herbivores;
- pterodactyl and egg eater: define only after their intended strategic roles are agreed.
