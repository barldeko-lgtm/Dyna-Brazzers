# Dyna — Current Project State

## Status

Dyna is an early Godot 4.7 ecosystem simulation prototype.

Current prototype includes:

- an editable 85x85 tile-based 2D world;
- autonomous stegosaurus and triceratops herbivores, plus one tyrannosaurus, one raptor, and one pterodactyl predator with egg reproduction;
- one egg eater that uses predator-style navigation to consume only stage-2 eggs;
- a fixed 2x2 player nature base reserved for future player-created eggs;
- quality-aware grass targeting;
- four-stage renewable grass;
- eggs, hatching, and population growth;
- species-specific data resources;
- species-specific two-stage egg visuals for all current reproducing species;
- temporary predator and simple duel-combat code;
- creature death with a short corpse/death-pose visual before removal;
- static flattened contour shadows beneath creatures;
- player nature powers;
- a local four-frame rain VFX;
- right-side HUD with live creature and egg counters;
- an interactive right-side terrain minimap showing ground, water, mountains, trees, creature markers, and the current camera view;
- separated player UI, creature info UI, debug status UI, and save system;
- stone corner hover/selection frame over creatures;
- compact always-visible FPS/Time/Mem line;
- F4 detailed text debug status;
- F3 grid/debug overlay;
- water, mountain, and tree terrain;
- free observer camera constrained to the map;
- centered startup screen;
- three save slots with date/time labels;
- loading from both the startup screen and the in-game right-side Menu;
- return to Main Menu with full active-session reset;
- Exit buttons in both the startup screen and the in-game menu.

Roadmap block `0.5 — Visuals and game interface` is complete. Work on `0.6 — Carnivores and species variety` includes triceratops, tyrannosaurus, raptor, pterodactyl, egg-eater behaviour, retained predator/combat prototype code, and the fixed player-base foundation for future egg creation. Roadmap block `0.7 — Player expansion and atmosphere` has started with the interactive terrain-minimap pass.

Automatic predator spawning is currently disabled.

## Design direction

The player is not a direct unit commander. The game should feel like an ecosystem that runs mostly by itself while the player influences conditions from above.

Keep:

- autonomous creature behaviour;
- indirect player influence;
- world/resource/entity logic separate from UI;
- simulation-first design, not a standard RTS.

## Startup screen

Current startup flow:

- `project.godot` starts `scenes/ui/start_screen.tscn`;
- `New Game` opens a fresh `scenes/main/main.tscn` session;
- `Load` shows three slots;
- occupied slots show save date and time;
- empty slots are visible but disabled;
- `Menu` remains a placeholder for future settings/options;
- `Exit` closes the application.

## In-game Menu and saving

The existing `MENU` button in the right-side player panel opens the save/load menu. No duplicate in-game menu button is used.

Opening the menu pauses the simulation. Closing it restores the speed that was active before the menu opened.

Available actions:

- `Save`;
- `Load`;
- `Main Menu`;
- `Close Game`;
- `Back`.

Saved dynamic state includes:

- creatures and their mutable state;
- grass stages and timers;
- eggs and their stage/timer state;
- player energy;
- camera position and zoom;
- simulation speed;
- save timestamp.

Static terrain and the fixed player base are not serialized. They come from the active start-map setup.

`Main Menu` unloads the active game scene and clears temporary `SaveSystem` references without deleting save files. Starting `New Game` afterwards creates a clean session.

## UI split

Current UI ownership:

- `scripts/ui/start_screen.gd` owns startup-screen flow and startup loading;
- `scripts/ui/creature_stats_ui.gd` owns creature information, hover/selection, deselection, and the lightning click bridge;
- `scripts/ui/player_ui.gd` owns the interactive terrain minimap, creature markers, camera-frame display and click navigation, creature/egg counters, and time-speed controls;
- `scripts/ui/debug_status_ui.gd` owns the compact FPS/Time/Mem line and F4 detailed text debug;
- `scripts/ui/player_nature_ui.gd` owns player energy and nature powers;
- `scripts/save/save_system.gd` owns persistence and the save/load content shown through the existing `MENU` button;
- `scripts/debug/grid_debug_overlay.gd` owns the F3 grid/debug overlay.

`scenes/main/main.tscn` wires these scripts directly to their normal UI nodes.

## Terrain minimap

Current minimap rules:

- `scripts/ui/player_ui.gd` builds the minimap inside the existing `MiniMapPlaceholder` panel;
- the minimap reads the current used bounds and terrain source ids from the active `Ground` TileMapLayer;
- the entire authored map is compressed into the existing 280x280 right-side interface area;
- ground is light brown, water is light blue, mountains are dark grey, and trees are dark green;
- the minimap texture is generated at runtime and does not require a separate manually maintained map image;
- herbivores are shown as light-green triangle markers;
- predator creatures are shown as red triangle markers;
- the egg eater is shown as a blue triangle marker;
- a bright rectangular frame shows the current camera viewport and changes size with camera zoom;
- left-clicking the minimap moves the observer camera to the selected world position;
- terrain stays static during a session, while a separate overlay redraws the camera frame and 6x6 creature triangle markers during play;
- eggs, the player base, and world events are not shown yet.

## Terrain

The active world is `scenes/world/world.tscn`.

The map is 85x85 tiles with a 128x128 tile size. The world contains ground, water, mountains, and trees. Terrain remains source-id driven:

- source id `0` — ground;
- source id `1` — water;
- source id `2` — mountain;
- source id `3` — tree.

Water, mountains, and trees are blocked terrain.

`start_map_layout.gd` contains the initial map description and matching water/mountain edge selection. It builds terrain only when the `Ground` TileMap is completely empty. Once the TileMap contains cells, the script returns without clearing or rebuilding it.

This allows the map to be edited in Godot and saved normally. Serialized TileMap data should be produced only by Godot, not rebuilt manually.

The observer camera:

- starts at the authored `CameraStart` marker for a fresh game;
- restores saved position and zoom when loading;
- supports WASD movement and mouse-wheel zoom;
- is clamped to the authored world bounds.

## Player base

Current player-base rules:

- `scripts/world/start_map_world_grid.gd` instantiates `scenes/world/player_base.tscn` at the authored `CameraStart` marker;
- the base is stationary and belongs to the `player_base` group;
- it occupies and blocks a 2x2 grid footprint, equivalent to 256x256 world pixels;
- creatures and pathfinding treat those four cells as unavailable, like blocked terrain;
- grass cannot spread onto the player-base footprint;
- `assets/sprites/world/player_base.png` remains a 512x512 source texture and is displayed at 256x256 with linear mipmapped filtering;
- the base is static world setup and is not included in save-slot entity data;
- it currently has no active ability; roadmap block 0.7 will use it as the player-created egg origin.

## Trees

Current tree rules:

- trees are TileMap terrain;
- trees do not spawn during gameplay;
- trees are not separate `Node2D` resource objects;
- each visual tree is assembled from a 2x2 block of normal 128x128 tiles;
- tree tiles are blocked;
- grass cannot grow on tree terrain;
- creatures cannot path through tree terrain.

Tree atlas:

- `assets/sprites/terrain/tree_tiles_independent.png`

A TileMap Pattern can be used in the editor to place complete 2x2 trees.

## Grass

Grass has four growth stages.

Rules:

- young grass grows through the stages over time;
- edible grass returns to the first stage when consumed;
- only mature grass attempts natural spreading;
- natural spreading checks cardinal neighbouring tiles;
- grass may spread across any normal walkable ground tile except the fixed player-base footprint;
- initial grass placements are only starting seeds, not an allowed-growth mask;
- rain advances grass growth and can trigger mature spreading;
- sun reduces or removes grass through the existing nature-power rules.

Dynamically created grass is positioned before it is added to the scene tree. This prevents `_ready()` from registering it on an incorrect temporary tile.

## Eggs

Eggs use the shared lifecycle from `scenes/resources/egg.tscn` and `scripts/resources/egg.gd`.

Current reproducing species use their own two-stage egg textures:

- stegosaurus;
- triceratops;
- tyrannosaurus;
- raptor;
- pterodactyl;
- egg eater.

The texture references live in each species `.tres` through:

- `egg_stage_1_texture`;
- `egg_stage_2_texture`.

The shared egg scene remains the fallback for a future species that does not yet provide custom egg textures.

## Grazing target scoring

Herbivores evaluate the total available food under their full footprint and compare it with travel distance.

More mature grass is worth more, but nearer lower-stage edible grass remains a valid fallback. Initial target selection and periodic retargeting use the same scoring logic.

A creature must reach a valid eating position before consuming grass.

## Creature selection highlight

Current creature highlight rules:

- hover and selection are coordinated by `scripts/ui/creature_stats_ui.gd`;
- the frame asset is `assets/ui/creature_selection_frame.png`;
- the frame is rendered as a world-space overlay from `scripts/creatures/creature.gd`;
- selected highlight persists while the creature is selected;
- hover highlight is suppressed when that creature is already selected;
- the overlay renders above grass and normal world props;
- dead creatures clear the highlight immediately.

## Rain visual effect

Current rain visual rules:

- the existing target preview shows the affected area;
- after a successful cast and confirmed energy spend, a four-frame rain animation appears over the selected area;
- playback uses real elapsed time and is not accelerated by simulation speed;
- the visual effect does not independently change grass;
- gameplay changes remain in the rain/nature-power logic;
- the effect removes itself after playback;
- the rain overlay remains below the creature selection frame.

## Creature death / corpse visual

Current death rules:

- death is entered through `scripts/creatures/creature.gd`;
- normal creature behaviour stops immediately;
- world-grid creature occupancy is released immediately;
- collision and hover/click picking are disabled for the corpse;
- a species death texture may be shown for a short corpse lifetime;
- the corpse is non-blocking;
- the creature is removed after the corpse lifetime expires.

The stegosaurus currently has a dedicated death-pose asset. Death visuals and corpse lifetime belong to species data rather than the shared creature scene.

## Fragile rules

- `world.tscn` is the only active world scene.
- The empty-map bootstrap must never overwrite a non-empty TileMap.
- Do not manually construct or rewrite Godot `tile_map_data`.
- Water variants must remain in source id `1`.
- Mountain variants must remain in source id `2`.
- Tree terrain must remain in source id `3`.
- The terrain minimap reads those source ids and must never modify TileMap data.
- Minimap clicks may move only the observer camera; they must not change terrain, entities, or simulation state.
- Trees use normal 128x128 tiles assembled into 2x2 visuals.
- The player base must stay a static 2x2 blocker and must not be serialized as a dynamic creature/resource entity.
- Grass spreads only onto normal walkable terrain and must not spread onto the player-base footprint.
- Initial grass nodes are starting seeds, not a growth whitelist.
- New grass must be positioned before `add_child()`.
- Species-specific egg textures belong in the species `.tres`, not in duplicated egg scenes.
- When custom egg textures are absent, preserve the shared egg scene defaults rather than assigning `null`.
- Dead creatures must unregister occupancy before their corpse visual disappears.
- Do not put counters, speed controls, or debug status back into `creature_stats_ui.gd`.
- Do not duplicate the in-game menu outside the existing `MENU` button.
- Returning to Main Menu resets the active session but does not delete saves.
- Major map edits can make old saved entity positions invalid; recreate saves or add an explicit migration.
