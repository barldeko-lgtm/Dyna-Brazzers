extends RefCounted

# Owns runtime distribution of species-flag orders: batched first assignments,
# interruption-safe commitments, path retries, arrival completion, and F3 data.
# Destination selection and tile reservation live in player_flag_target_allocator.gd.

const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const TARGET_ALLOCATOR := preload("res://scripts/flags/player_flag_target_allocator.gd")

const FLAG_COMPLETION_REVISION_META := &"player_flag_completed_revision"
const FLAG_COMMITMENT_REVISION_META := &"player_flag_committed_revision"
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)
const MAX_NEW_FLAG_PATHS_PER_UPDATE := 5
const FLAG_PATH_SEARCH_TILE_CAP := 1800
const FAILED_PATH_RETRY_SECONDS := 2.0

const CREATURE_STATE_SEEK_FOOD := 2
const CREATURE_STATE_EATING := 3
const CREATURE_STATE_LAYING_EGG := 4
const CREATURE_STATE_COMBAT := 5
const CREATURE_STATE_DEAD := 6

var owner: Node
var target_allocator: RefCounted
var failed_path_retry_until: Dictionary = {}
var pending_route_requests: Array[Node] = []
var pending_route_lookup: Dictionary = {}


func _init(owner_system: Node) -> void:
	owner = owner_system
	target_allocator = TARGET_ALLOCATOR.new(owner_system)


func update() -> void:
	_cleanup_runtime_data()

	if int(owner.call("get_flag_count")) <= 0:
		return

	PerformanceStats.add_counter("flag_updates")
	var scanned_creatures := 0

	for creature: Node in owner.get_tree().get_nodes_in_group("creatures"):
		scanned_creatures += 1
		var species_id := _get_creature_species_id(creature)

		if species_id == StringName() or not bool(owner.call("has_flag", species_id)):
			_clear_flag_commitment(creature)
			target_allocator.call("clear_retry_choice", creature)
			_release_creature_target(creature)
			continue

		if _has_completed_current_flag(creature, species_id):
			_clear_flag_commitment(creature)
			target_allocator.call("clear_retry_choice", creature)
			_release_creature_target(creature)
			continue

		var footprint_variant: Variant = creature.get("footprint_size")
		var anchor_variant: Variant = creature.get("anchor_tile")

		if not (footprint_variant is Vector2i) or not (anchor_variant is Vector2i):
			_release_creature_target(creature)
			continue

		var footprint: Vector2i = footprint_variant
		var anchor: Vector2i = anchor_variant

		if bool(target_allocator.call(
			"is_footprint_inside_flag_area",
			species_id,
			anchor,
			footprint
		)):
			_mark_flag_completed(creature, species_id)
			continue

		if _hunger_overrides_flag(creature):
			_remove_pending_route_request(creature)
			_drop_flag_route_for_hunger(creature)
			continue

		if not _can_follow_flag(creature):
			# Reproduction/combat/survival pause the route but retain commitment.
			_release_creature_target(creature)
			continue

		if Time.get_ticks_msec() < int(failed_path_retry_until.get(creature, 0)):
			continue

		var already_assigned := bool(target_allocator.call("has_assignment", creature))

		if already_assigned and _has_flag_route_in_progress(creature):
			continue

		if _has_current_flag_commitment(creature, species_id):
			# Previously assigned creatures resume outside the five-new-creature queue.
			_remove_pending_route_request(creature)
			_try_build_flag_route(creature, species_id, footprint, anchor, false)
			continue

		_enqueue_flag_route_request(creature)

	PerformanceStats.add_counter("flag_creatures_scanned", scanned_creatures)
	_process_pending_route_requests(MAX_NEW_FLAG_PATHS_PER_UPDATE)


func cancel_species(species_id: StringName) -> void:
	_remove_pending_requests_for_species(species_id)

	for creature: Node in owner.get_tree().get_nodes_in_group("creatures"):
		if _get_creature_species_id(creature) != species_id:
			continue

		if bool(target_allocator.call("has_assignment", creature)):
			_cancel_flag_route_continuation(creature)

		_clear_flag_commitment(creature)
		target_allocator.call("clear_retry_choice", creature)
		target_allocator.call("release", creature)
		failed_path_retry_until.erase(creature)


func clear_runtime(cancel_routes := true) -> void:
	if cancel_routes:
		_cancel_assigned_flag_routes()

	failed_path_retry_until.clear()
	_clear_pending_route_requests()
	target_allocator.call("clear")
	_clear_all_flag_commitments()


func get_next_revision(species_id: StringName, current_revision: int) -> int:
	var highest_revision := current_revision

	for creature: Node in owner.get_tree().get_nodes_in_group("creatures"):
		if _get_creature_species_id(creature) != species_id:
			continue

		highest_revision = max(
			highest_revision,
			int(creature.get_meta(FLAG_COMPLETION_REVISION_META, -1))
		)

	return max(highest_revision + 1, 1)


func get_debug_data(creature: Node) -> Dictionary:
	var result := {
		"status": "нет активного флага",
		"committed": false,
		"target_retry": int(target_allocator.call("get_retry_choice", creature))
	}

	if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
		result["status"] = "динозавр недоступен"
		return result

	var species_id := _get_creature_species_id(creature)

	if species_id == StringName():
		result["status"] = "не относится к флагам игрока"
		return result

	if not bool(owner.call("has_flag", species_id)):
		return result

	var flag_tile: Vector2i = owner.call("get_flag_tile", species_id)

	if flag_tile != INVALID_ANCHOR:
		result["flag_tile"] = flag_tile

	var target_tile: Vector2i = target_allocator.call("get_target", creature)

	if target_tile != INVALID_ANCHOR:
		result["target_tile"] = target_tile

	var committed := _has_current_flag_commitment(creature, species_id)
	result["committed"] = committed
	result["status"] = _resolve_debug_status(creature, species_id, committed)
	return result


func _process_pending_route_requests(max_requests: int) -> void:
	var attempted_requests := 0
	var queue_guard := pending_route_requests.size()

	while (
		attempted_requests < max_requests
		and not pending_route_requests.is_empty()
		and queue_guard > 0
	):
		queue_guard -= 1
		var creature: Node = pending_route_requests.pop_front()
		pending_route_lookup.erase(creature)

		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			continue

		var species_id := _get_creature_species_id(creature)

		if species_id == StringName() or not bool(owner.call("has_flag", species_id)):
			_clear_flag_commitment(creature)
			target_allocator.call("clear_retry_choice", creature)
			_release_creature_target(creature)
			continue

		if _has_completed_current_flag(creature, species_id):
			_clear_flag_commitment(creature)
			target_allocator.call("clear_retry_choice", creature)
			_release_creature_target(creature)
			continue

		if _hunger_overrides_flag(creature):
			_drop_flag_route_for_hunger(creature)
			continue

		if not _can_follow_flag(creature):
			_release_creature_target(creature)
			continue

		if Time.get_ticks_msec() < int(failed_path_retry_until.get(creature, 0)):
			continue

		var footprint_variant: Variant = creature.get("footprint_size")
		var anchor_variant: Variant = creature.get("anchor_tile")

		if not (footprint_variant is Vector2i) or not (anchor_variant is Vector2i):
			_release_creature_target(creature)
			continue

		var footprint: Vector2i = footprint_variant
		var anchor: Vector2i = anchor_variant

		if bool(target_allocator.call(
			"is_footprint_inside_flag_area",
			species_id,
			anchor,
			footprint
		)):
			_mark_flag_completed(creature, species_id)
			continue

		attempted_requests += 1
		_try_build_flag_route(creature, species_id, footprint, anchor, true)


func _try_build_flag_route(
	creature: Node,
	species_id: StringName,
	footprint: Vector2i,
	anchor: Vector2i,
	commit_on_success: bool
) -> bool:
	var world_grid := _get_world_grid()

	if world_grid == null:
		return false

	var navigation_anchor := anchor

	if creature.has_method("get_navigation_anchor"):
		var navigation_variant: Variant = creature.call("get_navigation_anchor")

		if navigation_variant is Vector2i:
			navigation_anchor = navigation_variant

	var target_anchor: Vector2i = target_allocator.call(
		"get_or_assign_target",
		creature,
		species_id,
		footprint
	)

	if target_anchor == INVALID_ANCHOR:
		_set_failed_path_retry(creature)
		return false

	PerformanceStats.add_counter("flag_path_requests")
	var path_variant: Variant = world_grid.call(
		"find_path",
		navigation_anchor,
		target_anchor,
		footprint,
		creature,
		FLAG_PATH_SEARCH_TILE_CAP
	)

	if not (path_variant is Array) or (path_variant as Array).is_empty():
		PerformanceStats.add_counter("flag_path_failures")
		target_allocator.call("advance_retry_choice", creature)
		_release_creature_target(creature, true)
		_set_failed_path_retry(creature)
		return false

	_apply_flag_path(creature, path_variant as Array)
	target_allocator.call("clear_retry_choice", creature)

	if commit_on_success:
		_mark_flag_committed(creature, species_id)

	return true


func _can_follow_flag(creature: Node) -> bool:
	if creature == null or _hunger_overrides_flag(creature):
		return false

	if not creature.has_method("can_accept_indirect_order"):
		return false

	return bool(creature.call("can_accept_indirect_order"))


func _has_flag_route_in_progress(creature: Node) -> bool:
	if creature == null or not creature.has_method("has_indirect_order_route_in_progress"):
		return false

	return bool(creature.call("has_indirect_order_route_in_progress"))


func _apply_flag_path(creature: Node, path: Array) -> void:
	if creature != null and creature.has_method("apply_indirect_order_route"):
		creature.call("apply_indirect_order_route", path)


func _drop_flag_route_for_hunger(creature: Node) -> void:
	var had_flag_assignment := bool(target_allocator.call("release", creature))
	_remove_pending_route_request(creature)
	failed_path_retry_until.erase(creature)

	if (
		had_flag_assignment
		and creature != null
		and creature.has_method("pause_indirect_order_for_food")
	):
		creature.call("pause_indirect_order_for_food")


func _cancel_flag_route_continuation(creature: Node) -> void:
	if creature != null and creature.has_method("cancel_indirect_order_route"):
		creature.call("cancel_indirect_order_route")


func _cancel_assigned_flag_routes() -> void:
	for creature: Node in owner.get_tree().get_nodes_in_group("creatures"):
		if bool(target_allocator.call("has_assignment", creature)):
			_cancel_flag_route_continuation(creature)


func _release_creature_target(creature: Node, clear_flag_route := false) -> void:
	_remove_pending_route_request(creature)
	var had_flag_assignment := bool(target_allocator.call("release", creature))
	failed_path_retry_until.erase(creature)

	if clear_flag_route and had_flag_assignment:
		_cancel_flag_route_continuation(creature)


func _cleanup_runtime_data() -> void:
	target_allocator.call("cleanup")

	for creature_variant: Variant in failed_path_retry_until.keys():
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			failed_path_retry_until.erase(creature_variant)

	var cleaned_queue: Array[Node] = []
	pending_route_lookup.clear()

	for creature: Node in pending_route_requests:
		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			continue

		if pending_route_lookup.has(creature):
			continue

		cleaned_queue.append(creature)
		pending_route_lookup[creature] = true

	pending_route_requests = cleaned_queue


func _get_creature_species_id(creature: Node) -> StringName:
	if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
		return StringName()

	if not CREATURE_FACTION.is_player(creature):
		return StringName()

	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null:
		return StringName()

	var species_id := StringName(species_data.species_id)
	return species_id if PLAYER_SPECIES_CATALOG.has_species(species_id) else StringName()


func _hunger_overrides_flag(creature: Node) -> bool:
	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null or species_data.is_egg_eater():
		return false

	return float(creature.get("hunger")) <= species_data.hunger_search_threshold


func _get_flag_revision(species_id: StringName) -> int:
	return max(int(owner.call("get_flag_revision", species_id)), 1)


func _has_completed_current_flag(creature: Node, species_id: StringName) -> bool:
	return int(creature.get_meta(FLAG_COMPLETION_REVISION_META, -1)) == _get_flag_revision(species_id)


func _has_current_flag_commitment(creature: Node, species_id: StringName) -> bool:
	return int(creature.get_meta(FLAG_COMMITMENT_REVISION_META, -1)) == _get_flag_revision(species_id)


func _mark_flag_committed(creature: Node, species_id: StringName) -> void:
	creature.set_meta(FLAG_COMMITMENT_REVISION_META, _get_flag_revision(species_id))


func _clear_flag_commitment(creature: Node) -> void:
	if (
		creature != null
		and is_instance_valid(creature)
		and creature.has_meta(FLAG_COMMITMENT_REVISION_META)
	):
		creature.remove_meta(FLAG_COMMITMENT_REVISION_META)


func _clear_all_flag_commitments() -> void:
	for creature: Node in owner.get_tree().get_nodes_in_group("creatures"):
		_clear_flag_commitment(creature)


func _mark_flag_completed(creature: Node, species_id: StringName) -> void:
	creature.set_meta(FLAG_COMPLETION_REVISION_META, _get_flag_revision(species_id))
	_clear_flag_commitment(creature)
	target_allocator.call("clear_retry_choice", creature)
	_release_creature_target(creature, true)


func _enqueue_flag_route_request(creature: Node) -> void:
	if pending_route_lookup.has(creature):
		return

	pending_route_requests.append(creature)
	pending_route_lookup[creature] = true


func _remove_pending_route_request(creature: Node) -> void:
	if not pending_route_lookup.has(creature):
		return

	pending_route_lookup.erase(creature)
	pending_route_requests.erase(creature)


func _remove_pending_requests_for_species(species_id: StringName) -> void:
	var kept_requests: Array[Node] = []
	pending_route_lookup.clear()

	for creature: Node in pending_route_requests:
		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			continue

		if _get_creature_species_id(creature) == species_id:
			continue

		kept_requests.append(creature)
		pending_route_lookup[creature] = true

	pending_route_requests = kept_requests


func _clear_pending_route_requests() -> void:
	pending_route_requests.clear()
	pending_route_lookup.clear()


func _resolve_debug_status(
	creature: Node,
	species_id: StringName,
	committed: bool
) -> String:
	var status := "ожидает первую команду"
	var footprint_variant: Variant = creature.get("footprint_size")
	var anchor_variant: Variant = creature.get("anchor_tile")
	var state := int(creature.get("state"))

	if _has_completed_current_flag(creature, species_id):
		status = "флаг выполнен"
	elif (
		footprint_variant is Vector2i
		and anchor_variant is Vector2i
		and bool(target_allocator.call(
			"is_footprint_inside_flag_area",
			species_id,
			anchor_variant,
			footprint_variant
		))
	):
		status = "в зоне флага"
	elif (
		_hunger_overrides_flag(creature)
		or state == CREATURE_STATE_SEEK_FOOD
		or state == CREATURE_STATE_EATING
	):
		status = "пауза — еда" if committed else "ждёт — еда"
	elif state == CREATURE_STATE_LAYING_EGG:
		status = "пауза — размножение" if committed else "ждёт — размножение"
	elif state == CREATURE_STATE_COMBAT:
		status = "пауза — бой" if committed else "ждёт — бой"
	elif state == CREATURE_STATE_DEAD:
		status = "мёртв"
	elif (
		bool(target_allocator.call("has_assignment", creature))
		and _has_flag_route_in_progress(creature)
	):
		status = "идёт к флагу"
	elif Time.get_ticks_msec() < int(failed_path_retry_until.get(creature, 0)):
		status = "повторяет поиск пути"
	elif committed:
		status = "возобновляет путь"
	elif pending_route_lookup.has(creature):
		status = "ждёт очередь флага"

	return status


func _set_failed_path_retry(creature: Node) -> void:
	failed_path_retry_until[creature] = (
		Time.get_ticks_msec() + int(FAILED_PATH_RETRY_SECONDS * 1000.0)
	)


func _get_world_grid() -> Node:
	var grid := owner.call("get_world_grid") as Node
	return grid if grid != null and is_instance_valid(grid) else null
