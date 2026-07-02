# Dyna — AGENTS.md

## Project snapshot
Dyna is an early Godot prototype of an autonomous dinosaur world inspired by Dyna Brothers. The target is an observable ecosystem with indirect player influence, not a normal RTS with direct unit control.

Current scope:
- a tile-based test world;
- one base species with several test creatures;
- directional sprites for the current creature;
- grass as the first renewable resource;
- egg laying, 2 egg stages, and hatching;
- a first player influence action: lightning;
- a debug UI for hover/selection and creature stats;
- a removable F3 grid debug overlay for grid/path/occupancy inspection;
- a free observer camera.

## Working rules
- Keep all changes inside `E:/dyna` unless explicitly approved otherwise.
- Local Godot lives in `E:/Godot_v4.7/`; preferred headless CLI: `E:/Godot_v4.7/Godot_v4.7-stable_win64_console.exe`; short smoke test: `'/e/Godot_v4.7/Godot_v4.7-stable_win64_console.exe' --headless --path '/e/dyna' --quit-after 10`.
- Before risky or structural code changes, make a git backup commit.
- Keep code comments short and in English.
- Do not push the project toward a standard RTS.
- Do not edit `docs/design_roadmap.md` unless the user asks for it.

## Current architecture canon
- The world grid is the source of truth for walkability, occupancy, and grazing queries.
- Creatures decide in grid space but move smoothly in world space.
- Large creatures use `anchor_tile + footprint`.
- Grass exists per tile, registers into the world, and is edible only in its adult stage.
- UI is observational only.
- Static creature stats and visuals now live in species resources.

## Key files
- `project.godot` — project entry, main scene `res://scenes/main/main.tscn`
- `scenes/main/main.tscn` — top-level assembly: camera, UI, world
- `scenes/debug/grid_debug_overlay.tscn` — removable grid debug overlay scene
- `scenes/world/world.tscn` — test world with tilemap, grass, eggs, and test creatures
- `scripts/world/world_grid.gd` — central world/grid manager
- `scripts/creatures/creature.gd` — base creature runtime logic
- `scripts/creatures/creature_species_data.gd` — species resource schema
- `data/species/stegosaurus.tres` — current species tuning and visuals
- `scripts/resources/grass.gd` — grass lifecycle
- `scripts/resources/egg.gd` — egg lifecycle and hatching
- `scripts/ui/creature_stats_ui.gd` — debug creature UI
- `scripts/debug/grid_debug_overlay.gd` — removable grid debug drawing and info panel
- `docs/project-map.md` — structure and responsibilities
- `docs/current-state.md` — live project snapshot
- `docs/design_roadmap.md` — broader design vision and roadmap

## Recommended read order
1. `AGENTS.md`
2. `docs/project-map.md`
3. `docs/current-state.md`
4. `docs/design_roadmap.md` only when broader design intent matters
5. then inspect task-relevant scenes/scripts

## Fragile areas
- The `world_grid.gd` <-> `creature.gd` link: anchor tiles, footprint, occupancy, grazing, movement.
- Grazing target selection and retargeting in `creature.gd`.
- Registration of grass, creatures, and blockers in the world registry.
- Any change touching `anchor_tile`, `pending_anchor_tile`, or visual-vs-logical sync.

## Near-term project meaning
This stage is a simulation testbed for:
- creature movement;
- food search;
- resource lifecycle;
- observation through UI;
- preparation for more species, player influence, and ecosystem depth.

## Original Dyna Brothers spirit
- Autonomous ecosystem strategy, not heavy micro RTS.
- Creatures should mostly act on their own.
- Combat and behaviour should grow from simple automatic states/roles.
- Readability should come more from world behaviour than heavy UI.
