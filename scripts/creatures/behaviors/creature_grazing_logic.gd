extends RefCounted

const GRAZING_DISTANCE_COST_PER_TILE: float = 2.0
const GLOBAL_GRAZING_CANDIDATE_LIMIT: int = 32

var creature: Node


func _init(owner_creature: Node) -> void:
	creature = owner_creature


# Food state machine.
func update_food_behavior() -> void:
	PerformanceStats.add_counter("grazing_food_behavior_ticks")

	if creature.species_data.is_predator:
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
		if not creature.is_moving and creature.current_path.is_empty():
			creature.choose_random_wander_step()

		creature.start_next_path_step_if_needed()
		return

	creature.start_next_path_step_if_needed()

	if not creature.is_moving and creature.current_path.is_empty() and creature.has_grazing_target:
		if creature.anchor_tile == creature.grazing_target_anchor:
			if can_start_eating_here():
				creature.enter_eating()
			else:
				creature.has_grazing_target = false
				try_acquire_grazing_target()
		else:
			build_path_to_grazing_target()

			if creature.current_path.is_empty():
				# The route to the current target just became blocked. Try the
				# next ranked candidate instead of retrying the same dead route.
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
# Grass stages 2-4 remain edible, but candidates are ranked by their actual
# food value: stage 4 > stage 3 > stage 2.
# Exact formula: total food value under the footprint - distance * 2.
func try_acquire_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_acquire_requests")

	if creature.world_grid == null:
		return

	var ranked_candidates: Array[Dictionary] = find_quality_ranked_grazing_candidates(
		creature.nearby_grazing_recheck_radius
	)

	if ranked_candidates.is_empty():
		ranked_candidates = find_quality_ranked_grazing_candidates(-1)

	creature.grazing_candidate_queue = _extract_candidate_anchors(ranked_candidates)
	advance_to_next_grazing_candidate()


func find_quality_ranked_grazing_candidates(search_radius: int) -> Array[Dictionary]:
	if creature.world_grid == null:
		return []

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var result_limit: int = max(int(creature.max_grazing_candidates), 1)
	var scan_limit: int = result_limit

	if search_radius >= 0:
		# A square search with radius R contains at most (2R + 1)^2 anchors.
		# Requesting that many results guarantees that the quality re-rank sees
		# every valid nearby patch instead of only the old count-ranked top few.
		var search_diameter: int = search_radius * 2 + 1
		scan_limit = max(scan_limit, search_diameter * search_diameter)
	else:
		# Global fallback is used only when there is no nearby edible patch.
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


func _extract_candidate_anchors(ranked_candidates: Array[Dictionary]) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []

	for candidate_result: Dictionary in ranked_candidates:
		anchors.append(candidate_result.get("anchor", creature.anchor_tile))

	return anchors


# Tries queued candidates in ranked order and commits to the first reachable one.
func advance_to_next_grazing_candidate() -> void:
	if creature.world_grid == null:
		creature.has_grazing_target = false
		creature.clear_path()
		return

	while not creature.grazing_candidate_queue.is_empty():
		var candidate_anchor: Vector2i = creature.grazing_candidate_queue.pop_front()
		var navigation_anchor: Vector2i = creature.get_navigation_anchor()
		var path: Array[Vector2i] = creature.world_grid.find_path(
			navigation_anchor,
			candidate_anchor,
			creature.footprint_size,
			creature,
			creature.max_path_search_tiles
		)

		if path.is_empty():
			PerformanceStats.add_counter("grazing_candidate_unreachable")
			continue

		creature.has_grazing_target = true
		creature.grazing_target_anchor = candidate_anchor
		creature.current_path = path
		return

	creature.has_grazing_target = false
	creature.grazing_target_anchor = creature.anchor_tile
	creature.clear_path()


func apply_grazing_target(target_data: Dictionary) -> void:
	creature.has_grazing_target = true
	creature.grazing_target_anchor = target_data.get("anchor", creature.anchor_tile)
	build_path_to_grazing_target()

	if creature.current_path.is_empty():
		advance_to_next_grazing_candidate()


func build_path_to_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_path_rebuild_requests")

	if creature.world_grid == null or not creature.has_grazing_target:
		return

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	creature.current_path = creature.world_grid.find_path(
		navigation_anchor,
		creature.grazing_target_anchor,
		creature.footprint_size,
		creature,
		creature.max_path_search_tiles
	)


func recheck_grazing_target() -> void:
	PerformanceStats.add_counter("grazing_recheck_requests")

	if creature.world_grid == null:
		return

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var nearby_candidates: Array[Dictionary] = find_quality_ranked_grazing_candidates(
		creature.nearby_grazing_recheck_radius
	)

	if nearby_candidates.is_empty():
		if creature.has_grazing_target and is_current_grazing_target_still_valid():
			return

		try_acquire_grazing_target()
		return

	var nearby_target: Dictionary = nearby_candidates[0]

	if not creature.has_grazing_target:
		apply_grazing_target(nearby_target)
		return

	var new_score: float = float(nearby_target.get("score", -INF))
	var current_food_value: int = get_grazing_target_food_value(
		creature.grazing_target_anchor
	)
	var current_distance: int = creature.world_grid.estimate_path_steps(
		navigation_anchor,
		creature.grazing_target_anchor
	)
	var current_score: float = (
		float(current_food_value)
		- float(current_distance) * GRAZING_DISTANCE_COST_PER_TILE
	)
	var new_distance: int = int(nearby_target.get("distance", 0))

	if new_score > current_score:
		apply_grazing_target(nearby_target)
		return

	if is_equal_approx(new_score, current_score) and new_distance < current_distance - creature.retarget_distance_advantage:
		apply_grazing_target(nearby_target)
		return

	if not is_current_grazing_target_still_valid():
		apply_grazing_target(nearby_target)


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
