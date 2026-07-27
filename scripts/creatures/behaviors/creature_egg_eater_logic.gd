extends RefCounted

const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)
const FOOD_SEARCH_INTERVAL := 0.5
const RETARGET_DISTANCE_ADVANTAGE := 2.0

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
		var nearby_egg := find_nearest_edible_egg()

		if should_retarget_to(nearby_egg):
			target_egg = nearby_egg
			# Keep an active tile step intact, but discard old queued steps.
			creature.current_path.clear()

	if target_egg != null:
		update_current_target()


func update_current_target() -> void:
	if target_egg == null or not is_valid_egg_target(target_egg):
		clear_target()
		return

	if is_egg_in_eating_range(target_egg):
		consume_egg(target_egg)
		return

	if creature.is_moving:
		return

	if not creature.current_path.is_empty():
		creature.start_next_path_step_if_needed()
		return

	if creature.predator_path_retry_cooldown_remaining > 0.0:
		return

	build_path_to_egg(target_egg)
	creature.start_next_path_step_if_needed()

	if creature.current_path.is_empty() and not creature.is_moving:
		creature.predator_path_retry_cooldown_remaining = creature.predator_path_retry_interval


func find_nearest_edible_egg() -> Node:
	var best_target: Node = null
	var best_distance := INF

	for candidate: Node in creature.get_tree().get_nodes_in_group("eggs"):
		if not is_valid_egg_target(candidate):
			continue

		var egg_anchor: Vector2i = candidate.get("anchor_tile")
		var distance := float(max(abs(egg_anchor.x - creature.anchor_tile.x), abs(egg_anchor.y - creature.anchor_tile.y)))

		if distance > float(_get_active_target_radius()):
			continue

		if distance < best_distance:
			best_distance = distance
			best_target = candidate

	return best_target


func should_retarget_to(candidate: Node) -> bool:
	if candidate == null or not is_valid_egg_target(candidate):
		return false

	if target_egg == null or not is_valid_egg_target(target_egg):
		return true

	if candidate == target_egg:
		return false

	return get_egg_distance(target_egg) - get_egg_distance(candidate) >= RETARGET_DISTANCE_ADVANTAGE


func get_egg_distance(egg: Node) -> float:
	var egg_anchor: Vector2i = egg.get("anchor_tile")
	return float(max(
		abs(egg_anchor.x - creature.anchor_tile.x),
		abs(egg_anchor.y - creature.anchor_tile.y)
	))


func is_valid_egg_target(candidate: Node) -> bool:
	if (
		candidate == null
		or not is_instance_valid(candidate)
		or candidate.is_queued_for_deletion()
	):
		return false

	if not candidate.has_method("can_be_eaten") or not candidate.can_be_eaten():
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


func build_path_to_egg(egg: Node) -> void:
	if egg == null or not is_instance_valid(egg):
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
	var best_distance: float = INF

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

	creature.current_path = creature.world_grid.find_path(
		creature.anchor_tile,
		best_anchor,
		creature.footprint_size,
		creature,
		creature.max_path_search_tiles
	)

	# Keep one zero-length final step as an interaction hold. Without it, the
	# generic WALK logic immediately chooses a random wander step in the same
	# physics frame in which the egg eater reaches the egg. The next frame then
	# starts with the creature already walking away and the egg is never eaten.
	if not creature.current_path.is_empty():
		creature.current_path.append(best_anchor)


func get_egg_footprint(egg: Node) -> Vector2i:
	if egg.has_method("get_current_footprint"):
		return egg.get_current_footprint()

	return Vector2i(2, 2)


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
