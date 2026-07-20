extends "res://scripts/flags/player_flag_system.gd"

# Catalog-backed and performance-bounded player flag layer. The mature
# placement/visual helpers remain in player_flag_system.gd, while this wrapper
# owns the fixed player roster, faction filtering, batched path requests and
# one-shot arrival semantics for each placement of a species flag.
const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")

const FLAG_COMPLETION_REVISION_META := &"player_flag_completed_revision"
const FLAG_COMMITMENT_REVISION_META := &"player_flag_committed_revision"
const MAX_NEW_FLAG_PATHS_PER_UPDATE := 5
const OPTIMIZED_FLAG_PATH_SEARCH_TILE_CAP := 1800
const NATURE_MENU_ATTACH_RETRY_FRAMES := 16

const CREATURE_STATE_EATING := 3
const CREATURE_STATE_LAYING_EGG := 4
const CREATURE_STATE_COMBAT := 5
const CREATURE_STATE_DEAD := 6

var flag_revisions: Dictionary = {}
var pending_route_requests: Array[Node] = []
var pending_route_lookup: Dictionary = {}
var reserved_target_tiles: Dictionary = {}
var reserved_tiles_by_creature: Dictionary = {}
var target_choice_offsets: Dictionary = {}


func _attach_to_game_scene(scene: Node) -> void:
	for _attempt in range(NATURE_MENU_ATTACH_RETRY_FRAMES):
		if scene == null or not is_instance_valid(scene) or get_tree().current_scene != scene:
			return

		world_grid = get_tree().get_first_node_in_group("world_grid")
		nature_ui = get_tree().get_first_node_in_group("player_nature_ui")
		nature_content = null
		main_menu_grid = null
		flag_menu_button = null

		if (
			nature_ui != null
			and nature_ui.has_method("get_menu_content_root")
			and nature_ui.has_method("get_main_menu_grid")
			and nature_ui.has_method("get_menu_button")
		):
			nature_content = nature_ui.call("get_menu_content_root") as Control
			main_menu_grid = nature_ui.call("get_main_menu_grid") as GridContainer
			flag_menu_button = nature_ui.call("get_menu_button", &"flags") as Button

		if _has_required_runtime_nodes():
			attached_to_game = true
			_ensure_flag_visual()
			_build_flag_menu()
			flag_menu_button.tooltip_text = "Флаги видов"

			if not flag_menu_button.pressed.is_connected(_on_flag_menu_button_pressed):
				flag_menu_button.pressed.connect(_on_flag_menu_button_pressed)

			_sync_flag_visual()
			return

		await get_tree().process_frame

	push_warning("PlayerFlags: nature-menu API or world grid was not found.")


func _build_flag_menu() -> void:
	if flag_menu_grid != null and is_instance_valid(flag_menu_grid):
		return

	if nature_content == null or flag_menu_button == null:
		return

	flag_menu_grid = GridContainer.new()
	flag_menu_grid.name = "SpeciesFlagMenu"
	flag_menu_grid.position = Vector2(0.0, 66.0)
	flag_menu_grid.size = Vector2(260.0, 218.0)
	flag_menu_grid.columns = 3
	flag_menu_grid.add_theme_constant_override("h_separation", 6)
	flag_menu_grid.add_theme_constant_override("v_separation", 6)
	flag_menu_grid.visible = false
	nature_content.add_child(flag_menu_grid)

	for entry: Dictionary in PLAYER_SPECIES_CATALOG.get_flag_entries():
		var species_data := entry.get("species_data") as CreatureSpeciesData

		if species_data == null:
			continue

		var species_id := StringName(species_data.species_id)
		var species_button := _duplicate_menu_button()
		species_button.name = "%sFlagButton" % String(species_id).capitalize()
		species_button.custom_minimum_size = Vector2(80.0, 52.0)
		species_button.text = String(entry.get("flag_button_text", "Флаг\nвида"))
		species_button.tooltip_text = String(
			entry.get("flag_tooltip", "Поставить или перенести флаг вида")
		)
		species_button.add_theme_font_size_override("font_size", 11)
		species_button.pressed.connect(_on_species_flag_pressed.bind(species_id))
		flag_menu_grid.add_child(species_button)

	var remove_button := _duplicate_menu_button()
	remove_button.name = "RemoveSpeciesFlagButton"
	remove_button.custom_minimum_size = Vector2(80.0, 52.0)
	remove_button.text = "Удалить\nфлаг"
	remove_button.tooltip_text = "Выбрать флаг на карте для удаления"
	remove_button.add_theme_font_size_override("font_size", 12)
	remove_button.pressed.connect(_on_remove_flag_pressed)
	flag_menu_grid.add_child(remove_button)

	var back_button := _duplicate_menu_button()
	back_button.name = "FlagMenuBackButton"
	back_button.custom_minimum_size = Vector2(80.0, 52.0)
	back_button.text = "← Назад"
	back_button.tooltip_text = "Вернуться в основное меню"
	back_button.add_theme_font_size_override("font_size", 14)
	back_button.pressed.connect(_on_back_button_pressed)
	flag_menu_grid.add_child(back_button)

	status_label = Label.new()
	status_label.name = "FlagStatusLabel"
	status_label.custom_minimum_size = Vector2(80.0, 52.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	flag_menu_grid.add_child(status_label)
	_update_status_for_current_flag()


func _get_species_flag_at_tile(tile: Vector2i) -> StringName:
	for species_id: StringName in PLAYER_SPECIES_CATALOG.get_supported_ids():
		if flags.get(species_id, INVALID_ANCHOR) == tile:
			return species_id

	return StringName()


func _get_species_button_text(species_id: StringName) -> String:
	var entry := PLAYER_SPECIES_CATALOG.get_entry(species_id)
	return String(entry.get("flag_button_text", "Флаг\nвида"))


func _get_species_flag_tooltip(species_id: StringName) -> String:
	var entry := PLAYER_SPECIES_CATALOG.get_entry(species_id)
	return String(entry.get("flag_tooltip", "Поставить или перенести флаг вида"))


func set_flag(species_id: StringName, tile: Vector2i) -> void:
	if not PLAYER_SPECIES_CATALOG.has_species(species_id):
		return

	# Moving one flag invalidates only routes and retries for its own species.
	_cancel_species_flag_routes(species_id)
	flags[species_id] = tile
	flag_revisions[species_id] = _get_next_flag_revision(species_id)
	_sync_flag_visual()


func remove_flag(species_id: StringName) -> void:
	_cancel_species_flag_routes(species_id)
	flags.erase(species_id)
	_sync_flag_visual()


func clear_all_flags() -> void:
	_cancel_assigned_flag_routes()
	flags.clear()
	flag_revisions.clear()
	assigned_targets.clear()
	failed_path_retry_until.clear()
	_clear_pending_route_requests()
	_clear_reserved_target_tiles()
	_clear_all_flag_commitments()
	_clear_all_target_choice_offsets()
	_sync_flag_visual()


func get_save_data() -> Dictionary:
	var saved_flags: Array[Dictionary] = []

	for species_id_variant: Variant in flags.keys():
		var tile_variant: Variant = flags.get(species_id_variant)

		if not (tile_variant is Vector2i):
			continue

		var species_id := StringName(species_id_variant)
		var tile: Vector2i = tile_variant
		saved_flags.append({
			"species_id": String(species_id),
			"tile_x": tile.x,
			"tile_y": tile.y,
			"revision": _get_flag_revision(species_id)
		})

	return {"flags": saved_flags}


func restore_save_data(save_data: Dictionary) -> void:
	_cancel_assigned_flag_routes()
	flags.clear()
	flag_revisions.clear()
	assigned_targets.clear()
	failed_path_retry_until.clear()
	_clear_pending_route_requests()
	_clear_reserved_target_tiles()
	_clear_all_flag_commitments()
	_clear_all_target_choice_offsets()

	var saved_flags_variant: Variant = save_data.get("flags", [])

	if saved_flags_variant is Array:
		for record_variant: Variant in saved_flags_variant:
			if not (record_variant is Dictionary):
				continue

			var record := record_variant as Dictionary
			var species_id := StringName(String(record.get("species_id", "")))

			if species_id == StringName() or not PLAYER_SPECIES_CATALOG.has_species(species_id):
				continue

			flags[species_id] = Vector2i(
				int(record.get("tile_x", 0)),
				int(record.get("tile_y", 0))
			)
			flag_revisions[species_id] = max(int(record.get("revision", 1)), 1)

	_sync_flag_visual()


func _update_creature_flag_behaviour() -> void:
	_cleanup_creature_runtime_data()

	if flags.is_empty():
		return

	PerformanceStats.add_counter("flag_updates")
	var scanned_creatures := 0

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		scanned_creatures += 1
		var species_id := _get_creature_species_id(creature)

		if species_id == StringName() or not has_flag(species_id):
			_clear_flag_commitment(creature)
			_clear_target_choice_offset(creature)
			_release_creature_target(creature)
			continue

		if _has_completed_current_flag(creature, species_id):
			_clear_flag_commitment(creature)
			_clear_target_choice_offset(creature)
			_release_creature_target(creature)
			continue

		var footprint_variant: Variant = creature.get("footprint_size")
		var anchor_variant: Variant = creature.get("anchor_tile")

		if not (footprint_variant is Vector2i) or not (anchor_variant is Vector2i):
			_release_creature_target(creature)
			continue

		var footprint: Vector2i = footprint_variant
		var anchor: Vector2i = anchor_variant

		# Arrival is one-shot for this exact flag revision. Once the creature has
		# physically entered the area it returns to normal autonomous wandering,
		# and leaving the area later does not reactivate the same flag.
		if _is_footprint_inside_flag_area(species_id, anchor, footprint):
			_mark_flag_completed(creature, species_id)
			continue

		if _hunger_overrides_flag(creature):
			_remove_pending_route_request(creature)
			_drop_flag_route_for_hunger(creature)
			continue

		var state := int(creature.get("state"))

		if state != CREATURE_STATE_IDLE and state != CREATURE_STATE_WALK:
			# Survival, reproduction and combat pause the route but preserve the
			# current flag commitment so it can resume without joining the new queue.
			_release_creature_target(creature)
			continue

		var retry_until := int(failed_path_retry_until.get(creature, 0))

		if Time.get_ticks_msec() < retry_until:
			continue

		# INVALID_ANCHOR is also a Vector2i, so only dictionary membership can
		# distinguish a real flag assignment from the missing-value sentinel.
		var already_assigned := assigned_targets.has(creature)

		if already_assigned and _has_flag_route_in_progress(creature):
			continue

		if _has_current_flag_commitment(creature, species_id):
			# This creature already received this flag order once. Rebuild its route
			# immediately after eating/reproduction/combat instead of putting it behind
			# creatures that have never received the order.
			_remove_pending_route_request(creature)
			_try_build_flag_route(creature, species_id, footprint, anchor, false)
			continue

		_enqueue_flag_route_request(creature)

	PerformanceStats.add_counter("flag_creatures_scanned", scanned_creatures)
	_process_pending_route_requests(MAX_NEW_FLAG_PATHS_PER_UPDATE)


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

		if species_id == StringName() or not has_flag(species_id):
			_clear_flag_commitment(creature)
			_clear_target_choice_offset(creature)
			_release_creature_target(creature)
			continue

		if _has_completed_current_flag(creature, species_id):
			_clear_flag_commitment(creature)
			_clear_target_choice_offset(creature)
			_release_creature_target(creature)
			continue

		if _hunger_overrides_flag(creature):
			_drop_flag_route_for_hunger(creature)
			continue

		var state := int(creature.get("state"))

		if state != CREATURE_STATE_IDLE and state != CREATURE_STATE_WALK:
			# Survival, reproduction and combat pause the route but preserve the
			# current flag commitment so it can resume without joining the new queue.
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

		if _is_footprint_inside_flag_area(species_id, anchor, footprint):
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
	var navigation_anchor := anchor

	if creature.has_method("get_navigation_anchor"):
		var navigation_variant: Variant = creature.call("get_navigation_anchor")

		if navigation_variant is Vector2i:
			navigation_anchor = navigation_variant

	var target_anchor := _get_or_assign_target(creature, species_id, footprint)

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
		OPTIMIZED_FLAG_PATH_SEARCH_TILE_CAP
	)

	if not (path_variant is Array) or (path_variant as Array).is_empty():
		PerformanceStats.add_counter("flag_path_failures")
		_advance_target_choice_offset(creature)
		_release_creature_target(creature, true)
		_set_failed_path_retry(creature)
		return false

	_apply_flag_path(creature, path_variant as Array)
	_clear_target_choice_offset(creature)

	if commit_on_success:
		_mark_flag_committed(creature, species_id)

	return true


func _get_or_assign_target(
	creature: Node,
	species_id: StringName,
	footprint: Vector2i
) -> Vector2i:
	var previous_variant: Variant = assigned_targets.get(creature, INVALID_ANCHOR)
	var previous_target := INVALID_ANCHOR

	if previous_variant is Vector2i:
		previous_target = previous_variant

	var target := super._get_or_assign_target(creature, species_id, footprint)

	if target == INVALID_ANCHOR:
		_unreserve_target_for_creature(creature)
		assigned_targets.erase(creature)
		return target

	if previous_target != INVALID_ANCHOR and previous_target != target:
		_unreserve_target_for_creature(creature)

	_reserve_target_for_creature(creature, target, footprint)
	return target


func _choose_spread_candidate(
	creature: Node,
	species_id: StringName,
	candidates: Array[Vector2i]
) -> Vector2i:
	if candidates.is_empty():
		return INVALID_ANCHOR

	# The base selector intentionally spreads creatures deterministically. Add a
	# per-creature offset only after path failure so the next retry tests another
	# valid destination instead of repeating the same unreachable tile forever.
	var seed_value := int(creature.get_instance_id())
	var flag_tile: Vector2i = flags.get(species_id, Vector2i.ZERO)
	var retry_offset := int(target_choice_offsets.get(creature, 0))
	var start_index := posmod(
		seed_value + flag_tile.x * 31 + flag_tile.y * 17 + retry_offset,
		candidates.size()
	)
	return candidates[start_index]


func _is_target_reserved_by_other(
	creature: Node,
	target: Vector2i,
	footprint: Vector2i
) -> bool:
	for tile_variant: Variant in world_grid.call("get_footprint_tiles", target, footprint):
		if not (tile_variant is Vector2i):
			continue

		var reserved_by_variant: Variant = reserved_target_tiles.get(tile_variant, null)
		var reserved_by := reserved_by_variant as Node

		if (
			reserved_by != null
			and reserved_by != creature
			and is_instance_valid(reserved_by)
			and not reserved_by.is_queued_for_deletion()
		):
			return true

	return false


func _release_creature_target(creature: Node, clear_flag_route := false) -> void:
	_unreserve_target_for_creature(creature)
	_remove_pending_route_request(creature)
	super._release_creature_target(creature, clear_flag_route)


func _cleanup_creature_runtime_data() -> void:
	super._cleanup_creature_runtime_data()

	for creature_variant: Variant in reserved_tiles_by_creature.keys():
		var creature := creature_variant as Node

		if (
			creature == null
			or not is_instance_valid(creature)
			or creature.is_queued_for_deletion()
			or not assigned_targets.has(creature)
		):
			_unreserve_target_for_creature(creature)

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

	for creature_variant: Variant in target_choice_offsets.keys():
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			target_choice_offsets.erase(creature_variant)


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


func _species_prefers_pasture(species_id: StringName) -> bool:
	var entry := PLAYER_SPECIES_CATALOG.get_entry(species_id)
	return int(entry.get(
		"flag_behaviour_type",
		PLAYER_SPECIES_CATALOG.FlagBehaviourType.GATHER
	)) == PLAYER_SPECIES_CATALOG.FlagBehaviourType.PASTURE


func _get_flag_revision(species_id: StringName) -> int:
	return max(int(flag_revisions.get(species_id, 1)), 1)


func _get_next_flag_revision(species_id: StringName) -> int:
	var highest_revision := int(flag_revisions.get(species_id, 0))

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		if _get_creature_species_id(creature) != species_id:
			continue

		highest_revision = max(
			highest_revision,
			int(creature.get_meta(FLAG_COMPLETION_REVISION_META, -1))
		)

	return max(highest_revision + 1, 1)


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
	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		_clear_flag_commitment(creature)


func _mark_flag_completed(creature: Node, species_id: StringName) -> void:
	creature.set_meta(FLAG_COMPLETION_REVISION_META, _get_flag_revision(species_id))
	_clear_flag_commitment(creature)
	_clear_target_choice_offset(creature)
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


func _cancel_species_flag_routes(species_id: StringName) -> void:
	_remove_pending_requests_for_species(species_id)

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		if _get_creature_species_id(creature) != species_id:
			continue

		if assigned_targets.has(creature):
			_cancel_flag_route_continuation(creature)

		_clear_flag_commitment(creature)
		_clear_target_choice_offset(creature)
		_unreserve_target_for_creature(creature)
		assigned_targets.erase(creature)
		failed_path_retry_until.erase(creature)


func get_creature_flag_debug_data(creature: Node) -> Dictionary:
	var result := {
		"status": "нет активного флага",
		"committed": false,
		"target_retry": int(target_choice_offsets.get(creature, 0))
	}

	if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
		result["status"] = "динозавр недоступен"
		return result

	var species_id := _get_creature_species_id(creature)

	if species_id == StringName():
		result["status"] = "не относится к флагам игрока"
		return result

	if not has_flag(species_id):
		return result

	var flag_tile_variant: Variant = flags.get(species_id, INVALID_ANCHOR)

	if flag_tile_variant is Vector2i:
		result["flag_tile"] = flag_tile_variant

	var assigned_target_variant: Variant = assigned_targets.get(creature, INVALID_ANCHOR)

	if assigned_target_variant is Vector2i and assigned_target_variant != INVALID_ANCHOR:
		result["target_tile"] = assigned_target_variant

	var committed := _has_current_flag_commitment(creature, species_id)
	result["committed"] = committed
	result["status"] = _resolve_creature_flag_debug_status(creature, species_id, committed)
	return result


func _resolve_creature_flag_debug_status(
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
		and _is_footprint_inside_flag_area(species_id, anchor_variant, footprint_variant)
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
	elif assigned_targets.has(creature) and _has_flag_route_in_progress(creature):
		status = "идёт к флагу"
	elif Time.get_ticks_msec() < int(failed_path_retry_until.get(creature, 0)):
		status = "повторяет поиск пути"
	elif committed:
		status = "возобновляет путь"
	elif pending_route_lookup.has(creature):
		status = "ждёт очередь флага"

	return status


func _advance_target_choice_offset(creature: Node) -> void:
	target_choice_offsets[creature] = int(target_choice_offsets.get(creature, 0)) + 1


func _clear_target_choice_offset(creature: Node) -> void:
	target_choice_offsets.erase(creature)


func _clear_all_target_choice_offsets() -> void:
	target_choice_offsets.clear()


func _reserve_target_for_creature(
	creature: Node,
	target: Vector2i,
	footprint: Vector2i
) -> void:
	_unreserve_target_for_creature(creature)
	var reserved_tiles: Array[Vector2i] = []

	for tile_variant: Variant in world_grid.call("get_footprint_tiles", target, footprint):
		if not (tile_variant is Vector2i):
			continue

		var tile: Vector2i = tile_variant
		reserved_target_tiles[tile] = creature
		reserved_tiles.append(tile)

	reserved_tiles_by_creature[creature] = reserved_tiles


func _unreserve_target_for_creature(creature: Node) -> void:
	var reserved_variant: Variant = reserved_tiles_by_creature.get(creature, [])

	if reserved_variant is Array:
		for tile_variant: Variant in reserved_variant:
			if not (tile_variant is Vector2i):
				continue

			if reserved_target_tiles.get(tile_variant, null) == creature:
				reserved_target_tiles.erase(tile_variant)

	reserved_tiles_by_creature.erase(creature)


func _clear_reserved_target_tiles() -> void:
	reserved_target_tiles.clear()
	reserved_tiles_by_creature.clear()
