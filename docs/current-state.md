# Dyna — Current Project State

> Purpose: describe what the prototype currently is and what systems already work. This file should not duplicate the project file map or detailed dependency bundles.

---

## 1. Status

Dyna is an early Godot 4.7 simulation prototype.

The project currently has:
- a tile-based 2D world;
- autonomous herbivore creatures;
- grass as a renewable resource;
- eggs, hatching, and population growth;
- a temporary predator and simple duel combat;
- player nature powers;
- debug/performance tools;
- a free observer camera.

The project is still a simulation sandbox, not a finished game.

---

## 2. Design direction

The player is not a direct unit commander. The intended feel is an ecosystem that mostly runs by itself while the player influences conditions from above.

Important direction rules:
- keep creature behaviour autonomous;
- prefer indirect influence over unit commands;
- keep world/resource/entity logic separate from UI;
- avoid turning the project into a standard RTS.

---

## 3. Implemented systems

### World

The prototype has a tile-based world using `TileMapLayer`.

The world currently supports:
- walkable terrain;
- blocked terrain types;
- map bounds caching;
- footprint placement;
- occupancy tracking;
- blocker tracking;
- pathfinding;
- grass/resource lookup.

### Creatures

The world contains autonomous creatures with:
- species-driven stats and visuals;
- logical tile anchors;
- smooth visual movement;
- hunger;
- health;
- aging;
- death;
- wandering;
- food seeking;
- eating;
- egg laying;
- combat state.

Creature logic is split between the main creature coordinator and helper scripts for grazing, predator behaviour, reproduction, and visuals.

### Species

Static creature data lives in species resources. Current species coverage includes:
- a herbivore species;
- a temporary predator species.

Species resources hold the stable per-species data that should not be duplicated into every creature script.

### Grass

Grass is the first renewable resource.

It currently supports:
- growth stages;
- edible adult state;
- consumption;
- spreading;
- tile registration in the world grid;
- reaction hooks for player nature powers.

Grass lifecycle logic belongs to grass itself.

### Eggs and reproduction

Reproduction currently works through eggs.

Eggs support:
- staged lifecycle;
- blocker registration when needed;
- vulnerability rules;
- hatching into a creature.

Egg blocker cleanup is important for honest world walkability.

### Predator and combat

The predator system is a temporary prototype layer.

It currently supports:
- prey search;
- chase/pathing toward valid contact;
- side-contact-only duel entry;
- simple one-on-one duel combat;
- basic combat cleanup.

Combat aftermath is still prototype-level and may need a richer corpse/eating/resource flow later.

### Player nature powers

The player has energy and nature powers.

Current power categories:
- creature-targeted damage;
- terrain-targeted grass acceleration;
- terrain-targeted grass reduction/recovery interaction.

Exact costs, radii, damage, counts, and other tuning values are intentionally not documented here. Read current values from exported variables/resources in code.

### UI, debug, and performance

The prototype currently includes:
- creature hover/selection;
- creature stats display;
- debug status text;
- simulation speed selection;
- grid/path/occupancy debug overlay;
- runtime counters;
- CSV performance logging;
- observer camera movement and zoom.

The UI is still prototype-level. Some responsibilities are mixed and should be split during UI cleanup.

---

## 4. Prototype-level or unfinished areas

The following systems work but are not final:
- predator behaviour;
- combat aftermath;
- player nature-power framework;
- UI organization;
- visual effects;
- terrain/biome depth;
- population balance;
- species variety;
- save/load;
- art pipeline and asset consistency.

---

## 5. Known technical debt

### UI responsibility mixing

`creature_stats_ui.gd` currently handles creature stats, selection, debug status, and simulation speed UI. This should be split during UI work.

### Creature coordinator growth

`creature.gd` is still a central coordinator. Keep pushing clear subsystem logic into helpers instead of growing it into a blob.

### Grazing performance

Food search/pathfinding can become expensive. Keep performance counters useful and check logs when grazing/path spikes appear.

### Player power framework

Current powers work, but the system is not yet a general reusable action framework.

---

## 6. Current fragile rules

- Creature logical anchors, pending anchors, visual position, and world occupancy must stay synchronized.
- Creatures should only eat after reaching a valid grazing anchor.
- World-grid registration for grass, creatures, and blockers must stay honest.
- Predator combat must remain side-contact-only unless deliberately redesigned.
- Egg blockers must unregister before hatching or removal.
- Player powers should not bypass grass/egg/creature lifecycle rules.
- Species stats should remain in species resources unless a value is truly per-instance runtime state.

---

## 7. Useful next directions

Possible near-term work:
- compact UI cleanup;
- better visual feedback for nature powers;
- grazing/pathfinding performance improvements;
- predator/combat polish;
- richer terrain and resource interactions;
- additional species;
- improved debug/performance instrumentation.

These are not strict roadmap items; see `docs/design_roadmap.md` for broader planning.
