extends RefCounted

# Owns destination selection inside 11x11 flag areas, per-creature target
# assignment, tile reservations, and retry rotation after unreachable targets.

const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")

const FLAG_AREA_SIZE := Vector2i(11, 11)
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)
const TARGET_DISTANCE_BAND_STEPS := 2
const PASTURE_ADULT_COUNT_TOLERANCE := 1

var owner: Node
var assigned_targets: Dictionary = {}
var reserved_target_tiles: Dictionary = {}
var reserved_tiles_by_creature: Dictionary = {}
var target_choice_offsets: Dictionary = {}


func _init(owner_system: Node) -> void:
	owner = owner_system


func get_or_assign_target(
	creature: Node,
	species_id: StringName,
	footprint: Vector2i
) -> Vector2i:
	var existing_variant: Variant = assigned_targets.get(creature, INVALID_ANCHOR)

	if existing_variant is Vector2i:
		var existing: Vector2i = existing_variant

		if existing != INVALID_ANCHOR and _is_valid_assigned_target(
			creature,
			species_id,
			existing,
			footprint
		):
			_reserve_target_for_creature(creature, existing, footprint)
			return existing

	var new_target := INVALID_ANCHOR

	if _species_prefers_pasture(species_id):
		new_target = _find_grass_target(creature, species_id, footprint)

	if new_target == INVALID_ANCHOR:
		new_target = _find_free_target(creature, species_id, footprint)

	if new_target == INVALID_ANCHOR:
		release(creature)
		return INVALID_ANCHOR

	assigned_targets[creature] = new_target
	_reserve_target_for_creature(creature, new_target, footprint)
	return new_target


func has_assignment(creature: Node) -> bool:
	return assigned_targets.has(creature)


func get_target(creature: Node) -> Vector2i:
	var target_variant: Variant = assigned_targets.get(creature, INVALID_ANCHOR)
	return target_variant if target_variant is Vector2i else INVALID_ANCHOR


func release(creature: Node) -> bool:
	var had_assignment := assigned_targets.has(creature)
	_unreserve_target_for_creature(creature)
	assigned_targets.erase(creature)
	return had_assignment


func clear() -> void:
	assigned_targets.clear()
	reserved_target_tiles.clear()
	reserved_tiles_by_creature.clear()
	target_choice_offsets.clear()


func cleanup() -> void:
	for creature_variant: Variant in assigned_targets.keys():
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			release(creature)

	for creature_variant: Variant in reserved_tiles_by_creature.keys():
		var creature := creature_variant as Node

		if (
			creature == null
			or not is_instance_valid(creature)
			or creature.is_queued_for_deletion()
			or not assigned_targets.has(creature)
		):
			_unreserve_target_for_creature(creature)

	for creature_variant: Variant in target_choice_offsets.keys():
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			target_choice_offsets.erase(creature_variant)


func is_footprint_inside_flag_area(
	species_id: StringName,
	anchor: Vector2i,
	footprint: Vector2i
) -> bool:
	var bounds := _get_flag_area_bounds(species_id)

	if bounds.is_empty():
		return false

	var area_min: Vector2i = bounds.get("min", Vector2i.ZERO)
	var area_end: Vector2i = bounds.get("end", Vector2i.ZERO)
	var footprint_center := Vector2(anchor) + Vector2(footprint) * 0.5
	return (
		footprint_center.x >= float(area_min.x)
		and footprint_center.x < float(area_end.x)
		and footprint_center.y >= float(area_min.y)
		and footprint_center.y < float(area_end.y)
	)


func advance_retry_choice(creature: Node) -> void:
	target_choice_offsets[creature] = int(target_choice_offsets.get(creature, 0)) + 1


func clear_retry_choice(creature: Node) -> void:
	target_choice_offsets.erase(creature)


func get_retry_choice(creature: Node) -> int:
	return int(target_choice_offsets.get(creature, 0))


func _find_grass_target(
	creature: Node,
	species_id: StringName,
	footprint: Vector2i
) -> Vector2i:
	var world_grid := _get_world_grid()
	var flag_tile: Vector2i = owner.call("get_flag_tile", species_id)

	if world_grid == null or flag_tile == INVALID_ANCHOR:
		return INVALID_ANCHOR

	var ranked_variant: Variant = world_grid.call(
		"find_best_grazing_targets",
		flag_tile,
		footprint,
		1,
		5,
		creature,
		24.0,
		0.5,
		16
	)

	if not (ranked_variant is Array):
		return INVALID_ANCHOR

	var candidate_entries: Array[Dictionary] = []
	var best_adult_count := 0

	for result_variant: Variant in ranked_variant:
		if not (result_variant is Dictionary):
			continue

		var result := result_variant as Dictionary
		var candidate_variant: Variant = result.get("anchor", INVALID_ANCHOR)

		if not (candidate_variant is Vector2i):
			continue

		var candidate: Vector2i = candidate_variant

		if not _anchor_fits_flag_area(species_id, candidate, footprint):
			continue

		if not bool(world_grid.call("can_place_footprint", candidate, footprint, creature)):
			continue

		if _is_target_reserved_by_other(creature, candidate, footprint):
			continue

		var adult_count := int(result.get("adult_count", 0))
		best_adult_count = maxi(best_adult_count, adult_count)
		candidate_entries.append({
			"anchor": candidate,
			"adult_count": adult_count
		})

	if candidate_entries.is_empty():
		return INVALID_ANCHOR

	var minimum_adult_count := maxi(
		best_adult_count - PASTURE_ADULT_COUNT_TOLERANCE,
		1
	)
	var candidates: Array[Vector2i] = []

	for entry: Dictionary in candidate_entries:
		if int(entry.get("adult_count", 0)) < minimum_adult_count:
			continue

		var anchor_variant: Variant = entry.get("anchor", INVALID_ANCHOR)

		if anchor_variant is Vector2i:
			candidates.append(anchor_variant)

	return _choose_spread_candidate(creature, species_id, candidates)


func _find_free_target(
	creature: Node,
	species_id: StringName,
	footprint: Vector2i
) -> Vector2i:
	var world_grid := _get_world_grid()
	var bounds := _get_flag_area_bounds(species_id)

	if world_grid == null or bounds.is_empty():
		return INVALID_ANCHOR

	var area_min: Vector2i = bounds.get("min", Vector2i.ZERO)
	var area_end: Vector2i = bounds.get("end", Vector2i.ZERO)
	var candidates: Array[Vector2i] = []

	for y in range(area_min.y, area_end.y - footprint.y + 1):
		for x in range(area_min.x, area_end.x - footprint.x + 1):
			var candidate := Vector2i(x, y)

			if not bool(world_grid.call("can_place_footprint", candidate, footprint, creature)):
				continue

			if _is_target_reserved_by_other(creature, candidate, footprint):
				continue

			candidates.append(candidate)

	return _choose_spread_candidate(creature, species_id, candidates)


func _choose_spread_candidate(
	creature: Node,
	species_id: StringName,
	candidates: Array[Vector2i]
) -> Vector2i:
	if candidates.is_empty():
		return INVALID_ANCHOR

	var navigation_anchor := _get_creature_navigation_anchor(creature)
	var remaining: Array[Vector2i] = []
	remaining.append_array(candidates)
	var retry_offset := maxi(int(target_choice_offsets.get(creature, 0)), 0)
	var selection_offset := posmod(retry_offset, remaining.size())
	var seed_value := int(creature.get_instance_id())
	var flag_tile: Vector2i = owner.call("get_flag_tile", species_id)
	var spread_seed := seed_value + flag_tile.x * 31 + flag_tile.y * 17

	while not remaining.is_empty():
		var nearest_distance := _estimate_anchor_steps(navigation_anchor, remaining[0])

		for candidate: Vector2i in remaining:
			nearest_distance = mini(
				nearest_distance,
				_estimate_anchor_steps(navigation_anchor, candidate)
			)

		var band_limit := nearest_distance + TARGET_DISTANCE_BAND_STEPS
		var band_candidates: Array[Vector2i] = []
		var farther_candidates: Array[Vector2i] = []

		for candidate: Vector2i in remaining:
			if _estimate_anchor_steps(navigation_anchor, candidate) <= band_limit:
				band_candidates.append(candidate)
			else:
				farther_candidates.append(candidate)

		if selection_offset < band_candidates.size():
			var start_index := posmod(spread_seed, band_candidates.size())
			return band_candidates[posmod(start_index + selection_offset, band_candidates.size())]

		selection_offset -= band_candidates.size()
		remaining = farther_candidates

	return INVALID_ANCHOR


func _get_creature_navigation_anchor(creature: Node) -> Vector2i:
	if creature == null or not is_instance_valid(creature):
		return Vector2i.ZERO

	if creature.has_method("get_navigation_anchor"):
		var navigation_variant: Variant = creature.call("get_navigation_anchor")

		if navigation_variant is Vector2i:
			return navigation_variant

	var anchor_variant: Variant = creature.get("anchor_tile")
	return anchor_variant if anchor_variant is Vector2i else Vector2i.ZERO


func _estimate_anchor_steps(from_anchor: Vector2i, to_anchor: Vector2i) -> int:
	return maxi(
		abs(to_anchor.x - from_anchor.x),
		abs(to_anchor.y - from_anchor.y)
	)


func _is_valid_assigned_target(
	creature: Node,
	species_id: StringName,
	target: Vector2i,
	footprint: Vector2i
) -> bool:
	var world_grid := _get_world_grid()

	if world_grid == null or not _anchor_fits_flag_area(species_id, target, footprint):
		return false

	if not bool(world_grid.call("can_place_footprint", target, footprint, creature)):
		return false

	return not _is_target_reserved_by_other(creature, target, footprint)


func _is_target_reserved_by_other(
	creature: Node,
	target: Vector2i,
	footprint: Vector2i
) -> bool:
	var world_grid := _get_world_grid()

	if world_grid == null:
		return false

	for tile_variant: Variant in world_grid.call("get_footprint_tiles", target, footprint):
		if not (tile_variant is Vector2i):
			continue

		var reserved_by := reserved_target_tiles.get(tile_variant, null) as Node

		if (
			reserved_by != null
			and reserved_by != creature
			and is_instance_valid(reserved_by)
			and not reserved_by.is_queued_for_deletion()
		):
			return true

	return false


func _anchor_fits_flag_area(
	species_id: StringName,
	anchor: Vector2i,
	footprint: Vector2i
) -> bool:
	var bounds := _get_flag_area_bounds(species_id)

	if bounds.is_empty():
		return false

	var area_min: Vector2i = bounds.get("min", Vector2i.ZERO)
	var area_end: Vector2i = bounds.get("end", Vector2i.ZERO)
	return (
		anchor.x >= area_min.x
		and anchor.y >= area_min.y
		and anchor.x + footprint.x <= area_end.x
		and anchor.y + footprint.y <= area_end.y
	)


func _get_flag_area_bounds(species_id: StringName) -> Dictionary:
	var flag_tile: Vector2i = owner.call("get_flag_tile", species_id)

	if flag_tile == INVALID_ANCHOR:
		return {}

	var area_min := flag_tile - Vector2i(FLAG_AREA_SIZE.x / 2, FLAG_AREA_SIZE.y / 2)
	return {"min": area_min, "end": area_min + FLAG_AREA_SIZE}


func _species_prefers_pasture(species_id: StringName) -> bool:
	var entry := PLAYER_SPECIES_CATALOG.get_entry(species_id)
	return int(entry.get(
		"flag_behaviour_type",
		PLAYER_SPECIES_CATALOG.FlagBehaviourType.GATHER
	)) == PLAYER_SPECIES_CATALOG.FlagBehaviourType.PASTURE


func _reserve_target_for_creature(
	creature: Node,
	target: Vector2i,
	footprint: Vector2i
) -> void:
	var world_grid := _get_world_grid()

	if world_grid == null:
		return

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


func _get_world_grid() -> Node:
	var grid := owner.call("get_world_grid") as Node
	return grid if grid != null and is_instance_valid(grid) else null
