extends RefCounted

const Duel = preload("res://scripts/combat/duel.gd")
const TARGET_RECHECK_INTERVAL := 2.0
const TARGET_SWITCH_ADVANTAGE_STEPS := 2
const TARGET_CANDIDATE_LIMIT := 3
const APPROACH_RECHECK_DISTANCE := 4

var creature: Node
var target_prey: Node = null
var target_recheck_remaining := 0.0
var approach_recheck_done := false
var locked_approach_anchor := Vector2i.ZERO
var has_locked_approach := false
var has_hunt_route := false


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func is_hunting() -> bool:
	return (
		is_instance_valid(target_prey)
		and creature.state != creature.State.COMBAT
		and creature.state != creature.State.DEAD
	)


func get_hunt_target() -> Node:
	return target_prey if is_instance_valid(target_prey) else null


func cancel_hunt_target() -> void:
	_clear_hunt_target()


func should_hold_at_locked_approach() -> bool:
	return (
		is_instance_valid(target_prey)
		and has_locked_approach
		and creature.anchor_tile == locked_approach_anchor
		and _remaining_route_steps() == 0
	)


func should_engage_target() -> bool:
	return (
		is_instance_valid(target_prey)
		and has_locked_approach
		and creature.is_moving
		and creature.pending_anchor_tile == locked_approach_anchor
		and _remaining_route_steps() == 1
		and _is_locked_approach_adjacent_to_target()
	)


func _is_locked_approach_adjacent_to_target() -> bool:
	if (
		creature.world_grid == null
		or not is_instance_valid(target_prey)
		or not creature.world_grid.creature_anchors.has(target_prey)
	):
		return false

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[target_prey]
	return are_footprints_side_adjacent(
		locked_approach_anchor,
		creature.footprint_size,
		prey_anchor,
		target_prey.footprint_size
	)


func update_predator_behavior(delta: float) -> void:
	if creature.species_data.is_predator():
		PerformanceStats.add_counter("predator_behavior_ticks")

	if not creature.species_data.is_predator() or creature.world_grid == null:
		_clear_hunt_target()
		return

	if creature.hunger > creature.species_data.hunger_search_threshold:
		_clear_hunt_target()
		return

	if (
		creature.state == creature.State.DEAD
		or creature.state == creature.State.EATING
		or creature.state == creature.State.LAYING_EGG
		or creature.state == creature.State.COMBAT
	):
		return

	var pending_prey: Node = creature.get_pending_duel_opponent()

	if pending_prey != null:
		_resolve_pending_duel(pending_prey)
		return

	# A dead/removed prey or a prey already engaged by another hunter is released
	# immediately. The same update may then select a different target.
	if target_prey != null and not _has_valid_hunt_target():
		_clear_hunt_target()

	if target_prey == null:
		target_recheck_remaining -= delta

		if target_recheck_remaining <= 0.0:
			_acquire_hunt_target()

		if target_prey == null:
			return
	elif not _is_target_engaged_by_creature():
		target_recheck_remaining -= delta

		if target_recheck_remaining <= 0.0:
			_recheck_hunt_target()
			target_recheck_remaining = TARGET_RECHECK_INTERVAL

	if not is_instance_valid(target_prey):
		_clear_hunt_target()
		return

	if is_prey_in_duel_range(target_prey):
		if creature.is_moving or bool(target_prey.get("is_moving")):
			_begin_duel_settlement(target_prey)
			return

		start_duel_with(target_prey)
		return

	if should_engage_target() and not _begin_target_engagement():
		# Another hunter won the engagement race. Drop this route and immediately
		# look for another available prey instead of waiting for the next interval.
		_clear_hunt_target()
		_acquire_hunt_target()
		return

	if _is_target_engaged_by_creature():
		if should_abort_target_engagement():
			_cancel_target_engagement()
			return

		if should_hold_at_locked_approach():
			_clear_hunt_target()
			return

		if creature.is_moving:
			return

		if _remaining_route_steps() > 0:
			creature.start_next_path_step_if_needed()
		return

	if _should_recheck_approach_side():
		_refresh_approach_path()

	if creature.is_moving:
		return

	if _remaining_route_steps() == 0:
		if creature.predator_path_retry_cooldown_remaining <= 0.0:
			_refresh_approach_path()

			if _remaining_route_steps() == 0:
				# The locked target currently has no reachable approach side.
				creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval
		return

	creature.start_next_path_step_if_needed()


func _has_valid_hunt_target() -> bool:
	if not is_instance_valid(target_prey):
		return false

	if not target_prey.has_method("can_be_hunted") or not target_prey.can_be_hunted():
		return false

	if _is_prey_claimed_by_other_hunter(target_prey):
		return false

	if target_prey.has_method("get_pending_duel_opponent"):
		var pending_opponent: Node = target_prey.get_pending_duel_opponent()

		if pending_opponent != null and pending_opponent != creature:
			return false

	if target_prey.has_method("get_is_predator"):
		return not bool(target_prey.get_is_predator())

	var target_species := target_prey.get("species_data") as CreatureSpeciesData
	return target_species != null and not target_species.is_predator()


func _is_prey_claimed_by_other_hunter(prey: Node) -> bool:
	if not is_instance_valid(prey) or not prey.has_method("get_combat_engagement_hunter"):
		return false

	var engagement_hunter: Node = prey.get_combat_engagement_hunter()
	return engagement_hunter != null and engagement_hunter != creature


func _is_target_engaged_by_creature() -> bool:
	return (
		is_instance_valid(target_prey)
		and target_prey.has_method("get_combat_engagement_hunter")
		and target_prey.get_combat_engagement_hunter() == creature
	)


func should_abort_target_engagement() -> bool:
	return (
		_is_target_engaged_by_creature()
		and not creature.is_moving
		and _remaining_route_steps() == 0
		and creature.anchor_tile != locked_approach_anchor
	)


func _cancel_target_engagement() -> void:
	if is_instance_valid(target_prey) and target_prey.has_method("cancel_combat_engagement"):
		target_prey.cancel_combat_engagement(creature)


func _begin_target_engagement() -> bool:
	if (
		not is_instance_valid(target_prey)
		or _is_prey_claimed_by_other_hunter(target_prey)
		or not target_prey.has_method("begin_combat_engagement")
	):
		return false

	target_prey.begin_combat_engagement(creature)
	return _is_target_engaged_by_creature()


func _clear_hunt_target() -> void:
	if is_instance_valid(target_prey) and target_prey.has_method("cancel_combat_engagement"):
		target_prey.cancel_combat_engagement(creature)

	target_prey = null
	target_recheck_remaining = 0.0
	approach_recheck_done = false
	locked_approach_anchor = Vector2i.ZERO
	has_locked_approach = false

	if has_hunt_route:
		_clear_predator_route()

	has_hunt_route = false


func _clear_predator_route() -> void:
	if creature.movement_controller != null and creature.movement_controller.has_method("clear_behavior_route"):
		creature.movement_controller.clear_behavior_route()


func _replace_predator_route(path: Array) -> void:
	if creature.movement_controller != null and creature.movement_controller.has_method("replace_behavior_route"):
		creature.movement_controller.replace_behavior_route(path)


func _acquire_hunt_target() -> void:
	# A failed acquisition must not scan the population again every physics frame.
	target_recheck_remaining = TARGET_RECHECK_INTERVAL

	var candidates := find_nearest_prey_candidates(TARGET_CANDIDATE_LIMIT)
	var plan := _find_best_hunt_plan(candidates)

	if plan.is_empty():
		return

	_commit_hunt_plan(plan)


func _recheck_hunt_target() -> void:
	var candidates := find_nearest_prey_candidates(
		TARGET_CANDIDATE_LIMIT,
		target_prey
	)
	var candidate_plan := _find_best_hunt_plan(candidates)

	if candidate_plan.is_empty():
		return

	var candidate_steps := int(candidate_plan.get("route_steps", 0))

	if candidate_steps + TARGET_SWITCH_ADVANTAGE_STEPS > _remaining_route_steps():
		return

	_commit_hunt_plan(candidate_plan)


func _find_best_hunt_plan(candidates: Array[Node]) -> Dictionary:
	var best_plan: Dictionary = {}
	var best_route_steps := 2147483647
	var origin_anchor: Vector2i = creature.get_navigation_anchor()
	var active_step_count := 1 if creature.is_moving else 0

	for prey: Node in candidates:
		if not is_valid_prey(prey):
			continue

		var plan: Dictionary = {}

		if _is_prey_in_duel_range_from_anchor(prey, origin_anchor):
			plan = {
				"prey": prey,
				"path": [],
				"approach_anchor": origin_anchor,
				"has_approach": true,
				"route_steps": active_step_count
			}
		else:
			plan = _find_best_approach_plan(prey, origin_anchor)

			if plan.is_empty():
				continue

			var path: Array = plan.get("path", []) as Array
			plan["prey"] = prey
			plan["route_steps"] = path.size() + active_step_count

		var route_steps := int(plan.get("route_steps", 0))

		if route_steps < best_route_steps:
			best_route_steps = route_steps
			best_plan = plan

	return best_plan


func _commit_hunt_plan(plan: Dictionary) -> void:
	var prey := plan.get("prey", null) as Node

	if not is_instance_valid(prey):
		return

	var path: Array = plan.get("path", []) as Array
	var approach_anchor: Vector2i = plan.get("approach_anchor", Vector2i.ZERO)
	var has_approach := bool(plan.get("has_approach", false))
	_commit_hunt_target(prey, path, approach_anchor, has_approach)


func _commit_hunt_target(
	prey: Node,
	path: Array,
	approach_anchor: Vector2i,
	has_approach: bool = true
) -> void:
	target_prey = prey
	target_recheck_remaining = TARGET_RECHECK_INTERVAL
	approach_recheck_done = false
	locked_approach_anchor = approach_anchor
	has_locked_approach = has_approach
	has_hunt_route = true
	_replace_predator_route(path)


func _should_recheck_approach_side() -> bool:
	return (
		has_locked_approach
		and not approach_recheck_done
		and _remaining_route_steps() <= APPROACH_RECHECK_DISTANCE
	)


func _refresh_approach_path() -> void:
	if not is_instance_valid(target_prey):
		return

	var plan := _find_best_approach_plan(
		target_prey,
		creature.get_navigation_anchor()
	)

	if not plan.is_empty():
		var path: Array = plan.get("path", []) as Array
		has_hunt_route = true
		_replace_predator_route(path)
		locked_approach_anchor = plan.get("approach_anchor", Vector2i.ZERO)
		has_locked_approach = bool(plan.get("has_approach", false))

	approach_recheck_done = true


func _remaining_route_steps() -> int:
	if (
		creature.movement_controller != null
		and creature.movement_controller.has_method("get_remaining_route_steps")
	):
		return int(creature.movement_controller.get_remaining_route_steps())

	return 1 if creature.is_moving else 0


func find_nearest_prey() -> Node:
	var candidates := find_nearest_prey_candidates(1)
	return candidates[0] if not candidates.is_empty() else null


func find_nearest_prey_candidates(
	max_candidates: int = TARGET_CANDIDATE_LIMIT,
	excluded_prey: Node = null
) -> Array[Node]:
	PerformanceStats.add_counter("predator_prey_searches")

	var result: Array[Node] = []

	if creature.world_grid == null or max_candidates <= 0:
		return result

	var ranked_candidates: Array[Dictionary] = []
	var candidate_checks := 0
	var origin_anchor: Vector2i = creature.get_navigation_anchor()

	for candidate_variant: Variant in creature.world_grid.creature_anchors.keys():
		candidate_checks += 1

		if not (candidate_variant is Node):
			continue

		var candidate := candidate_variant as Node

		if candidate == excluded_prey or not is_valid_prey(candidate):
			continue

		var candidate_anchor: Vector2i = creature.world_grid.creature_anchors.get(
			candidate,
			creature.anchor_tile
		)
		var distance := int(creature.world_grid.estimate_path_steps(
			origin_anchor,
			candidate_anchor
		))

		if distance > creature.species_data.predator_target_radius:
			continue

		_insert_ranked_prey_candidate(
			ranked_candidates,
			{"prey": candidate, "distance": distance},
			max_candidates
		)

	PerformanceStats.add_counter("predator_prey_candidates", candidate_checks)

	for candidate_data: Dictionary in ranked_candidates:
		var prey := candidate_data.get("prey", null) as Node

		if is_instance_valid(prey):
			result.append(prey)

	return result


func _insert_ranked_prey_candidate(
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


func is_valid_prey(candidate: Node) -> bool:
	if candidate == null or candidate == creature or not is_instance_valid(candidate):
		return false

	if not candidate.has_method("can_be_hunted") or not candidate.can_be_hunted():
		return false

	if candidate.has_method("get_pending_duel_opponent"):
		var pending_opponent: Node = candidate.get_pending_duel_opponent()

		if pending_opponent != null and pending_opponent != creature:
			return false

	if _is_prey_claimed_by_other_hunter(candidate):
		return false

	if candidate.has_method("get_is_predator"):
		return not bool(candidate.call("get_is_predator"))

	var candidate_species := candidate.get("species_data") as CreatureSpeciesData
	return candidate_species != null and not candidate_species.is_predator()


func is_prey_in_duel_range(prey: Node) -> bool:
	return _is_prey_in_duel_range_from_anchor(prey, creature.anchor_tile)


func _is_prey_in_duel_range_from_anchor(prey: Node, hunter_anchor: Vector2i) -> bool:
	if (
		creature.world_grid == null
		or not is_instance_valid(prey)
		or not creature.world_grid.creature_anchors.has(prey)
	):
		return false

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	return are_footprints_side_adjacent(
		hunter_anchor,
		creature.footprint_size,
		prey_anchor,
		prey.footprint_size
	)


func _resolve_pending_duel(prey: Node) -> void:
	if not is_instance_valid(prey):
		creature.cancel_pending_duel()
		return

	if not prey.has_method("can_be_hunted") or not bool(prey.can_be_hunted()):
		_cancel_duel_settlement(prey)
		return

	if creature.is_moving or bool(prey.get("is_moving")):
		return

	if is_prey_in_duel_range(prey):
		start_duel_with(prey)
		return

	_cancel_duel_settlement(prey)


func _begin_duel_settlement(prey: Node) -> void:
	if not is_instance_valid(prey):
		return

	creature.begin_duel_settlement(prey)

	if prey.has_method("begin_duel_settlement"):
		prey.begin_duel_settlement(creature)


func _cancel_duel_settlement(prey: Node) -> void:
	creature.cancel_pending_duel(prey)

	if is_instance_valid(prey) and prey.has_method("cancel_pending_duel"):
		prey.cancel_pending_duel(creature)


func are_footprints_side_adjacent(
	a_anchor: Vector2i,
	a_size: Vector2i,
	b_anchor: Vector2i,
	b_size: Vector2i
) -> bool:
	var a_left := a_anchor.x
	var a_right := a_anchor.x + a_size.x - 1
	var a_top := a_anchor.y
	var a_bottom := a_anchor.y + a_size.y - 1
	var b_left := b_anchor.x
	var b_right := b_anchor.x + b_size.x - 1
	var b_top := b_anchor.y
	var b_bottom := b_anchor.y + b_size.y - 1

	var vertical_overlap: int = min(a_bottom, b_bottom) - max(a_top, b_top) + 1

	if vertical_overlap > 0 and (a_right + 1 == b_left or b_right + 1 == a_left):
		return true

	var horizontal_overlap: int = min(a_right, b_right) - max(a_left, b_left) + 1

	if horizontal_overlap > 0 and (a_bottom + 1 == b_top or b_bottom + 1 == a_top):
		return true

	return false


func build_path_to_prey(prey: Node) -> void:
	var plan := _find_best_approach_plan(prey, creature.get_navigation_anchor())

	if plan.is_empty():
		if has_hunt_route:
			_clear_predator_route()
		has_hunt_route = false
		return

	has_hunt_route = true
	_replace_predator_route(plan.get("path", []) as Array)


func _find_best_approach_plan(prey: Node, origin_anchor: Vector2i) -> Dictionary:
	PerformanceStats.add_counter("predator_path_rebuild_requests")

	if (
		creature.world_grid == null
		or not is_instance_valid(prey)
		or not creature.world_grid.creature_anchors.has(prey)
	):
		return {}

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	var ranked_anchors: Array[Vector2i] = []

	for candidate_anchor: Vector2i in _build_side_approach_anchors(
		prey_anchor,
		prey.footprint_size
	):
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

	for approach_anchor: Vector2i in ranked_anchors:
		var estimated_steps := int(creature.world_grid.estimate_path_steps(
			origin_anchor,
			approach_anchor
		))

		# Anchors are sorted by a lower-bound distance. Once that bound cannot beat
		# the best real path already found, later anchors cannot improve the plan.
		if estimated_steps >= best_path_steps:
			break

		# find_path() returns an empty array both for failure and for start == goal.
		if approach_anchor == origin_anchor:
			return {
				"path": [],
				"approach_anchor": approach_anchor,
				"has_approach": true
			}

		var path: Array[Vector2i] = creature.world_grid.find_path(
			origin_anchor,
			approach_anchor,
			creature.footprint_size,
			creature,
			creature.max_path_search_tiles
		)

		if path.is_empty() or path.size() >= best_path_steps:
			continue

		best_path_steps = path.size()
		best_plan = {
			"path": path,
			"approach_anchor": approach_anchor,
			"has_approach": true
		}

	return best_plan


func _build_side_approach_anchors(
	prey_anchor: Vector2i,
	prey_size: Vector2i
) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var anchor_lookup: Dictionary = {}

	# Any overlap of at least one tile along a side is valid. With the current
	# shared 2x2 footprint this produces center plus +/-1 tile shifts on every
	# side, while full corner diagonals remain excluded.
	for vertical_shift in range(-(creature.footprint_size.y - 1), prey_size.y):
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(-creature.footprint_size.x, vertical_shift)
		)
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(prey_size.x, vertical_shift)
		)

	for horizontal_shift in range(-(creature.footprint_size.x - 1), prey_size.x):
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(horizontal_shift, -creature.footprint_size.y)
		)
		_append_unique_anchor(
			anchors,
			anchor_lookup,
			prey_anchor + Vector2i(horizontal_shift, prey_size.y)
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


func _insert_approach_anchor_by_distance(
	ranked_anchors: Array[Vector2i],
	candidate_anchor: Vector2i,
	origin_anchor: Vector2i
) -> void:
	var candidate_distance: int = creature.world_grid.estimate_path_steps(
		origin_anchor,
		candidate_anchor
	)
	var insert_index: int = ranked_anchors.size()

	for index in range(ranked_anchors.size()):
		var current_distance: int = creature.world_grid.estimate_path_steps(
			origin_anchor,
			ranked_anchors[index]
		)

		if candidate_distance < current_distance:
			insert_index = index
			break

	ranked_anchors.insert(insert_index, candidate_anchor)


func start_duel_with(opponent: Node) -> Duel:
	if opponent == null or opponent == creature:
		return null

	if not creature.can_fight():
		return null

	if not opponent.has_method("can_be_hunted") or not opponent.can_be_hunted():
		return null

	if not is_prey_in_duel_range(opponent):
		return null

	creature.face_target(opponent)

	if opponent.has_method("face_target"):
		opponent.face_target(creature)

	var duel := Duel.new()
	var duel_parent := creature.get_tree().current_scene

	if duel_parent == null:
		duel_parent = creature.get_parent()

	if duel_parent == null:
		return null

	duel_parent.add_child(duel)

	var finished_callable := Callable(creature, "_on_duel_finished")

	if duel.duel_finished.is_connected(finished_callable) == false:
		duel.duel_finished.connect(finished_callable)

	duel.setup(creature, opponent, creature, 1.0)
	target_prey = null
	target_recheck_remaining = 0.0
	approach_recheck_done = false
	locked_approach_anchor = Vector2i.ZERO
	has_locked_approach = false
	has_hunt_route = false
	return duel
