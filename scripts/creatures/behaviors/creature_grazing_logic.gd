extends RefCounted

const GRAZING_DISTANCE_COST_PER_TILE: float = 3.0
const GRAZING_PATH_CANDIDATE_LIMIT: int = 10
const GRAZING_FULL_RECHECK_INTERVAL: float = 5.0
const GRAZING_PATH_LIMIT_NEAR: int = 80
const GRAZING_PATH_LIMIT_MEDIUM: int = 150
const GRAZING_PATH_LIMIT_FALLBACK: int = 300
const GLOBAL_GRAZING_CANDIDATE_LIMIT: int = 32
const GRAZING_CACHE_FOOTPRINT_SIZE: Vector2i = Vector2i(2, 2)
const GRAZING_CACHE_SECTOR_SIZE: int = 8

# Shared between every herbivore in the active world. Grass nodes update only
# the four 2x2 pasture anchors touched by a stage/register/unregister change.
# The cache is split into small sectors so local searches inspect only nearby
# pasture entries rather than rebuilding anchors from the full grass registry.
static var grazing_pasture_cache_by_world: Dictionary = {}

var creature: Node
var full_recheck_timer: float = GRAZING_FULL_RECHECK_INTERVAL


func _init(owner_creature: Node) -> void:
	creature = owner_creature


# Shared 2x2 pasture cache.
static func notify_grass_changed(world_grid: Node, grass_tile: Vector2i) -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		return

	var cache: Dictionary = _get_grazing_cache(world_grid)

	for offset_y: int in range(GRAZING_CACHE_FOOTPRINT_SIZE.y):
		for offset_x: int in range(GRAZING_CACHE_FOOTPRINT_SIZE.x):
			_refresh_cached_pasture(
				world_grid,
				cache,
				grass_tile - Vector2i(offset_x, offset_y)
			)

	PerformanceStats.add_counter(
		"grazing_cache_anchor_refreshes",
		GRAZING_CACHE_FOOTPRINT_SIZE.x * GRAZING_CACHE_FOOTPRINT_SIZE.y
	)


static func _get_grazing_cache(world_grid: Node) -> Dictionary:
	var world_id: int = int(world_grid.get_instance_id())

	if grazing_pasture_cache_by_world.has(world_id):
		var existing_cache: Dictionary = grazing_pasture_cache_by_world[world_id]
		var cached_world: Variant = existing_cache.get("world", null)

		if cached_world != null and is_instance_valid(cached_world) and cached_world == world_grid:
			return existing_cache

	var new_cache: Dictionary = {
		"world": world_grid,
		"pastures": {},
		"sectors": {}
	}
	grazing_pasture_cache_by_world[world_id] = new_cache
	return new_cache


static func _refresh_cached_pasture(
	world_grid: Node,
	cache: Dictionary,
	pasture_anchor: Vector2i
) -> void:
	var bottom_right := pasture_anchor + GRAZING_CACHE_FOOTPRINT_SIZE - Vector2i.ONE

	if not world_grid.is_tile_inside_map(pasture_anchor) or not world_grid.is_tile_inside_map(
		bottom_right
):
		_remove_cached_pasture(cache, pasture_anchor)
		return

	var adult_count: int = 0
	var food_value: int = 0

	for offset_y: int in range(GRAZING_CACHE_FOOTPRINT_SIZE.y):
		for offset_x: int in range(GRAZING_CACHE_FOOTPRINT_SIZE.x):
			var tile := pasture_anchor + Vector2i(offset_x, offset_y)
			var grass: Node = world_grid.get_grass_at_tile(tile)

			if not is_instance_valid(grass):
				continue

			if not grass.has_method("can_be_eaten") or not grass.can_be_eaten():
				continue

			adult_count += 1

			if grass.has_method("get_food_value"):
				food_value += int(grass.get_food_value())
			else:
				food_value += 7

	if adult_count <= 0:
		_remove_cached_pasture(cache, pasture_anchor)
		return

	var pastures: Dictionary = cache["pastures"]
	pastures[pasture_anchor] = {
		"anchor": pasture_anchor,
		"adult_count": adult_count,
		"food_value": food_value
	}

	var sectors: Dictionary = cache["sectors"]
	var sector_key: Vector2i = _get_grazing_cache_sector(pasture_anchor)

	if not sectors.has(sector_key):
		sectors[sector_key] = {}

	var sector_entries: Dictionary = sectors[sector_key]
	sector_entries[pasture_anchor] = true


static func _remove_cached_pasture(
	cache: Dictionary,
	pasture_anchor: Vector2i
) -> void:
	var pastures: Dictionary = cache["pastures"]
	pastures.erase(pasture_anchor)
	var sectors: Dictionary = cache["sectors"]
	var sector_key: Vector2i = _get_grazing_cache_sector(pasture_anchor)

	if not sectors.has(sector_key):
		return

	var sector_entries: Dictionary = sectors[sector_key]
	sector_entries.erase(pasture_anchor)

	if sector_entries.is_empty():
		sectors.erase(sector_key)


static func _get_grazing_cache_sector(anchor: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(anchor.x) / float(GRAZING_CACHE_SECTOR_SIZE)),
		floori(float(anchor.y) / float(GRAZING_CACHE_SECTOR_SIZE))
	)


static func _collect_cached_pastures(
	world_grid: Node,
	origin_anchor: Vector2i,
	search_radius: int
) -> Array[Dictionary]:
	var cache: Dictionary = _get_grazing_cache(world_grid)
	var pastures: Dictionary = cache["pastures"]
	var collected: Array[Dictionary] = []

	if search_radius < 0:
		for pasture_data_variant: Variant in pastures.values():
			if not (pasture_data_variant is Dictionary):
				continue

			var pasture_data: Dictionary = pasture_data_variant
			collected.append(pasture_data.duplicate())

		return collected

	var start_tile := origin_anchor - Vector2i(search_radius, search_radius)
	var end_tile := origin_anchor + Vector2i(search_radius, search_radius)
	var min_sector: Vector2i = _get_grazing_cache_sector(start_tile)
	var max_sector: Vector2i = _get_grazing_cache_sector(end_tile)
	var sectors: Dictionary = cache["sectors"]

	for sector_y: int in range(min_sector.y, max_sector.y + 1):
		for sector_x: int in range(min_sector.x, max_sector.x + 1):
			var sector_key := Vector2i(sector_x, sector_y)

			if not sectors.has(sector_key):
				continue

			var sector_entries: Dictionary = sectors[sector_key]

			for pasture_anchor_variant: Variant in sector_entries.keys():
				if not (pasture_anchor_variant is Vector2i):
					continue

				var pasture_anchor: Vector2i = pasture_anchor_variant

				if pasture_anchor.x < start_tile.x or pasture_anchor.x > end_tile.x:
					continue

				if pasture_anchor.y < start_tile.y or pasture_anchor.y > end_tile.y:
					continue

				if pastures.has(pasture_anchor):
					var pasture_data: Dictionary = pastures[pasture_anchor]
					collected.append(pasture_data.duplicate())

	return collected


# Food state machine.
func update_food_behavior() -> void:
	PerformanceStats.add_counter("grazing_food_behavior_ticks")

	if creature.species_data.is_predator():
		return

	if creature.world_grid == null:
		return

	if creature.state == creature.State.EATING:
		creature.hunger = clamp(creature.hunger - creature.species_data.hunger_decay_rate * creature.get_physics_process_delta_time(), 0.0, creature.species_data.max_hunger)
		return

	if creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
		return

	if creature.is_moving:
		return

	if creature.hunger > creature.species_data.hunger_search_threshold:
		return

	if creature.state != creature.State.SEEK_FOOD:
		creature.enter_seek_food()


func update_seek_food(delta: float) -> void:
	PerformanceStats.add_counter("grazing_seek_food_ticks")
	creature.food_recheck_timer -= delta
	full_recheck_timer -= delta

	var acquired_during_route_check: bool = false

	# Every two seconds validate the already selected target and every queued
	# route step against current occupancy and reservations. This catches a path
	# blocked by another creature without launching a new search while the route
	# remains clear.
	if creature.food_recheck_timer <= 0.0:
		acquired_during_route_check = recheck_current_grazing_route()
		creature.food_recheck_timer = creature.food_recheck_interval

	# Every five seconds compare the current target with up to ten alternatives.
	# If the two-second validation already had to reacquire a target this frame,
	# do not immediately repeat the same full search.
	if full_recheck_timer <= 0.0:
		full_recheck_timer = GRAZING_FULL_RECHECK_INTERVAL

		if not acquired_during_route_check:
			recheck_grazing_target()

	if not creature.is_moving and can_start_eating_here() and (not creature.has_grazing_target or creature.anchor_tile == creature.grazing_target_anchor):
		creature.enter_eating()
		return

	if not creature.has_grazing_target:
		if not creature.is_moving and _get_queued_route_steps() == 0:
			creature.choose_random_wander_step()

		creature.start_next_path_step_if_needed()
		return

	creature.start_next_path_step_if_needed()

	if not creature.is_moving and _get_queued_route_steps() == 0 and creature.has_grazing_target:
		if creature.anchor_tile == creature.grazing_target_anchor:
			if can_start_eating_here():
				creature.enter_eating()
			else:
				_clear_grazing_target()
				try_acquire_grazing_target()
		else:
			# The queued path was exhausted or cancelled before arrival. Rebuild it
			# with the same single-wave search instead of retrying candidates one by
			# one through separate A* calls.
			build_path_to_grazing_target()


func enter_seek_food() -> void:
	creature.food_recheck_timer = creature.food_recheck_interval
	full_recheck_timer = GRAZING_FULL_RECHECK_INTERVAL
	creature.has_grazing_target = false
	creature.grazing_candidate_queue.clear()
	creature.clear_path()
	creature.change_state(creature.State.SEEK_FOOD)
	try_acquire_grazing_target()


func can_start_eating_here() -> bool:
	if creature.world_grid == null:
		return false

	return creature.world_grid.count_adult_grass_under_footprint(
		creature.anchor_tile,
		creature.footprint_size
	) >= creature.min_grass_to_eat


# Grazing target selection.
#
# A shared sector cache keeps up to ten eligible 2x2 pasture anchors. Grass
# stage/register/unregister changes refresh only the four affected anchors.
# One breadth-first path wave then starts at the herbivore and reaches all ten
# candidates through the same visited-cell map. The wave expands at most 300
# anchors total, not 300 anchors per candidate. Thresholds 80, 150 and 300
# continue the same queue without restarting work.
#
# Final score:
# total food value under the footprint - actual route steps * 3.
func try_acquire_grazing_target(include_current_target: bool = false) -> void:
	PerformanceStats.add_counter("grazing_acquire_requests")

	if creature.world_grid == null:
		return

	var best_plan: Dictionary = _find_best_grazing_plan(
		creature.nearby_grazing_recheck_radius,
		include_current_target
	)

	if best_plan.is_empty():
		best_plan = _find_best_grazing_plan(-1, include_current_target)

	_commit_grazing_plan(best_plan)
	full_recheck_timer = GRAZING_FULL_RECHECK_INTERVAL


func _find_best_grazing_plan(
	search_radius: int,
	include_current_target: bool
) -> Dictionary:
	if creature.world_grid == null:
		return {}

	var candidates: Array[Dictionary] = find_quality_ranked_grazing_candidates(
		search_radius,
		GRAZING_PATH_CANDIDATE_LIMIT
	)

	if include_current_target:
		_append_current_target_candidate(candidates)

	if candidates.is_empty():
		return {}

	var plan: Dictionary = _find_best_path_in_shared_wave(candidates)

	if plan.is_empty():
		PerformanceStats.add_counter("grazing_candidate_unreachable")

	return plan


func _append_current_target_candidate(candidates: Array[Dictionary]) -> void:
	if not is_current_grazing_target_still_valid():
		return

	for candidate: Dictionary in candidates:
		var candidate_anchor: Vector2i = candidate.get(
			"anchor",
			creature.anchor_tile
		)

		if candidate_anchor == creature.grazing_target_anchor:
			candidate["prefer_on_tie"] = true
			return

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var distance: int = creature.world_grid.estimate_path_steps(
		navigation_anchor,
		creature.grazing_target_anchor
	)
	var food_value: int = get_grazing_target_food_value(
		creature.grazing_target_anchor
	)
	var adult_count: int = get_current_grazing_target_adult_count()

	if candidates.size() >= GRAZING_PATH_CANDIDATE_LIMIT:
		candidates.pop_back()

	candidates.append({
		"anchor": creature.grazing_target_anchor,
		"adult_count": adult_count,
		"food_value": food_value,
		"distance": distance,
		"score": float(food_value) - float(distance) * GRAZING_DISTANCE_COST_PER_TILE,
		"prefer_on_tie": true
	})


func find_quality_ranked_grazing_candidates(
	search_radius: int,
	result_limit_override: int = -1
) -> Array[Dictionary]:
	if creature.world_grid == null:
		return []

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var result_limit: int = GRAZING_PATH_CANDIDATE_LIMIT

	if result_limit_override > 0:
		result_limit = result_limit_override

	result_limit = max(result_limit, 1)
	var scan_limit: int = result_limit

	if search_radius >= 0:
		# A square search with radius R contains at most (2R + 1)^2 anchors.
		# Keep the same first-stage ranking breadth as the previous grass-registry
		# scan, but source those anchors from nearby cache sectors.
		var search_diameter: int = search_radius * 2 + 1
		scan_limit = max(scan_limit, search_diameter * search_diameter)
	else:
		# Preserve the bounded global fallback shortlist before the final food-value
		# re-rank, matching the previous selection semantics.
		scan_limit = max(
			scan_limit * 8,
			GLOBAL_GRAZING_CANDIDATE_LIMIT
		)

	var raw_candidates: Array[Dictionary] = []

	if creature.footprint_size == GRAZING_CACHE_FOOTPRINT_SIZE:
		raw_candidates = _find_cached_raw_grazing_candidates(
			navigation_anchor,
			search_radius,
			scan_limit
		)
	else:
		# Current species all use 2x2 footprints. Keep the old generic world-grid
		# scan as a compatibility fallback for a future differently sized species.
		raw_candidates = creature.world_grid.find_best_grazing_targets(
			navigation_anchor,
			creature.footprint_size,
			creature.min_grass_to_eat,
			search_radius,
			creature,
			creature.grazing_grass_weight,
			creature.grazing_distance_penalty,
			scan_limit
		)

	var quality_ranked: Array[Dictionary] = []

	for raw_candidate: Dictionary in raw_candidates:
		var anchor: Vector2i = raw_candidate.get(
			"anchor",
			creature.anchor_tile
		)
		var distance: int = int(raw_candidate.get("distance", 0))
		var food_value: int = int(raw_candidate.get("food_value", -1))

		if food_value < 0:
			food_value = get_grazing_target_food_value(anchor)

		var rescored_candidate: Dictionary = raw_candidate.duplicate()
		rescored_candidate["food_value"] = food_value
		rescored_candidate["score"] = (
			float(food_value)
			- float(distance) * GRAZING_DISTANCE_COST_PER_TILE
		)
		rescored_candidate["prefer_on_tie"] = false
		_insert_quality_ranked_candidate(
			quality_ranked,
			rescored_candidate,
			result_limit
		)

	return quality_ranked


func _find_cached_raw_grazing_candidates(
	navigation_anchor: Vector2i,
	search_radius: int,
	max_results: int
) -> Array[Dictionary]:
	PerformanceStats.add_counter("grazing_searches")
	PerformanceStats.add_counter("grazing_cache_queries")
	var ranked_results: Array[Dictionary] = []
	var candidate_checks: int = 0
	var valid_footprint_checks: int = 0
	var cached_pastures: Array[Dictionary] = _collect_cached_pastures(
		creature.world_grid,
		navigation_anchor,
		search_radius
	)

	for cached_pasture: Dictionary in cached_pastures:
		candidate_checks += 1
		var adult_count: int = int(cached_pasture.get("adult_count", 0))

		if adult_count < creature.min_grass_to_eat:
			continue

		var anchor: Vector2i = cached_pasture.get(
			"anchor",
			creature.anchor_tile
		)

		# Occupancy and movement reservations are intentionally not cached. They
		# remain live per creature, so crowding behaviour is unchanged.
		if not creature.world_grid.can_place_footprint(
			anchor,
			creature.footprint_size,
			creature
		):
			continue

		valid_footprint_checks += 1
		var distance: int = creature.world_grid.estimate_path_steps(
			navigation_anchor,
			anchor
		)
		var rough_score: float = (
			float(adult_count) * float(creature.grazing_grass_weight)
			- float(distance) * float(creature.grazing_distance_penalty)
		)
		var raw_candidate: Dictionary = cached_pasture.duplicate()
		raw_candidate["distance"] = distance
		raw_candidate["score"] = rough_score
		_insert_cached_raw_candidate(
			ranked_results,
			raw_candidate,
			max_results
		)

	PerformanceStats.add_counter("grazing_candidate_checks", candidate_checks)
	PerformanceStats.add_counter(
		"grazing_valid_footprints",
		valid_footprint_checks
	)

	if ranked_results.is_empty():
		PerformanceStats.add_counter("grazing_search_misses")
	else:
		PerformanceStats.add_counter("grazing_search_hits")

	return ranked_results


func _insert_cached_raw_candidate(
	ranked_candidates: Array[Dictionary],
	candidate: Dictionary,
	max_results: int
) -> void:
	if max_results <= 0:
		return

	var insert_index: int = ranked_candidates.size()

	for index: int in range(ranked_candidates.size()):
		if _is_cached_raw_candidate_better(
			candidate,
			ranked_candidates[index]
		):
			insert_index = index
			break

	if insert_index >= max_results:
		return

	ranked_candidates.insert(insert_index, candidate)

	if ranked_candidates.size() > max_results:
		ranked_candidates.resize(max_results)


func _is_cached_raw_candidate_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	var candidate_score: float = float(candidate.get("score", -INF))
	var current_score: float = float(current_best.get("score", -INF))

	if not is_equal_approx(candidate_score, current_score):
		return candidate_score > current_score

	var candidate_distance: int = int(candidate.get("distance", 0))
	var current_distance: int = int(current_best.get("distance", 0))

	if candidate_distance != current_distance:
		return candidate_distance < current_distance

	return int(candidate.get("adult_count", 0)) > int(
		current_best.get("adult_count", 0)
	)


func _insert_quality_ranked_candidate(
	ranked_candidates: Array[Dictionary],
	candidate: Dictionary,
	max_results: int
) -> void:
	if max_results <= 0:
		return

	var insert_index: int = ranked_candidates.size()

	for index: int in range(ranked_candidates.size()):
		if is_quality_candidate_better(candidate, ranked_candidates[index]):
			insert_index = index
			break

	if insert_index >= max_results:
		return

	ranked_candidates.insert(insert_index, candidate)

	if ranked_candidates.size() > max_results:
		ranked_candidates.resize(max_results)


func is_quality_candidate_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	var candidate_score: float = float(candidate.get("score", -INF))
	var current_score: float = float(current_best.get("score", -INF))

	if not is_equal_approx(candidate_score, current_score):
		return candidate_score > current_score

	var candidate_food_value: int = int(candidate.get("food_value", 0))
	var current_food_value: int = int(current_best.get("food_value", 0))

	if candidate_food_value != current_food_value:
		return candidate_food_value > current_food_value

	var candidate_distance: int = int(candidate.get("distance", 0))
	var current_distance: int = int(current_best.get("distance", 0))

	if candidate_distance != current_distance:
		return candidate_distance < current_distance

	return int(candidate.get("adult_count", 0)) > int(
		current_best.get("adult_count", 0)
	)


# One shared breadth-first wave for every shortlisted pasture. The queue uses a
# read index rather than pop_front(), so queue removal itself stays O(1).
func _find_best_path_in_shared_wave(candidates: Array[Dictionary]) -> Dictionary:
	PerformanceStats.add_counter("path_calls")

	if creature.world_grid == null or candidates.is_empty():
		PerformanceStats.add_counter("path_failed")
		return {}

	var start_anchor: Vector2i = creature.get_navigation_anchor()
	var active_step_count: int = 1 if creature.is_moving else 0
	var unresolved_targets: Dictionary = {}

	for source_candidate: Dictionary in candidates:
		var target_anchor: Vector2i = source_candidate.get(
			"anchor",
			creature.anchor_tile
		)

		if unresolved_targets.has(target_anchor):
			continue

		if target_anchor != start_anchor and not creature.world_grid.can_place_footprint(
			target_anchor,
			creature.footprint_size,
			creature
		):
			PerformanceStats.add_counter("path_blocked_goal")
			continue

		var candidate: Dictionary = source_candidate.duplicate()
		candidate["upper_bound_score"] = (
			float(candidate.get("score", -INF))
			- float(active_step_count) * GRAZING_DISTANCE_COST_PER_TILE
		)
		unresolved_targets[target_anchor] = candidate

	if unresolved_targets.is_empty():
		PerformanceStats.add_counter("path_failed")
		return {}

	var expansion_limits: Array[int] = _get_grazing_path_limits()
	var stage_index: int = 0
	var current_limit: int = expansion_limits[stage_index]
	var open_queue: Array[Vector2i] = [start_anchor]
	var queue_index: int = 0
	var steps_by_anchor: Dictionary = {start_anchor: 0}
	var came_from: Dictionary = {}
	var best_plan: Dictionary = {}
	var expanded_tiles: int = 0
	var search_capped: bool = false

	while queue_index < open_queue.size():
		if expanded_tiles >= current_limit:
			if not best_plan.is_empty() and not _unresolved_candidate_can_beat(
				best_plan,
				unresolved_targets
			):
				break

			stage_index += 1

			if stage_index >= expansion_limits.size():
				search_capped = true
				break

			current_limit = expansion_limits[stage_index]

		var current: Vector2i = open_queue[queue_index]
		queue_index += 1
		expanded_tiles += 1
		var route_steps: int = int(steps_by_anchor.get(current, 0))

		if unresolved_targets.has(current):
			var reached_candidate: Dictionary = unresolved_targets[current]
			var path: Array[Vector2i] = _reconstruct_shared_path(
				came_from,
				start_anchor,
				current
			)
			var total_route_steps: int = route_steps + active_step_count
			var food_value: int = int(reached_candidate.get("food_value", 0))
			var plan: Dictionary = reached_candidate.duplicate()
			plan["anchor"] = current
			plan["path"] = path
			plan["route_steps"] = total_route_steps
			plan["score"] = (
				float(food_value)
				- float(total_route_steps) * GRAZING_DISTANCE_COST_PER_TILE
			)
			unresolved_targets.erase(current)

			if best_plan.is_empty() or _is_shared_plan_better(plan, best_plan):
				best_plan = plan

			if unresolved_targets.is_empty() or not _unresolved_candidate_can_beat(
				best_plan,
				unresolved_targets
			):
				break

		var neighbors: Array[Vector2i] = creature.world_grid.get_neighbors(
			current,
			creature.footprint_size,
			creature
		)

		for neighbor: Vector2i in neighbors:
			if steps_by_anchor.has(neighbor):
				continue

			steps_by_anchor[neighbor] = route_steps + 1
			came_from[neighbor] = current
			open_queue.append(neighbor)

	PerformanceStats.add_counter("path_expanded_tiles", expanded_tiles)

	if search_capped:
		PerformanceStats.add_counter("path_capped")

	if best_plan.is_empty():
		PerformanceStats.add_counter("path_failed")
		return {}

	PerformanceStats.add_counter("path_success")
	best_plan["search_capped"] = search_capped
	best_plan["path_limit"] = current_limit
	return best_plan


func _get_grazing_path_limits() -> Array[int]:
	var max_allowed: int = max(int(creature.max_path_search_tiles), 1)
	var configured_limits: Array[int] = [
		GRAZING_PATH_LIMIT_NEAR,
		GRAZING_PATH_LIMIT_MEDIUM,
		GRAZING_PATH_LIMIT_FALLBACK
	]
	var path_limits: Array[int] = []

	for configured_limit: int in configured_limits:
		var path_limit: int = min(configured_limit, max_allowed)

		if path_limit > 0 and not path_limits.has(path_limit):
			path_limits.append(path_limit)

	if path_limits.is_empty():
		path_limits.append(max_allowed)

	return path_limits


func _unresolved_candidate_can_beat(
	best_plan: Dictionary,
	unresolved_targets: Dictionary
) -> bool:
	if best_plan.is_empty():
		return true

	var best_score: float = float(best_plan.get("score", -INF))

	for target_variant: Variant in unresolved_targets.keys():
		if not (target_variant is Vector2i):
			continue

		var target_anchor: Vector2i = target_variant
		var candidate: Dictionary = unresolved_targets[target_anchor]
		var upper_bound: float = float(
			candidate.get("upper_bound_score", -INF)
		)

		# Equality remains relevant because the current target wins an exact tie.
		if upper_bound > best_score or is_equal_approx(upper_bound, best_score):
			return true

	return false


func _is_shared_plan_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	var candidate_score: float = float(candidate.get("score", -INF))
	var current_score: float = float(current_best.get("score", -INF))

	if not is_equal_approx(candidate_score, current_score):
		return candidate_score > current_score

	var candidate_preferred: bool = bool(candidate.get("prefer_on_tie", false))
	var current_preferred: bool = bool(current_best.get("prefer_on_tie", false))

	if candidate_preferred != current_preferred:
		return candidate_preferred

	var candidate_food_value: int = int(candidate.get("food_value", 0))
	var current_food_value: int = int(current_best.get("food_value", 0))

	if candidate_food_value != current_food_value:
		return candidate_food_value > current_food_value

	var candidate_steps: int = int(candidate.get("route_steps", 0))
	var current_steps: int = int(current_best.get("route_steps", 0))

	if candidate_steps != current_steps:
		return candidate_steps < current_steps

	return int(candidate.get("adult_count", 0)) > int(
		current_best.get("adult_count", 0)
	)


func _reconstruct_shared_path(
	came_from: Dictionary,
	start_anchor: Vector2i,
	target_anchor: Vector2i
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor: Vector2i = target_anchor
	var safety_counter: int = 0

	while cursor != start_anchor:
		if not came_from.has(cursor):
			return []

		path.push_front(cursor)
		cursor = came_from[cursor]
		safety_counter += 1

		if safety_counter > 4096:
			return []

	return path


func _commit_grazing_plan(plan: Dictionary) -> void:
	creature.grazing_candidate_queue.clear()

	if plan.is_empty():
		_clear_grazing_target()
		return

	_apply_grazing_plan(plan)


func _apply_grazing_plan(plan: Dictionary) -> void:
	creature.has_grazing_target = true
	creature.grazing_target_anchor = plan.get(
		"anchor",
		creature.anchor_tile
	)

	var path_variant: Variant = plan.get("path", [])
	var path: Array = []

	if path_variant is Array:
		path = path_variant as Array

	_replace_grazing_route(path)


# Compatibility entry point retained for creature.gd and older callers. A fresh
# shared search replaces the old saved-runner-up loop.
func advance_to_next_grazing_candidate() -> void:
	try_acquire_grazing_target(true)


func apply_grazing_target(target_data: Dictionary) -> void:
	if target_data.has("path"):
		_apply_grazing_plan(target_data)
		return

	creature.has_grazing_target = true
	creature.grazing_target_anchor = target_data.get(
		"anchor",
		creature.anchor_tile
	)
	build_path_to_grazing_target()


func build_path_to_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_path_rebuild_requests")

	if creature.world_grid == null or not creature.has_grazing_target:
		return

	# The old queued route is no longer usable. Reconsider the current pasture
	# together with nearby alternatives in one shared wave, so a blocked route
	# never causes a separate current-target search followed by another full one.
	try_acquire_grazing_target(true)


# Returns true when route validation had to perform a full target acquisition.
func recheck_current_grazing_route() -> bool:
	PerformanceStats.add_counter("grazing_route_validation_requests")

	if creature.world_grid == null or not creature.has_grazing_target:
		return false

	if not is_current_grazing_target_still_valid() or not is_current_grazing_route_clear():
		try_acquire_grazing_target(true)
		return true

	return false


func recheck_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_recheck_requests")

	if creature.world_grid == null:
		return

	try_acquire_grazing_target(true)


func is_current_grazing_route_clear() -> bool:
	if not creature.has_grazing_target or creature.world_grid == null:
		return false

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()

	if navigation_anchor == creature.grazing_target_anchor:
		return true

	var path_variant: Variant = creature.get("current_path")

	if not (path_variant is Array):
		return false

	var route: Array = path_variant as Array

	if route.is_empty():
		return false

	var previous_anchor: Vector2i = navigation_anchor

	for step_variant: Variant in route:
		if not (step_variant is Vector2i):
			return false

		var step_anchor: Vector2i = step_variant
		var neighbors: Array[Vector2i] = creature.world_grid.get_neighbors(
			previous_anchor,
			creature.footprint_size,
			creature
		)

		if not neighbors.has(step_anchor):
			return false

		previous_anchor = step_anchor

	return previous_anchor == creature.grazing_target_anchor


func is_current_grazing_target_still_valid() -> bool:
	if not creature.has_grazing_target or creature.world_grid == null:
		return false

	if not creature.world_grid.can_place_footprint(
		creature.grazing_target_anchor,
		creature.footprint_size,
		creature
	):
		return false

	return get_current_grazing_target_adult_count() >= creature.min_grass_to_eat


func get_current_grazing_target_adult_count() -> int:
	if creature.world_grid == null or not creature.has_grazing_target:
		return 0

	return creature.world_grid.count_adult_grass_under_footprint(
		creature.grazing_target_anchor,
		creature.footprint_size
	)


func get_grazing_target_food_value(target_anchor: Vector2i) -> int:
	if creature.world_grid == null:
		return 0

	var total_food_value: int = 0
	var footprint_tiles: Array[Vector2i] = creature.world_grid.get_footprint_tiles(
		target_anchor,
		creature.footprint_size
	)

	for tile: Vector2i in footprint_tiles:
		var grass: Node = creature.world_grid.get_grass_at_tile(tile)

		if not is_instance_valid(grass):
			continue

		if grass.has_method("can_be_eaten") and not bool(grass.can_be_eaten()):
			continue

		if grass.has_method("get_food_value"):
			total_food_value += int(grass.get_food_value())
		else:
			# Compatibility fallback for an older grass object.
			total_food_value += 7

	return total_food_value


func _clear_grazing_target() -> void:
	creature.has_grazing_target = false
	creature.grazing_target_anchor = creature.anchor_tile
	creature.grazing_candidate_queue.clear()
	_clear_grazing_route()


func _replace_grazing_route(path: Array) -> void:
	if creature.movement_controller != null and creature.movement_controller.has_method("replace_behavior_route"):
		creature.movement_controller.replace_behavior_route(path)


func _clear_grazing_route() -> void:
	if creature.movement_controller != null and creature.movement_controller.has_method("clear_behavior_route"):
		creature.movement_controller.clear_behavior_route()


func _get_queued_route_steps() -> int:
	if creature.movement_controller != null and creature.movement_controller.has_method("get_queued_route_step_count"):
		return int(creature.movement_controller.get_queued_route_step_count())

	return 0
