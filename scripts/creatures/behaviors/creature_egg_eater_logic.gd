extends RefCounted

const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)

var creature: Node


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func update_egg_eater_behavior() -> void:
	if not creature.is_egg_eater() or creature.world_grid == null:
		return

	if creature.hunger > creature.species_data.hunger_search_threshold:
		return

	if creature.state == creature.State.DEAD or creature.state == creature.State.EATING or creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
		return

	var egg := find_nearest_edible_egg()

	if egg == null:
		return

	if is_egg_in_eating_range(egg):
		consume_egg(egg)
		return

	if creature.is_moving or creature.predator_path_retry_cooldown_remaining > 0.0:
		return

	build_path_to_egg(egg)
	creature.start_next_path_step_if_needed()

	if creature.current_path.is_empty():
		creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval


func find_nearest_edible_egg() -> Node:
	var best_target: Node = null
	var best_distance := INF

	for candidate: Node in creature.get_tree().get_nodes_in_group("eggs"):
		if not is_valid_egg_target(candidate):
			continue

		var egg_anchor: Vector2i = candidate.get("anchor_tile")
		var distance := float(max(abs(egg_anchor.x - creature.anchor_tile.x), abs(egg_anchor.y - creature.anchor_tile.y)))

		if distance > float(creature.species_data.predator_target_radius):
			continue

		if distance < best_distance:
			best_distance = distance
			best_target = candidate

	return best_target


func is_valid_egg_target(candidate: Node) -> bool:
	return candidate != null and is_instance_valid(candidate) and candidate.has_method("can_be_eaten") and candidate.can_be_eaten()


func is_egg_in_eating_range(egg: Node) -> bool:
	if egg == null:
		return false

	var egg_anchor: Vector2i = egg.get("anchor_tile")
	var egg_footprint := get_egg_footprint(egg)
	return creature.are_footprints_side_adjacent(creature.anchor_tile, creature.footprint_size, egg_anchor, egg_footprint)


func build_path_to_egg(egg: Node) -> void:
	if egg == null:
		return

	var egg_anchor: Vector2i = egg.get("anchor_tile")
	var egg_footprint := get_egg_footprint(egg)
	var approach_offsets: Array[Vector2i] = [
		Vector2i(-creature.footprint_size.x, 0),
		Vector2i(egg_footprint.x, 0),
		Vector2i(0, -creature.footprint_size.y),
		Vector2i(0, egg_footprint.y)
	]
	var best_anchor := INVALID_ANCHOR
	var best_distance := INF

	for offset in approach_offsets:
		var candidate_anchor: Vector2i = egg_anchor + offset

		if not creature.world_grid.can_place_footprint(candidate_anchor, creature.footprint_size, creature):
			continue

		var distance := float(creature.world_grid.estimate_path_steps(creature.anchor_tile, candidate_anchor))

		if distance < best_distance:
			best_distance = distance
			best_anchor = candidate_anchor

	if best_anchor == INVALID_ANCHOR:
		return

	creature.current_path = creature.world_grid.find_path(creature.anchor_tile, best_anchor, creature.footprint_size, creature, creature.max_path_search_tiles)


func get_egg_footprint(egg: Node) -> Vector2i:
	if egg.has_method("get_current_footprint"):
		return egg.get_current_footprint()

	return Vector2i(2, 2)


func consume_egg(egg: Node) -> void:
	if egg == null or not egg.has_method("consume"):
		return

	if not egg.consume():
		return

	creature.hunger = clamp(creature.hunger + creature.species_data.hunger_restore_amount, 0.0, creature.species_data.max_hunger)
	creature.enter_walk()
