extends RefCounted

const GRAZING_DISTANCE_COST_PER_TILE: float = 2.0
const GRAZING_PATH_CANDIDATE_LIMIT: int = 10
const GRAZING_FULL_RECHECK_INTERVAL: float = 5.0
const GRAZING_PATH_LIMIT_NEAR: int = 80
const GRAZING_PATH_LIMIT_MEDIUM: int = 150
const GRAZING_PATH_LIMIT_FALLBACK: int = 300
const GLOBAL_GRAZING_CANDIDATE_LIMIT: int = 32

var creature: Node
var full_recheck_timer := GRAZING_FULL_RECHECK_INTERVAL
var current_target_score: float = -INF
var current_target_route_steps := 0


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
	full_recheck_timer -= delta

	var acquired_during_route_check := false

	# Every two seconds only the current target and its real route are validated.
	# A full ten-candidate comparison is intentionally kept on a slower timer.
	if creature.food_recheck_timer <= 0.0:
		acquired_during_route_check = recheck_current_grazing_route()
		creature.food_recheck_timer = creature.food_recheck_interval

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
			build_path_to_grazing_target()

			if _get_queued_route_steps() == 0:
				# The route to the current target just became blocked. Try a saved
				# runner-up first, then perform a fresh staged search if needed.
				advance_to_next_grazing_candidate()


func enter_seek_food() -> void:
	creature.food_recheck_timer = creature.food_recheck_interval
	full_recheck_timer = GRAZING_FULL_RECHECK_INTERVAL
	current_target_score = -INF
	current_target_route_steps = 0
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
# least min_grass_to_eat edible tiles are eligible. A cheap pass builds a
# ten-anchor shortlist. Real routes are compared with staged expansion caps:
# 80 first, 150 only if the first stage finds nothing, and 300 only as the final
# fallback. The final score is:
# total food value under the footprint - actual route steps * 2.
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
	full_recheck_timer = GRAZING_FULL_RECHECK_INTERVAL


func _find_path_ranked_grazing_plans(
	search_radius: int,
	minimum_score_to_beat: float = -INF,
	allow_fallback_stages: bool = true
) -> Array[Dictionary]:
	if creature.world_grid == null:
		return []

	var rough_candidates: Array[Dictionary] = find_quality_ranked_grazing_candidates(
		search_radius,
		GRAZING_PATH_CANDIDATE_LIMIT
	)

	if rough_candidates.is_empty():
		return []

	var path_limits: Array[int] = _get_grazing_path_limits()

	if not allow_fallback_stages and path_limits.size() > 1:
		path_limits.resize(1)

	for path_limit: int in path_limits:
		var stage_plans: Array[Dictionary] = _evaluate_grazing_candidates_at_limit(
			rough_candidates,
			path_limit,
			minimum_score_to_beat
		)

		# A more expensive stage is used only when the cheaper stage found no
		# reachable option at all. This keeps the normal case bounded by 80 tiles.
		if not stage_plans.is_empty():
			return stage_plans

	return []


func _evaluate_grazing_candidates_at_limit(
	rough_candidates: Array[Dictionary],
	path_limit: int,
	minimum_score_to_beat: float
) -> Array[Dictionary]:
	var path_ranked_plans: Array[Dictionary] = []
	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var active_step_count: int = 1 if creature.is_moving else 0
	var best_score := minimum_score_to_beat
	var has_best_score := minimum_score_to_beat != -INF
	var has_minimum_score := minimum_score_to_beat != -INF

	for rough_candidate: Dictionary in rough_candidates:
		var rough_score: float = float(rough_candidate.get("score", -INF))

		# The cheap score uses the minimum possible step count. A real route can
		# only be equal or longer, so once this upper bound is below the current
		# winner, every remaining sorted candidate is unable to win.
		if has_best_score and rough_score < best_score:
			break

		var plan: Dictionary = _build_grazing_plan(
			rough_candidate,
			navigation_anchor,
			active_step_count,
			path_limit
		)

		if plan.is_empty():
			continue

		var plan_score: float = float(plan.get("score", -INF))

		# Periodic retargeting keeps the current target on an exact score tie.
		if has_minimum_score and (plan_score < minimum_score_to_beat or is_equal_approx(plan_score, minimum_score_to_beat)):
			continue

		_insert_path_ranked_grazing_plan(
			path_ranked_plans,
			plan,
			GRAZING_PATH_CANDIDATE_LIMIT
		)

		if not has_best_score or plan_score > best_score:
			best_score = plan_score
			has_best_score = true

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

	return path_limits


func _build_grazing_plan(
	candidate: Dictionary,
	navigation_anchor: Vector2i,
	active_step_count: int,
	max_expanded_tiles: int = GRAZING_PATH_LIMIT_NEAR
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
			max_expanded_tiles
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
	plan["rough_score"] = float(candidate.get("score", path_score))
	plan["path"] = path
	plan["route_steps"] = route_steps
	plan["score"] = path_score
	plan["path_limit"] = max_expanded_tiles
	return plan


func _build_current_target_plan(max_expanded_tiles: int) -> Dictionary:
	if not creature.has_grazing_target:
		return {}

	return _build_grazing_plan(
		{
			"anchor": creature.grazing_target_anchor,
			"food_value": get_grazing_target_food_value(creature.grazing_target_anchor),
			"adult_count": get_current_grazing_target_adult_count()
		},
		creature.get_navigation_anchor(),
		1 if creature.is_moving else 0,
		max_expanded_tiles
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
		_clear_grazing_target()
		return

	creature.grazing_candidate_queue = _extract_candidate_anchors(ranked_plans, 1)
	_apply_grazing_plan(ranked_plans[0])


func _apply_grazing_plan(plan: Dictionary) -> void:
	creature.has_grazing_target = true
	creature.grazing_target_anchor = plan.get("anchor", creature.anchor_tile)
	current_target_route_steps = int(plan.get("route_steps", 0))
	current_target_score = float(plan.get("score", -INF))

	var path_variant: Variant = plan.get("path", [])
	var path: Array = []

	if path_variant is Array:
		path = path_variant as Array

	_replace_grazing_route(path)


# Tries queued candidates in the path-ranked order captured by the last scan.
func advance_to_next_grazing_candidate() -> void:
	if creature.world_grid == null:
		_clear_grazing_target()
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
			1 if creature.is_moving else 0,
			GRAZING_PATH_LIMIT_NEAR
		)

		if plan.is_empty():
			continue

		_apply_grazing_plan(plan)
		return

	_clear_grazing_target()
	try_acquire_grazing_target()


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

	var plan: Dictionary = _build_current_target_plan(GRAZING_PATH_LIMIT_NEAR)

	if plan.is_empty():
		current_target_score = -INF
		current_target_route_steps = 0
		_clear_grazing_route()
		return

	_apply_grazing_plan(plan)


# Returns true when the cheap current-route check had to run a full acquisition.
func recheck_current_grazing_route() -> bool:
	PerformanceStats.add_counter("grazing_route_validation_requests")

	if creature.world_grid == null:
		return false

	if not creature.has_grazing_target:
		# With no current route there is nothing cheap to validate. The next
		# full five-second search owns reacquisition, avoiding a heavy scan every
		# two seconds when the map temporarily has no reachable pasture.
		return false

	if not is_current_grazing_target_still_valid():
		_clear_grazing_target()
		try_acquire_grazing_target()
		return true

	var current_plan: Dictionary = _build_current_target_plan(GRAZING_PATH_LIMIT_NEAR)

	if current_plan.is_empty():
		_clear_grazing_target()
		try_acquire_grazing_target()
		return true

	_apply_grazing_plan(current_plan)
	return false


# Full alternative comparison. The current route itself is refreshed by the
# two-second validation above; every five seconds nearby alternatives may replace
# it only when their real score is strictly better.
func recheck_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_recheck_requests")

	if creature.world_grid == null:
		return

	if not creature.has_grazing_target or not is_current_grazing_target_still_valid():
		try_acquire_grazing_target()
		return

	if current_target_score == -INF:
		var current_plan: Dictionary = _build_current_target_plan(GRAZING_PATH_LIMIT_NEAR)

		if current_plan.is_empty():
			_clear_grazing_target()
			try_acquire_grazing_target()
			return

		_apply_grazing_plan(current_plan)

	var nearby_plans: Array[Dictionary] = _find_path_ranked_grazing_plans(
		creature.nearby_grazing_recheck_radius,
		current_target_score,
		false
	)

	if nearby_plans.is_empty():
		return

	_commit_ranked_grazing_plans(nearby_plans)


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
	current_target_score = -INF
	current_target_route_steps = 0
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
