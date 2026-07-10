# Dyna — Current Project State

## Status

Dyna is an early Godot 4.7 ecosystem simulation prototype.

Current prototype includes:

- tile-based 2D world;
- autonomous herbivore creatures;
- quality-aware grass targeting;
- 4-stage renewable grass;
- eggs, hatching, and population growth;
- temporary predator and simple duel combat;
- creature death state with a short corpse/death-pose visual before removal;
- player nature powers;
- one-second four-frame local rain VFX;
- right-side HUD with live creature/egg counters;
- separated player UI, creature info UI, debug status UI, and save system;
- stone corner hover/selection frame over creatures;
- compact always-visible FPS/Time/Mem line;
- F4 detailed text debug status;
- F3 grid/debug overlay;
- manually selectable water and mountain variants;
- tree terrain tiles;
- free observer camera;
- centered startup screen;
- three save slots with date/time labels;
- loading from both the startup screen and the in-game right-side Menu;
- return to Main Menu with full active-session reset;
- Exit buttons in both the startup screen and the in-game menu.

Roadmap block `0.5 — Visuals and game interface` is complete. The next major block is `0.6 — Carnivores and species variety`.

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

The existing `MENU` button in the right-side player panel is used. No separate duplicate in-game menu button is added.

Opening the in-game Menu pauses simulation by setting `Engine.time_scale` to `0`. Closing it restores the speed that was active before opening the menu.

Available actions:

- `Save`;
- `Load`;
- `Main Menu`;
- `Close Game`;
- `Back`.

Save/load uses three slots. Occupied slots show date and time.

Saved dynamic state includes:

- creatures: species, anchor position, health, hunger, age, age-tick progress, reproduction cooldown;
- grass: tile, stage, spread-attempt state, growth/spread timer remainder;
- eggs: species, anchor, stage, timer remainders, hatch stats;
- player energy;
- camera position and zoom;
- simulation speed.

Static terrain is not serialized because ground, water, mountains, and trees currently come from `scenes/world/world.tscn` and do not change during play.

Save files are stored in `user://` as JSON:

- `dyna_save_slot_1.json`;
- `dyna_save_slot_2.json`;
- `dyna_save_slot_3.json`.

`Main Menu` fully unloads the active game scene and clears temporary `SaveSystem` references. It does not delete save files. Starting `New Game` afterwards creates a clean world.

## UI split

Current UI ownership:

- `scripts/ui/start_screen.gd` owns startup-screen button flow and startup loading list;
- `scripts/ui/creature_stats_ui.gd` owns only creature info panel, hover/selection, empty-click deselection, and the lightning click bridge;
- `scripts/ui/player_ui.gd` owns side-panel creature/egg counters and time speed controls;
- `scripts/ui/debug_status_ui.gd` owns the always-visible compact FPS/Time/Mem line and F4 detailed text debug;
- `scripts/ui/player_nature_ui.gd` owns player energy and nature powers;
- `scripts/save/save_system.gd` owns persistence and the save/load content shown through the existing right-side `MENU` button;
- `scripts/debug/grid_debug_overlay.gd` owns the F3 grid/debug overlay.

`scenes/main/main.tscn` should wire the normal gameplay UI scripts directly to their UI nodes. Avoid reconnecting player/debug UI from `creature_stats_ui.gd`.

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

- Stage 1 — young grass, not edible;
- Stage 2 — edible, restores 3 satiety;
- Stage 3 — edible, restores 5 satiety;
- Stage 4 — edible, restores 7 satiety and can spread.

Rules:

- growth advances by 1 stage every 5 seconds until stage 4;
- eating any edible grass resets it to stage 1;
- only stage 4 grass can spread;
- rain advances grass by 1 stage; stage 4 tries to spread;
- sun reduces grass by 2 stages, but never below stage 1;
- random sun-based grass removal remains separate.

## Grazing target scoring

Herbivores evaluate the total food value under their full footprint.

Current formula:

`target_score = total_food_value_under_footprint - estimated_distance * 2`

Food values are:

- Stage 2 = `3`;
- Stage 3 = `5`;
- Stage 4 = `7`.

Stages 2 and 3 remain valid emergency food. Stage 4 is preferred through higher food value, but distance still matters. The periodic target recheck uses the same formula as the initial search.

## Creature selection highlight

Current creature highlight rules:

- hover and selection highlighting are coordinated by `scripts/ui/creature_stats_ui.gd`;
- the frame asset is `assets/ui/creature_selection_frame.png`;
- the frame is rendered as a world-space overlay from `scripts/creatures/creature.gd`;
- selected highlight persists while the creature is selected;
- hover highlight is suppressed when the same creature is already selected;
- the highlight overlay uses a high absolute z-index so it stays above grass and other world props;
- dead creatures clear their highlight immediately.

## Rain visual effect

Current rain visual rules:

- the existing 5x5 targeting preview remains unchanged;
- after a successful rain placement and confirmed energy spend, a four-frame 640x640 animation appears over the selected 5x5-tile area;
- total animation duration is 1 real second;
- playback uses real elapsed time and is not accelerated by simulation speeds x2/x3/x5;
- the effect is visual only; grass simulation changes still happen through the existing rain gameplay logic;
- the effect removes itself after the fourth frame;
- the rain overlay renders above normal world entities and below the creature selection frame.

## Creature death / corpse visual

Current death rules:

- death is entered through `scripts/creatures/creature.gd`;
- a dead creature stops normal behaviour immediately;
- its world-grid creature occupancy is released immediately so other creatures can path through those tiles;
- collision and hover/click picking are disabled for the corpse;
- a species death texture can be shown for a short corpse lifetime;
- after the corpse lifetime expires, the creature is removed with `queue_free()`.

Current stegosaurus death asset:

- `assets/sprites/creatures/stegosaurus/stegosaurus_dead.png`

Current species fields:

- `death_texture`;
- `corpse_lifetime`.

## Fragile rules

- Water variants must remain in source id `1`.
- Mountain variants must remain in source id `2`.
- Tree terrain must remain in source id `3`.
- Trees should use normal 128x128 TileMap tiles, not large 256x256 TileMap tiles.
- Do not use `texture_origin` hacks for trees.
- Grass is edible from stage 2, but spreads only from stage 4.
- Grass food values are `3 / 5 / 7` for stages `2 / 3 / 4`.
- Grazing score is food sum minus distance multiplied by `2`.
- Dead creatures must unregister creature occupancy immediately, before their corpse visual disappears.
- Do not put player counters, time speed controls, or debug status back into `creature_stats_ui.gd`.
- Do not duplicate the in-game Menu outside the existing right-side `MENU` button.
- Returning to Main Menu must reset the active session but must not delete save files.
