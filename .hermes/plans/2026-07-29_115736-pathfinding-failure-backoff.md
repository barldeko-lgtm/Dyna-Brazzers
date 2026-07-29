# Pathfinding Failure Backoff Implementation Plan

> **For Hermes:** Implement task-by-task with RED→GREEN probes. Do not create commits unless Sasha explicitly asks.

**Goal:** Eliminate repeated expensive failed/capped path searches by egg eaters and predators, bound movement-repath work per frame, and preserve fast selection of genuinely reachable targets.

**Architecture:** Add a detailed path-search result alongside the existing array-returning API, then give each behavior a short-lived per-target/per-approach failure cache. Expensive planning becomes incremental: at most one A* attempt per behavior update, successful routes remain stable, and cached failures expire or invalidate when route context changes. Movement-repath remains secondary and is converted from a same-frame chain into staged retries.

**Tech Stack:** Godot 4.7.1, typed GDScript, existing `WorldGrid`, `PerformanceStats`, headless runtime probes.

---

## Confirmed current behavior

- `WorldGrid.find_path()` returns only `Array[Vector2i]`; an empty array conflates blocked goal, exhausted search, capped search, and same-tile success.
- A capped search currently increments both `path_capped` and then `path_failed`; therefore current CSV percentages overlap and are not mutually exclusive.
- Egg eater reevaluates challengers every `0.5` simulation seconds, even while its current target and route remain usable.
- Egg eater can evaluate up to three eggs and multiple approach anchors synchronously.
- Predator reevaluates prey every `2.0` simulation seconds and can evaluate up to three prey plus many side anchors synchronously.
- Existing predator cooldown begins only after a complete planning failure; it does not remember which prey/side just failed.
- Movement-repath already waits for the blocker signature to change after complete failure. Its real spike risk is the same-frame chain: up to seven local searches capped at `192`, followed by a full search capped at `1800`.
- Latest full-match CSV: predator produced `48.3%` and egg eater `19.5%` of path expansions during FPS<60 samples. Egg-eater searches were about `60% failed`, `54% capped`, and `218` expanded tiles per call.

## Design rules

1. Never permanently blacklist a target or side.
2. Successful routes are never cached as failures.
3. Failure backoff uses real monotonic time (`Time.get_ticks_msec()`), so x3/x5 cannot compress several seconds of protection into a fraction of a real second.
4. A cache entry is contextual, not global: target identity + target anchor/footprint + approach anchor + hunter origin at failure.
5. Cache entries invalidate early when the target moves/changes footprint, the hunter moves materially, or the target becomes invalid.
6. Dynamic occupancy is not treated as permanent topology. Ordinary failure gets a shorter backoff than a capped expensive search.
7. At most one synchronous A* request per behavior planner update. Candidate generation may remain synchronous because it is cheap compared with path expansion.
8. No global reduction of `max_path_search_tiles`; grazing is healthy and must not be degraded.

---

### Task 1: Expose a detailed path-search outcome without breaking existing callers

**Objective:** Let optimized behaviors distinguish success, ordinary failure, blocked goal, same tile, and capped search.

**Files:**
- Modify: `scripts/world/world_grid.gd:498-559`
- Create: `tests/path_search_result_probe.gd`
- Create: `tests/path_search_result_probe.tscn`

**Step 1: RED probe**

Create deterministic cases for:

- reachable route → `status == SUCCESS`, non-empty path;
- exhausted disconnected route → `status == FAILED`;
- deliberately tiny expansion cap → `status == CAPPED`;
- occupied/invalid destination → `status == BLOCKED_GOAL`;
- start equals goal → `status == SAME_TILE`.

Verify the existing `find_path()` still returns the same array shape for old callers.

**Step 2: Minimal API**

Add a detailed method conceptually shaped as:

```gdscript
enum PathSearchStatus {
    SUCCESS,
    FAILED,
    CAPPED,
    BLOCKED_GOAL,
    SAME_TILE
}

func find_path_result(...) -> Dictionary:
    return {
        "status": PathSearchStatus.SUCCESS,
        "path": path,
        "expanded_tiles": expanded_tiles
    }
```

Keep `find_path(...) -> Array[Vector2i]` as a compatibility wrapper that calls the detailed implementation and returns only `result.path`.

Do not duplicate A* logic and do not count metrics twice.

**Step 3: Outcome metrics**

Make capped and ordinary failed outcomes distinguishable to callers. Preserve existing CSV columns during this first task; if metric exclusivity is changed, add a schema probe and document the semantic change explicitly rather than silently changing historical comparisons.

**Verification:** Run `path_search_result_probe.tscn`, existing pathfinding probes, Godot parser.

---

### Task 2: Add reusable temporary failure-entry helpers inside each behavior

**Objective:** Standardize contextual cache entries without introducing a global cache service.

**Files:**
- Modify: `scripts/creatures/behaviors/creature_egg_eater_logic.gd`
- Modify: `scripts/creatures/behaviors/creature_predator_logic.gd`
- Test through the behavior probes in Tasks 3 and 4.

**Entry data:**

```text
target instance id
target anchor
target footprint/stage
approach anchor
hunter origin anchor at failure
status: failed | capped | blocked_goal
retry_after_real_msec
```

The cache lives on the individual behavior instance; one dinosaur cannot accidentally blacklist a route for another.

**Proposed initial timings:**

| Behavior | Ordinary failed/blocked | Capped |
|---|---:|---:|
| Egg eater | 3.0 real seconds | 6.0 real seconds |
| Predator | 2.5 real seconds + jitter | 5.0 real seconds + jitter |

These are starting values for measurement, not permanent balance constants.

**Early invalidation:**

- target freed, eaten, hatched, dead, or otherwise invalid;
- target anchor changes;
- egg stage/footprint changes;
- hunter moves at least three Manhattan tiles from the failure origin;
- cooldown expires.

Do not add a world-wide navigation revision yet: current terrain topology is static during a match. Short expiry covers dynamic creature occupancy without building unused infrastructure.

---

### Task 3: Make egg-eater planning stable and incremental

**Objective:** Stop healthy-route challenger searches and prevent one failed plan from cascading through every egg and side in one tick.

**Files:**
- Modify: `scripts/creatures/behaviors/creature_egg_eater_logic.gd:4-137,277-403`
- Modify: `tests/egg_eater_retarget_probe.gd`
- Extend: `tests/egg_eater_route_planning_probe.gd`
- Create: `tests/egg_eater_path_backoff_probe.gd`
- Create: `tests/egg_eater_path_backoff_probe.tscn`

**New state machine:**

```text
NO_TARGET
  -> build cheap ranked egg/approach queue
  -> PLAN_PENDING

PLAN_PENDING
  -> process at most one non-cached approach with A*
  -> success: commit target and route -> FOLLOWING_ROUTE
  -> failed/capped: cache that side, defer remaining queue
  -> all sides for egg suppressed: cache egg context, continue with next egg later

FOLLOWING_ROUTE
  -> do not evaluate challenger eggs
  -> continue while target valid and route has movement/queued steps
  -> replan only if route is cleared/blocked, target context changes, or target vanishes
```

**Important behavior change:** Remove the half-second challenger comparison while a valid route exists. `FOOD_SEARCH_INTERVAL` remains useful for idle acquisition, but must not trigger full path comparison during healthy travel.

**One-attempt budget:** Candidate eggs and approach anchors may be ranked in one update, but only the first uncached A* attempt is executed. The remaining queue is retained for later planner service ticks. The first successful route is accepted; do not continue searching merely to prove another route is two steps shorter.

This trades tiny theoretical route optimality for bounded frame cost and stable behavior.

**RED→GREEN cases:**

1. A valid active route receives zero challenger path calls after repeated `0.5` intervals.
2. One update performs at most one A* request even with three eggs and many sides.
3. Failed side is skipped until three real seconds expire.
4. Capped side is skipped until six real seconds expire.
5. A reachable alternative egg is selected over time without retrying the cached side.
6. Moving the egg/changing stage invalidates only that egg's stale cache entries.
7. Moving the eater three tiles permits an early retry.
8. Egg deletion clears planning state safely.
9. Existing faction, hunger, stage-one, flag-hunger, and retarget behavior remains correct; update retarget expectation so a healthy committed route remains stable.

---

### Task 4: Cache predator prey+side failures and remove healthy-route retarget scans

**Objective:** Prevent repeated multi-prey/multi-side A* bursts while preserving hunting, defense, interventions, and target validity.

**Files:**
- Modify: `scripts/creatures/behaviors/creature_predator_logic.gd:5-32,193-224,645-766,996-1067`
- Extend: `tests/predator_runtime_probe.gd`
- Extend: `tests/predator_engagement_probe.gd`
- Create: `tests/predator_path_backoff_probe.gd`
- Create: `tests/predator_path_backoff_probe.tscn`

**Stable route rule:** A normal hunt target is not periodically replaced while:

- target remains valid for the current hunt mode;
- creature is moving or queued route steps remain;
- target anchor has not changed in a way that invalidates the locked approach.

The old `TARGET_RECHECK_INTERVAL := 2.0` should no longer trigger full challenger planning during a healthy route. Replanning occurs when the target becomes invalid, the route disappears before reaching the approach, the approach becomes stale, or hunt mode changes.

**Incremental planning:** Rank up to three prey cheaply, build sorted side anchors, and execute at most one uncached A* attempt per planner update. Accept the first successful approach rather than continuing to globally minimize all alternatives.

**Failure key:** Since each behavior belongs to one hunter, cache:

```text
prey instance id + prey anchor + approach anchor + hunter failure origin
```

**Deterministic jitter:** Add `0–0.5` real seconds derived from stable IDs, not RNG:

```text
jitter_msec = hash(hunter_instance_id, prey_instance_id, approach_anchor) mod 501
```

This spreads retries without changing save-state randomness or making probes flaky.

**Capped handling:** A capped result receives the longer five-second backoff. It is not declared permanently unreachable; target motion, hunter motion, or expiry allows another attempt.

**Interventions:** Preserve the urgent `INTERVENTION_RECHECK_INTERVAL`. An intervention may preempt a normal hunt, but it still obeys one A* per planner update and the contextual side cache. First intervention attempt is not delayed by jitter; jitter applies only after failure.

**RED→GREEN cases:**

1. Healthy hunt route does not create path calls after repeated two-second intervals.
2. Same prey+side failed result is skipped during backoff.
3. Capped side remains suppressed longer than ordinary failed side.
4. Different side of the same prey remains eligible.
5. Different prey remains eligible.
6. Hunter or prey movement invalidates stale entries correctly.
7. Two hunters calculate different but deterministic retry deadlines.
8. No update performs more than one predator A* request.
9. Defense, hunger, strategic targeting, duel engagement, and egg-eater intervention probes remain green.

---

### Task 5: Stage movement-repath work instead of extending a cooldown blindly

**Objective:** Bound indirect-order repair work per frame while retaining eventual route recovery.

**Files:**
- Modify: `scripts/creatures/behaviors/creature_movement_controller.gd:138-195,359-480`
- Create: `tests/movement_repath_budget_probe.gd`
- Create: `tests/movement_repath_budget_probe.tscn`

**Corrected diagnosis:** The controller already stores a blocker signature and waits when rebuilding fails. Do not add a redundant generic cooldown on top of this.

**Staged repair:**

1. When the next indirect-order tile is occupied, wait about `0.25` real seconds first; transient traffic may clear without A*.
2. If still blocked, create a pending local-rejoin queue.
3. Try at most one local rejoin anchor (`cap 192`) per update, preserving the remaining candidates.
4. If local candidates all fail, perform at most one full destination rebuild (`cap 1800`) in a later update, never in the same frame as the last local failure.
5. On complete failure, retain the current signature-based wait.
6. Permit a safety retry after roughly three real seconds even if the immediate blocker signature is unchanged, because a distant part of the route may have opened.
7. Immediately retry when the blocker signature changes.

Do not lower `INDIRECT_ORDER_REPATH_TILE_CAP` until post-change telemetry shows that the isolated full search itself still creates visible hitches.

**RED→GREEN cases:**

- transient blocker clears before any A* call;
- one update produces at most one movement-repath call;
- local candidates are tried across updates, not synchronously;
- full rebuild occurs only after local queue exhaustion and on a later update;
- unchanged signature suppresses repeated work;
- changed signature resumes planning immediately;
- successful rejoin preserves the untouched tail of the indirect route.

---

### Task 6: Add telemetry proving that backoff, not target starvation, caused the reduction

**Objective:** Make the next F8 log directly measure cache effectiveness and deferred work.

**Files:**
- Modify: `scripts/debug/performance_stats.gd:29-104,293-360`
- Create or extend a CSV schema probe under `tests/`.

Append new columns at the end of the schema to avoid shifting existing columns:

```text
egg_path_cache_skips_per_sec
egg_path_plans_deferred_per_sec
predator_path_cache_skips_per_sec
predator_path_plans_deferred_per_sec
movement_repath_deferred_per_sec
```

Do not add extra F4/F3 UI lines unless requested; these metrics belong in F8 CSV only.

Counters must be cheap: increment once when a candidate is skipped/deferred, never inside A* tile expansion.

---

### Task 7: Documentation and regression verification

**Objective:** Synchronize current behavior and prove no reachable-target regression.

**Files:**
- Modify: `docs/current-state.md`
- Modify: `docs/dependencies.md`
- Modify only if relevant: `docs/project-map.md`
- Do not modify: `docs/design_roadmap.md` unless Sasha explicitly requests it.

**Focused regression order:**

1. Path-result status probe.
2. Egg-eater backoff probe.
3. Existing egg-eater route, retarget, hunger/faction, stage-one, and flag probes.
4. Predator backoff probe.
5. Existing predator runtime, engagement, intervention, and combat probes.
6. Movement-repath budget probe.
7. Existing flag/indirect-order route probes.
8. Performance CSV schema probe.
9. Godot headless editor parser.
10. `git diff --check`.
11. `git status --short --untracked-files=all`.

No broad gameplay rebalance and no species-stat changes belong in this work.

---

## Acceptance criteria

### Deterministic probes

- Maximum one A* call per egg-eater/predator planner update.
- Maximum one movement-repath A* call per update.
- Healthy routes produce no periodic challenger A* calls.
- Failed/capped side is not retried before its deadline.
- Reachable alternative targets are still selected without waiting for the failed target's cooldown.
- Cache invalidation works for target deletion/motion/stage and meaningful hunter motion.
- All existing faction, hunger, duel, intervention, flag, and stage behavior remains green.

### Follow-up full-match F8 comparison

Compare against `perf_log_2026-07-29T11-28-25.csv`:

- egg-eater calls/sec and expanded tiles/sec, especially p95;
- egg-eater share during FPS<60 samples (current `19.5%`);
- predator expanded tiles/sec and share during FPS<60 samples (current `48.3%`);
- count and duration of FPS<60/FPS<30 streaks;
- cache-skip/deferred counters to prove work was intentionally suppressed;
- number of successful egg-eater/predator paths, ensuring optimization did not merely stop creatures from acting.

A successful result is not just fewer calls: egg eaters and predators must still acquire reachable targets promptly, while repeated identical failures disappear.

## Risks and mitigations

- **Risk: delayed reaction when a route opens.** Mitigated by short expiry and early invalidation on hunter/target movement.
- **Risk: worse target choice from accepting first reachable route.** Candidates and sides remain lower-bound sorted; probes verify accessible nearby targets are still preferred. Avoid exhaustive shortest-path comparison because that is the measured source of spikes.
- **Risk: intervention becomes sluggish.** Urgent intervention discovery stays at `0.5`; only repeated failed path attempts are delayed.
- **Risk: real-time cooldown feels different at x5.** Intentional: it protects real frame time. Successful simulation and movement still run at x5; only repeated negative proof is throttled.
- **Risk: stale cache holds Node references.** Use instance IDs/context snapshots, prune expired/invalid entries, and never retain deleted nodes strongly.
- **Risk: scope drift into global A*.** Keep `find_path()` compatibility and do not rewrite A* or lower global caps in this phase.
