extends RefCounted

# Creature-owned movement and indirect-order boundary. External systems ask the
# creature to apply or cancel routes; only this controller touches route/FSM
# internals, keeping callers insulated from future creature.gd changes.

const INDIRECT_ORDER_STATE_TIMER := 30.0
const INDIRECT_ORDER_REPATH_TILE_CAP := 1800
const LOCAL_BLOCKED_ROUTE_REJOIN_STEPS := 8
const LOCAL_BLOCKED_ROUTE_TILE_CAP := 192
const DIAGONAL_STEP_COST := 1.41421356
const ROUTE_COST_EPSILON := 0.0001
const STATIC_ROUTE_MIN_EXTRA_COST := 2.0
const STATIC_ROUTE_SHORTCUT_CHECK_CAP := 96
const STATIC_ROUTE_SHORTCUT_LOOKAHEAD_STEPS := 24
const PROACTIVE_BYPASS_REJOIN_STEPS := 5
const PROACTIVE_BYPASS_TILE_CAP := 64
const PROACTIVE_BYPASS_MAX_ADDED_COST := 3.0
const CALM_IDLE_CHANCE := 0.6
const CALM_IDLE_DURATION := 2.0
const CALM_WALK_MIN_DURATION := 2.0
const CALM_WALK_MAX_DURATION := 3.0
const RAPTOR_GUARD_POLICY := preload("res://scripts/flags/raptor_guard_policy.gd")

var creature: Node
var state_idle: int
var state_walk: int
var state_seek_food: int
var is_following_indirect_order_route := false
var is_waiting_for_blocked_indirect_route := false
var blocked_indirect_route_anchor := Vector2i.ZERO
var blocked_indirect_route_signature := ""
var calm_choice_pending := true
var is_applying_calm_choice := false
var last_completed_movement_physics_frame := -1
var route_debug_source := "none"
var route_debug_reason := "not assigned"

func _init(owner: Node, idle_state: int, walk_state: int, seek_food_state: int) -> void:
	creature = owner
	state_idle = idle_state
	state_walk = walk_state
	state_seek_food = seek_food_state

func update_idle(delta: float) -> void:
	var timer := float(creature.get("state_timer")) - delta
	creature.set("state_timer", timer)

	if timer <= 0.0:
		_choose_next_calm_state()

func update_walk(delta: float) -> void:
	var path_variant: Variant = creature.get("current_path")

	if calm_choice_pending and _can_choose_calm_state(path_variant):
		_choose_next_calm_state()

		if int(creature.get("state")) == state_idle:
			return

		path_variant = creature.get("current_path")

	var timer := float(creature.get("state_timer")) - delta
	creature.set("state_timer", timer)

	if bool(creature.get("is_moving")):
		return

	path_variant = creature.get("current_path")

	# A completed step gets one stationary physics frame before another calm
	# wander step may start. This lets higher-priority behaviour run first.
	if (
		path_variant is Array
		and (path_variant as Array).is_empty()
		and last_completed_movement_physics_frame == Engine.get_physics_frames()
	):
		return

	var has_indirect_route := (
		is_following_indirect_order_route
		and path_variant is Array
		and not (path_variant as Array).is_empty()
	)

	if timer <= 0.0:
		if has_indirect_route or not _can_choose_calm_state(path_variant):
			creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
		elif _can_stop_at_current_anchor():
			_choose_next_calm_state()

			if int(creature.get("state")) == state_idle:
				return

			path_variant = creature.get("current_path")
		else:
			# A flying route may be interrupted over aerial terrain. Keep moving until
			# the creature reaches a normal ground anchor where idle is legal.
			creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)

	if not (path_variant is Array) or (path_variant as Array).is_empty():
		if creature.has_method("is_hunting") and bool(creature.is_hunting()):
			return

		if creature.has_method("should_hold_at_locked_approach") and bool(creature.should_hold_at_locked_approach()):
			return

		_reset_blocked_indirect_route_wait()

		if is_following_indirect_order_route:
			is_following_indirect_order_route = false
			calm_choice_pending = true

		if calm_choice_pending and _can_choose_calm_state(path_variant):
			_choose_next_calm_state()

			if int(creature.get("state")) == state_idle:
				return

		choose_random_wander_step()

	start_next_path_step_if_needed()

func _can_choose_calm_state(path_variant: Variant) -> bool:
	if is_following_indirect_order_route or bool(creature.get("is_moving")):
		return false

	if path_variant is Array and not (path_variant as Array).is_empty():
		return false

	if creature.has_method("is_hunting") and bool(creature.is_hunting()):
		return false

	if creature.has_method("should_hold_at_locked_approach") and bool(creature.should_hold_at_locked_approach()):
		return false

	return true

func _choose_next_calm_state() -> void:
	calm_choice_pending = false
	is_applying_calm_choice = true

	if randf() < CALM_IDLE_CHANCE and _can_stop_at_current_anchor():
		if creature.has_method("enter_idle"):
			creature.call("enter_idle")
			creature.set("state_timer", CALM_IDLE_DURATION)
			_set_route_debug("none", "calm cycle chose idle")
		is_applying_calm_choice = false
		return

	if creature.has_method("enter_walk"):
		creature.call("enter_walk")
		creature.set(
			"state_timer",
			randf_range(CALM_WALK_MIN_DURATION, CALM_WALK_MAX_DURATION)
		)
		_set_route_debug("none", "calm cycle chose walk")

	is_applying_calm_choice = false

func _can_stop_at_current_anchor() -> bool:
	var world_grid: Node = creature.get("world_grid")

	if world_grid == null or not world_grid.has_method("can_place_footprint"):
		return true

	var anchor: Vector2i = creature.get("anchor_tile")
	var footprint: Vector2i = creature.get("footprint_size")
	return bool(world_grid.call("can_place_footprint", anchor, footprint, creature))


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
	_set_route_debug("wander", "calm walk selected a random step")

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
	var normalized_path := _normalize_route(path)
	creature.set("current_path", normalized_path)

	if normalized_path.is_empty():
		calm_choice_pending = true
		_set_route_debug("none", "autonomous behavior route cleared")
	else:
		calm_choice_pending = false
		_set_route_debug("behavior", "autonomous behavior replaced the route")

func clear_behavior_route() -> void:
	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
	_clear_queued_path()
	calm_choice_pending = true
	_set_route_debug("none", "autonomous behavior route cleared")

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

	if (
		is_following_indirect_order_route
		and allow_rebuild
		and not is_waiting_for_blocked_indirect_route
	):
		var proactive_route := _find_proactive_indirect_bypass(
			current_path,
			world_grid,
			footprint
		)

		if not proactive_route.is_empty():
			current_path = proactive_route
			creature.set("current_path", current_path)
			next_anchor = proactive_route[0]
			_set_route_debug("lookahead bypass", "second route step was occupied")

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
	last_completed_movement_physics_frame = Engine.get_physics_frames()

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

	if not is_applying_calm_choice:
		calm_choice_pending = true

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

	normalized_path = _simplify_indirect_route_ignoring_dynamic_occupancy(
		normalized_path
	)
	_reset_blocked_indirect_route_wait()

	if bool(creature.get("is_moving")):
		is_following_indirect_order_route = true
		calm_choice_pending = false
		creature.set("current_path", normalized_path)
		creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
		_set_route_debug("flag static", "new flag route queued after the active step")
		return true

	if not creature.has_method("enter_walk"):
		return false

	creature.call("enter_walk")
	is_following_indirect_order_route = true
	calm_choice_pending = false
	creature.set("state_timer", INDIRECT_ORDER_STATE_TIMER)
	creature.set("current_path", normalized_path)
	_set_route_debug("flag static", "new flag route assigned")
	start_next_path_step_if_needed()
	return true

func pause_indirect_order_for_food() -> void:
	is_following_indirect_order_route = false
	_reset_blocked_indirect_route_wait()
	_clear_queued_path()
	calm_choice_pending = true
	_set_route_debug("none", "flag route paused for food")
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
	calm_choice_pending = true
	_set_route_debug("none", "flag route cancelled")

	if bool(creature.get("is_moving")):
		creature.set("state_timer", 0.0)
		return

	if creature.has_method("enter_walk"):
		creature.call("enter_walk")

func _simplify_indirect_route_ignoring_dynamic_occupancy(
	original_route: Array[Vector2i]
) -> Array[Vector2i]:
	var world_grid: Node = creature.get("world_grid")

	if world_grid == null or original_route.size() < 2:
		return original_route

	var start_anchor := get_navigation_anchor()
	var cleanup_result := _remove_route_loops(original_route, start_anchor)
	var cleaned_variant: Variant = cleanup_result.get("route", [])

	if not (cleaned_variant is Array):
		return original_route

	var source_route := _normalize_route(cleaned_variant as Array)

	if source_route.is_empty():
		return original_route

	var goal_anchor := source_route[source_route.size() - 1]
	var source_cost := _calculate_route_cost(start_anchor, source_route)
	var minimum_cost := _estimate_direct_route_cost(start_anchor, goal_anchor)
	var removed_loops := int(cleanup_result.get("loop_count", 0))

	if removed_loops <= 0 and source_cost <= minimum_cost + STATIC_ROUTE_MIN_EXTRA_COST:
		return source_route

	PerformanceStats.add_counter("static_route_simplify_attempts")
	var started_usec := Time.get_ticks_usec()
	var footprint: Vector2i = creature.get("footprint_size")
	var simplified_route: Array[Vector2i] = []
	var current_anchor := start_anchor
	var source_index := 0
	var candidate_checks := 0

	while source_index < source_route.size():
		var chosen_route: Array[Vector2i] = []
		var chosen_index := source_index

		var farthest_index := mini(
			source_index + STATIC_ROUTE_SHORTCUT_LOOKAHEAD_STEPS,
			source_route.size() - 1
		)

		for target_index in range(farthest_index, source_index - 1, -1):
			if candidate_checks >= STATIC_ROUTE_SHORTCUT_CHECK_CAP:
				break

			candidate_checks += 1
			var direct_route := _build_static_direct_route(
				world_grid,
				current_anchor,
				source_route[target_index],
				footprint
			)

			if direct_route.is_empty():
				continue

			chosen_route = direct_route
			chosen_index = target_index
			break

		if chosen_route.is_empty():
			for remaining_index in range(source_index, source_route.size()):
				simplified_route.append(source_route[remaining_index])
			break

		simplified_route.append_array(chosen_route)
		current_anchor = source_route[chosen_index]
		source_index = chosen_index + 1

	PerformanceStats.add_counter("static_route_simplify_candidate_checks", candidate_checks)
	var elapsed_usec := maxi(Time.get_ticks_usec() - started_usec, 0)
	PerformanceStats.add_counter("static_route_simplify_search_usec", elapsed_usec)
	PerformanceStats.set_max_value(
		"static_route_simplify_search_max_usec",
		float(elapsed_usec)
	)

	if simplified_route.is_empty():
		PerformanceStats.add_counter("static_route_simplify_fallback")
		return source_route

	var simplified_cost := _calculate_route_cost(start_anchor, simplified_route)
	var source_turns := _count_route_turns(start_anchor, source_route)
	var simplified_turns := _count_route_turns(start_anchor, simplified_route)

	if (
		simplified_cost > source_cost + ROUTE_COST_EPSILON
		or (
			absf(simplified_cost - source_cost) <= ROUTE_COST_EPSILON
			and simplified_turns >= source_turns
		)
	):
		PerformanceStats.add_counter("static_route_simplify_fallback")
		return source_route

	PerformanceStats.add_counter("static_route_simplify_success")
	var saved_steps := maxi(source_route.size() - simplified_route.size(), 0)

	if saved_steps > 0:
		PerformanceStats.add_counter("static_route_simplify_steps_saved", saved_steps)

	return simplified_route

func _build_static_direct_route(
	world_grid: Node,
	start_anchor: Vector2i,
	target_anchor: Vector2i,
	footprint: Vector2i
) -> Array[Vector2i]:
	if start_anchor == target_anchor:
		return []

	var best_route: Array[Vector2i] = []
	var best_turn_count := 2147483647
	var delta := target_anchor - start_anchor
	var modes: Array[int] = [0]

	if absi(delta.x) > absi(delta.y):
		modes.append(1)
	elif absi(delta.y) > absi(delta.x):
		modes.append(2)

	for mode: int in modes:
		var candidate := _build_static_direct_route_mode(
			world_grid,
			start_anchor,
			target_anchor,
			footprint,
			mode
		)

		if candidate.is_empty():
			continue

		var turn_count := _count_route_turns(start_anchor, candidate)

		if turn_count >= best_turn_count:
			continue

		best_route = candidate
		best_turn_count = turn_count

	return best_route

func _build_static_direct_route_mode(
	world_grid: Node,
	start_anchor: Vector2i,
	target_anchor: Vector2i,
	footprint: Vector2i,
	mode: int
) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	var current := start_anchor
	var delta := target_anchor - start_anchor
	var x_direction := signi(delta.x)
	var y_direction := signi(delta.y)
	var diagonal_steps := mini(absi(delta.x), absi(delta.y))
	var straight_x_steps := absi(delta.x) - diagonal_steps
	var straight_y_steps := absi(delta.y) - diagonal_steps
	var step_plan: Array[Vector2i] = []

	if mode == 1:
		for _step in range(straight_x_steps):
			step_plan.append(Vector2i(x_direction, 0))
	elif mode == 2:
		for _step in range(straight_y_steps):
			step_plan.append(Vector2i(0, y_direction))

	for _step in range(diagonal_steps):
		step_plan.append(Vector2i(x_direction, y_direction))

	if mode != 1:
		for _step in range(straight_x_steps):
			step_plan.append(Vector2i(x_direction, 0))

	if mode != 2:
		for _step in range(straight_y_steps):
			step_plan.append(Vector2i(0, y_direction))

	for direction: Vector2i in step_plan:
		var next_anchor := current + direction

		if not _is_static_step_valid(
			world_grid,
			current,
			next_anchor,
			footprint
		):
			return []

		route.append(next_anchor)
		current = next_anchor

	return route if current == target_anchor else []

func _is_static_step_valid(
	world_grid: Node,
	from_anchor: Vector2i,
	to_anchor: Vector2i,
	footprint: Vector2i
) -> bool:
	if not _is_static_anchor_traversable(world_grid, to_anchor, footprint):
		return false

	var delta := to_anchor - from_anchor

	if delta.x == 0 or delta.y == 0:
		return true

	return (
		_is_static_anchor_traversable(
			world_grid,
			from_anchor + Vector2i(delta.x, 0),
			footprint
		)
		and _is_static_anchor_traversable(
			world_grid,
			from_anchor + Vector2i(0, delta.y),
			footprint
		)
	)

func _is_static_anchor_traversable(
	world_grid: Node,
	anchor: Vector2i,
	footprint: Vector2i
) -> bool:
	if not world_grid.has_method("can_traverse_static_footprint"):
		return false

	return bool(world_grid.call(
		"can_traverse_static_footprint",
		anchor,
		footprint,
		creature
	))

func _estimate_direct_route_cost(from_anchor: Vector2i, to_anchor: Vector2i) -> float:
	var delta := to_anchor - from_anchor
	var diagonal_steps := mini(absi(delta.x), absi(delta.y))
	var straight_steps := maxi(absi(delta.x), absi(delta.y)) - diagonal_steps
	return float(diagonal_steps) * DIAGONAL_STEP_COST + float(straight_steps)

func _find_proactive_indirect_bypass(
	current_path: Array,
	world_grid: Node,
	footprint: Vector2i
) -> Array[Vector2i]:
	PerformanceStats.add_counter("proactive_route_lookahead_checks")

	if current_path.size() < 3:
		return []

	var current_anchor_variant: Variant = creature.get("anchor_tile")
	var first_anchor_variant: Variant = current_path[0]
	var second_anchor_variant: Variant = current_path[1]

	if (
		not (current_anchor_variant is Vector2i)
		or not (first_anchor_variant is Vector2i)
		or not (second_anchor_variant is Vector2i)
	):
		return []

	var current_anchor: Vector2i = current_anchor_variant
	var first_anchor: Vector2i = first_anchor_variant
	var second_anchor: Vector2i = second_anchor_variant

	if not _is_static_anchor_traversable(world_grid, second_anchor, footprint):
		return []

	if bool(world_grid.call(
		"can_traverse_footprint",
		second_anchor,
		footprint,
		creature
	)):
		return []

	if not bool(world_grid.call(
		"can_traverse_footprint",
		first_anchor,
		footprint,
		creature
	)):
		return []

	PerformanceStats.add_counter("proactive_route_lookahead_blocked")
	var max_rejoin_index := mini(
		PROACTIVE_BYPASS_REJOIN_STEPS - 1,
		current_path.size() - 1
	)
	var goals: Array[Vector2i] = []

	for index in range(2, max_rejoin_index + 1):
		var goal_variant: Variant = current_path[index]

		if goal_variant is Vector2i:
			goals.append(goal_variant)

	if goals.is_empty():
		return []

	PerformanceStats.add_counter("proactive_route_bypass_attempts")
	var started_usec := Time.get_ticks_usec()
	var result_variant: Variant = world_grid.call(
		"find_path_to_any",
		current_anchor,
		goals,
		footprint,
		creature,
		PROACTIVE_BYPASS_TILE_CAP,
		&"movement_lookahead"
	)
	var elapsed_usec := maxi(Time.get_ticks_usec() - started_usec, 0)
	PerformanceStats.add_counter("proactive_route_bypass_search_usec", elapsed_usec)
	PerformanceStats.set_max_value(
		"proactive_route_bypass_search_max_usec",
		float(elapsed_usec)
	)

	if not (result_variant is Dictionary):
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	var result: Dictionary = result_variant
	var route_variant: Variant = result.get("path", [])
	var goal_variant: Variant = result.get("goal_anchor", null)

	if not (route_variant is Array) or not (goal_variant is Vector2i):
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	var local_route := _normalize_route(route_variant as Array)
	var rejoin_anchor: Vector2i = goal_variant

	if local_route.is_empty():
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	var rejoin_index := -1

	for index in range(2, max_rejoin_index + 1):
		if current_path[index] == rejoin_anchor:
			rejoin_index = index
			break

	if rejoin_index < 0:
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	var original_direction := _get_step_direction(current_anchor, first_anchor)
	var bypass_direction := _get_step_direction(current_anchor, local_route[0])
	var direction_dot := (
		original_direction.x * bypass_direction.x
		+ original_direction.y * bypass_direction.y
	)

	if direction_dot < 0:
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	var original_segment: Array[Vector2i] = []

	for index in range(0, rejoin_index + 1):
		var segment_variant: Variant = current_path[index]

		if segment_variant is Vector2i:
			original_segment.append(segment_variant)

	var added_cost := (
		_calculate_route_cost(current_anchor, local_route)
		- _calculate_route_cost(current_anchor, original_segment)
	)

	if added_cost > PROACTIVE_BYPASS_MAX_ADDED_COST + ROUTE_COST_EPSILON:
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	var rebuilt_route: Array[Vector2i] = []
	rebuilt_route.append_array(local_route)

	for index in range(rejoin_index + 1, current_path.size()):
		var tail_variant: Variant = current_path[index]

		if tail_variant is Vector2i:
			rebuilt_route.append(tail_variant)

	var cleanup_result := _remove_route_loops(rebuilt_route, current_anchor)
	var cleaned_variant: Variant = cleanup_result.get("route", [])

	if not (cleaned_variant is Array):
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	var cleaned_route := _normalize_route(cleaned_variant as Array)

	if cleaned_route.is_empty():
		PerformanceStats.add_counter("proactive_route_bypass_failed")
		return []

	PerformanceStats.add_counter("proactive_route_bypass_success")
	return cleaned_route

func _get_step_direction(from_anchor: Vector2i, to_anchor: Vector2i) -> Vector2i:
	var delta := to_anchor - from_anchor
	return Vector2i(signi(delta.x), signi(delta.y))

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
		_set_route_debug("local rejoin", "next route step was blocked")
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
		&"movement_repath",
		true
	)

	if not (rebuilt_path_variant is Array):
		return false

	var rebuilt_path := _normalize_route(rebuilt_path_variant as Array)

	if rebuilt_path.is_empty():
		return false

	creature.set("current_path", rebuilt_path)
	_set_route_debug("full static repath", "local rejoin was unavailable")
	return true

func _find_local_indirect_rejoin_route(
	current_path: Array,
	world_grid: Node,
	footprint: Vector2i,
	current_anchor: Vector2i
) -> Array[Vector2i]:
	if current_path.size() < 2:
		return []

	var started_usec := Time.get_ticks_usec()
	PerformanceStats.add_counter("blocked_route_rejoin_attempts")
	var max_rejoin_index := mini(
		LOCAL_BLOCKED_ROUTE_REJOIN_STEPS - 1,
		current_path.size() - 1
	)
	var best_route: Array[Vector2i] = []
	var best_cost := INF
	var best_turn_count := 2147483647
	var best_rejoin_index := -1
	var best_removed_loop_count := 0
	var best_removed_step_count := 0

	# Check every nearby place where the detour can safely reconnect. The previous
	# implementation accepted the first reachable (and farthest) point, which could
	# choose a long detour even when a shorter local bypass also existed.
	for rejoin_index in range(1, max_rejoin_index + 1):
		var rejoin_variant: Variant = current_path[rejoin_index]

		if not (rejoin_variant is Vector2i):
			continue

		PerformanceStats.add_counter("blocked_route_rejoin_candidates_checked")
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

		PerformanceStats.add_counter("blocked_route_rejoin_candidates_reachable")

		for tail_index in range(rejoin_index + 1, current_path.size()):
			var tail_step: Variant = current_path[tail_index]

			if tail_step is Vector2i:
				rebuilt_path.append(tail_step)

		var cleanup_result := _remove_route_loops(rebuilt_path, current_anchor)
		var candidate_route_variant: Variant = cleanup_result.get("route", [])

		if not (candidate_route_variant is Array):
			continue

		var candidate_route := _normalize_route(candidate_route_variant as Array)

		if candidate_route.is_empty():
			continue

		var candidate_removed_loop_count := int(cleanup_result.get("loop_count", 0))
		var candidate_removed_step_count := int(cleanup_result.get("removed_steps", 0))
		var candidate_cost := _calculate_route_cost(current_anchor, candidate_route)
		var candidate_turn_count := _count_route_turns(current_anchor, candidate_route)

		if not _is_better_rejoin_candidate(
			candidate_cost,
			candidate_turn_count,
			rejoin_index,
			best_cost,
			best_turn_count,
			best_rejoin_index
		):
			continue

		best_route = candidate_route
		best_cost = candidate_cost
		best_turn_count = candidate_turn_count
		best_rejoin_index = rejoin_index
		best_removed_loop_count = candidate_removed_loop_count
		best_removed_step_count = candidate_removed_step_count

	if best_removed_loop_count > 0:
		PerformanceStats.add_counter(
			"blocked_route_rejoin_loops_removed",
			best_removed_loop_count
		)
	if best_removed_step_count > 0:
		PerformanceStats.add_counter(
			"blocked_route_rejoin_steps_removed",
			best_removed_step_count
		)

	var elapsed_usec := maxi(Time.get_ticks_usec() - started_usec, 0)
	PerformanceStats.add_counter("blocked_route_rejoin_search_usec", elapsed_usec)
	PerformanceStats.set_max_value("blocked_route_rejoin_search_max_usec", float(elapsed_usec))

	if best_route.is_empty():
		PerformanceStats.add_counter("blocked_route_rejoin_failed")
	else:
		PerformanceStats.add_counter("blocked_route_rejoin_success")

	return best_route

func _remove_route_loops(path: Array[Vector2i], start_anchor: Vector2i) -> Dictionary:
	var cleaned_path: Array[Vector2i] = []
	var index_by_anchor: Dictionary = {start_anchor: -1}
	var loop_count := 0
	var removed_steps := 0

	for anchor: Vector2i in path:
		if not index_by_anchor.has(anchor):
			index_by_anchor[anchor] = cleaned_path.size()
			cleaned_path.append(anchor)
			continue

		loop_count += 1
		var keep_index := int(index_by_anchor.get(anchor, -1))

		while cleaned_path.size() - 1 > keep_index:
			var removed_anchor_variant: Variant = cleaned_path.pop_back()
			index_by_anchor.erase(removed_anchor_variant)
			removed_steps += 1

		# The repeated occurrence closes the loop and is omitted as well.
		removed_steps += 1

	return {
		"route": cleaned_path,
		"loop_count": loop_count,
		"removed_steps": removed_steps
	}

func _is_better_rejoin_candidate(
	candidate_cost: float,
	candidate_turn_count: int,
	candidate_rejoin_index: int,
	best_cost: float,
	best_turn_count: int,
	best_rejoin_index: int
) -> bool:
	if candidate_cost < best_cost - ROUTE_COST_EPSILON:
		return true

	if absf(candidate_cost - best_cost) > ROUTE_COST_EPSILON:
		return false

	if candidate_turn_count != best_turn_count:
		return candidate_turn_count < best_turn_count

	# On a complete tie, reconnect farther along the old route so more of the
	# temporarily blocked segment is bypassed.
	return candidate_rejoin_index > best_rejoin_index

func _calculate_route_cost(start_anchor: Vector2i, route: Array[Vector2i]) -> float:
	var total_cost := 0.0
	var previous_anchor := start_anchor

	for anchor: Vector2i in route:
		var delta := anchor - previous_anchor
		total_cost += DIAGONAL_STEP_COST if delta.x != 0 and delta.y != 0 else 1.0
		previous_anchor = anchor

	return total_cost

func _count_route_turns(start_anchor: Vector2i, route: Array[Vector2i]) -> int:
	var turn_count := 0
	var previous_anchor := start_anchor
	var previous_direction := Vector2i.ZERO

	for anchor: Vector2i in route:
		var delta := anchor - previous_anchor
		var direction := Vector2i(signi(delta.x), signi(delta.y))

		if previous_direction != Vector2i.ZERO and direction != previous_direction:
			turn_count += 1

		previous_direction = direction
		previous_anchor = anchor

	return turn_count

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

func get_route_debug_data() -> Dictionary:
	return {
		"source": route_debug_source,
		"reason": route_debug_reason
	}

func _set_route_debug(source: String, reason: String) -> void:
	route_debug_source = source
	route_debug_reason = reason

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
