# Dyna — Current Project State

This document describes implemented gameplay and player-visible behaviour.

Cold-start reading order:

1. `docs/current-state.md`
2. `docs/project-map.md`
3. `docs/dependencies.md`

`current-state.md` explains what works, `project-map.md` locates ownership, and `dependencies.md` records fragile contracts.

## Documentation policy

The current repository is the source of truth.

Frequently tuned balance values such as costs, timers, thresholds, search limits, radii, and visual durations should normally be read from their owning scripts or resources. This document repeats numbers only when they are stable structural identifiers or are necessary to understand a save/compatibility contract.

## Status

Dyna is an early Godot 4.7 autonomous 2D ecosystem simulation.

Implemented foundations include:

- two selectable tile-based level layouts sharing one world scene and gameplay stack;
- one fixed player nature base and one fixed enemy base;
- six current species: stegosaurus, triceratops, tyrannosaurus, raptor, pterodactyl, and egg eater;
- shared player/enemy creature biology with separate resource variants and runtime faction ownership;
- eggs, hatching, autonomous population growth, hunger, grazing, reproduction, hunting, duels, death, and corpse visuals;
- player nature powers: lightning, rain, sun, and earthquake;
- player energy, enemy energy, player egg purchases, and enemy strategic egg production;
- species-specific player flags and persistent enemy rally objectives;
- automatic enemy priority lightning, profitable earthquake targeting, plus rain scoring and performance diagnostics;
- startup, in-game menu, three save slots, settings, global audio, minimap, HUD, debug overlays, and elimination-based victory/defeat results.

Roadmap block `0.5 — Visuals and game interface` is complete. Work from the later creature, player-expansion, and enemy blocks is partially implemented. `docs/design_roadmap.md` remains the design roadmap and must not be edited unless explicitly requested.

## Design direction

The player does not directly command units. Creatures remain autonomous and the player influences conditions indirectly.

Preserve:

- simulation-first behaviour;
- autonomous survival and movement;
- indirect player and enemy objectives;
- shared biological systems for every faction;
- separation between world logic, entity logic, UI, and diagnostics.

Do not turn Dyna into a standard RTS or create enemy-only copies of common creature systems.

## World, terrain, and camera

The active world is `scenes/world/world.tscn`.

Level 1 preserves the authored 85x85 TileMap. Level 2 is built at runtime from `assets/maps/level_2_map.png`, where one exact-color pixel is one tile. The supplied 84x70 layout defines terrain, DryGround, grass, complete 2x2 trees, and two 2x2 base footprints with the player base on the left.

The current map uses stable TileSet source ids:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

Water, mountains, trees, faction-base footprints, and occupied DryGround cells are unavailable to normal movement and grass placement.

`start_map_layout.gd` preserves the authored level-1 TileMap. For level 2 it replaces only the runtime Ground/DryGround layout before world-grid initialization and rebuilds map-defined grass and base markers.

Trees are TileMap terrain, not separate resource nodes. Each visual tree is assembled from normal terrain tiles and all occupied cells are blocked.

The observer camera:

- renders the world through a dedicated gameplay viewport ending at the live left edge of the adaptive right-side panel;
- starts from the authored `CameraStart` marker on a fresh game;
- restores position and zoom from saves;
- supports WASD movement and mouse-wheel zoom;
- remains clamped to the map and to limits owned only by `camera_controller.gd`;
- moves in real time independently of simulation speed.

DryGround is a world overlay rather than a terrain source. Rain records partial progress, eventually clears cells, and reopens them to normal walking and grass recovery. Cleared cells and partial progress are saved as deltas over the authored map.

## Creatures and autonomous behaviour

All current species use the shared `creature.tscn` and common behaviour modules.

`creature.gd` remains the public creature coordinator. Dedicated controllers own:

- movement and queued routes;
- directional visuals, animations, shadows, and death poses;
- mouse interaction and selection;
- grazing, predator, egg-eater, reproduction, and combat behaviour.

All current creatures use the shared logical footprint. Movement reserves the next footprint before visual travel so two creatures cannot commit to the same destination.

Player and enemy pterodactyls use flight traversal: route steps may cross water, trees, and DryGround, while mountains remain blocked. Normal ground placement remains the destination contract, so a pterodactyl cannot idle, begin combat, or reproduce over aerial-only terrain. If an active route ends or is interrupted there, ordinary movement continues until a ground anchor is reached.

Long indirect-order routes are planned against terrain and persistent blockers rather than temporary creature positions. If the next real step is occupied, managed flag and behaviour routes first try a short rejoin around the obstruction, then a full alternate route to the same destination. When neither route exists, the creature keeps its goal and queued path, waits while the blocking footprint remains unchanged, and retries immediately after that occupancy changes.

Survival, food, reproduction, hunting, combat, and death take priority over player or enemy strategic objectives.

### Reproduction

All current species build persistent egg-laying progress from satiety after their minimum-age gate. Zero satiety pauses progress, low satiety advances it at half rate, and satiety at or above the high threshold advances it at full rate. Existing health, satiety, and age gates still control the start of laying. Progress resets only after successful egg creation and is preserved by save/load.

### Grazing

Herbivores use a shared cached pasture system rather than scanning all grass from scratch for every decision.

The current approach:

- caches useful pasture footprints and groups them into local sectors;
- builds a small quality shortlist;
- evaluates reachability with one shared breadth-first route wave;
- ranks reachable food by food value minus actual route cost;
- periodically validates the current route and compares alternatives;
- updates only pasture entries affected by a changed grass tile.

Occupancy and movement reservations are checked live and are not stored in the pasture cache.

### Predators and egg eaters

Predators compare a small nearest-prey set by reachable route length, reserve only the final combat engagement, and use shared movement and duel systems. Every prey candidate uses one shared route search that can finish at any valid side approach instead of launching a separate search for each side. While following a healthy route, their periodically staggered scan cheaply estimates only the nearest challenger and starts route search only when that challenger can plausibly beat the remaining route; an unreachable candidate is skipped for a short temporary cooldown. Predator role, thresholds, and mode-specific search radii are species data. Tyrannosaurus and pterodactyl are attacker-role predators: above their normal hunger threshold and at or below their strategic threshold they scan a shorter strategic radius for any creature of the opposing player/enemy faction, including herbivores, predators, and egg eaters. Until a target is found they may continue an indirect flag route; acquiring a strategic target replaces that route, while reproduction eligibility remains higher priority. At or below the normal hunger threshold, attacker-role predators switch to their wider survival hunt across factions and diet categories, except that they never attack the same biological species of their own faction. Raptors are defender-role predators: while not critically hungry they repeatedly scan a smaller guard radius for any opposing-faction creature, and a detected enemy hunt overrides indirect flag travel and prevents a new egg laying from starting. An egg laying already in progress remains uninterrupted. At or below the raptor hunger threshold, the wider survival hunt accepts herbivores of any faction while still rejecting same-faction predators and egg eaters.

Defender raptors may actively protect an allied herbivore or egg eater from a predator of the opposing faction while not critically hungry. Attacker-role tyrannosaurus and pterodactyl never switch targets or search for a fight solely for protection, but they may continue pursuing an already selected opposing predator after that target attacks an allied herbivore or egg eater. The first eligible protector to reach the attacker reserves the intervention, waits for the next scheduled duel hit to finish, then replaces the protected creature in a new one-on-one duel. The protected creature leaves combat, and the replacement duel cannot be interrupted again. Predator-versus-predator duels are never eligible for this protection.

A predator that wins a completed duel restores its species-defined satiety reward and a clamped amount of health. An intervention handoff has no winner and grants no reward; only the eventual winner of the replacement duel is rewarded.

Egg eaters are a separate diet category. From 90 to above 25 satiety they scan radius 20 for opposing-faction eggs, continuing an indirect flag route until a reachable target is found. At or below 25 satiety hunger overrides the flag even without a target, and they accept any egg except one matching both their species and faction. Initial acquisition shortlists three nearby eggs and compares real routes; each egg uses one shared search that can finish at any valid side approach. While following a healthy route, the egg eater checks on an approximately one-second cadence with a small stable per-creature offset, cheaply estimates only the nearest new candidate, and builds a challenger route only when it can plausibly be meaningfully shorter. Failed current or challenger eggs are skipped for a short temporary cooldown, then become eligible again. Stage-one eggs remain trackable from safe non-blocking waiting cells, and only stage two can be consumed. Player and enemy variants share this rule.

### Death and visuals

Death stops normal behaviour immediately, releases world-grid occupancy, disables collision and picking, and leaves a short non-blocking corpse visual before removal. Species may show a brief transition pose before the final corpse pose; all current player and enemy species variants use this two-step sequence.

Death transition texture and duration, final death texture, and corpse lifetime belong to species data. Missing transition art skips that step, while a missing final death texture falls back through the shared visual controller.

Creature contour shadows follow static or animated directional visuals and never affect gameplay systems.

## Grass and nature powers

Grass has four stages. `scripts/resources/grass.gd` is the single owner of growth timing, mature spread timing, stage-dependent food value, consumption reset, spreading, and reactions to nature powers.

Core grass rules:

- young grass advances through stages;
- edible grass returns to the first stage when consumed;
- only mature grass attempts cardinal spreading;
- grass may occupy valid normal ground but not blocked terrain, DryGround, or either faction-base footprint;
- initial grass nodes are starting seeds, not an allowed-growth mask;
- grass registration, removal, and edible-stage changes update only overlapping pasture-cache entries.

Rain may advance existing grass, trigger mature spreading, and contribute to DryGround clearing. Before applying one rain cast, the shared nature-effects system snapshots the grass already present in the cast area. Grass created during that cast is not processed again and therefore starts at stage 1.

When DryGround clears, adjacent mature grass is allowed to resume its normal recovery path.

Sun reduces or removes grass through the shared nature-effects system.

Earthquake affects eggs but does not damage creatures or alter grass.

Failed player or enemy nature-power application refunds the exact energy already charged.

## Species data, catalogs, and faction ownership

Biology, resource variant, and runtime ownership are separate concepts:

- `CreatureSpeciesData` describes biological identity, diet, stats, visuals, survival, combat, and reproduction;
- `PlayerSpeciesCatalog` stores player-only roster order, egg economy, energy income, and flag presentation;
- `EnemySpeciesCatalog` selects enemy resource variants and enemy economy values;
- `CreatureFaction` stores runtime ownership as `player`, `enemy`, or `neutral`.

Player and enemy variants keep the same biological `species_id`. Their resource path selects the visual/stat variant; their faction selects ownership and system eligibility.

Current enemy resources:

- exist separately under `data/species/enemy/`;
- currently mirror the corresponding player balance values;
- use faction-specific directional sprites under `assets/sprites/creatures/enemy/<species>/`;
- currently reuse player egg textures;
- intentionally omit walk/eat animation frame resources, so static directional poses are used.

Old saves without faction fields restore missing ownership as player. Unknown non-empty faction ids normalize to neutral.

Only living catalog-supported player creatures generate player energy. Only living catalog-supported enemy creatures generate enemy energy.

## Eggs and faction bases

All species and factions use the shared egg scene and lifecycle. Egg timing is defined only in `scripts/resources/egg.gd`; species resources provide visuals and hatchling biology, not incubation timing.

The shared egg scene keeps generic fallback textures under `assets/sprites/eggs/`. Every current species resource selects its own two-stage egg textures; missing custom textures fall back to those shared defaults.

Faction inheritance rules:

- naturally laid eggs inherit the parent faction;
- player-base eggs are assigned `player`;
- enemy-base eggs are assigned `enemy`;
- hatchlings inherit the egg faction.

Both bases use the shared `FactionBase` foundation:

- each is a fixed 2x2 blocker;
- both reject grass on their footprint;
- both use the same nearby egg-placement plumbing;
- both are static world setup and are not serialized as dynamic entities.

The player base is created at `CameraStart` and exposes `create_player_egg()`.

The enemy base uses an authored `EnemyBaseStart` marker when available and otherwise chooses a deterministic valid fallback near the opposite map edge. It exposes `create_enemy_egg()` to enemy strategy code.

Energy is spent only after a base successfully creates an egg. Failed placement costs nothing.

## Enemy strategic systems

Enemy strategy is split by responsibility.

### Production AI

`enemy_ai_controller.gd` periodically builds one derived snapshot from the stable creature and egg groups.

The snapshot:

- includes only explicitly enemy-owned, catalog-supported entities;
- stores adult, egg, and projected totals separately;
- counts an egg as one future adult of its hatch species;
- calculates normalized average satiety from adult enemy herbivores only;
- excludes eggs from satiety;
- is rebuilt after load rather than serialized as a second source of truth.

Current production behaviour:

- treats the first scheduled strategic cadence of a fresh match as a complete no-action turn, so production and spell decisions begin on the following cadence;
- builds a stegosaurus-heavy herbivore mix while the configured hunger gate allows it;
- skips herbivore production when the adult herbivore herd is below its configured satiety threshold;
- switches to the current combat-production priority after the configured herbivore-cap phase;
- establishes two living adult raptors, one living adult tyrannosaurus, and one living adult pterodactyl before ordering an egg eater;
- keeps egg-eater production locked for the first ten simulation minutes and orders at most one while any enemy egg eater or its egg exists;
- returns the egg eater to the production priority after all enemy egg eaters and their eggs are gone; natural reproduction is not capped;
- waits rather than substituting another species when the selected target cannot be bought or placed.

The disabled legacy round-robin producer remains instantiated only for backward-compatible saved cursor/timer data and must stay disabled.

### Enemy combat-spell reserve

`enemy_spell_controller.gd` owns a separate reserve for future offensive spells. Match time increases only its storage capacity; it does not create reserve energy. The capacity opens at the ten-minute mark, grows by the configured early amount on each full minute through 20:00, grows by the configured late amount from 21:00 onward, and stops at the configured maximum.

Actual reserve energy comes only from living enemy-creature income. `enemy_energy.gd` keeps the gross income calculation; after the ten-minute unlock, when gross income meets the configured threshold and reserve space remains, the configured share is deposited into the combat reserve and the remainder enters ordinary enemy energy. Below the threshold, before unlock, or while the reserve is full, all income enters ordinary energy.

Offensive spells check stored reserve energy only. After each successful offensive cast, the exact cost is removed from stored energy, which may fall to zero. The reserve capacity loses the same amount but cannot fall below its configured capacity floor; later minute ticks rebuild that reduced capacity normally. A failed target or failed shared effect changes neither amount nor capacity.

Rain remains an economic support spell. It spends ordinary enemy energy whenever that store can cover the complete cost. Otherwise it may pay the complete cost from the combat reserve; the two stores are never combined for one cast. Rain spending changes only stored reserve energy, never capacity, and a failed application refunds the same store that paid.

The exact reserve amount, capacity, and next capacity tick are saved. Saves from the earlier time-charged prototype discard its artificial stored amount, rebuild only capacity from restored enemy-AI time, and resume filling from real creature income.

### Enemy lightning

Enemy lightning is evaluated on completed strategic turns before support rain. It uses the shared world lightning effect and targets only living player tyrannosauruses or egg eaters.

Egg eaters have priority. When the enemy has no living hatched raptor anywhere, a player egg eater inside the configured radius around the enemy base reserves lightning priority. An egg eater at or below one-strike health requires one lightning cost. A healthier egg eater is attacked only when two strikes are sufficient to kill it and two full lightning costs are stored; the controller applies the first strike immediately and the second after the configured simulation-time delay. Passive regeneration during that short delay cannot invalidate the approved kill. Each successful strike separately spends one cost from both stored reserve energy and capacity. If no threatening egg eater is currently killable, the reserve is held instead of being spent on a tyrannosaurus, while support rain may still run.

A player tyrannosaurus is eligible only at or below the configured one-strike health threshold, inside its configured enemy-base radius, and when no living hatched enemy raptor is inside the configured guard radius around that tyrannosaurus. Among eligible tyrannosauruses, lower health wins, then shorter base distance. There is no separate lightning cooldown.

### Enemy earthquake

Enemy earthquake is considered on the strategic cadence after egg-eater lightning and emergency rain, but before opportunistic lightning against a weakened tyrannosaurus. It uses the shared world earthquake effect and the controller-owned offensive reserve cost.

The controller skips the search until the stored reserve can pay the complete cast and at least two valid player eggs exist. Candidate centers are derived from map-clipped overlap regions for all current egg footprints rather than sampled randomly or tested tile by tile; the representative point inside each unchanged region is the one nearest the enemy base. A zone is valid only when it contains at least the configured minimum number of player eggs, contains no non-player egg, and the summed player purchase value of the affected eggs is strictly greater than the earthquake cost. Values come directly from `PlayerSpeciesCatalog`, so later egg-price rebalance automatically changes the decision.

The best profitable zone is ranked by greater total egg value, then more stage-two eggs, then more eggs, then shorter distance to the enemy base. The zone is revalidated immediately before application. Failed or stale targets spend nothing; a successful shared earthquake uses the normal offensive reserve amount-and-capacity spending rule.

### Enemy rain

`enemy_spell_controller.gd` listens to the completed AI snapshot but does not own population decisions.

When adult enemy herbivore satiety is below the configured threshold and energy is available, it:

- searches only the map-clipped area around the enemy base;
- preserves immediate-spread candidates from mature grass whose spread attempt remains available;
- also builds candidates from DryGround only when that DryGround has cardinally adjacent existing grass;
- ignores isolated DryGround because grass cannot expand into it directly;
- scores each center with controller-owned weights for unique immediate new-grass cells and adjacent DryGround at zero, one, or two prior rain hits, with more advanced DryGround progress valued more highly;
- during the configured opening phase, multiplies only the herbivore-demand step and enemy-base proximity step by the opening-priority multiplier while preserving the normal DryGround weights and demand ceiling;
- switches at exactly ten minutes of restored simulation time to the configured expansion-phase DryGround weights and stronger enemy-base proximity step;
- counts each unique immediate new-grass cell once even when several mature sources could create it;
- collects valid adult enemy herbivores once per rain search and builds a bounded local demand map around their logical footprints;
- measures herbivore distance to the edge of the candidate rain area, applies near/middle/far demand weights, and multiplies the ecological score by a clamped controller-owned demand coefficient;
- applies a separate small multiplier that rises linearly as the complete rain area approaches the enemy-base footprint;
- still ignores young-grass growth and recovery value beyond the current DryGround hit state;
- spends energy only after a positive target is found;
- refunds the cost if the shared rain application still fails.

The persistent orange contour shows the current search boundary. A blue outline shows the latest successful rain area for its configured diagnostic duration. That duration uses real time but pauses with the in-game menu.

F5 displays compact read-only enemy-AI and rain diagnostics, including the selected new-grass, DryGround buckets, nearby-herbivore demand, herd multiplier, base distance/proximity multiplier, and total-score breakdown. F8 can record performance samples including search workload, prediction versus actual new grass, selected DryGround value, demand multiplier, total target score, and application timing.

### Enemy rally objectives

The enemy has persistent attack objectives for tyrannosaurus, pterodactyl, and egg eater at the player base, plus a raptor guard objective at the enemy base.

They:

- accept only explicitly enemy-owned creatures using matching enemy resources;
- reuse shared player-flag routing and target-allocation plumbing;
- remain lower priority than autonomous survival and combat;
- are rebuilt from the runtime faction-base positions on new game and load;
- are not serialized.

AI production limits only purchased egg-eater eggs. Natural enemy egg-eater reproduction remains unrestricted.

## Player flags

The player has one independent species flag for each current species.

Player flags are soft, non-blocking movement preferences:

- only matching player-faction creatures are eligible;
- hunger, eating, reproduction, hunting, combat, and death remain higher priority;
- herbivores prefer useful grass destinations; other species use valid free destinations;
- target reservations prevent creatures from repeatedly choosing the same footprint;
- route work is batched and bounded;
- long flag routes ignore temporary creature occupancy while still respecting terrain, DryGround, eggs, and faction bases;
- when the next real step is occupied, the movement controller first tries a short rejoin around the obstruction and then a full alternate route to the same target;
- if no alternate route currently exists, the destination and queued route remain intact until the blocking footprint changes, after which movement retries without waiting for the flag assignment cycle;
- temporary higher-priority behaviour pauses a committed flag route rather than discarding it;
- entering the area completes the current placement revision, except for the persistent raptor guard assignment;
- player and enemy raptors keep ordinary wandering within eight tile steps of their guard flag; active hunt chains may leave the leash, and an idle raptor outside it receives a return route;
- moving a species flag creates a new revision and makes that species eligible again;
- active flag revisions and per-creature completion are saved.

Enemy and neutral creatures ignore player flags.

## Match end

The match-end controller tracks simulation time independently of real time. During the first two simulation minutes elimination checks are disabled, so a fresh session cannot end before either side has created its opening population. Pausing the simulation also pauses this grace period, while faster simulation speeds advance it proportionally.

After the grace period:

- the player wins when the enemy has no living creatures and no eggs;
- the player loses when the player faction has no living creatures and no eggs;
- corpses, queued-for-deletion entities, neutral creatures, energy, and faction bases do not keep a side alive.

A finished match sets simulation speed to zero and shows a full-screen result overlay with a victory or defeat heading, one short result message, the total simulation-time duration, and a single `В главное меню` button. There is no draw result and no continue-observing option.

Match elapsed time and any already-finished result are saved. Older saves without match-end data reuse the persisted enemy-AI simulation clock instead of receiving a new two-minute grace period.

## UI and diagnostics

The gameplay UI is split into dedicated scenes:

- `player_hud.tscn`;
- `creature_info_panel.tscn`;
- `nature_menu.tscn`;
- `game_result_overlay.tscn`.

Dynamic save, flag, egg, and time-control menus resolve the nature panel through the stable `player_nature_ui` group API rather than deep scene paths.

The HUD provides:

- player and enemy creature/egg counters;
- minimap;
- player energy and nature controls;
- time controls;
- base-focus buttons;
- creature information and selection.

The minimap is generated from the active terrain, overlays current grass presence as muted salad-green cells on a one-simulation-second cadence, paints both faction-base footprints red, and draws faction/diet creature markers plus the current camera view. It does not require a manually maintained map image.

Debug systems remain separate:

- F3 — world grid, paths, occupancy, and selected-creature flag information;
- F4 — general text diagnostics;
- F5 — enemy strategic AI, combat reserve, and enemy rain diagnostics;
- F8 — performance CSV recording.

Debug UI reads public state but must not make strategic decisions or mutate simulation state.

## Audio

`AudioManager` is the single global owner of music, one-shot world sounds, UI clicks, audio-bus setup, and persistent Music/Sounds settings.

Gameplay music and one-shot effects continue independently of simulation speed. Opening the in-game menu does not interrupt music or audio fades.

Audio settings are stored in `user://audio_settings.cfg`, independently from gameplay save slots.

## Startup, menu, and saving

`project.godot` starts `scenes/ui/start_screen.tscn`.

The startup screen provides New Game, Continue, autosave plus three-slot Load, Settings, and Exit. Continue sits directly below New Game, loads the newest valid timestamp across autosave and all manual slots, prefers autosave on equal-second ties, and remains visible but disabled when no valid save exists. The five-button main panel is shifted 150 pixels below screen centre and uses the supplied 720x840 `start_menu_frame.png` at a fixed 370x432 display size. Main buttons are 260x50, centred with 10-pixel separation and shifted down inside the frame, leaving both side ornaments untouched and reducing excess clearance above the lower emblem. Startup buttons and headings use Philosopher Bold; secondary labels use Philosopher Regular. The empty status label remains hidden in the main state. The in-game `MENU` button provides Save, autosave plus three-slot Load, Settings, Main Menu, Close Game, and Back.

Player-facing menus and HUD use Godot translations from `localization/ui.csv` for `ru`, `en`, `fr`, `de`, and `uk`. Russian is the first-run default; `LocalizationManager` persists the selection in `user://dyna_locale.cfg`, and both startup and in-game Settings place the language selector before audio controls. Open UI refreshes after locale changes. Developer-only F3-F8 overlays, AI diagnostics, and internal debug status text remain outside localization.

Empty manual entries are labelled `Слот 1` through `Слот 3`. Occupied manual entries show only the saved map and save time in the form `М1 - ДД.ММ ЧЧ:ММ`; their slot label is omitted. The separate autosave uses the compact form `Автосохр. - М1 - ДД.ММ ЧЧ:ММ`. Save/load button fonts shrink within an approved range when needed to keep their text inside the fixed menu width. Older saves without a stored UTC offset use the current system timezone.

Opening the in-game menu pauses simulation. Closing it restores the previously selected simulation speed.

One protected autosave is written every five simulation minutes during an active match. Speed controls advance this cadence proportionally; an open menu, loading, pause, or finished match suspends it. Loading resets the five-minute timer. The autosave uses its own file and never replaces the three manual slots.

Saved dynamic state includes:

- creatures and their mutable state;
- grass stages and timers;
- eggs, species data, blockers, and faction;
- player and enemy energy;
- player flag placements/revisions and per-creature completion;
- enemy strategic timing state plus combat-reserve amount, capacity, and capacity schedule;
- match elapsed simulation time and result state;
- DryGround cleared cells and partial rain progress;
- camera state;
- simulation speed;
- save timestamp and the computer UTC offset used for its local-time label.

Static terrain, the two faction bases, derived enemy population snapshots, enemy rally-objective positions, temporary rain diagnostics, and corpses are not serialized.

Manual and automatic save writes validate a temporary JSON file before replacing their live file and retain backup recovery. Invalid entries remain visible but cannot be loaded.

Returning to Main Menu unloads the active session without deleting save files. Starting New Game afterwards creates a clean session.

## Current limitations

Not implemented yet:

- final enemy-specific creature animations;
- additional enemy spells beyond lightning, earthquake, and rain;
- dynamic enemy attack planning and base damage;
- dynamic enemy rally placement;
- minimap markers for eggs and world events.

## Change-safety reference

Exact paths and ownership are indexed in `docs/project-map.md`.

Cross-file invariants, stable groups/APIs, loading order, save compatibility, and rules that must survive refactoring are maintained in `docs/dependencies.md`. Do not treat this document alone as sufficient preparation for code changes.
