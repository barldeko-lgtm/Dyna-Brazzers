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

Current animation coverage is also data-driven. The authoritative answer for whether one species currently has idle, walk, eat, attack, or death animation data is its resource under `data/species/` or `data/species/enemy/` together with `data/animations/`. Do not maintain a second per-species coverage list in documentation.

## Status

Dyna is a Godot 4.7 autonomous 2D ecosystem simulation.

Implemented foundations include:

- two selectable tile-based level layouts sharing one world scene and gameplay stack;
- one fixed player nature base and one fixed enemy base;
- six current species: stegosaurus, triceratops, tyrannosaurus, raptor, pterodactyl, and egg eater;
- shared player/enemy creature biology with separate resource variants and runtime faction ownership;
- eggs, hatching, autonomous population growth, hunger, grazing, reproduction, hunting, duels, protection interventions, death, and corpse visuals;
- player nature powers: lightning, rain, sun, and earthquake;
- player energy, enemy energy, player egg purchases, and enemy strategic egg production;
- species-specific player flags and persistent enemy rally objectives;
- enemy lightning, earthquake, and rain strategy with diagnostics;
- startup and in-game settings, three manual save slots plus autosave, global audio, minimap, HUD, debug overlays, and elimination-based victory/defeat results.

Roadmap block `0.5 — Visuals and game interface` is complete. Later creature, player-expansion, and enemy work is partially implemented. `docs/design_roadmap.md` remains the design roadmap and must not be edited unless explicitly requested.

## Design direction

The player does not directly command units. Creatures remain autonomous and the player influences conditions indirectly.

Preserve:

- simulation-first behaviour;
- autonomous survival and movement;
- indirect player and enemy objectives;
- shared biological systems for every faction;
- separation between world logic, entity logic, UI, persistence, and diagnostics.

Do not turn Dyna into a standard RTS or create enemy-only copies of common creature systems.

## World, terrain, and camera

The active world is `scenes/world/world.tscn`.

Level 1 preserves the authored TileMap. Level 2 is built at runtime from `assets/maps/level_2_map.png`, where one exact-color pixel represents one tile. The pixel-map layout defines terrain, DryGround, grass, complete 2x2 trees, and both faction-base footprints.

Water, mountains, trees, faction-base footprints, and occupied DryGround cells are unavailable to normal ground movement and grass placement.

`start_map_layout.gd` preserves level 1. For a registered pixel-map level it replaces only the runtime Ground/DryGround layout before world-grid initialization and rebuilds map-defined grass and base markers.

Trees are TileMap terrain, not separate resource nodes. Each visual tree occupies a complete blocked terrain footprint.

The observer camera:

- renders the world through a dedicated gameplay viewport ending at the live left edge of the right-side HUD;
- starts from the authored `CameraStart` marker on a fresh game;
- restores position and zoom from saves;
- supports WASD movement and mouse-wheel zoom;
- remains clamped to map bounds owned by `camera_controller.gd`;
- moves in real time independently of simulation speed.

DryGround is a world overlay rather than a terrain source. Rain records partial progress, eventually clears cells, and reopens them to normal walking and grass recovery. Cleared cells and partial progress are saved as deltas over the authored map.

## Creatures and autonomous behaviour

All current species use the shared `creature.tscn` and common behaviour modules.

`creature.gd` remains the public creature coordinator. Dedicated controllers own movement, visuals, interaction, grazing, hunting, egg eating, reproduction, and duel behaviour.

All current creatures use the shared logical footprint. Movement reserves the next footprint before visual travel so two creatures cannot commit to the same destination.

When no higher-priority behaviour or indirect objective is active, creatures alternate between short idle periods and short random walks. Survival, food, reproduction, hunting, combat, and death always outrank player flags or enemy rally objectives.

Player and enemy pterodactyls use flight traversal: routes may cross water, trees, and DryGround, while mountains remain blocked. Idle anchors, combat positions, reproduction, and final route destinations still require normal ground placement. A route interrupted over aerial-only terrain continues until the pterodactyl reaches a valid ground anchor.

Long player-flag and enemy-rally routes are planned against terrain and persistent blockers rather than temporary creature occupancy. Temporary blockages are handled by shared movement rerouting while preserving the original strategic destination when possible.

### Reproduction

All current species build persistent egg-laying progress from satiety after their minimum-age gate.

Zero satiety pauses progress, low satiety advances it more slowly, and high satiety advances it at full rate. Health, satiety, and age gates still control whether laying may begin. Progress resets only after successful egg creation and is preserved by save/load.

### Grazing

Herbivores share a cached pasture system instead of rescanning all grass for every decision.

The cache stores useful food information and local sectors, while live creature occupancy and movement reservations are checked separately. Reachable food is ranked using food value and route cost. Grass changes refresh only affected cache entries.

### Predators and egg eaters

Predators select reachable prey through shared route and duel systems. Predator role, hunger thresholds, hunting radii, strategic behaviour, and optional defender guard values belong to species data rather than hard-coded species-name branches.

Tyrannosaurus and pterodactyl use attacker-role behaviour. Raptors use defender-role behaviour and may guard their faction base. Defender raptors may also replace an allied herbivore or egg eater in an eligible duel against an opposing predator. Attacker-role predators never search for a fight solely to protect an ally, although an already selected opposing predator may still become an intervention target.

Only the eventual winner of a completed duel receives the configured satiety/health victory reward.

Egg eaters are a separate diet category. Their strategic behaviour targets opposing-faction eggs, while critical hunger broadens the allowed egg set according to shared faction/species rules. Stage-one eggs may be tracked but only stage two is edible.

### Combat, death, and visuals

`Duel` owns combat timing and damage. Visual attack animations and lunges never move the creature's logical anchor, collision, occupancy, or pathfinding position.

Species resources may provide optional directional walk, eat, duel-attack, idle, death-transition, and final death visuals. The shared visual controller plays available animation resources and falls back to static directional textures when they are absent. Both player and enemy resource variants may use animation resources; exact current coverage is defined by the resources, not by this document.

Right-facing action resources may be mirrored for the corresponding left-facing action when the shared visual controller supports that action.

Death stops normal behaviour immediately, releases world-grid occupancy, disables collision and picking, and leaves a short non-blocking corpse visual before removal. Optional transition and final corpse poses are species data.

Creature contour shadows follow static or animated visuals and never affect gameplay.

## Grass and nature powers

Grass has four stages. `scripts/resources/grass.gd` is the single owner of growth timing, mature spread timing, stage-dependent food value, consumption reset, spreading, and reactions to nature powers.

Core grass rules:

- young grass advances through stages;
- edible grass returns to the first stage when consumed;
- mature grass may spread cardinally;
- grass may occupy valid normal ground but not blocked terrain, DryGround, or faction-base footprints;
- initial grass nodes are starting seeds, not an allowed-growth mask;
- grass registration/removal and edible-stage changes refresh only affected pasture-cache entries.

One rain cast snapshots the grass present before the cast. Grass created by that same cast starts at stage 1 and is not processed again immediately.

Rain may advance grass, spread mature grass, and clear DryGround. Sun reduces or removes grass. Earthquake affects eggs but not creatures or grass. Failed player or enemy nature-power application refunds the exact energy already charged.

## Species data, catalogs, and faction ownership

Biology, resource variant, and runtime ownership are separate concepts:

- `CreatureSpeciesData` describes biological identity, diet, stats, visuals, survival, combat, navigation capability, and reproduction;
- `PlayerSpeciesCatalog` stores player roster order, egg economy, energy income, and flag presentation;
- `EnemySpeciesCatalog` selects enemy resource variants and enemy economy values;
- `CreatureFaction` stores runtime ownership as `player`, `enemy`, or `neutral`.

Player and enemy variants keep the same biological `species_id`. Their resource path selects the visual/stat variant; their faction selects ownership and system eligibility.

Enemy resources live under `data/species/enemy/` and select faction-specific assets. Player and enemy resources may independently provide optional animation data. Current egg textures remain resource-defined and may be shared where a dedicated enemy version does not exist.

Old saves without faction fields restore missing ownership as player. Unknown non-empty faction ids normalize to neutral.

Only living catalog-supported player creatures generate player energy. Only living catalog-supported enemy creatures generate enemy energy.

## Eggs and faction bases

All species and factions use the shared egg scene and lifecycle. Egg timing is defined only in `scripts/resources/egg.gd`; species resources provide visuals and hatchling biology, not incubation timing.

The shared egg scene keeps generic fallback textures under `assets/sprites/eggs/`. Species resources may select custom two-stage textures.

Faction inheritance rules:

- naturally laid eggs inherit the parent faction;
- player-base eggs are assigned `player`;
- enemy-base eggs are assigned `enemy`;
- hatchlings inherit the egg faction.

Both bases use the shared `FactionBase` foundation. Each is a fixed 2x2 blocker, rejects grass on its footprint, uses common nearby egg-placement plumbing, and is static world setup rather than a dynamic save entity.

Base purchases use a two-part launch presentation:

- the real stage-one egg immediately reserves its final anchor and counts as a real faction egg;
- a separate faction-specific visual projectile travels from the base to that anchor;
- incubation, egg-eater tracking, and earthquake eligibility begin after landing;
- simulation speed accelerates the launch and pause stops it;
- saving during flight restores the real egg as already landed rather than serializing the temporary projectile.

Natural reproduction does not use the base-launch gate.

Energy is spent only after a base successfully creates a real egg. Failed placement costs nothing.

## Enemy strategic systems

Enemy strategy is split by responsibility.

### Production AI

`enemy_ai_controller.gd` periodically builds a derived snapshot from stable creature and egg groups.

The snapshot keeps adult, egg, and projected per-species totals, validates enemy resource/faction ownership, and derives herbivore satiety from living adult enemy herbivores. It is rebuilt after load rather than serialized.

The production controller owns population goals, hunger gating, purchase priority, and one production attempt per eligible strategic cadence. The first scheduled cadence of a fresh match is intentionally a no-action turn. The current strategy builds its herbivore economy, establishes its configured combat core, later allows a limited purchased egg eater, and waits instead of silently substituting another species when the chosen purchase cannot be completed.

The disabled legacy round-robin producer remains only for old save compatibility.

### Combat-spell reserve

`enemy_spell_controller.gd` owns a separate combat reserve used by offensive spells. Match time increases reserve capacity but does not create stored energy; actual stored reserve comes from eligible enemy-creature income routed through `enemy_energy.gd`.

Successful offensive casts spend stored reserve and reduce capacity according to the controller contract. Rain remains an economic support spell and may pay its full cost from ordinary enemy energy or, when needed, from the reserve without splitting one cast across both stores.

Reserve amount, capacity, and capacity schedule are saved. Compatibility logic converts saves from the earlier time-charged prototype without preserving artificial stored energy.

### Enemy spells

`EnemySpellController` is the strategic facade and owns spell priority, reserve state, tuning, public diagnostics, and save compatibility.

Dedicated child modules own:

- lightning target selection and delayed double-strike execution;
- profitable earthquake target search over player eggs;
- rain payment orchestration, ecological target scoring, and rain diagnostics.

`NatureEffectsSystem` remains the only owner of actual world damage/changes, VFX, and successful-cast sounds.

Current strategic priority preserves emergency/priority behaviour between delayed lightning, egg-eater lightning, rain, earthquake, and weakened-tyrannosaurus lightning. Exact thresholds, radii, costs, weights, and phase timings remain code-owned tuning.

F5 exposes read-only enemy strategy/spell diagnostics. F8 can record performance samples. Debug systems never make strategic decisions.

### Enemy rally objectives

The enemy has persistent indirect objectives for its implemented attacker species at the player base and a raptor guard objective at the enemy base.

They reuse shared flag routing and target allocation, remain lower priority than autonomous behaviour, are rebuilt from runtime base positions, and are not serialized.

## Player flags

The player has one independent species flag for each current species.

Player flags are soft, non-blocking movement preferences:

- only matching player-faction creatures are eligible;
- autonomous survival/food/reproduction/combat remains higher priority;
- route work is batched and bounded;
- temporary higher-priority behaviour pauses rather than destroys a committed objective;
- moving one species flag creates a new revision without cancelling other species;
- persistent raptor guard behaviour uses the shared player/enemy guard policy;
- active player flag revisions and per-creature completion are saved.

Enemy and neutral creatures ignore player flags.

## Match end

The match-end controller tracks simulation time independently of wall time. During its opening grace period elimination checks are disabled.

After the grace period:

- the player wins when the enemy has no living creatures and no eggs;
- the player loses when the player faction has no living creatures and no eggs;
- corpses, queued-for-deletion entities, neutral creatures, energy, and faction bases do not keep a side alive.

A finished match sets simulation speed to zero and shows a full-screen victory/defeat result with match duration and a single main-menu action. There is no draw result or continue-observing mode.

Match elapsed time and an already-finished result are saved. Older saves without match-end data reuse persisted enemy-AI simulation time rather than receiving a fresh grace period.

## UI, display settings, localization, and diagnostics

The gameplay UI is split into dedicated scenes:

- `player_hud.tscn`;
- `creature_info_panel.tscn`;
- `nature_menu.tscn`;
- `game_result_overlay.tscn`.

Dynamic save, flag, egg, time-control, and system menus resolve the nature panel through the stable `player_nature_ui` API rather than deep scene paths.

The HUD provides player/enemy creature and egg counters, minimap, player energy and nature controls, time controls, base focus, and creature information.

The right-side HUD remains a fixed logical side panel made from the supplied top and bottom art while the gameplay viewport dynamically ends at its live left edge.

The minimap is generated from active terrain, shows current grass, both faction bases, creature markers, and the current camera view.

Display settings are shared by startup and in-game Settings:

- first-run default is windowed `1366×768`;
- supported window choices are `1366×768`, `1600×900`, and `1920×1080`;
- fullscreen uses the current monitor size;
- fullscreen on a non-16:9 display preserves the 16:9 game presentation with letterbox/pillarbox space rather than stretching;
- returning to windowed mode restores the selected window preference;
- when the preferred decorated window cannot fit the usable desktop, the client area is reduced proportionally so the operating-system title bar and close controls remain visible;
- free-form window resizing/maximizing is disabled; the settings list owns the supported window sizes.

`DisplaySettings` persists display state in `user://display_settings.cfg`, separately from gameplay saves. `LocalizationManager` persists locale in `user://dyna_locale.cfg`. `AudioManager` persists audio settings in `user://audio_settings.cfg`.

Player-facing UI supports `ru`, `en`, `fr`, `de`, and `uk`. General UI strings live in `localization/ui.csv`; display-mode strings live in `localization/display_settings.csv`. Russian is the first-run fallback. Startup and in-game Settings expose the same language, display, resolution, music, and sound state.

Debug systems remain separate:

- F3 — world grid, paths, occupancy, and selected-creature route/flag diagnostics;
- F4 — general text diagnostics;
- F5 — enemy strategic AI and spell diagnostics;
- F8 — performance CSV recording.

Debug UI reads public state but must not make strategic decisions or mutate simulation state.

## Audio

`AudioManager` is the single global owner of music, one-shot world sounds, UI clicks, audio-bus setup, and persistent Music/Sounds settings.

The startup menu and gameplay use separate music tracks through the shared Music bus and fade path. Music and one-shot effects continue independently of simulation speed, and opening the in-game menu does not interrupt music or fades.

Audio settings are stored independently from gameplay save slots.

## Startup, menu, and saving

`project.godot` starts `scenes/ui/start_screen.tscn`.

The startup screen provides New Game, Continue, Load, Settings, and Exit. New Game exposes the registered level list; currently available levels and disabled placeholders are defined by the startup implementation. Continue loads the newest valid candidate across autosave and manual slots.

The Load page exposes autosave, three manual slots, and Back. Startup and in-game system menus share the same save files and validated reconstruction path.

Opening the in-game menu pauses simulation. Closing it restores the previously selected simulation speed.

One protected autosave is written on its simulation-time cadence during an active match. Loading, pause/menu state, or a finished match suspends that cadence.

Saved dynamic state includes:

- creatures and mutable creature state;
- grass stages and timers;
- eggs, resource identity, blockers, and faction;
- player and enemy energy;
- player flag placements/revisions and per-creature completion;
- enemy strategic timing and combat-reserve state;
- match elapsed simulation time and result state;
- DryGround deltas and partial rain progress;
- camera state;
- simulation speed;
- save timestamp and timezone metadata used by slot labels.

Static terrain, faction bases, derived enemy snapshots, enemy rally positions, temporary diagnostics/effects, and corpses are not serialized.

Manual and automatic writes validate temporary JSON before replacing live files and retain backup recovery. Invalid entries remain visible but cannot be loaded.

Returning to Main Menu unloads the active session without deleting save files. Starting New Game afterwards creates a clean session.

## Current limitations

Not implemented yet:

- complete final animation coverage for every species, direction, and action;
- additional enemy spells beyond lightning, earthquake, and rain;
- dynamic enemy attack planning and base damage;
- dynamic enemy rally placement;
- minimap markers for eggs and world events.

## Change-safety reference

Exact paths and ownership are indexed in `docs/project-map.md`.

Cross-file invariants, stable groups/APIs, loading order, save compatibility, and rules that must survive refactoring are maintained in `docs/dependencies.md`. Do not treat this document alone as sufficient preparation for code changes.
