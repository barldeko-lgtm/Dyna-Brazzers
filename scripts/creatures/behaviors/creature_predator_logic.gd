extends RefCounted

const Duel = preload("res://scripts/combat/duel.gd")
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)

var creature: Node


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func update_predator_behavior() -> void:
	if creature.species_data.is_predator():
		PerformanceStats.add_counter("predator_behavior_ticks")

	if not creature.species_data.is_predator() or creature.world_grid == null:
		return

	if creature.hunger > creature.species_data.hunger_search_threshold:
		return

	if creature.state == creature.State.DEAD or creature.state == creature.State.EATING or creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
		return

	var prey: Node = find_nearest_prey()

	if prey == null:
		return

	if is_prey_in_duel_range(prey):
		start_duel_with(prey)
		return

	if creature.is_moving:
		return

	if creature.predator_path_retry_cooldown_remaining > 0.0:
		return

	build_path_to_prey(prey)
	creature.start_next_path_step_if_needed()

	if creature.current_path.is_empty():
		# Prey is currently unreachable (e.g. boxed in by other creatures).
		# Back off instead of rebuilding a full path search every physics
		# frame until it becomes reachable again.
		creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval


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

	if candidate.has_method("get_is_predator"):
		return not bool(candidate.call("get_is_predator"))

	var candidate_species := candidate.get("species_data") as CreatureSpeciesData
	return candidate_species != null and not candidate_species.is_predator()


func is_prey_in_duel_range(prey: Node) -> bool:
	if creature.world_grid == null or prey == null or not creature.world_grid.creature_anchors.has(prey):
		return false

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	return are_footprints_side_adjacent(creature.anchor_tile, creature.footprint_size, prey_anchor, prey.footprint_size)


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
	PerformanceStats.add_counter("predator_path_rebuild_requests")

	if creature.world_grid == null or prey == null or not creature.world_grid.creature_anchors.has(prey):
		return

	var prey_anchor: Vector2i = creature.world_grid.creature_anchors[prey]
	var approach_offsets: Array[Vector2i] = [
		Vector2i(-creature.footprint_size.x, 0),
		Vector2i(prey.footprint_size.x, 0),
		Vector2i(0, -creature.footprint_size.y),
		Vector2i(0, prey.footprint_size.y)
	]
	var best_anchor := INVALID_ANCHOR
	var best_distance: float = INF

	for offset in approach_offsets:
		var candidate_anchor: Vector2i = prey_anchor + offset

		if not creature.world_grid.can_place_footprint(candidate_anchor, creature.footprint_size, creature):
			continue

		var distance: float = float(creature.world_grid.estimate_path_steps(creature.anchor_tile, candidate_anchor))

		if distance < best_distance:
			best_distance = distance
			best_anchor = candidate_anchor

	if best_anchor == INVALID_ANCHOR:
		return

	creature.current_path = creature.world_grid.find_path(creature.anchor_tile, best_anchor, creature.footprint_size, creature, creature.max_path_search_tiles)


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
