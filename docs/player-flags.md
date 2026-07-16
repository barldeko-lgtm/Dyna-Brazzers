# Dyna — Player Species Flags

## Purpose

Species flags are indirect player orders. They give otherwise-idle creatures a preferred 11x11 area without turning Dyna into a direct-control RTS.

All current player species support one independent flag:

- stegosaurus — pasture;
- triceratops — pasture;
- tyrannosaurus — hunt;
- raptor — defence;
- pterodactyl — patrol;
- egg eater — search.

The names communicate player intent only. The current movement rule is shared: when a creature has no higher-priority task, it moves toward a valid anchor inside its own flag area.

## Player flow

1. The existing `⚑` button opens the species-flag menu.
2. Select a species flag, then left-click a walkable map tile to place or move it.
3. Right-click cancels placement.
4. `Удалить флаг` enters removal mode; left-click a flag center to remove that species flag.

Flags do not cost nature energy and never block terrain, creatures, eggs, grass, or pathfinding.

## Behaviour priority

Current effective priority:

1. death and active combat;
2. hunger and food seeking;
3. egg laying and reproduction;
4. species flag;
5. ordinary idle wandering.

Only fed creatures in `IDLE` or `WALK` may receive a flag route. The current grid step always completes before a new flag route begins. Once a creature reaches the area, it resumes normal autonomous behaviour and can later be attracted back after leaving it.

Stegosauruses and triceratops prefer mature grass anchors inside their pasture area. Other current species use free valid anchors in their area. Hungry predators resume prey hunting; hungry egg eaters resume stage-2 egg seeking.

## Area and distribution

- one flag is stored per supported species;
- each area is 11x11 tiles, centered on its flag tile;
- destinations are distributed across valid footprint anchors to avoid stacking;
- species flags use distinct colors; the stegosaurus flag retains its plate marker.

## Files and ownership

- `project.godot` registers the `PlayerFlags` autoload and the flag-aware `SaveSystem` extension.
- `scripts/flags/player_flag_system.gd` owns UI, placement, save state, route assignment, and soft attraction for all current species.
- `scripts/flags/player_flag_visual.gd` draws non-blocking flags, areas, and placement previews.
- `scripts/save/save_system_with_flags.gd` adds optional `player_flags` data over the base save system.

## Save compatibility

New saves store all active species flag tile records. Old saves without `player_flags` load with no active flags.
