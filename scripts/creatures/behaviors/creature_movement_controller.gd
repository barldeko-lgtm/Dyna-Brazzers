extends RefCounted

# Creature-owned movement and indirect-order boundary. External systems ask the
# creature to apply or cancel routes; only this controller touches route/FSM
# internals, keeping callers insulated from future creature.gd changes.

const INDIRECT_ORDER_STATE_TIMER := 30.0

var creature: Node
var state_idle: int
var state_walk: int
var state_seek_food: int


func _init(owner: Node, idle_state: int, walk_state: int, seek_food_state: int) -> void:
	creature = owner
	state_idle = idle_state
	state_walk = walk_state
	state_seek_food = seek_food_state


func update_idle(delta: float) -> void:
	var timer := float(creature.get("state_timer")) - delta
	creature.set("state_timer", timer)

	if timer <= 0.0 and creature.has_method("enter_walk"):
		creature.call("enter_walk")


func update_walk(delta: float) -> void:
	var timer := float(creature.get("state_timer")) - delta
	creature.set("state_timer", timer)

	if bool(creature.get("is_moving")):
		return

	if timer <= 0.0:
		if creature.has_method("enter_idle"):
			creature.call("enter_idle")
		return

	var path_variant: Variant = creature.get("current_path")

	if not (path_variant is Array) or (path_variant as Array).is_empty():
		if creature.has_method("is_hunting") and bool(creature.is_hunting()):
			return

		if creature.has_method("should_hold_at_locked_approach") and bool(creature.should_hold_at_locked_approach()):
			return

		choose_random_wander_step()

	start_next_path_step_if_needed()


func choose_random_wander_step() -> void:
	var world_grid: Node = creature.get("world_grid")

	if world_grid == null:
		return

	var anchor: Vector2i = creature.get("anchor_tile")
	var footprint: Vector2i = creature.get("footprint_size")
	var neighbors_variant: Variant = world_grid.call(
		"get_neighbors", anchor, footprint, creature
	)

	if not (neighbors_variant is Array):
		return

	var neighbors: Array[Vector2i] = []

	for neighbor_variant: Variant in neighbors_variant:
		if neighbor_variant is Vector2i:
			neighbors.append(neighbor_variant)

	if neighbors.is_empty():
		return

	var random_index := randi_range(0, neighbors.size() - 1)
	var route: Array[Vector2i] = [neighbors[random_index]]
	creature.set("current_path", route)


func get_navigation_anchor() -> Vector2i:
	var anchor_variant: Variant = creature.get(
		"pending_anchor_tile" if bool(creature.get("is_moving")) else "anchor_tile"
	)

	return anchor_variant if anchor_variant is Vector2i else Vector2i.ZERO


# Internal autonomous behaviours such as predator hunting replace only queued
# steps here. An already active smooth step and its reservation are preserved.
func replace_behavior_route(path: Array) -> void:
	creature.set("current_path", _normalize_route(path))


func clear_behavior_route() -> void:
	_clear_queued_path()


func get_queued_route_step_count() -> int:
	var path_variant: Variant = creature.get("current_path")

	if not (path_variant is Array):
		return 0

	return (path_variant as Array).size()


func get_remaining_route_steps() -> int:
	return get_queued_route_step_count() + (1 if bool(creature.get("is_moving")) else 0)


func start_next_path_step_if_needed() -> void:
	if bool(creature.get("is_moving")):
		return

	var path_variant: Variant = creature.get("current_path")

	if not (path_variant is Array) or (path_variant as Array).is_empty():
		return

	var current_path := path_variant as Array
	var next_anchor_variant: Variant = current_path[0]

	if not (next_anchor_variant is Vector2i):
		current_path.remove_at(0)
		creature.set("current_path", current_path)
		return

	var next_anchor: Vector2i = next_anchor_variant
	var world_grid: Node = creature.get("world_grid")

	if world_grid == null:
		return

	var footprint: Vector2i = creature.get("footprint_size")

	if not bool(world_grid.call(
		"reserve_movement_destination", creature, next_anchor, footprint
	)):
		clear_path()
		return

	current_path.remove_at(0)
	creature.set("current_path", current_path)
	creature.set("pending_anchor_tile", next_anchor)

	var target_position: Vector2 = world_grid.call(
		"anchor_to_world_position", next_anchor, footprint
	)
	var body := creature as CharacterBody2D

	if body == null:
		world_grid.call("release_movement_reservation", creature, footprint)
		return

	creature.set("movement_target_position", target_position)
	creature.set("direction", body.global_position.direction_to(target_position))
	creature.set("is_moving", true)

	if creature.has_method("update_sprite_visual"):
		creature.call("update_sprite_visual")


func advance_movement(delta: float) -> void:
	var body := creature as CharacterBody2D

	if body == null:
		return

	var target_position: Vector2 = creature.get("movement_target_position")
	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null:
		return

	body.global_position = body.global_position.move_toward(
		target_position, species_data.speed * delta
	)

	if body.global_position.distance_to(target_position) > 0.1:
		return

	body.global_position = target_position
	creature.set("is_moving", false)

	var world_grid: Node = creature.get("world_grid")
	var pending_anchor: Vector2i = creature.get("pending_anchor_tile")
	var footprint: Vector2i = creature.get("footprint_size")

	if (
		world_grid != null
		and not bool(world_grid.call("move_creature", creature, pending_anchor, footprint))
	):
		var anchor: Vector2i = creature.get("anchor_tile")
		body.global_position = world_grid.call(
			"anchor_to_world_position", anchor, footprint
		)
		clear_path()
		creature.set("has_grazing_target", false)
		return

	creature.set("anchor_tile", pending_anchor)

	if int(creature.get("state")) != state_seek_food:
		return

	if not creature.has_method("can_start_eating_here"):
		return

	var has_grazing_target := bool(creature.get("has_grazing_target"))
	var grazing_target: Vector2i = creature.get("grazing_target_anchor")

	if (
		bool(creature.call("can_start_eating_here"))
		and (not has_grazing_target or pending_anchor == grazing_target)
		and creature.has_method("enter_eating")
	):
		creature.call("enter_eating")


func clear_path() -> void:
	var world_grid: Node = creature.get("world_grid")

	if world_grid != null:
		var footprint: Vector2i = creature.get("footprint_size")
		world_grid.call("release_movement_reservation", creature, footprint)

	_clear_queued_path()
	creature.set("is_moving", false)
	creature.set("pending_anchor_tile", creature.get("anchor_tile"))

	var body := creature as Node2D

	if body != null:
		creature.set("movement_target_position", body.global_position)


func can_accept_indirect_order() -> bool:
	var current_state := int(creature.get("state"))
	return current_state == state_idle or current_state == state_walk


func has_indirect_order_route_in_progress() -> bool:
	return get_remaining_route_steps() > 0


func apply_indirect_order_route(path: Array) -> bool:
	var normalized_path := _normalize_route(path)

	if normalized_path.is_empty():
		return false

	if bool(creature.get("is_moving")):
		creature.set("current_path", normalized_path)
		creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
		return true

	if not creature.has_method("enter_walk"):
		return false

	creature.call("enter_walk")
	creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
	creature.set("current_path", normalized_path)
	start_next_path_step_if_needed()
	return true


func pause_indirect_order_for_food() -> void:
	_clear_queued_path()
	creature.set("has_grazing_target", false)
	creature.set("food_recheck_timer", 0.0)

	var candidate_queue_variant: Variant = creature.get("grazing_candidate_queue")

	if candidate_queue_variant is Array:
		(candidate_queue_variant as Array).clear()
		creature.set("grazing_candidate_queue", candidate_queue_variant)

	if bool(creature.get("is_moving")):
		if creature.has_method("change_state"):
			creature.call("change_state", state_seek_food)
		return

	if creature.has_method("enter_hungry_behavior"):
		creature.call("enter_hungry_behavior")


func cancel_indirect_order_route() -> void:
	if not can_accept_indirect_order():
		return

	_clear_queued_path()

	if bool(creature.get("is_moving")):
		creature.set("state_timer", 0.0)
		return

	if creature.has_method("enter_walk"):
		creature.call("enter_walk")


func _normalize_route(path: Array) -> Array[Vector2i]:
	var normalized_path: Array[Vector2i] = []

	for step_variant: Variant in path:
		if step_variant is Vector2i:
			normalized_path.append(step_variant)

	return normalized_path


func _clear_queued_path() -> void:
	var path_variant: Variant = creature.get("current_path")

	if not (path_variant is Array):
		return

	var current_path := path_variant as Array
	current_path.clear()
	creature.set("current_path", current_path)
