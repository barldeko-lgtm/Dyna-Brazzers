extends RefCounted

const GRAZING_DISTANCE_COST_PER_TILE: float = 2.0
const GRAZING_PATH_CANDIDATE_LIMIT: int = 8
const GLOBAL_GRAZING_CANDIDATE_LIMIT: int = 32

var creature: Node


func _init(owner_creature: Node) -> void:
	creature = owner_creature


# Food state machine.
func update_food_behavior() -> void:
	PerformanceStats.add_counter("grazing_food_behavior_ticks")

	if creature.species_data.is_predator():
		return

	if creature.world_grid == null:
		return

	if creature.state == creature.State.EATING or creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
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

	if creature.food_recheck_timer <= 0.0:
		recheck_grazing_target()
		creature.food_recheck_timer = creature.food_recheck_interval

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
				creature.has_grazing_target = false
				try_acquire_grazing_target()
		else:
			build_path_to_grazing_target()

			if _get_queued_route_steps() == 0:
				# The route to the current target just became blocked. Try the
				# next path-ranked candidate instead of retrying the same dead route.
				advance_to_next_grazing_candidate()


func enter_seek_food() -> void:
	creature.food_recheck_timer = creature.food_recheck_interval
	creature.has_grazing_target = false
	creature.grazing_candidate_queue.clear()
	creature.clear_path()
	creature.change_state(creature.State.SEEK_FOOD)
	try_acquire_grazing_target()


func can_start_eating_here() -> bool:
	if creature.world_grid == null:
		return false

	return creature.world_grid.count_adult_grass_under_footprint(creature.anchor_tile, creature.footprint_size) >= creature.min_grass_to_eat


# Grazing target selection.
# Grass stages 2-4 remain edible. Only 2x2 footprint anchors containing at
# least min_grass_to_eat edible tiles are eligible. A cheap pass builds an
# eight-anchor shortlist; real routes are then built to all eight and the final
# score uses actual remaining route steps:
# total food value under the footprint - route steps * 2.
func try_acquire_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_acquire_requests")

	if creature.world_grid == null:
		return

	var ranked_plans: Array[Dictionary] = _find_path_ranked_grazing_plans(
		creature.nearby_grazing_recheck_radius
	)

	if ranked_plans.is_empty():
		ranked_plans = _find_path_ranked_grazing_plans(-1)

	_commit_ranked_grazing_plans(ranked_plans)


func _find_path_ranked_grazing_plans(search_radius: int) -> Array[Dictionary]:
	if creature.world_grid == null:
		return []

	var result_limit: int = GRAZING_PATH_CANDIDATE_LIMIT
	var compare_limit: int = GRAZING_PATH_CANDIDATE_LIMIT
	var rough_candidates: Array[Dictionary] = find_quality_ranked_grazing_candidates(
		search_radius,
		compare_limit
	)
	var path_ranked_plans: Array[Dictionary] = []
	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var active_step_count: int = 1 if creature.is_moving else 0

	for rough_candidate: Dictionary in rough_candidates:
		var plan: Dictionary = _build_grazing_plan(
			rough_candidate,
			navigation_anchor,
			active_step_count
		)

		if plan.is_empty():
			continue

		_insert_path_ranked_grazing_plan(path_ranked_plans, plan, result_limit)

	return path_ranked_plans


func find_quality_ranked_grazing_candidates(
	search_radius: int,
	result_limit_override: int = -1
) -> Array[Dictionary]:
	if creature.world_grid == null:
		return []

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var result_limit: int = max(
		result_limit_override if result_limit_override > 0 else GRAZING_PATH_CANDIDATE_LIMIT,
		1
	)
	var scan_limit: int = result_limit

	if search_radius >= 0:
		# A square search with radius R contains at most (2R + 1)^2 anchors.
		# Requesting that many results guarantees that the quality re-rank sees
		# every valid nearby patch instead of only the old count-ranked top few.
		var search_diameter: int = search_radius * 2 + 1
		scan_limit = max(scan_limit, search_diameter * search_diameter)
	else:
		# Global fallback is used only when there is no nearby reachable patch.
		# Keep it bounded to avoid building a huge temporary candidate list.
		scan_limit = max(scan_limit * 8, GLOBAL_GRAZING_CANDIDATE_LIMIT)

	var raw_candidates: Array[Dictionary] = creature.world_grid.find_best_grazing_targets(
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
		var anchor: Vector2i = raw_candidate.get("anchor", creature.anchor_tile)
		var distance: int = int(raw_candidate.get(
			"distance",
			creature.world_grid.estimate_path_steps(navigation_anchor, anchor)
		))
		var food_value: int = get_grazing_target_food_value(anchor)
		var score: float = (
			float(food_value)
			- float(distance) * GRAZING_DISTANCE_COST_PER_TILE
		)

		var rescored_candidate: Dictionary = raw_candidate.duplicate()
		rescored_candidate["food_value"] = food_value
		rescored_candidate["distance"] = distance
		rescored_candidate["score"] = score

		_insert_quality_ranked_candidate(
			quality_ranked,
			rescored_candidate,
			result_limit
		)

	return quality_ranked


func _build_grazing_plan(
	candidate: Dictionary,
	navigation_anchor: Vector2i,
	active_step_count: int
) -> Dictionary:
	if creature.world_grid == null:
		return {}

	var target_anchor: Vector2i = candidate.get("anchor", creature.anchor_tile)
	var path: Array[Vector2i] = []

	if target_anchor != navigation_anchor:
		path = creature.world_grid.find_path(
			navigation_anchor,
			target_anchor,
			creature.footprint_size,
			creature,
			creature.max_path_search_tiles
		)

		if path.is_empty():
			PerformanceStats.add_counter("grazing_candidate_unreachable")
			return {}

	var food_value: int = int(candidate.get(
		"food_value",
		get_grazing_target_food_value(target_anchor)
	))
	var route_steps: int = path.size() + active_step_count
	var path_score: float = (
		float(food_value)
		- float(route_steps) * GRAZING_DISTANCE_COST_PER_TILE
	)
	var plan: Dictionary = candidate.duplicate()
	plan["anchor"] = target_anchor
	plan["food_value"] = food_value
	plan["path"] = path
	plan["route_steps"] = route_steps
	plan["score"] = path_score
	return plan


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


func _insert_path_ranked_grazing_plan(
	ranked_plans: Array[Dictionary],
	plan: Dictionary,
	max_results: int
) -> void:
	if max_results <= 0:
		return

	var insert_index: int = ranked_plans.size()

	for index: int in range(ranked_plans.size()):
		if _is_path_ranked_plan_better(plan, ranked_plans[index]):
			insert_index = index
			break

	if insert_index >= max_results:
		return

	ranked_plans.insert(insert_index, plan)

	if ranked_plans.size() > max_results:
		ranked_plans.resize(max_results)


func is_quality_candidate_better(candidate: Dictionary, current_best: Dictionary) -> bool:
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

	return int(candidate.get("adult_count", 0)) > int(current_best.get("adult_count", 0))


func _is_path_ranked_plan_better(candidate: Dictionary, current_best: Dictionary) -> bool:
	var candidate_score: float = float(candidate.get("score", -INF))
	var current_score: float = float(current_best.get("score", -INF))

	if not is_equal_approx(candidate_score, current_score):
		return candidate_score > current_score

	var candidate_food_value: int = int(candidate.get("food_value", 0))
	var current_food_value: int = int(current_best.get("food_value", 0))

	if candidate_food_value != current_food_value:
		return candidate_food_value > current_food_value

	var candidate_route_steps: int = int(candidate.get("route_steps", 0))
	var current_route_steps: int = int(current_best.get("route_steps", 0))

	if candidate_route_steps != current_route_steps:
		return candidate_route_steps < current_route_steps

	return int(candidate.get("adult_count", 0)) > int(current_best.get("adult_count", 0))


func _extract_candidate_anchors(
	ranked_plans: Array[Dictionary],
	start_index: int = 0
) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []

	for index: int in range(start_index, ranked_plans.size()):
		anchors.append(ranked_plans[index].get("anchor", creature.anchor_tile))

	return anchors


func _commit_ranked_grazing_plans(ranked_plans: Array[Dictionary]) -> void:
	if ranked_plans.is_empty():
		creature.has_grazing_target = false
		creature.grazing_target_anchor = creature.anchor_tile
		creature.grazing_candidate_queue.clear()
		_clear_grazing_route()
		return

	creature.grazing_candidate_queue = _extract_candidate_anchors(ranked_plans, 1)
	_apply_grazing_plan(ranked_plans[0])


func _apply_grazing_plan(plan: Dictionary) -> void:
	creature.has_grazing_target = true
	creature.grazing_target_anchor = plan.get("anchor", creature.anchor_tile)

	var path_variant: Variant = plan.get("path", [])
	var path: Array = []

	if path_variant is Array:
		path = path_variant as Array

	_replace_grazing_route(path)


# Tries queued candidates in the path-ranked order captured by the last scan.
func advance_to_next_grazing_candidate() -> void:
	if creature.world_grid == null:
		creature.has_grazing_target = false
		_clear_grazing_route()
		return

	while not creature.grazing_candidate_queue.is_empty():
		var candidate_anchor: Vector2i = creature.grazing_candidate_queue.pop_front()

		if not creature.world_grid.can_place_footprint(
			candidate_anchor,
			creature.footprint_size,
			creature
		):
			continue

		var adult_count: int = creature.world_grid.count_adult_grass_under_footprint(
			candidate_anchor,
			creature.footprint_size
		)

		if adult_count < creature.min_grass_to_eat:
			continue

		var plan: Dictionary = _build_grazing_plan(
			{
				"anchor": candidate_anchor,
				"adult_count": adult_count,
				"food_value": get_grazing_target_food_value(candidate_anchor)
			},
			creature.get_navigation_anchor(),
			1 if creature.is_moving else 0
		)

		if plan.is_empty():
			continue

		_apply_grazing_plan(plan)
		return

	creature.has_grazing_target = false
	creature.grazing_target_anchor = creature.anchor_tile
	_clear_grazing_route()


func apply_grazing_target(target_data: Dictionary) -> void:
	if target_data.has("path"):
		_apply_grazing_plan(target_data)
		return

	creature.has_grazing_target = true
	creature.grazing_target_anchor = target_data.get("anchor", creature.anchor_tile)
	build_path_to_grazing_target()

	if _get_queued_route_steps() == 0 and creature.grazing_target_anchor != creature.get_navigation_anchor():
		advance_to_next_grazing_candidate()


func build_path_to_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_path_rebuild_requests")

	if creature.world_grid == null or not creature.has_grazing_target:
		return

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var path: Array[Vector2i] = []

	if navigation_anchor != creature.grazing_target_anchor:
		path = creature.world_grid.find_path(
			navigation_anchor,
			creature.grazing_target_anchor,
			creature.footprint_size,
			creature,
			creature.max_path_search_tiles
		)

	_replace_grazing_route(path)


func recheck_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_recheck_requests")

	if creature.world_grid == null:
		return

	var nearby_plans: Array[Dictionary] = _find_path_ranked_grazing_plans(
		creature.nearby_grazing_recheck_radius
	)

	if nearby_plans.is_empty():
		if creature.has_grazing_target and is_current_grazing_target_still_valid():
			return

		try_acquire_grazing_target()
		return

	var nearby_plan: Dictionary = nearby_plans[0]
	var nearby_anchor: Vector2i = nearby_plan.get("anchor", creature.anchor_tile)

	if not creature.has_grazing_target:
		_commit_ranked_grazing_plans(nearby_plans)
		return

	if nearby_anchor == creature.grazing_target_anchor:
		return

	if not is_current_grazing_target_still_valid():
		_commit_ranked_grazing_plans(nearby_plans)
		return

	var current_food_value: int = get_grazing_target_food_value(
		creature.grazing_target_anchor
	)
	var current_route_steps: int = _get_current_grazing_route_steps()
	var current_score: float = (
		float(current_food_value)
		- float(current_route_steps) * GRAZING_DISTANCE_COST_PER_TILE
	)
	var new_score: float = float(nearby_plan.get("score", -INF))

	if new_score > current_score:
		_commit_ranked_grazing_plans(nearby_plans)


func _get_current_grazing_route_steps() -> int:
	# Rebuild the route from the current navigation anchor so periodic target
	# comparison uses current terrain, occupancy and movement reservations rather
	# than the length of a route calculated during an older scan.
	var current_candidate: Dictionary = {
		"anchor": creature.grazing_target_anchor,
		"food_value": get_grazing_target_food_value(creature.grazing_target_anchor),
		"adult_count": get_current_grazing_target_adult_count()
	}
	var current_plan: Dictionary = _build_grazing_plan(
		current_candidate,
		creature.get_navigation_anchor(),
		1 if creature.is_moving else 0
	)

	if current_plan.is_empty():
		return 2147483647

	return int(current_plan.get("route_steps", 2147483647))


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

