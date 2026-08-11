# Dyna — Dependencies and Invariants

This document is the change-safety map for a new agent. It records ownership boundaries, runtime order, stable ids/groups/APIs, save compatibility, and rules that must survive refactoring.

Read `docs/current-state.md` and `docs/project-map.md` first.

## Documentation and source-of-truth rules

The current repository is authoritative.

Frequently tuned balance values—costs, timers, thresholds, search limits, radii, weights, visual durations, and current per-species animation coverage—belong in their owning scripts/resources. Do not duplicate them across documentation.

When behaviour and prose disagree, verify the implementation before editing and update the relevant working document as part of the same change.

`docs/display-settings.md` is a compatibility pointer, not a fourth source of truth.

## Global architecture rules

- Preserve the simulation-first direction and autonomous creature behaviour.
- Do not introduce direct unit control as the primary game loop.
- Keep world, creature, UI, save, settings, audio, debug, and strategic-decision responsibilities separate.
- Reuse common player/enemy biological systems; do not create enemy-only copies of creature, egg, movement, survival, combat, or world logic.
- Keep `scenes/main/main.tscn` as a small compositor.
- Do not edit `docs/design_roadmap.md` unless explicitly requested.

## World bootstrap and terrain

Main files:

- `res://scenes/world/world.tscn`
- `res://scripts/world/world_grid.gd`
- `res://scripts/world/start_map_layout.gd`
- `res://scripts/world/pixel_map_parser.gd`
- `res://scripts/world/start_map_world_grid.gd`
- `res://scripts/camera/camera_controller.gd`

Runtime order:

1. `world.tscn` supplies authored terrain, containers, markers, and world grid.
2. `start_map_layout.gd` preserves level 1 or builds the selected registered pixel-map layout before grid initialization.
3. `world_grid.gd` initializes terrain state, grass lookup, occupancy, blockers, and pathfinding.
4. `start_map_world_grid.gd` creates faction bases, energy nodes, enemy runtime controllers, and enemy rally objectives.
5. The camera reads the resulting authored/runtime bounds and start marker.

Stable terrain source ids:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

Rules:

- never clear/rebuild the authored level-1 map during startup;
- a registered pixel-map level may replace runtime Ground/DryGround only before world-grid initialization;
- pixel-map colors are exact; unknown colors must fail visibly rather than default to ground;
- base/tree markers must form complete 2x2 blocks;
- never hand-generate or replace serialized `tile_map_data`;
- changing stable terrain source ids requires a deliberate migration of every dependent system;
- faction bases are runtime blockers, not terrain sources;
- static fallback placement may inspect terrain but must not rewrite it;
- camera movement remains real-time and camera zoom limits remain owned only by `camera_controller.gd`.

`world_grid.gd` is the authority for terrain queries, DryGround state, grass registry, walkability, species-aware traversal, ground placement, pathfinding, blockers, creature occupancy, movement reservations, and footprint APIs. Other systems must not maintain competing world state.

Pterodactyl flight is a traversal capability, not another placement layer. Flight routes may cross water, trees, and DryGround but not mountains. Goals, idle anchors, reproduction, and combat approaches still require normal ground placement.

## Faction bases and base-created eggs

Main files:

- `res://scenes/world/player_base.tscn`
- `res://scenes/world/enemy_base.tscn`
- `res://scripts/world/faction_base.gd`
- `res://scripts/world/player_base.gd`
- `res://scripts/world/enemy_base.gd`
- `res://scenes/effects/base_egg_launch_effect.tscn`
- `res://scripts/effects/base_egg_launch_effect.gd`

Rules:

- create exactly one runtime player base and one runtime enemy base;
- both remain stationary, non-passable, shared-footprint world blockers and reject grass;
- bases are never destructible, receive no health/damage system, and do not determine match results;
- both are static world setup and never dynamic save entities;
- shared blocker/placement/launch plumbing belongs in `faction_base.gd`;
- `player_base.gd` and `enemy_base.gd` remain thin public wrappers;
- a base-created real egg must reserve its final anchor and enter the normal `eggs` group before purchase energy is committed;
- species data and faction must be assigned before the real egg enters the scene tree;
- the base launch projectile is visual-only: never a blocker, save entity, population entity, egg-eater target, or earthquake target;
- the real egg's base-landing gate delays incubation and gameplay targeting until landing;
- the launch uses simulation-scaled time, so speed controls accelerate it and pause stops it;
- saving during flight serializes only the real egg; loading restores it already landed rather than restoring a temporary projectile;
- natural reproduction bypasses the base-launch gate;
- strategic decisions must not move into either base scene.

`CameraStart` anchors the player base/start camera on a fresh game. `EnemyBaseStart` is preferred for the enemy base when authored; fallback placement must remain deterministic and non-destructive.

## Species data, catalogs, faction, and animation data

Main files:

- `res://scripts/creatures/creature_species_data.gd`
- `res://scripts/creatures/creature_faction.gd`
- `res://scripts/catalogs/player_species_catalog.gd`
- `res://scripts/catalogs/enemy_species_catalog.gd`
- species resources under `res://data/species/`
- enemy resources under `res://data/species/enemy/`
- optional animation resources under `res://data/animations/`

Ownership:

1. `CreatureSpeciesData` describes biology, diet, stats, navigation capability, visuals, combat, survival, and reproduction.
2. The resource path selects the player/enemy visual/stat variant.
3. `CreatureFaction` selects runtime ownership.
4. `PlayerSpeciesCatalog` owns player roster/economy/flag presentation.
5. `EnemySpeciesCatalog` owns enemy resource selection/economy.
6. Strategic priorities belong to enemy controllers.

Stable faction ids:

- `player`
- `enemy`
- `neutral`

Rules:

- player and enemy variants retain the same biological `species_id`;
- `diet_type` is the stored diet category; use helpers rather than asset/file naming;
- untagged current entities and old save records default to player;
- unknown non-empty faction ids normalize to neutral;
- a new faction id requires review of save, UI, combat, energy, flags, and targeting;
- all current creatures use the shared logical footprint;
- player/enemy energy counts only living faction creatures supported by the corresponding catalog;
- stable resource paths matter once saves reference them;
- optional idle/walk/eat/attack/death animation resources are species data; missing resources must fall back through the shared visual controller;
- do not duplicate current animation coverage in documentation or hard-code it from species names.

## Grass lifecycle and shared nature effects

Main files:

- `res://scripts/resources/grass.gd`
- `res://scenes/resources/grass.tscn`
- `res://scripts/world/world_grid.gd`
- `res://scripts/world/nature_effects_system.gd`
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`

Rules:

- `grass.gd` owns lifecycle timing/food/spread; the scene supplies structure/textures;
- grass exists only on valid normal ground, never blocked terrain, DryGround, or faction bases;
- initial grass nodes are seeds, not a growth mask;
- prevent duplicate grass registration;
- position dynamically created grass before `add_child()`;
- grass registry/edibility changes refresh only overlapping pasture-cache anchors;
- nature powers call grass/world lifecycle APIs rather than directly mutating competing state;
- one rain cast uses a pre-cast grass snapshot so newly spawned grass cannot receive the same cast again;
- DryGround progress lives in the world grid;
- `NatureEffectsSystem` owns actual lightning/rain/sun/earthquake application, cast ordering, VFX, and successful-cast sounds.

## Grazing, movement, hunting, and combat

Main files:

- `res://scripts/creatures/creature.gd`
- `res://scripts/creatures/behaviors/creature_movement_controller.gd`
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/creatures/behaviors/creature_egg_eater_logic.gd`
- `res://scripts/combat/duel.gd`
- `res://scripts/world/world_grid.gd`

Shared movement rules:

- `creature.gd` remains the public state/route facade;
- `creature_movement_controller.gd` owns queued-route mutation and grid-step execution;
- reserve the next footprint atomically before visual movement and convert it to normal occupancy on arrival;
- cancellation, failure, death, and removal release reservations;
- long indirect routes plan against terrain/persistent blockers, not temporary creature occupancy;
- temporary indirect-route blockage first attempts shared rerouting while preserving the strategic destination;
- if rerouting fails, keep the commitment while the relevant blockage remains transient and retry through movement-controller logic;
- ordinary one-step wandering is not a persistent strategic route;
- replacing queued behaviour must not interrupt an active smooth grid step;
- autonomous survival, food, reproduction, hunting, combat, and death outrank indirect orders;
- player and enemy creatures reuse the same movement/FSM path.

Grazing rules:

- use one pasture cache for compatible herbivores;
- cache food data, never live creature occupancy/reservations;
- update only affected cache anchors;
- create a bounded candidate set before route work;
- rank reachable food consistently using food value and route cost;
- route replacement/clearing goes through the movement controller;
- consumption requires a valid eating footprint.

Predator and egg-eater rules:

- prey/egg selection must validate real reachable side approaches rather than pure straight-line distance;
- multi-goal route search should resolve valid approaches for one target without launching independent full searches for every side;
- combat approach anchors always require normal ground placement, including for flying pterodactyls;
- predator role, hunger thresholds, strategic/guard behaviour, and hunting radii are species data;
- attacker-role and defender-role target rules must be applied consistently during acquisition and revalidation;
- strategic pterodactyl acquisition skips tyrannosauruses above 70 health before candidate ranking, while current-target revalidation and critical-hunger acquisition deliberately ignore that limit;
- defender raptor protection is allowed only for eligible allied herbivore/egg-eater versus opposing-predator duels;
- attacker-role predators never acquire/switch solely for protection;
- one protector may reserve a handoff; the replacement duel cannot recursively trigger another intervention;
- predator-versus-predator duels are not protection candidates;
- a completed duel connects both fighters to settlement so a predator winner is handled whether it initiated the duel or defended;
- a predator winner atomically inherits its own defeated opponent's anchor when both use the same footprint; the old winner footprint is released and the corpse is removed from occupancy in the same world-grid operation;
- after the lethal 64-pixel attack lunge, the winner visually advances another 64 pixels, starts a 1.5-second eating animation, and settles onto its already-transferred logical position without changing collision or pathfinding through visual offsets;
- the winner receives satiety/health once at the eating midpoint, removes the corpse at the end, then resumes autonomous behaviour from the victim's coordinates;
- intervention handoffs, null winners, and non-predator winners receive no corpse-eating reward;
- egg eaters may track stage-one eggs but consume only stage two;
- egg-eater faction/species rules must remain identical during acquisition, waiting, revalidation, and consumption;
- only one egg eater may claim a stage-two egg; claiming pauses hatching without discarding the remaining timer, and cancellation resumes it;
- egg eating keeps both logical footprints unchanged through the visual approach and timed eating phase, so saving mid-sequence remains conflict-free;
- the egg stays visible through eating, then claimant-authorized completion atomically transfers its 2x2 blocker anchor to the eater and grants satiety;
- final combat engagement remains exclusive even when several hunters pursue one prey.

## Creature visuals and interaction

Main files:

- `res://scripts/creatures/creature.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`
- `res://scripts/creatures/behaviors/creature_interaction_controller.gd`
- `res://scripts/ui/creature_stats_ui.gd`
- `res://scripts/combat/duel.gd`

Rules:

- `creature.gd` owns FSM state and ordered death cleanup;
- the visual controller owns directional textures, optional animations, visual attack lunges, shadows, and death poses;
- `Duel` owns damage/timing; visual hooks must not become gameplay timing authorities;
- animation availability is optional resource data and missing resources fall back to static directional visuals;
- visual attack movement changes only rendered body/animation/shadow state, never logical anchor, occupancy, collision, or pathfinding position;
- interaction controller owns world-space hover/highlight input bridge; UI owns selected information;
- dead/corpse creatures are non-selectable;
- world render priority keeps grass below corpse visuals and corpse visuals below living creatures;
- shadows/highlights never affect navigation or collision.

Death ordering:

- release occupancy first;
- disable collision/picking;
- lower the corpse below living creatures regardless of scene-tree insertion order;
- then show optional transition/final corpse visuals;
- corpse visuals remain non-blocking;
- a claimed duel victim remains visible through its predator winner's eating phase and is removed when that phase ends;
- do not delay occupancy release until `queue_free()`.

## Player flags and enemy rally objectives

Player main files:

- `res://scripts/flags/player_flag_system.gd`
- `res://scripts/flags/player_flag_system_with_catalog.gd`
- `res://scripts/flags/player_flag_ui_controller.gd`
- `res://scripts/flags/player_flag_assignment_service.gd`
- `res://scripts/flags/player_flag_target_allocator.gd`
- `res://scripts/flags/player_flag_visual.gd`
- `res://scripts/flags/raptor_guard_policy.gd`

Rules:

- player flags affect only matching player-faction catalog species;
- facade, UI controller, assignment service, allocator, and visual keep their current responsibility split;
- route work stays batched/bounded and uses creature/movement public APIs;
- temporary autonomous behaviour pauses a commitment instead of deleting it;
- moving one species flag creates a new revision without cancelling another species;
- raptor ordinary wandering/recall uses the shared guard policy; an active hunt outranks guard recall;
- active revisions and per-creature completion remain save-compatible optional fields.

Enemy objectives:

- reuse the shared assignment/allocator and creature indirect-order APIs;
- specialize only enemy faction/resource eligibility and persistent-rally semantics;
- remain lower priority than autonomous behaviour;
- derive attack/guard positions from runtime faction bases;
- are rebuilt rather than saved.

## Enemy runtime bootstrap and strategic AI

`start_map_world_grid.gd` must create exactly one runtime instance for each active enemy subsystem: enemy AI, enemy spell controller, enemy rally facade, enemy energy, and the disabled compatibility producer.

`EnemySpellController` listens to `EnemyAI.turn_completed`. Spell decisions remain outside `enemy_ai_controller.gd`.

Enemy objectives are created only after both bases exist because their positions depend on runtime base locations.

AI snapshot rules:

- scan stable `creatures`/`eggs` groups only on the strategic cadence;
- reject invalid/dead/wrong-faction/wrong-resource/unsupported entries;
- validate adult resources against `EnemySpeciesCatalog`;
- count eggs as projected adults using hatch species data with stored id fallback;
- keep adult, egg, and projected totals distinct;
- derive herbivore satiety only from living adult enemy herbivores;
- rebuild the snapshot after load instead of saving it.

Production rules:

- the first scheduled fresh-match cadence advances strategic timing but performs no production/spell turn;
- the controller owns population goals, hunger gating, species choice, and one purchase attempt;
- do not silently substitute another species when the selected target cannot be afforded/placed;
- spend ordinary enemy energy only after a real egg was created;
- natural reproduction is not capped by the purchase controller;
- save strategic progression/timing, not the derived population snapshot;
- the old round-robin producer stays disabled even when compatibility state is restored.

## Enemy spells, reserve, and diagnostics

Main files:

- `res://scripts/enemies/enemy_spell_controller.gd`
- `res://scripts/enemies/spells/enemy_lightning_spell.gd`
- `res://scripts/enemies/spells/enemy_earthquake_spell.gd`
- `res://scripts/enemies/spells/enemy_rain_spell.gd`
- `res://scripts/enemies/enemy_energy.gd`
- `res://scripts/world/nature_effects_system.gd`
- `res://scripts/debug/enemy_ai_debug_overlay.gd`
- `res://scripts/debug/performance_stats.gd`

Module boundaries:

- `EnemySpellController` is the only strategic spell facade/listener and owns strict action priority, tuning exports, reserve state/API, save compatibility, runtime references, and merged public diagnostics;
- lightning/earthquake/rain child modules own only their spell-specific targeting/execution/diagnostics and never subscribe independently to the AI cadence;
- `NatureEffectsSystem` owns actual world effects.

Combat reserve:

- time may increase capacity but never creates stored reserve energy;
- stored reserve comes only from eligible enemy creature income through `EnemyEnergy`;
- `EnemyEnergy` must account for all accepted/unaccepted reserve income without creating or losing energy;
- offensive spells require full stored cost and spend only after successful application;
- failed target/application changes neither stored reserve nor capacity;
- rain pays one full cast from ordinary energy first or reserve second; never split one cast across both;
- reserve-funded rain changes stored reserve only, not offensive post-cast capacity rules;
- save exact stored amount, capacity, and capacity schedule;
- compatibility loading from the old time-charged prototype may rebuild capacity but must not restore artificial stored energy.

Spell targeting contracts:

- preserve the controller's one-action strategic priority, including completion of an active delayed lightning sequence before another strategic action;
- lightning validates living player targets from stable creature state and preserves egg-eater priority over opportunistic tyrannosaurus spending;
- lightning kill planning reads the actual per-strike damage from `NatureEffectsSystem`; the enemy controller must not keep a duplicate damage threshold;
- delayed two-strike lightning must reserve/validate its approved kill plan without wall-time dependence and spend each successful strike separately;
- earthquake scans valid landed player eggs, derives their values from `PlayerSpeciesCatalog`, rejects contaminated/non-profitable zones, revalidates before application, and spends only after success;
- rain checks complete affordability before target work, keeps target scoring in `EnemyRainSpell`, uses world/grass public APIs including DryGround progress, and refunds the same store if application fails;
- rain search/scoring may use restored simulation time for strategic phases but must not create parallel grass/DryGround state.

Diagnostics:

- F5 reads public strategy/spell data only and never mutates state;
- rain contours are visual-only, non-blocking, and non-serialized;
- diagnostic contour lifetime uses real elapsed time but pauses with the in-game menu;
- F8 records performance data but never influences decisions.

## UI ownership and display settings

Main files:

- `res://scenes/main/main.tscn`
- `res://scenes/ui/player_hud.tscn`
- `res://scenes/ui/creature_info_card.tscn`
- `res://scenes/ui/creature_info_panel.tscn`
- `res://scenes/ui/nature_menu.tscn`
- `res://scripts/main/main.gd`
- `res://scripts/main/game_viewport_input_bridge.gd`
- `res://scripts/ui/player_nature_ui.gd`
- `res://scripts/settings/display_settings.gd`
- `res://scripts/ui/in_game_system_menu.gd`
- `res://scripts/ui/button_text_fitter.gd`
- `res://localization/display_settings.csv`

Stable wiring:

- `main.tscn/UI` instances `player_hud.tscn`;
- world canvas renders through the dedicated gameplay SubViewport whose width follows the live left edge of the side panel;
- gameplay camera consumers use the gameplay-viewport API rather than assuming root viewport dimensions;
- root-owned spell/flag clicks pass through `game_viewport_input_bridge.gd`;
- nested menus resolve nature/system controls through the `player_nature_ui` group/API;
- `creature_info_card.tscn` owns one card's visual composition, while `creature_info_panel.tscn` owns the primary selected/hover card and the right-side hover comparison instance;
- creature hover-exit wiring passes the originating creature so a stale exit cannot clear a newer hovered target;
- base focus resolves bases through stable groups;
- debug overlays remain separate from player-facing UI.

Display ownership:

- `DisplaySettings` is the single owner of window/fullscreen state, supported window resolution, content scaling/aspect behaviour, and `user://display_settings.cfg`;
- first-run display state is windowed `1366×768`;
- supported window preferences remain `1366×768`, `1600×900`, and `1920×1080` unless deliberately changed together with UI/testing expectations;
- fullscreen uses the current monitor size and non-16:9 fullscreen must preserve the game's 16:9 content aspect rather than stretch it;
- returning to windowed mode restores a decorated window and selected preference;
- if the selected client size plus operating-system decorations cannot fit the usable desktop, fit it proportionally so title-bar/close controls remain accessible;
- resolution selection is disabled while fullscreen uses monitor size;
- free-form resizing/maximizing remains disabled while the settings list owns supported window sizes;
- display settings are independent of gameplay save slots.

The startup settings presentation is normalized by `display_settings.gd`. The in-game presentation lives in `in_game_system_menu.gd`, which only calls the owning `DisplaySettings`, `AudioManager`, and `LocalizationManager` services. Both UI layers use `button_text_fitter.gd` directly for localized button labels; SaveSystem does not own text layout.

Layout pixel offsets inside Settings/Load are implementation details and should not be copied into this document. Read the current UI code/scene before layout changes.

## Localization and audio

Localization:

- `LocalizationManager` owns runtime locale and `user://dyna_locale.cfg`;
- supported player-facing locales are `ru`, `en`, `fr`, `de`, and `uk`;
- general player-facing strings use `localization/ui.csv`;
- display-mode strings use `localization/display_settings.csv`;
- locale changes refresh open player-facing UI;
- F3-F8/internal diagnostics remain intentionally outside localization.

Audio:

- `AudioManager` is the only global audio state owner;
- preserve the current bus hierarchy and global shared music/SFX/UI paths;
- music/fades remain active through simulation pause;
- world-origin SFX use the actual gameplay SubViewport canvas transform and play only while their source projects inside its visible rectangle; music, UI, and result cues bypass this gate;
- one-shot cast sounds play only after successful gameplay application;
- audio settings live in `user://audio_settings.cfg`, not gameplay saves;
- settings UI calls `AudioManager`, not scene-local competing state.

## Match end and result UI

Main files:

- `res://scripts/gameplay/game_end_controller.gd`
- `res://scripts/tutorial/tutorial_manager.gd`
- `res://scripts/tutorial/tutorial_controller.gd`
- `res://scripts/tutorial/tutorial_spotlight.gd`
- `res://scenes/ui/tutorial_overlay.tscn`
- `res://scripts/ui/game_result_overlay.gd`
- `res://scenes/ui/game_result_overlay.tscn`
- `res://scripts/save/save_system.gd`

Rules:

- match-end controller owns elapsed simulation time, grace period, population checks, and the one-time victory/defeat transition;
- population checks use stable creature/egg groups, reject invalid/dead/queued entries, and use `CreatureFaction`;
- a faction stays alive while at least one living creature or one egg exists;
- bases, energy, corpses, neutral entities, and future purchasing ability do not count;
- grace period and match duration use simulation-scaled time;
- while a requested or active tutorial suspends the match clock, `GameEndController` must not advance grace or result-check timing; Skip or the completion plaque's sole Next action ends that suspension and the ordinary grace clock starts from zero;
- while a requested or active tutorial suspends the match clock, `EnemyAIController` must also pause its recurring timer and elapsed strategic time; no turn index, production action, or `turn_completed` spell opportunity may advance, and tutorial completion restarts the normal recurring timer from a full interval;
- step-2 tutorial spotlight holes are presentation-only and keep the full HUD blocked; interactive tutorial steps replace the full blocker with four controls surrounding exactly one permitted target, then advance from that target's real `pressed` signal instead of invoking game mechanics directly;
- the tutorial resolves minimap, population counters, energy, speed, egg-menu, and species-button targets through public UI APIs/groups rather than hard-coded main-scene paths;
- `PlayerEggCreationUI.egg_created` is emitted only after a real egg exists and its energy payment succeeds; tutorial step 5 must not begin from the species-button press alone;
- `Egg.hatched` is emitted only after the new creature is registered in the world grid; tutorial step 6 advances from that signal rather than an incubation timer guess;
- tutorial step 5 may resume simulation and allow x1/x2/x3 while `TutorialManager` keeps grace/result timing suspended; its raised panel is positioned against the projected runtime egg bounds, not fixed map coordinates;
- tutorial body text stays at 20 px across every layout; frame geometry absorbs content-length differences instead of per-step font scaling;
- step 6 advances from the real spell-menu button click after the ordinary toggle opens its submenu; step 7 resolves and spotlights the existing rain button through the public nature-UI API without invoking rain itself;
- step 8 begins only after the real rain toggle enables targeting, then invokes the existing Back-button action and opens the complete gameplay viewport so the ordinary preview follows subviewport mouse-motion events; its scoped target rule requires grass on the center tile before energy spending or world mutation, while ordinary non-tutorial rain keeps its broader validity contract;
- `PlayerNatureUI.rain_applied(center_tile)` is emitted only after target validation, successful 50-energy payment, and successful `NatureEffectsSystem.apply_rain`; tutorial completion state must use that signal rather than the button or world click;
- game-subviewport spell and flag motion/clicks use the event position delivered through `game_viewport_input_bridge.gd`, avoiding dependence on root/global mouse state when the world is rendered in a stretched `SubViewport`;
- confirmed grass-centered rain cancels targeting but keeps step 8 visible for two real-time seconds before opening step 9; the real flag-menu click opens step 10, and `PlayerFlagSystem.flag_targeting_started` confirms the Stegosaurus species choice before the raised placement phase exposes the gameplay viewport;
- `PlayerFlagSystem.flag_placed(species_id, tile)` is emitted only after ordinary flag validation and state update; only a confirmed Stegosaurus placement opens the unnumbered completion plaque, which keeps simulation paused, hides Skip, and exposes one Next action that hands control to normal x1 gameplay;
- current result types are victory/defeat only;
- finishing sets simulation speed to zero and displays the result once;
- result overlay owns presentation and emits its public main-menu action; it does not decide populations;
- save/load restores elapsed time/result after entity reconstruction;
- old saves without match-end data use the compatible enemy-AI simulation clock fallback.

## Startup and save system

Main files:

- `res://project.godot`
- `res://scenes/ui/start_screen.tscn`
- `res://scripts/ui/start_screen.gd`
- `res://scripts/save/save_system.gd`
- `res://scripts/save/save_storage.gd`
- `res://scripts/save/world_save_codec.gd`
- `res://scripts/ui/in_game_system_menu.gd`

Startup flow:

1. `project.godot` starts `start_screen.tscn`.
2. Continue chooses the newest valid autosave/manual candidate.
3. New Game selects a registered level and asks whether to start the tutorial.
4. No opens gameplay normally; Yes records a cross-scene tutorial request and opens the same selected level.
5. The gameplay scene builds the selected world layout and its tutorial overlay consumes any pending request.
6. Load validates the saved level and delegates reconstruction to `SaveSystem` without requesting a tutorial.

Startup loading rules:

- New Game, Continue, autosave, and manual-slot entry from the startup screen resolve the target level before scene replacement;
- `start_screen.gd` owns the visible loading frame and threaded `PackedScene` request while the startup background remains alive;
- `SaveSystem` accepts that validated preloaded scene for the actual transition and falls back to file-based loading for existing callers;
- save reconstruction still begins only after the gameplay scene has replaced the startup screen.

Stable gameplay slot paths:

- `user://dyna_autosave.json`
- `user://dyna_save_slot_1.json`
- `user://dyna_save_slot_2.json`
- `user://dyna_save_slot_3.json`

Independent preference files:

- `user://audio_settings.cfg`
- `user://display_settings.cfg`
- `user://dyna_locale.cfg`

Save ownership:

- `save_system.gd` — active facade for autosave cadence, level routing, public save/load API, and ordered feature-state orchestration;
- `save_storage.gd` — slot paths, validated JSON I/O, temporary-write/backup safety, and newest-save selection;
- `world_save_codec.gd` — base dynamic-world collection and reconstruction;
- `in_game_system_menu.gd` — in-game Save/Load/Settings/Main Menu presentation only.

Loading order:

1. validate the slot before replacing the active scene;
2. resolve and activate the saved level;
3. pause reconstruction;
4. clear dynamic creature, egg, and grass nodes;
5. restore DryGround deltas;
6. restore grass/timers;
7. restore eggs/blockers;
8. restore creatures and mutable state from exact resource paths;
9. preserve already spawned static faction bases;
10. restore energies and camera while simulation remains paused;
11. reapply factions and player flag state;
12. restore enemy strategic/legacy timing and combat-reserve state against that clock;
13. restore match-end time/result after entity reconstruction;
14. keep the legacy producer disabled, rebuild derived snapshots/objectives from runtime state, then resume at x1.

Save rules:

- writes validate temporary JSON before replacing live files and retain recovery state;
- autosave uses the same validated write path in its separate file;
- autosave cadence uses simulation time and pauses with loading/menu/pause/finished match;
- startup/in-game load UIs expose autosave separately and never replace manual slots;
- invalid slots remain visible but cannot be loaded;
- missing optional faction/flag/enemy/reserve/match-end fields remain backward compatible;
- creature faction/flag-completion fields and egg faction fields are added while each base entity record is created, then applied from that same record before the restored node enters the scene tree; no save path may correlate a second scene-group traversal by array index or reconstructed key;
- a restored stage-two egg remains in the world only after its 2x2 blocker registration succeeds; conflicting or invalid records are skipped with a warning;
- missing `level_id` falls back according to the existing compatibility path; unavailable levels must fail before scene replacement;
- static terrain and faction bases are never dynamic save entities;
- temporary corpses, diagnostic contours, base-launch projectiles, derived enemy snapshots, and enemy rally positions are not serialized;
- display/audio/locale preference files are not gameplay save fields;
- returning to Main Menu preserves slots and a subsequent New Game creates a clean session;
- changing persisted schema/resource paths may require migration.

## Removed or obsolete paths

Do not reintroduce:

- `res://scenes/world/world_triceratops.tscn`;
- species-specific egg scenes;
- `res://scenes/resources/tree.tscn`;
- `res://scripts/resources/tree.gd`;
- `res://assets/sprites/terrain/trees/`;
- `res://assets/sprites/terrain/tree_tiles_large.png`;
- `res://data/species/predator.tres`;
- `res://assets/sprites/creatures/predator/`.

Trees are terrain. Species and factions are resource/data variants over shared scenes and systems.
