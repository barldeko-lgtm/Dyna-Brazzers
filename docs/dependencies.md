# Dyna — Dependencies and Invariants

This document is the change-safety map for a new agent. It records ownership boundaries, runtime order, stable ids/groups/APIs, save compatibility, and rules that must survive refactoring.

Read `docs/current-state.md` and `docs/project-map.md` first.

## Documentation and source-of-truth rules

The current repository is authoritative.

Frequently tuned balance values—costs, timers, thresholds, search limits, radii, and visual durations—belong in their owning scripts or resources. Do not copy them into several documents. This file repeats only values that are stable identifiers or required compatibility contracts.

When behaviour and prose disagree, verify the implementation before editing and update the relevant working document as part of the same change.

## Global architecture rules

- Preserve the simulation-first direction and autonomous creature behaviour.
- Do not introduce direct unit control as the primary game loop.
- Keep world, creature, UI, save, audio, debug, and strategic-decision responsibilities separate.
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

1. `world.tscn` supplies the authored Ground TileMap, containers, markers, and world grid.
2. `start_map_layout.gd` preserves authored level 1 or builds the selected pixel-map level before grid initialization.
3. The world grid initializes terrain, grass lookup, occupancy, blockers, and pathfinding.
4. `start_map_world_grid.gd` places the player base, enemy base, energy nodes, enemy controllers, and enemy rally objectives.
5. The camera reads authored bounds and the start marker.

Stable terrain source ids:

- `0` — ground;
- `1` — water;
- `2` — mountain;
- `3` — tree.

Rules:

- never clear or rebuild the authored level-1 map during startup;
- a registered pixel-map level may replace runtime Ground/DryGround only before world-grid initialization;
- pixel-map colors are exact; unknown colors must fail with pixel coordinates rather than default to ground;
- base and tree markers must form complete 2x2 blocks; the left base marker belongs to the player;
- never hand-generate or replace serialized `tile_map_data`;
- preserve terrain source ids unless a deliberate migration updates every dependent system;
- keep authored grass, egg/creature containers, camera marker, and base spawn regions on valid terrain;
- faction bases are runtime blockers, not terrain sources;
- runtime fallback placement may inspect existing terrain but must never rewrite it;
- map layout/schema changes may require new saves or migration logic;
- camera movement remains real-time and must not be multiplied by simulation speed;
- camera zoom limits are owned only by `camera_controller.gd` and must be normalized after loading.

`world_grid.gd` owns terrain queries, DryGround state, grass registry, walkability, pathfinding, creature/blocker occupancy, next-step reservations, footprint placement, and edible-grass footprint queries. Other systems should use its public APIs rather than maintain competing world state.

## Faction bases

Main files:

- `res://scenes/world/player_base.tscn`
- `res://scenes/world/enemy_base.tscn`
- `res://scripts/world/faction_base.gd`
- `res://scripts/world/player_base.gd`
- `res://scripts/world/enemy_base.gd`
- `res://scripts/world/start_map_world_grid.gd`

Rules:

- create exactly one runtime `PlayerBase` and one runtime `EnemyBase`;
- both remain stationary, non-passable, and use the shared 2x2 logical footprint;
- both register through world-grid blocker APIs;
- `can_host_grass()` must reject any `faction_base` footprint;
- both are static world setup and must not join dynamic save groups;
- shared blocker, visuals, faction assignment, and nearby egg placement belong in `faction_base.gd`;
- `player_base.gd` remains a thin wrapper exposing `create_player_egg()`;
- `enemy_base.gd` remains a thin wrapper exposing `create_enemy_egg()`;
- player UI finds the player base through the `player_base` group;
- enemy strategy finds the enemy base through the `enemy_base` group;
- species data and faction must be assigned before `add_child()` starts an egg lifecycle;
- strategic decisions must not be moved into either base scene.

`CameraStart` is the player-base/start-camera anchor for a fresh game. `EnemyBaseStart` is preferred when authored; otherwise the bootstrap chooses a deterministic valid fallback without changing terrain.

## Species data, catalogs, and faction ownership

Main files:

- `res://scripts/creatures/creature_species_data.gd`
- `res://scripts/creatures/creature_faction.gd`
- `res://scripts/catalogs/player_species_catalog.gd`
- `res://scripts/catalogs/enemy_species_catalog.gd`
- player resources under `res://data/species/`
- enemy resources under `res://data/species/enemy/`

Ownership layers:

1. `CreatureSpeciesData` describes biology, diet, stats, visuals, survival, combat, and reproduction.
2. A species resource path selects the player/enemy visual and stat variant.
3. `CreatureFaction` selects runtime ownership.
4. `PlayerSpeciesCatalog` owns player-only roster/economy/flag presentation.
5. `EnemySpeciesCatalog` owns enemy resource selection and enemy economy values.
6. Strategic priorities belong to enemy controllers, not either catalog.

Stable faction ids:

- `player`
- `enemy`
- `neutral`

Rules:

- `diet_type` is the single stored diet category; use the species helper methods rather than filenames;
- player and enemy variants retain the same biological `species_id`;
- untagged current entities and old save records default to player;
- unknown non-empty faction ids normalize to neutral;
- do not introduce another faction id without reviewing save, UI, combat, energy, flags, and targeting;
- all current creatures keep the shared logical footprint; do not duplicate it in catalogs;
- living player energy uses only player-faction creatures present in `PlayerSpeciesCatalog`;
- living enemy energy uses only enemy-faction creatures present in `EnemySpeciesCatalog`;
- enemy resources select faction-specific directional sprites under `assets/sprites/creatures/enemy/<species>/` through `.tres` references; current egg textures remain shared with player resources;
- stable enemy resource paths matter once saves contain enemy creatures.

## Enemy runtime bootstrap

`start_map_world_grid.gd` must create exactly one runtime node for each active enemy subsystem:

- `EnemyAI`, registered in `enemy_ai`;
- `EnemySpellController`, registered in `enemy_spell_controller`;
- `EnemyAttackFlags`, registered through its enemy-flag facade/group contract;
- enemy energy;
- the disabled legacy egg producer retained for compatibility.

`EnemySpellController` connects to the public `EnemyAI.turn_completed` signal. Spell decisions must remain outside `enemy_ai_controller.gd`.

Enemy attack objectives must be created only after both bases exist because they derive their positions from the runtime player base.

## Enemy strategic AI

Main files:

- `res://scripts/enemies/enemy_ai_controller.gd`
- `res://scripts/enemies/enemy_energy.gd`
- `res://scripts/enemies/enemy_egg_production_controller.gd`
- `res://scripts/catalogs/enemy_species_catalog.gd`
- `res://scripts/world/enemy_base.gd`
- `res://scripts/save/save_system_with_enemy.gd`

Snapshot rules:

- scan the stable `creatures` and `eggs` groups only on the controller's strategic cadence, never every frame;
- ignore invalid, queued-for-deletion, dead, non-enemy, unsupported-species, or wrong-resource entities;
- adult creatures must match the corresponding enemy-catalog resource;
- count eggs as projected adults through `hatch_species_data.species_id`, with stored egg `species_id` only as fallback;
- store adult, egg, and projected per-species totals separately;
- normalize each adult herbivore by its own maximum hunger;
- exclude eggs and non-herbivores from the satiety average;
- rebuild the snapshot after load instead of serializing it.

Production rules:

- the controller owns population goals, hunger gating, species choice, and one production attempt;
- the current herbivore phase maintains the configured stegosaurus-heavy mix;
- the configured hunger threshold may block herbivore production;
- the combat phase first establishes two living adult raptors, one living adult tyrannosaurus, and one living adult pterodactyl;
- egg-eater production stays locked before ten simulation minutes, then enters the priority only while that living four-predator core exists and no enemy egg eater or egg-eater egg is already counted;
- any naturally reproduced enemy egg eater also blocks another AI purchase, but the AI does not cap natural reproduction;
- after all enemy egg eaters and their eggs are gone, the egg eater becomes eligible again before the long-term tyrannosaurus/pterodactyl rotation;
- do not silently substitute another species when the selected target is unaffordable or cannot be placed;
- spend energy only after `create_enemy_egg()` returns a real egg;
- failed placement costs nothing;
- save only strategic timing/progression fields needed to resume the controller, not its derived snapshot.

The old round-robin producer must remain disabled. Compatibility state may be restored into it, but restore must not restart its timer.

## Enemy spells and diagnostics

Main files:

- `res://scripts/enemies/enemy_spell_controller.gd`
- `res://scripts/world/nature_effects_system.gd`
- `res://scripts/resources/grass.gd`
- `res://scripts/debug/enemy_ai_debug_overlay.gd`
- `res://scripts/debug/performance_stats.gd`

Combat-reserve rules:

- `EnemySpellController` owns the combat-reserve amount and its time-based capacity; elapsed time may grow capacity but must never create stored reserve energy;
- capacity opens on the configured ten-minute tick, the early capacity gain applies through the 20:00 tick, the late gain starts with the 21:00 tick, and capacity remains capped at the configured maximum;
- `EnemyEnergy` remains the authority for gross creature income and diverts the configured share only when gross income meets the configured threshold and the reserve has free capacity;
- before unlock, below the income threshold, or while capacity is full, all gross creature income goes to ordinary enemy energy;
- `deposit_combat_reserve_income()` returns the amount actually accepted so `EnemyEnergy` can send every unaccepted fraction to ordinary energy without creating or losing income;
- offensive spells must require sufficient stored reserve before attempting a cast and call `spend_combat_reserve_after_success()` only after each shared effect succeeds;
- successful offensive spending may reduce stored reserve energy to zero, reduces capacity by the same exact cost, and clamps only capacity to the configured post-cast floor; failed targeting/application changes neither amount nor capacity;
- rain first uses ordinary energy when it can cover the complete cost, otherwise it may use the complete cost from stored reserve; never split one rain payment across both stores;
- reserve-funded rain subtracts the exact rain cost without applying the combat-spell post-cast floor and never changes capacity; failed application refunds the same payment source;
- save exact stored reserve, exact capacity, and the next capacity tick; old time-charged-prototype saves discard artificial stored energy and rebuild capacity only;
- F5 may read reserve, capacity, gross income, split threshold/share, and last accepted deposit through public diagnostics but must not mutate them.

Lightning target rules:

- use one strategic spell action per completed enemy turn in this order: finish an active delayed lightning sequence, egg-eater lightning, emergency rain, profitable earthquake, then weakened-tyrannosaurus lightning;
- scan only the stable `creatures` group and reject invalid, queued-for-deletion, dead, zero-health, neutral, or enemy-owned targets;
- hatched living enemy raptors are creature nodes with enemy faction and raptor species id; raptor eggs never count as adults;
- a threatening player egg eater must be inside the configured enemy-base radius and is considered only when no living enemy raptor exists anywhere;
- egg eaters reserve target priority over tyrannosauruses: if a threatening egg eater exists but stored reserve cannot fund the number of strikes needed to kill it, do not spend that reserve on a tyrannosaurus;
- an egg eater at or below one lightning hit uses one strike; a healthier egg eater is eligible only when two hits can kill it, requires two complete costs before the first strike, and receives the second strike after the configured simulation-time delay; passive regeneration during that delay must not invalidate the approved kill;
- each successful strike spends one lightning cost and reduces capacity through the common offensive-spend API; a strike that cannot be applied spends nothing;
- a player tyrannosaurus is eligible only at or below the configured health threshold, inside the configured base radius, and with no living enemy raptor inside its configured guard radius;
- rank eligible tyrannosauruses by lower health first and shorter base distance second; there is no separate lightning cooldown;
- use `NatureEffectsSystem.can_apply_lightning()` and `apply_lightning()` rather than duplicating damage, VFX, or sound logic.

Earthquake target rules:

- skip all earthquake target work until stored combat reserve can pay the complete controller-owned cost and at least two valid player eggs exist;
- scan the stable `eggs` group only on the enemy strategic cadence, reject invalid or queued-for-deletion eggs, and read faction through `CreatureFaction`;
- resolve egg species from `hatch_species_data.species_id` with stored `species_id` as fallback, then read purchase value only from `PlayerSpeciesCatalog` rather than copying a second price table;
- partition each axis by the map-clipped center ranges that can overlap every current egg footprint, including non-player eggs, and test the point nearest the enemy base inside each unchanged overlap region; do not sample random centers or scan every map tile;
- evaluate overlap with the same anchor, current footprint, and configured shared earthquake radius used by `NatureEffectsSystem`;
- require at least the configured minimum of two player eggs, reject any zone containing a non-player egg, and require summed affected player-egg value to be strictly greater than the earthquake cost;
- rank valid zones by greater total value, then more stage-two eggs, then more eggs, then shorter enemy-base distance, with tile order only as a deterministic final tie-break;
- re-collect and revalidate the selected zone immediately before calling `can_apply_earthquake()` and `apply_earthquake()`; a stale or failed zone spends nothing;
- after a successful shared earthquake, spend the complete cost through `spend_combat_reserve_after_success()` so stored energy may reach zero while capacity keeps its configured floor;
- F5 may display the last earthquake decision, selected egg count/value/stage mix, and candidate-center count but must not influence targeting.

Rain trigger and cost rules:

- enemy rain may run only from a completed AI snapshot that reports eligible adult enemy herbivores below the configured satiety threshold;
- check full-cost affordability from ordinary energy first and reserve second before scanning the grass registry;
- keep target search and spell cost ownership in `EnemySpellController`;
- require a positive target and `can_apply_rain()` before spending;
- refund the exact cost to the same ordinary/reserve store if shared `apply_rain()` still fails.

Current target-search contract:

- resolve the search contour from the current enemy-base footprint, the controller's configured search radius, and map bounds;
- reject grass sources, relevant DryGround, and future grass cells outside the contour;
- reject centers whose complete shared rain area would cross the contour;
- preserve registered mature-grass candidates only when their spread attempt remains unused;
- use the same `can_host_grass()` and `has_grass_at_tile()` rules as real immediate spreading;
- count each unique immediately spawnable cell once even when several mature sources could create it;
- allow DryGround to create candidates and contribute score only when at least one cardinal neighbouring tile contains existing grass;
- ignore isolated DryGround because cardinal grass spreading cannot reach it directly;
- obtain partial DryGround progress through the world-grid public `get_dry_ground_rain_hit_data()` API rather than maintaining competing state;
- sum controller-owned weights for unique immediate new grass and adjacent DryGround at zero, one, or two prior rain hits; keep those tunable weights in `enemy_spell_controller.gd`;
- collect eligible adult enemy herbivore footprints once per rain search from the stable `creatures` group, using faction, enemy-catalog resource, and herbivore-diet validation;
- build only a bounded demand map around those footprints, measure distance to the edge of each candidate rain area, and use controller-owned near/middle/far weights;
- multiply the ecological base score by a clamped controller-owned herbivore-demand coefficient; candidates with no nearby herbivore demand remain valid at the configured baseline multiplier;
- multiply that result by a separate controller-owned base-proximity coefficient computed from the distance between the full rain area and the enemy-base footprint; the coefficient must remain neutral at the configured reference distance and rise only toward the base;
- still ignore young-grass growth and recovery value beyond the current DryGround hit state.

Diagnostics:

- the orange search contour and blue last-cast contour are non-blocking, non-serialized visuals;
- their drawing must not alter targeting, terrain, occupancy, or spell cost;
- the blue contour uses real elapsed time but its remaining duration pauses with the in-game menu;
- simulation speed must not shorten the diagnostic duration;
- F5 reads public `enemy_ai` data and `enemy_spell_controller.get_rain_debug_data()` only, including read-only combat-reserve fields;
- F5 may display selected immediate-grass count, DryGround hit buckets, eligible/nearby herbivore demand, herd multiplier, base distance/proximity multiplier, base score, and total target score;
- F5 must not mutate enemy state or make decisions;
- F8 may record search counts/workload, search/application timing, predicted/actual new grass, selected DryGround value, total target score, and cast rate.

## Grass lifecycle and shared rain

Main files:

- `res://scripts/resources/grass.gd`
- `res://scenes/resources/grass.tscn`
- `res://scripts/world/world_grid.gd`
- `res://scripts/world/nature_effects_system.gd`
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`

`grass.gd` is the single owner of grass timing and lifecycle behaviour. `grass.tscn` supplies nodes/textures and must not override lifecycle exports or Timer wait values.

Rules:

- use explicit script values or restored remaining time when starting grass timers;
- grass may exist only on valid normal ground, not blocked terrain, DryGround, or faction bases;
- initial grass nodes do not define an allowed-growth mask;
- mature spreading checks cardinal neighbours;
- prevent duplicate grass registration on one tile;
- position dynamically created grass at its target tile before `add_child()`;
- registration, unregistration, consumption, and edible-stage changes must refresh only overlapping pasture-cache anchors;
- nature powers must use grass lifecycle methods rather than bypassing them.

One rain cast must operate on a snapshot of valid grass nodes present before any grass `apply_rain()` call. Grass spawned during that cast must not receive the same rain again or advance beyond stage 1.

DryGround processing happens through the world grid. Clearing a cell may reset/restart adjacent mature-grass recovery, but the shared rain system remains the single owner of cast order, VFX, and successful-cast sound.

## Grazing and path ranking

Main files:

- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- `res://scripts/creatures/behaviors/creature_movement_controller.gd`
- `res://scripts/world/world_grid.gd`

Rules:

- keep one pasture cache shared by all compatible herbivores;
- partition cached pasture anchors into local sectors;
- refresh only anchors overlapping a changed grass tile;
- cache food data, not creature occupancy or movement reservations;
- validate occupancy/reservations live;
- create a bounded quality shortlist before route work;
- evaluate the shortlist through one continuing breadth-first route wave rather than independent full searches;
- rank reachable options with the same food-value-minus-route-cost formula in acquisition, comparisons, bounds, and reached-target validation;
- periodically validate the current target/route and compare alternatives without pathfinding every frame;
- preserve the uncached fallback for a future incompatible footprint;
- route replacement/clearing must go through the movement controller;
- a creature must reach a valid eating footprint before consuming grass.

## Creature movement, hunting, and indirect orders

Main files:

- `res://scripts/creatures/creature.gd`
- `res://scripts/creatures/behaviors/creature_movement_controller.gd`
- `res://scripts/creatures/behaviors/creature_predator_logic.gd`
- `res://scripts/creatures/behaviors/creature_grazing_logic.gd`
- flag assignment services

Rules:

- `creature.gd` remains the external public facade for route/state transitions;
- `creature_movement_controller.gd` owns every queued-route mutation and grid-step execution;
- reserve the next footprint atomically before smooth movement;
- build long indirect-order routes against terrain and persistent blockers rather than temporary creature occupancy or movement reservations;
- when the next footprint of a managed indirect or behaviour route is occupied, first try a bounded local path that rejoins the existing route, then a bounded full path to the same final destination;
- if both rebuilds fail, retain the destination and queued route while the blocking footprint is unchanged; retry as soon as its occupancy signature changes, without a fixed retry timer or failure limit;
- ordinary one-step wandering is not a persistent managed route and may still be discarded when its chosen step becomes unavailable;
- arrival converts a reservation into normal occupancy;
- cancellation, failure, death, and removal release reservations;
- autonomous behaviour and flag code must use movement-controller/creature public APIs rather than mutate `current_path` or FSM fields;
- replacing queued behaviour must not interrupt an already active smooth grid step;
- survival, food, reproduction, hunting, combat, and death outrank indirect orders;
- enemy creatures reuse the same autonomous FSM and movement controller.

Predator rules:

- compare a small nearest available prey set by actual reachable approach routes;
- valid approaches overlap a footprint side; full corner-only diagonals remain invalid;
- predator role, normal hunger threshold, optional strategic-hunt threshold, strategic-hunt radius/flag precedence, normal hunt radius, and optional defender guard radius belong to `CreatureSpeciesData` resources;
- attacker-role strategic hunting accepts herbivores, predators, and egg eaters of the opposing player/enemy faction; when the species resource enables flag override, an acquired strategic target replaces indirect flag travel while reproduction eligibility remains higher priority;
- attacker-role survival hunting may cross faction and diet boundaries but must always reject the same biological species of the hunter's own faction;
- defender guard hunting repeatedly scans only its guard radius for opposing player/enemy creatures and outranks indirect flag routes and eligibility to begin reproduction once a target is found; an egg laying already in progress remains uninterrupted;
- defender survival hunting uses the normal predator radius, accepts herbivores regardless of faction, and rejects same-faction predators and egg eaters;
- egg eaters in strategic mode continue an indirect flag route until an opposing-faction egg is acquired, then the target overrides the flag;
- egg eaters at the normal hunger threshold suspend the flag even without a target and accept all eggs except the same species of their own faction;
- apply egg-eater faction rules during both acquisition and target revalidation, and reject eggs queued for deletion;
- shortlist at most three egg targets by cheap distance, then select by real reachable route across all valid side approaches;
- stage-one eggs are trackable but not edible; waiting footprints must preserve both possible stage-two expansions and repath after the transition;
- apply the active mode's prey rule consistently during acquisition, target revalidation, pending-duel settlement, and duel start;
- prey may be pursued by several hunters, but final combat engagement is exclusive;
- hunters losing engagement must release the target and search again through normal predator logic.
- a non-critical defender raptor may actively protect an allied herbivore or egg eater from an opposing-faction predator that initiated the current duel;
- attacker-role tyrannosaurus and pterodactyl must never acquire or switch targets solely for protection, but may continue pursuing and intervene against an opposing predator that was already their selected target before it attacked an allied herbivore or egg eater;
- eligible protectors approach the existing target through normal side-contact routing, and the first protector to arrive exclusively reserves that duel for intervention;
- a reserved intervention waits until the next scheduled duel hit resolves; if both original fighters remain alive, the protected herbivore or egg eater leaves combat and the protector starts a replacement one-on-one duel with the attacker;
- the replacement duel must disable further intervention so several protectors cannot replace one another against the same attacker;
- never intervene in predator-versus-predator combat, same-faction predation, an already replaced duel, or a duel that ends before the reserved handoff;
- only a predator reported as the winner of a completed duel receives the clamped satiety and health rewards; an intervention handoff reports no winner and grants no reward.

## Player flags and enemy rally objectives

Player main files:

- `res://scripts/flags/player_flag_system.gd`
- `res://scripts/flags/player_flag_system_with_catalog.gd`
- `res://scripts/flags/player_flag_ui_controller.gd`
- `res://scripts/flags/player_flag_assignment_service.gd`
- `res://scripts/flags/player_flag_target_allocator.gd`
- `res://scripts/flags/player_flag_visual.gd`
- `res://scripts/flags/raptor_guard_policy.gd`

Ownership:

- facade — placed data, scene attachment, world visual, public save/debug API;
- catalog layer — player-species validation and placement revisions;
- UI controller — menu, targeting input, preview, and user text;
- assignment service — eligibility, batching, commitments, retries, completion, and route application;
- target allocator — candidates, pasture preference, reservations, and retry rotation;
- visual — non-blocking drawing only.

Player rules:

- affect only matching player-faction catalog species;
- route work remains batched and bounded;
- temporary autonomous interruptions pause a committed route;
- entering the area completes the current placement revision, except for the persistent raptor guard assignment;
- raptor ordinary-wander candidates must stay within the shared eight-step guard leash;
- an active raptor hunt outranks guard recall; recall resumes only when no hunt target remains outside the leash;
- moving/replacing a species flag creates a new revision;
- changing one species flag must not cancel other species work;
- active revisions and per-creature completion are optional saved fields;
- old saves without completion data remain valid.

Enemy objectives:

- reuse the shared assignment/allocator and creature indirect-order API;
- specialize only faction/resource eligibility and persistent-rally semantics;
- accept only matching enemy resources for the implemented objective species;
- remain lower priority than autonomous behaviour;
- keep attack objectives at the player base and the raptor guard objective at the enemy base;
- are rebuilt from both runtime faction-base positions;
- are not saved as a second source of truth.

## Egg lifecycle and species visuals

Main files:

- `res://scenes/resources/egg.tscn`
- `res://scripts/resources/egg.gd`
- `res://scripts/creatures/creature_species_data.gd`
- `res://scripts/creatures/behaviors/creature_reproduction_logic.gd`
- `res://scripts/world/faction_base.gd`
- species resources and egg assets

Rules:

- all species/factions use the shared egg scene and lifecycle;
- incubation timing lives only in `egg.gd`;
- species resources may define egg textures and hatchling biology, never separate timing;
- generic fallback egg textures live under `assets/sprites/eggs/`; species-specific stage pairs live beside their player visuals and are selected by the resource;
- store both stage texture references in species resources when custom visuals exist;
- preserve shared scene defaults when custom textures are absent;
- faction and species data must be assigned before adding a created egg to the tree;
- natural eggs inherit the parent faction;
- base-created eggs receive the owning base faction;
- hatchlings inherit the egg faction;
- reproduction-progress capacity belongs to species data; runtime progress belongs to the creature;
- satiety controls progress accumulation, while existing health, satiety, and age gates still control laying;
- only successful egg creation resets progress, and save/load must preserve it;
- stage changes, blockers, hatching, save/load, egg-eater targeting, and earthquake destruction must not depend on which textures are assigned;
- earthquake destroys through the egg lifecycle so blockers release normally;
- do not duplicate `egg.tscn` per species or faction;
- moving egg assets requires updating every player/enemy resource that references them.

## UI ownership

Main scenes:

- `res://scenes/main/main.tscn`
- `res://scenes/ui/player_hud.tscn`
- `res://scenes/ui/creature_info_panel.tscn`
- `res://scenes/ui/nature_menu.tscn`
- `res://scenes/ui/game_result_overlay.tscn`

Stable wiring:

- `main.tscn/UI` instances `player_hud.tscn`;
- `main.tscn` renders world-space canvas items through a dedicated gameplay `SubViewport` whose width follows the live left edge of the adaptive right-side panel;
- the gameplay camera is registered in `game_camera`; camera bounds, minimap framing, save/load, targeting, and debug projections must use its gameplay-viewport API rather than the root viewport size;
- unhandled game-area clicks reach root-owned spell and flag targeting through `game_viewport_input_bridge.gd`;
- the HUD instances `CreatureStatsPanel` and `PlayerNaturePanel`;
- the active world owns `PlayerEnergy`;
- UI and SaveSystem resolve player energy through the `player_energy` group;
- dynamic nested menus resolve nature controls through the `player_nature_ui` group API.

Rules:

- keep physical HUD layout out of `main.tscn`;
- do not move counters or speed controls into `creature_stats_ui.gd`;
- keep F3, F4, F5, and F8 as separate diagnostic systems;
- debug systems may read public data but must not own simulation behaviour;
- creature selection must remain compatible with nature-power targeting;
- dead/corpse creatures must not remain selectable;
- base-focus buttons find bases through stable groups, not deep scene paths;
- time shortcuts must use `player_ui.gd`'s existing speed-application path so engine speed and button state stay synchronized;
- preserve stable root instance names used by existing diagnostics and integrations.

## Match end and result UI

Main files:

- `res://scripts/gameplay/game_end_controller.gd`
- `res://scripts/ui/game_result_overlay.gd`
- `res://scenes/ui/game_result_overlay.tscn`
- `res://scenes/main/main.tscn`
- `res://scripts/save/save_system_with_enemy.gd`

Rules:

- the match-end controller owns elapsed simulation time, the opening grace period, population checks, and the one-time transition to victory or defeat;
- check only stable `creatures` and `eggs` groups, reject invalid or queued-for-deletion nodes, reject dead creature state, and use `CreatureFaction` as ownership authority;
- a faction remains alive while at least one living creature or one egg of that faction exists; bases, energy, corpses, neutral entities, and future purchasing ability do not count;
- elimination checks remain disabled for the controller-owned opening grace period and run on a bounded interval rather than every frame;
- the grace period and displayed match duration use simulation-scaled delta, so pause stops them and speed controls advance them proportionally;
- the current implementation exposes only victory and defeat; do not invent a draw branch or continue-observing flow;
- finishing the match sets `Engine.time_scale` to zero, shows the result overlay once, and leaves only the public main-menu action available;
- the result overlay owns presentation and emits `main_menu_requested`; it must not count populations or decide the result;
- `SaveSystem` persists controller elapsed time/result through the final enemy save layer and exposes the public result-to-main-menu bridge;
- old saves without `game_end` data fall back to `enemy_ai.elapsed_simulation_seconds`, avoiding a renewed grace period after loading;
- loading active match state must resume checks only after normal entity reconstruction; loading a finished state must restore the paused result overlay.

## Creature visuals and interaction

Main files:

- `res://scripts/creatures/creature.gd`
- `res://scripts/creatures/behaviors/creature_visual_controller.gd`
- `res://scripts/creatures/behaviors/creature_interaction_controller.gd`
- `res://scripts/ui/creature_stats_ui.gd`

Rules:

- `creature.gd` owns FSM state and ordered death cleanup;
- the visual controller owns directional textures, animation playback, contour shadows, and displayed death poses;
- missing animation resources fall back to static directional textures;
- the interaction controller owns the world-space highlight and mouse bridge, not UI selection state;
- UI callers use the creature facade highlight methods;
- visuals and interaction must not alter survival, combat, reproduction, occupancy, or pathfinding;
- shadows and highlights never affect collision or navigation.

Death:

- release occupancy immediately;
- disable collision and picking;
- keep corpse visuals non-blocking;
- species data owns the optional death-transition texture/duration, final death texture, and corpse lifetime;
- release occupancy and disable interaction before showing either death pose;
- skip the transition delay when no transition texture is assigned;
- missing death textures may fall back to the right-facing texture;
- do not delay occupancy release until `queue_free()`.

## Audio system

Main files:

- `res://project.godot`
- `res://default_bus_layout.tres`
- `res://scripts/audio/audio_manager.gd`
- audio settings UI
- nature-effects sound call sites

Rules:

- `AudioManager` is the only global gameplay audio owner;
- keep the current bus hierarchy and route non-music player-facing volume through `Sounds`;
- music, ambient, SFX, and UI feedback use their dedicated buses;
- audio settings live in `user://audio_settings.cfg`, not gameplay save slots;
- gameplay music and fades remain active through menu pauses;
- shared short sounds use temporary players and free themselves;
- cast sounds play only after successful gameplay application;
- keep the global button click global; do not attach duplicate players/callbacks to individual scenes;
- settings UI calls `AudioManager`, not scene-local players or direct competing state.

## Startup and save system

Main files:

- `res://project.godot`
- `res://scenes/ui/start_screen.tscn`
- `res://scripts/ui/start_screen.gd`
- `res://scripts/save/save_system.gd`
- `res://scripts/save/save_system_with_flags.gd`
- `res://scripts/save/save_system_with_enemy.gd`

Startup flow:

1. `project.godot` starts `start_screen.tscn`.
2. New Game selects a registered level and opens its gameplay scene.
3. The gameplay scene instances the active world and applies its level layout.
4. Load delegates slot validation, saved-level routing, and reconstruction to `SaveSystem`.

Stable slot paths:

- `user://dyna_save_slot_1.json`
- `user://dyna_save_slot_2.json`
- `user://dyna_save_slot_3.json`

Save ownership:

- `save_system.gd` — base slot validation, temporary-write/backup safety, and reconstruction;
- `save_system_with_flags.gd` — faction, player-flag, completion, and audio-related extensions;
- `save_system_with_enemy.gd` — enemy energy, combat-reserve amount/capacity state, strategic/legacy enemy state, and match-end timing/result state.

Loading order:

1. validate the slot before changing the active scene;
2. resolve the saved level id and activate its registered gameplay scene;
3. pause reconstruction;
4. clear dynamic creature, egg, and grass nodes;
5. restore DryGround deltas;
6. restore grass and timer state;
7. restore eggs and blockers;
8. restore creatures and mutable stats from exact resource paths;
9. preserve already spawned static faction bases;
10. restore energies, camera, and simulation speed;
11. reapply factions and player flag state;
12. restore enemy strategic timing/legacy compatibility state, then restore combat-reserve capacity/amount against that clock;
13. restore match-end elapsed time/result state after entity reconstruction;
14. leave the legacy producer disabled and rebuild derived snapshots/objectives from runtime state.

Rules:

- save writes must validate a temporary JSON before replacing the live slot and retain recoverable backup state;
- invalid slots remain visible but cannot be loaded;
- missing optional faction/flag/enemy/combat-reserve/match-end fields must not invalidate old saves;
- slot labels derive `М1`/`М2` from `level_id`; new saves store `saved_at_utc_offset_minutes` so their timestamp remains in the originating computer-local time, while old saves fall back to the current system UTC offset;
- missing `level_id` defaults to level 1; an unavailable saved level must fail before scene replacement;
- missing faction defaults to player; unknown non-empty faction becomes neutral;
- static terrain and faction bases are not dynamic save entities;
- temporary corpses and rain diagnostic contours are not saved;
- enemy population snapshots and enemy rally-objective positions are derived and rebuilt;
- returning to Main Menu must not delete slots and must allow a clean New Game;
- changing map layout, schema, or persisted resource paths may require migration.

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

Trees are terrain. Species and factions are data/resource variants over shared scenes and systems.
