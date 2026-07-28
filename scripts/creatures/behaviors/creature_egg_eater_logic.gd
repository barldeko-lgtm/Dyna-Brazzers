extends RefCounted

const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const FOOD_SEARCH_INTERVAL := 0.5
const TARGET_SWITCH_ADVANTAGE_STEPS := 2
const TARGET_CANDIDATE_LIMIT := 3

enum EggHuntMode {
	NONE,
	STRATEGIC,
	HUNGER
}

var creature: Node
var search_cooldown_remaining := 0.0
var target_egg: Node = null


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func is_hunting() -> bool:
	return target_egg != null and is_valid_egg_target(target_egg)


func update_egg_eater_behavior() -> void:
	if not creature.is_egg_eater() or creature.world_grid == null:
		return

	if _get_hunt_mode() == EggHuntMode.NONE:
		# A satiated egg eater has no food task. Keep any independent route,
		# including a species-flag route, and only forget a stale egg target.
		target_egg = null
		search_cooldown_remaining = 0.0
		return

	if creature.state == creature.State.DEAD or creature.state == creature.State.EATING or creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
		return

	search_cooldown_remaining = max(
		search_cooldown_remaining - creature.get_physics_process_delta_time(),
		0.0
	)

	if target_egg != null and not is_valid_egg_target(target_egg):
		clear_target()

	if search_cooldown_remaining <= 0.0:
		search_cooldown_remaining = FOOD_SEARCH_INTERVAL

		if target_egg == null:
			var acquisition_plan := find_best_egg_plan()

			if not acquisition_plan.is_empty():
				_commit_egg_plan(acquisition_plan)
		else:
			var challenger_plan := find_best_egg_plan(
				target_egg,
				TARGET_CANDIDATE_LIMIT - 1
			)

			if _should_retarget_to_plan(challenger_plan):
				_commit_egg_plan(challenger_plan)

	if target_egg != null:
		update_current_target()


func update_current_target() -> void:
	if target_egg == null or not is_valid_egg_target(target_egg):
		clear_target()
		return

	if is_egg_in_eating_range(target_egg):
		if target_egg.has_method("can_be_eaten") and bool(target_egg.can_be_eaten()):
			consume_egg(target_egg)
		return

	if creature.is_moving:
		return

	if not creature.current_path.is_empty():
		creature.start_next_path_step_if_needed()
		return

	if creature.predator_path_retry_cooldown_remaining > 0.0:
		return

	var path_built := build_path_to_egg(target_egg)
	creature.start_next_path_step_if_needed()

	if path_built:
		return

	var fallback_plan := find_best_egg_plan(
		target_egg,
		TARGET_CANDIDATE_LIMIT - 1
	)

	if not fallback_plan.is_empty():
		_commit_egg_plan(fallback_plan)
		creature.start_next_path_step_if_needed()
		return

	creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval


func find_best_egg_plan(
	excluded_egg: Node = null,
	max_candidates: int = TARGET_CANDIDATE_LIMIT
) -> Dictionary:
	var candidates := find_nearest_egg_candidates(max_candidates, excluded_egg)
	var best_plan: Dictionary = {}
	var best_route_steps := 2147483647
	var best_is_edible := false

	for egg: Node in candidates:
		var plan := _find_best_egg_approach_plan(egg, _get_navigation_anchor())

		if plan.is_empty():
			continue

		var route_steps := int(plan.get("route_steps", 2147483647))
		var is_edible := egg.has_method("can_be_eaten") and bool(egg.can_be_eaten())

		if route_steps > best_route_steps:
			continue

		if route_steps == best_route_steps and (best_is_edible or not is_edible):
			continue

		best_route_steps = route_steps
		best_is_edible = is_edible
		best_plan = plan

	return best_plan


func find_nearest_egg_candidates(
	max_candidates: int = TARGET_CANDIDATE_LIMIT,
	excluded_egg: Node = null
) -> Array[Node]:
	var result: Array[Node] = []

	if creature.world_grid == null or max_candidates <= 0:
		return result

	var ranked_candidates: Array[Dictionary] = []
	var origin_anchor := _get_navigation_anchor()
	var active_radius := _get_active_target_radius()

	for candidate: Node in creature.get_tree().get_nodes_in_group("eggs"):
		if candidate == excluded_egg or not is_valid_egg_target(candidate):
			continue

		var egg_anchor: Vector2i = candidate.get("anchor_tile")
		var distance := int(creature.world_grid.estimate_path_steps(origin_anchor, egg_anchor))

		if distance > active_radius:
			continue

		_insert_ranked_egg_candidate(
			ranked_candidates,
			{"egg": candidate, "distance": distance},
			max_candidates
		)

	for candidate_data: Dictionary in ranked_candidates:
		var egg := candidate_data.get("egg", null) as Node

		if is_instance_valid(egg):
			result.append(egg)

	return result


func _insert_ranked_egg_candidate(
	ranked_candidates: Array[Dictionary],
	candidate_data: Dictionary,
	max_candidates: int
) -> void:
	var candidate_distance := int(candidate_data.get("distance", 2147483647))
	var insert_index := ranked_candidates.size()

	for index in range(ranked_candidates.size()):
		if candidate_distance < int(ranked_candidates[index].get("distance", 2147483647)):
			insert_index = index
			break

	if insert_index >= max_candidates:
		return

	ranked_candidates.insert(insert_index, candidate_data)

	if ranked_candidates.size() > max_candidates:
		ranked_candidates.resize(max_candidates)


func _should_retarget_to_plan(candidate_plan: Dictionary) -> bool:
	if candidate_plan.is_empty():
		return false

	if target_egg == null or not is_valid_egg_target(target_egg):
		return true

	var candidate_steps := int(candidate_plan.get("route_steps", 2147483647))
	return candidate_steps + TARGET_SWITCH_ADVANTAGE_STEPS <= _remaining_route_steps()


func is_valid_egg_target(candidate: Node) -> bool:
	if (
		candidate == null
		or not is_instance_valid(candidate)
		or candidate.is_queued_for_deletion()
	):
		return false

	if candidate.has_method("can_be_tracked_by_egg_eater"):
		if not bool(candidate.call("can_be_tracked_by_egg_eater")):
			return false
	elif not candidate.has_method("can_be_eaten") or not bool(candidate.can_be_eaten()):
		return false

	var hunt_mode := _get_hunt_mode()

	if hunt_mode == EggHuntMode.NONE:
		return false

	var creature_faction := CREATURE_FACTION.get_id(creature)
	var candidate_faction := CREATURE_FACTION.get_id(candidate)

	if hunt_mode == EggHuntMode.STRATEGIC:
		return (
			(creature_faction == CREATURE_FACTION.PLAYER and candidate_faction == CREATURE_FACTION.ENEMY)
			or (creature_faction == CREATURE_FACTION.ENEMY and candidate_faction == CREATURE_FACTION.PLAYER)
		)

	var same_species: bool = (
		String(candidate.get("species_id")) == String(creature.species_data.species_id)
	)
	return not (same_species and candidate_faction == creature_faction)


func _get_hunt_mode() -> EggHuntMode:
	if creature.hunger <= creature.species_data.hunger_search_threshold:
		return EggHuntMode.HUNGER

	if creature.hunger <= creature.species_data.strategic_hunt_threshold:
		return EggHuntMode.STRATEGIC

	return EggHuntMode.NONE


func _get_active_target_radius() -> int:
	if _get_hunt_mode() == EggHuntMode.STRATEGIC:
		var strategic_radius := maxi(
			int(creature.species_data.strategic_hunt_radius),
			0
		)

		if strategic_radius > 0:
			return strategic_radius

	return maxi(int(creature.species_data.predator_target_radius), 0)


func is_egg_in_eating_range(egg: Node) -> bool:
	if egg == null or not is_instance_valid(egg):
		return false

	var egg_anchor: Vector2i = egg.get("anchor_tile")
	var egg_footprint := get_egg_footprint(egg)
	return creature.are_footprints_side_adjacent(creature.anchor_tile, creature.footprint_size, egg_anchor, egg_footprint)


func build_path_to_egg(egg: Node) -> bool:
	var plan := _find_best_egg_approach_plan(egg, _get_navigation_anchor())

	if plan.is_empty():
		return false

	_commit_egg_plan(plan)
	return true


func _find_best_egg_approach_plan(egg: Node, origin_anchor: Vector2i) -> Dictionary:
	if creature.world_grid == null or not is_valid_egg_target(egg):
		return {}

	var active_step_count := 1 if creature.is_moving else 0

	if _is_egg_in_eating_range_from_anchor(egg, origin_anchor):
		return {
			"egg": egg,
			"path": [],
			"approach_anchor": origin_anchor,
			"route_steps": active_step_count
		}

	var ranked_anchors: Array[Vector2i] = []

	for candidate_anchor in build_egg_approach_anchors(egg):
		if not creature.world_grid.can_place_footprint(
			candidate_anchor,
			creature.footprint_size,
			creature
		):
			continue

		_insert_approach_anchor_by_distance(
			ranked_anchors,
			candidate_anchor,
			origin_anchor
		)

	var best_plan: Dictionary = {}
	var best_path_steps := 2147483647

	for approach_anchor in ranked_anchors:
		var estimated_steps := int(creature.world_grid.estimate_path_steps(
			origin_anchor,
			approach_anchor
		))

		if estimated_steps >= best_path_steps:
			break

		if approach_anchor == origin_anchor:
			return {
				"egg": egg,
				"path": [],
				"approach_anchor": approach_anchor,
				"route_steps": active_step_count
			}

		var path_variant: Variant = creature.world_grid.find_path(
			origin_anchor,
			approach_anchor,
			creature.footprint_size,
			creature,
			creature.max_path_search_tiles,
			&"egg_eater"
		)

		if not (path_variant is Array):
			continue

		var path := _normalize_route(path_variant as Array)

		if path.is_empty() or path.size() >= best_path_steps:
			continue

		best_path_steps = path.size()
		best_plan = {
			"egg": egg,
			"path": path,
			"approach_anchor": approach_anchor,
			"route_steps": path.size() + active_step_count
		}

	return best_plan


func _insert_approach_anchor_by_distance(
	ranked_anchors: Array[Vector2i],
	candidate_anchor: Vector2i,
	origin_anchor: Vector2i
) -> void:
	var candidate_distance := int(creature.world_grid.estimate_path_steps(
		origin_anchor,
		candidate_anchor
	))
	var insert_index := ranked_anchors.size()

	for index in range(ranked_anchors.size()):
		var current_distance := int(creature.world_grid.estimate_path_steps(
			origin_anchor,
			ranked_anchors[index]
		))

		if candidate_distance < current_distance:
			insert_index = index
			break

	ranked_anchors.insert(insert_index, candidate_anchor)


func _commit_egg_plan(plan: Dictionary) -> void:
	var egg := plan.get("egg", null) as Node

	if not is_instance_valid(egg):
		return

	var path_variant: Variant = plan.get("path", [])
	var path: Array[Vector2i] = []

	if path_variant is Array:
		path = _normalize_route(path_variant as Array)

	target_egg = egg
	search_cooldown_remaining = FOOD_SEARCH_INTERVAL
	_replace_egg_route(path)


func _replace_egg_route(path: Array[Vector2i]) -> void:
	if (
		creature.movement_controller != null
		and creature.movement_controller.has_method("replace_behavior_route")
	):
		creature.movement_controller.replace_behavior_route(path)
		return

	creature.current_path = path.duplicate()


func _get_navigation_anchor() -> Vector2i:
	if creature.has_method("get_navigation_anchor"):
		return creature.get_navigation_anchor()

	return creature.pending_anchor_tile if creature.is_moving else creature.anchor_tile


func _remaining_route_steps() -> int:
	if (
		creature.movement_controller != null
		and creature.movement_controller.has_method("get_remaining_route_steps")
	):
		return int(creature.movement_controller.get_remaining_route_steps())

	return creature.current_path.size() + (1 if creature.is_moving else 0)


func _normalize_route(path: Array) -> Array[Vector2i]:
	var normalized: Array[Vector2i] = []

	for step_variant: Variant in path:
		if step_variant is Vector2i:
			normalized.append(step_variant)

	return normalized


func _is_egg_in_eating_range_from_anchor(egg: Node, eater_anchor: Vector2i) -> bool:
	if egg == null or not is_instance_valid(egg):
		return false

	var egg_anchor: Vector2i = egg.get("anchor_tile")
	return creature.are_footprints_side_adjacent(
		eater_anchor,
		creature.footprint_size,
		egg_anchor,
		get_egg_footprint(egg)
	)


func get_egg_footprint(egg: Node) -> Vector2i:
	if egg.has_method("get_current_footprint"):
		return egg.get_current_footprint()

	return Vector2i(2, 2)


func build_egg_approach_anchors(egg: Node) -> Array[Vector2i]:
	if egg == null or not is_instance_valid(egg):
		return []

	var egg_anchor: Vector2i = egg.get("anchor_tile")

	if egg.has_method("can_be_eaten") and not bool(egg.can_be_eaten()):
		return _build_stage_one_approach_anchors(egg_anchor)

	return _build_side_approach_anchors(egg_anchor, get_egg_footprint(egg))


func _build_stage_one_approach_anchors(egg_anchor: Vector2i) -> Array[Vector2i]:
	var right_expansion := Rect2i(egg_anchor, Vector2i(2, 2))
	var left_expansion := Rect2i(egg_anchor + Vector2i.LEFT, Vector2i(2, 2))
	var anchors: Array[Vector2i] = []
	var anchor_lookup: Dictionary = {}

	for expansion_rect in [right_expansion, left_expansion]:
		for candidate_anchor in _build_side_approach_anchors(
			expansion_rect.position,
			expansion_rect.size
		):
			var eater_rect := Rect2i(candidate_anchor, creature.footprint_size)

			if eater_rect.intersects(right_expansion) or eater_rect.intersects(left_expansion):
				continue

			if not creature.are_footprints_side_adjacent(
				candidate_anchor,
				creature.footprint_size,
				egg_anchor,
				Vector2i(1, 2)
			):
				continue

			_append_unique_anchor(anchors, anchor_lookup, candidate_anchor)

	return anchors


func _build_side_approach_anchors(
	target_anchor: Vector2i,
	target_size: Vector2i
) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var anchor_lookup: Dictionary = {}

	for vertical_shift in range(-(creature.footprint_size.y - 1), target_size.y):
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			target_anchor + Vector2i(-creature.footprint_size.x, vertical_shift)
		)
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			target_anchor + Vector2i(target_size.x, vertical_shift)
		)

	for horizontal_shift in range(-(creature.footprint_size.x - 1), target_size.x):
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			target_anchor + Vector2i(horizontal_shift, -creature.footprint_size.y)
		)
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			target_anchor + Vector2i(horizontal_shift, target_size.y)
		)

	return anchors


func _append_unique_anchor(
	anchors: Array[Vector2i],
	anchor_lookup: Dictionary,
	candidate_anchor: Vector2i
) -> void:
	if anchor_lookup.has(candidate_anchor):
		return

	anchor_lookup[candidate_anchor] = true
	anchors.append(candidate_anchor)


func consume_egg(egg: Node) -> void:
	if egg == null or not is_instance_valid(egg) or not egg.has_method("consume"):
		clear_target()
		return

	if not egg.consume():
		clear_target()
		return

	target_egg = null
	creature.hunger = clamp(
		creature.hunger + creature.species_data.hunger_restore_amount,
		0.0,
		creature.species_data.max_hunger
	)
	creature.enter_walk()


func clear_target() -> void:
	target_egg = null

	# Drop queued target steps but let an already-started tile step finish.
	# Stopping movement mid-step would leave the sprite between grid anchors.
	creature.current_path.clear()
