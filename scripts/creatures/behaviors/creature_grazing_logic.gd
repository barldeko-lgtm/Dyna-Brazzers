extends RefCounted

var creature: Node


func _init(owner_creature: Node) -> void:
	creature = owner_creature


# Food state machine.
func update_food_behavior() -> void:
	if creature.is_predator:
		return

	if creature.world_grid == null:
		return

	if creature.state == creature.State.EATING or creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
		return

	if creature.is_moving:
		return

	if creature.hunger > creature.hunger_search_threshold:
		return

	if creature.state != creature.State.SEEK_FOOD:
		creature.enter_seek_food()


func update_seek_food(delta: float) -> void:
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


func enter_seek_food() -> void:
	creature.state = creature.State.SEEK_FOOD
	creature.food_recheck_timer = creature.food_recheck_interval
	creature.has_grazing_target = false
	creature.clear_path()
	try_acquire_grazing_target()


func can_start_eating_here() -> bool:
	if creature.world_grid == null:
		return false

	return creature.world_grid.count_adult_grass_under_footprint(creature.anchor_tile, creature.footprint_size) >= creature.min_grass_to_eat


# Grazing target selection.
func try_acquire_grazing_target() -> void:
	if creature.world_grid == null:
		return

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var local_target: Dictionary = creature.world_grid.find_best_grazing_target(
		navigation_anchor,
		creature.footprint_size,
		creature.min_grass_to_eat,
		creature.nearby_grazing_recheck_radius,
		creature,
		creature.grazing_grass_weight,
		creature.grazing_distance_penalty
	)

	if not local_target.is_empty():
		apply_grazing_target(local_target)
		return

	var global_target: Dictionary = creature.world_grid.find_best_grazing_target(
		navigation_anchor,
		creature.footprint_size,
		creature.min_grass_to_eat,
		-1,
		creature,
		creature.grazing_grass_weight,
		creature.grazing_distance_penalty
	)

	if not global_target.is_empty():
		apply_grazing_target(global_target)
		return

	creature.has_grazing_target = false
	creature.grazing_target_anchor = creature.anchor_tile
	creature.clear_path()


func apply_grazing_target(target_data: Dictionary) -> void:
	creature.has_grazing_target = true
	creature.grazing_target_anchor = target_data.get("anchor", creature.anchor_tile)
	build_path_to_grazing_target()


func build_path_to_grazing_target() -> void:
	if creature.world_grid == null or not creature.has_grazing_target:
		return

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	creature.current_path = creature.world_grid.find_path(navigation_anchor, creature.grazing_target_anchor, creature.footprint_size, creature)


func recheck_grazing_target() -> void:
	if creature.world_grid == null:
		return

	var navigation_anchor: Vector2i = creature.get_navigation_anchor()
	var nearby_target: Dictionary = creature.world_grid.find_best_grazing_target(
		navigation_anchor,
		creature.footprint_size,
		creature.min_grass_to_eat,
		creature.nearby_grazing_recheck_radius,
		creature,
		creature.grazing_grass_weight,
		creature.grazing_distance_penalty
	)

	if nearby_target.is_empty():
		if creature.has_grazing_target and is_current_grazing_target_still_valid():
			return

		try_acquire_grazing_target()
		return

	if not creature.has_grazing_target:
		apply_grazing_target(nearby_target)
		return

	var new_score: float = float(nearby_target.get("score", -INF))
	var current_adult_count: int = get_current_grazing_target_adult_count()
	var current_distance: int = creature.world_grid.estimate_path_steps(navigation_anchor, creature.grazing_target_anchor)
	var current_score: float = float(current_adult_count) * float(creature.grazing_grass_weight) - float(current_distance) * float(creature.grazing_distance_penalty)
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

	if not creature.world_grid.can_place_footprint(creature.grazing_target_anchor, creature.footprint_size, creature):
		return false

	return get_current_grazing_target_adult_count() >= creature.min_grass_to_eat


func get_current_grazing_target_adult_count() -> int:
	if creature.world_grid == null or not creature.has_grazing_target:
		return 0

	return creature.world_grid.count_adult_grass_under_footprint(creature.grazing_target_anchor, creature.footprint_size)
