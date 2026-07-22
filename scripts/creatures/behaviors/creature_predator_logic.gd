extends RefCounted

const Duel = preload("res://scripts/combat/duel.gd")
const TARGET_RECHECK_INTERVAL := 2.0
const TARGET_SWITCH_ADVANTAGE_STEPS := 2
const APPROACH_RECHECK_DISTANCE := 4

var creature: Node
var target_prey: Node = null
var target_recheck_remaining := 0.0
var approach_recheck_done := false
var locked_approach_anchor := Vector2i.ZERO
var has_locked_approach := false
var last_found_approach_anchor := Vector2i.ZERO
var has_last_found_approach_anchor := false


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func is_hunting() -> bool:
	return (
		target_prey != null
		and creature.state != creature.State.COMBAT
		and creature.state != creature.State.DEAD
	)


func get_hunt_target() -> Node:
	return target_prey if is_instance_valid(target_prey) else null


func cancel_hunt_target() -> void:
	_clear_hunt_target()


func should_hold_at_locked_approach() -> bool:
	return (
		target_prey != null
		and has_locked_approach
		and creature.anchor_tile == locked_approach_anchor
		and creature.current_path.is_empty()
	)


func should_engage_target() -> bool:
	return (
		target_prey != null
		and has_locked_approach
		and creature.is_moving
		and creature.pending_anchor_tile == locked_approach_anchor
		and creature.current_path.is_empty()
		and _is_locked_approach_adjacent_to_target()
	)


func _is_locked_approach_adjacent_to_target() -> bool:
	if creature.world_grid == null or target_prey == null or not creature.world_grid.creature_anchors.has(target_prey):
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

	if creature.state == creature.State.DEAD or creature.state == creature.State.EATING or creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
		return

	var pending_prey: Node = creature.get_pending_duel_opponent()

	if pending_prey != null:
		_resolve_pending_duel(pending_prey)
		return

	if not _has_valid_hunt_target():
		_acquire_hunt_target()
	elif not _is_target_engaged_by_creature():
		target_recheck_remaining -= delta

		if target_recheck_remaining <= 0.0:
			_recheck_hunt_target()
			target_recheck_remaining = TARGET_RECHECK_INTERVAL

	if target_prey == null:
		return

	if is_prey_in_duel_range(target_prey):
		if creature.is_moving or bool(target_prey.get("is_moving")):
			_begin_duel_settlement(target_prey)
			return

		start_duel_with(target_prey)
		return

	if should_engage_target():
		_begin_target_engagement()

	if _is_target_engaged_by_creature():
		if should_abort_target_engagement():
			_cancel_target_engagement()
			return

		if should_hold_at_locked_approach():
			_clear_hunt_target()
			return

		if creature.is_moving:
			return

		if not creature.current_path.is_empty():
			creature.start_next_path_step_if_needed()
		return

	if _should_recheck_approach_side():
		_refresh_approach_path()

	if creature.is_moving:
		return

	if creature.current_path.is_empty():
		if creature.predator_path_retry_cooldown_remaining <= 0.0:
			_refresh_approach_path()

			if creature.current_path.is_empty():
				# The locked target currently has no reachable approach side.
				creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval
		return

	creature.start_next_path_step_if_needed()


func _has_valid_hunt_target() -> bool:
	if target_prey == null or not is_instance_valid(target_prey):
		return false

	if not target_prey.has_method("can_be_hunted") or not target_prey.can_be_hunted():
		return false

	if target_prey.has_method("get_is_predator"):
		return not bool(target_prey.get_is_predator())

	var target_species := target_prey.get("species_data") as CreatureSpeciesData
	return target_species != null and not target_species.is_predator()


func _is_target_engaged_by_creature() -> bool:
	return (
		target_prey != null
		and target_prey.has_method("get_combat_engagement_hunter")
		and target_prey.get_combat_engagement_hunter() == creature
	)


func should_abort_target_engagement() -> bool:
	return (
		_is_target_engaged_by_creature()
		and not creature.is_moving
		and creature.current_path.is_empty()
		and creature.anchor_tile != locked_approach_anchor
	)


func _cancel_target_engagement() -> void:
	if target_prey != null and target_prey.has_method("cancel_combat_engagement"):
		target_prey.cancel_combat_engagement(creature)


func _begin_target_engagement() -> void:
	if target_prey != null and target_prey.has_method("begin_combat_engagement"):
		target_prey.begin_combat_engagement(creature)


func _clear_hunt_target() -> void:
	if target_prey != null and target_prey.has_method("cancel_combat_engagement"):
		target_prey.cancel_combat_engagement(creature)

	target_prey = null
	target_recheck_remaining = 0.0
	approach_recheck_done = false
	has_locked_approach = false


func _acquire_hunt_target() -> void:
	if creature.predator_path_retry_cooldown_remaining > 0.0:
		return

	var prey: Node = find_nearest_prey()

	if prey == null:
		return

	if is_prey_in_duel_range(prey):
		_commit_hunt_target(prey, [], Vector2i.ZERO, false)
		return

	var path: Array[Vector2i] = _find_best_approach_path(prey, creature.get_navigation_anchor())

	if path.is_empty():
		creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval
		return

	_commit_hunt_target(prey, path, last_found_approach_anchor, has_last_found_approach_anchor)


func _recheck_hunt_target() -> void:
	var candidate: Node = find_nearest_prey()

	if candidate == null or candidate == target_prey:
		return

	if is_prey_in_duel_range(candidate):
		_commit_hunt_target(candidate, [], Vector2i.ZERO, false)
		return

	var candidate_path: Array[Vector2i] = _find_best_approach_path(
		candidate,
		creature.get_navigation_anchor()
	)

	if candidate_path.is_empty():
		return

	if candidate_path.size() + TARGET_SWITCH_ADVANTAGE_STEPS > _remaining_route_steps():
		return

	_commit_hunt_target(candidate, candidate_path, last_found_approach_anchor, has_last_found_approach_anchor)


func _commit_hunt_target(
	prey: Node,
	path: Array[Vector2i],
	approach_anchor: Vector2i,
	has_approach: bool = true
) -> void:
	target_prey = prey
	target_recheck_remaining = TARGET_RECHECK_INTERVAL
	approach_recheck_done = false
	locked_approach_anchor = approach_anchor
	has_locked_approach = has_approach
	creature.current_path = path


func _should_recheck_approach_side() -> bool:
	return not approach_recheck_done and _remaining_route_steps() <= APPROACH_RECHECK_DISTANCE


func _refresh_approach_path() -> void:
	if target_prey == null:
		return

	var path: Array[Vector2i] = _find_best_approach_path(
		target_prey,
		creature.get_navigation_anchor()
	)

	if not path.is_empty():
		creature.current_path = path
		locked_approach_anchor = last_found_approach_anchor
		has_locked_approach = has_last_found_approach_anchor

	approach_recheck_done = true


func _remaining_route_steps() -> int:
	return creature.current_path.size() + (1 if creature.is_moving else 0)


func find_nearest_prey() -> Node:
	PerformanceStats.add_counter("predator_prey_searches")

	if creature.world_grid == null:
		return null

	var best_target: Node = null
	var best_distance: float = INF
	var candidate_checks := 0

	for candidate in creature.world_grid.creature_anchors.keys():
		candidate_checks += 1
		if not is_valid_prey(candidate):
			continue

		var candidate_anchor: Vector2i = creature.world_grid.creature_anchors.get(candidate, creature.anchor_tile)
		var distance: float = float(max(abs(candidate_anchor.x - creature.anchor_tile.x), abs(candidate_anchor.y - creature.anchor_tile.y)))

		if distance > float(creature.species_data.predator_target_radius):
			continue

		if distance < best_distance:
			best_distance = distance
			best_target = candidate

	PerformanceStats.add_counter("predator_prey_candidates", candidate_checks)
	return best_target


func is_valid_prey(candidate: Node) -> bool:
	if candidate == null or candidate == creature or not is_instance_valid(candidate):
		return false

	if not candidate.has_method("can_be_hunted") or not candidate.can_be_hunted():
		return false

	if candidate.has_method("is_waiting_for_duel") and bool(candidate.is_waiting_for_duel()):
		return false

	if candidate.has_method("is_waiting_for_combat_engagement") and bool(candidate.is_waiting_for_combat_engagement()):
		return false

	if candidate.has_method("get_is_predator"):
		return not bool(candidate.call("get_is_predator"))

	var candidate_species := candidate.get("species_data") as CreatureSpeciesData
	return candidate_species != null and not candidate_species.is_predator()


func is_prey_in_duel_range(prey: Node) -> bool:
	if creature.world_grid == null or prey == null or not creature.world_grid.creature_anchors.has(prey):
		return false

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	return are_footprints_side_adjacent(creature.anchor_tile, creature.footprint_size, prey_anchor, prey.footprint_size)


func _resolve_pending_duel(prey: Node) -> void:
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
	creature.begin_duel_settlement(prey)

	if prey.has_method("begin_duel_settlement"):
		prey.begin_duel_settlement(creature)


func _cancel_duel_settlement(prey: Node) -> void:
	creature.cancel_pending_duel(prey)

	if prey.has_method("cancel_pending_duel"):
		prey.cancel_pending_duel(creature)


func are_footprints_side_adjacent(a_anchor: Vector2i, a_size: Vector2i, b_anchor: Vector2i, b_size: Vector2i) -> bool:
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
	var path: Array[Vector2i] = _find_best_approach_path(prey, creature.get_navigation_anchor())
	creature.current_path = path


func _find_best_approach_path(prey: Node, origin_anchor: Vector2i) -> Array[Vector2i]:
	PerformanceStats.add_counter("predator_path_rebuild_requests")
	has_last_found_approach_anchor = false

	if creature.world_grid == null or prey == null or not creature.world_grid.creature_anchors.has(prey):
		return []

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	var approach_offsets: Array[Vector2i] = [
		Vector2i(-creature.footprint_size.x, 0),
		Vector2i(prey.footprint_size.x, 0),
		Vector2i(0, -creature.footprint_size.y),
		Vector2i(0, prey.footprint_size.y)
	]
	var ranked_anchors: Array[Vector2i] = []

	for offset in approach_offsets:
		var candidate_anchor: Vector2i = prey_anchor + offset

		if not creature.world_grid.can_place_footprint(candidate_anchor, creature.footprint_size, creature):
			continue

		_insert_approach_anchor_by_distance(ranked_anchors, candidate_anchor, origin_anchor)

	for approach_anchor in ranked_anchors:
		var path: Array[Vector2i] = creature.world_grid.find_path(
			origin_anchor,
			approach_anchor,
			creature.footprint_size,
			creature,
			creature.max_path_search_tiles
		)

		if path.is_empty():
			continue

		last_found_approach_anchor = approach_anchor
		has_last_found_approach_anchor = true
		return path

	return []


func _insert_approach_anchor_by_distance(ranked_anchors: Array[Vector2i], candidate_anchor: Vector2i, origin_anchor: Vector2i) -> void:
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
	return duel
