extends RefCounted

# Creature-owned movement and indirect-order boundary. External systems ask the
# creature to apply or cancel routes; only this controller touches route/FSM
# internals, keeping callers insulated from future creature.gd changes.

const INDIRECT_ORDER_STATE_TIMER := 30.0
const INDIRECT_ORDER_REPATH_TILE_CAP := 1800
const LOCAL_BLOCKED_ROUTE_REJOIN_STEPS := 8
const LOCAL_BLOCKED_ROUTE_TILE_CAP := 192
const RAPTOR_GUARD_POLICY := preload("res://scripts/flags/raptor_guard_policy.gd")

var creature: Node
var state_idle: int
var state_walk: int
var state_seek_food: int
var is_following_indirect_order_route := false
var is_waiting_for_blocked_indirect_route := false
var blocked_indirect_route_anchor := Vector2i.ZERO
var blocked_indirect_route_signature := ""

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

	var path_variant: Variant = creature.get("current_path")
	var has_indirect_route := (
		is_following_indirect_order_route
		and path_variant is Array
		and not (path_variant as Array).is_empty()
	)

	if timer <= 0.0:
		if has_indirect_route:
			creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
		else:
			if creature.has_method("enter_idle"):
				creature.call("enter_idle")
			return

	if not (path_variant is Array) or (path_variant as Array).is_empty():
		if creature.has_method("is_hunting") and bool(creature.is_hunting()):
			return

		if creature.has_method("should_hold_at_locked_approach") and bool(creature.should_hold_at_locked_approach()):
			return

		_reset_blocked_indirect_route_wait()
		is_following_indirect_order_route = false
		choose_random_wander_step()

	start_next_path_step_if_needed()

func choose_random_wander_step() -> void:
	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
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
		if not (neighbor_variant is Vector2i):
			continue

		var neighbor: Vector2i = neighbor_variant

		if not RAPTOR_GUARD_POLICY.is_wander_anchor_allowed(creature, neighbor):
			continue

		neighbors.append(neighbor)

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
	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
	creature.set("current_path", _normalize_route(path))

func clear_behavior_route() -> void:
	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
	_clear_queued_path()

func get_queued_route_step_count() -> int:
	var path_variant: Variant = creature.get("current_path")

	if not (path_variant is Array):
		return 0

	return (path_variant as Array).size()

func get_remaining_route_steps() -> int:
	return get_queued_route_step_count() + (1 if bool(creature.get("is_moving")) else 0)

func start_next_path_step_if_needed(allow_rebuild: bool = true) -> void:
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

	if is_waiting_for_blocked_indirect_route:
		if not is_following_indirect_order_route or next_anchor != blocked_indirect_route_anchor:
			_reset_blocked_indirect_route_wait()
		else:
			var current_signature := _get_blocked_indirect_route_signature(
				world_grid,
				next_anchor,
				footprint
			)

			if current_signature == blocked_indirect_route_signature:
				return

			_reset_blocked_indirect_route_wait()

	if not bool(world_grid.call(
		"reserve_movement_destination", creature, next_anchor, footprint
	)):
		if is_following_indirect_order_route:
			if allow_rebuild and _try_rebuild_blocked_indirect_order_route(
				current_path,
				world_grid,
				footprint
			):
				_reset_blocked_indirect_route_wait()
				start_next_path_step_if_needed(false)
				return

			_begin_blocked_indirect_route_wait(world_grid, next_anchor, footprint)
			return

		clear_path()
		return

	_reset_blocked_indirect_route_wait()
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
	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
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
	return is_following_indirect_order_route and get_remaining_route_steps() > 0

func apply_indirect_order_route(path: Array) -> bool:
	var normalized_path := _normalize_route(path)

	if normalized_path.is_empty():
		return false

	_reset_blocked_indirect_route_wait()

	if bool(creature.get("is_moving")):
		is_following_indirect_order_route = true
		creature.set("current_path", normalized_path)
		creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
		return true

	if not creature.has_method("enter_walk"):
		return false

	creature.call("enter_walk")
	is_following_indirect_order_route = true
	creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
	creature.set("current_path", normalized_path)
	start_next_path_step_if_needed()
	return true

func pause_indirect_order_for_food() -> void:
	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
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

	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
	_clear_queued_path()

	if bool(creature.get("is_moving")):
		creature.set("state_timer", 0.0)
		return

	if creature.has_method("enter_walk"):
		creature.call("enter_walk")

func _try_rebuild_blocked_indirect_order_route(
	current_path: Array,
	world_grid: Node,
	footprint: Vector2i
) -> bool:
	if not is_following_indirect_order_route or current_path.is_empty():
		return false

	var current_anchor_variant: Variant = creature.get("anchor_tile")

	if not (current_anchor_variant is Vector2i):
		return false

	var current_anchor: Vector2i = current_anchor_variant
	var local_route := _find_local_indirect_rejoin_route(
		current_path,
		world_grid,
		footprint,
		current_anchor
	)

	if not local_route.is_empty():
		creature.set("current_path", local_route)
		return true

	var final_anchor_variant: Variant = current_path[current_path.size() - 1]

	if not (final_anchor_variant is Vector2i):
		return false

	var rebuilt_path_variant: Variant = world_grid.call(
		"find_path",
		current_anchor,
		final_anchor_variant,
		footprint,
		creature,
		INDIRECT_ORDER_REPATH_TILE_CAP,
		&"movement_repath"
	)

	if not (rebuilt_path_variant is Array):
		return false

	var rebuilt_path := _normalize_route(rebuilt_path_variant as Array)

	if rebuilt_path.is_empty():
		return false

	creature.set("current_path", rebuilt_path)
	return true

func _find_local_indirect_rejoin_route(
	current_path: Array,
	world_grid: Node,
	footprint: Vector2i,
	current_anchor: Vector2i
) -> Array[Vector2i]:
	if current_path.size() < 2:
		return []

	var max_rejoin_index := mini(
		LOCAL_BLOCKED_ROUTE_REJOIN_STEPS - 1,
		current_path.size() - 1
	)

	for rejoin_index in range(max_rejoin_index, 0, -1):
		var rejoin_variant: Variant = current_path[rejoin_index]

		if not (rejoin_variant is Vector2i):
			continue

		var rejoin_anchor: Vector2i = rejoin_variant

		if not bool(world_grid.call(
			"can_place_footprint",
			rejoin_anchor,
			footprint,
			creature
		)):
			continue

		var local_path_variant: Variant = world_grid.call(
			"find_path",
			current_anchor,
			rejoin_anchor,
			footprint,
			creature,
			LOCAL_BLOCKED_ROUTE_TILE_CAP,
			&"movement_repath"
		)

		if not (local_path_variant is Array):
			continue

		var rebuilt_path := _normalize_route(local_path_variant as Array)

		if rebuilt_path.is_empty():
			continue

		for tail_index in range(rejoin_index + 1, current_path.size()):
			var tail_step: Variant = current_path[tail_index]

			if tail_step is Vector2i:
				rebuilt_path.append(tail_step)

		return rebuilt_path

	return []

func _begin_blocked_indirect_route_wait(
	world_grid: Node,
	next_anchor: Vector2i,
	footprint: Vector2i
) -> void:
	is_waiting_for_blocked_indirect_route = true
	blocked_indirect_route_anchor = next_anchor
	blocked_indirect_route_signature = _get_blocked_indirect_route_signature(
		world_grid,
		next_anchor,
		footprint
	)

func _get_blocked_indirect_route_signature(
	world_grid: Node,
	anchor: Vector2i,
	footprint: Vector2i
) -> String:
	var occupied_variant: Variant = world_grid.get("occupied_by_tile")
	var reserved_variant: Variant = world_grid.get("reserved_by_tile")
	var occupied: Dictionary = occupied_variant if occupied_variant is Dictionary else {}
	var reserved: Dictionary = reserved_variant if reserved_variant is Dictionary else {}
	var footprint_tiles_variant: Variant = world_grid.call(
		"get_footprint_tiles",
		anchor,
		footprint
	)
	var parts := PackedStringArray()

	if not (footprint_tiles_variant is Array):
		return "invalid"

	for tile_variant: Variant in footprint_tiles_variant:
		if not (tile_variant is Vector2i):
			continue

		var tile: Vector2i = tile_variant
		parts.append("%d,%d:%d:%d:%d" % [
			tile.x,
			tile.y,
			1 if bool(world_grid.call("is_tile_walkable", tile)) else 0,
			_get_navigation_object_id(occupied.get(tile, null)),
			_get_navigation_object_id(reserved.get(tile, null))
		])

	return "|".join(parts)

func _get_navigation_object_id(value: Variant) -> int:
	if value == creature:
		return 0

	if value is Object and is_instance_valid(value):
		return int((value as Object).get_instance_id())

	return 0

func _reset_blocked_indirect_route_wait() -> void:
	is_waiting_for_blocked_indirect_route = false
	blocked_indirect_route_anchor = Vector2i.ZERO
	blocked_indirect_route_signature = ""

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
