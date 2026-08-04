extends Node
class_name EnemyEarthquakeSpell

# Profitable egg-zone search and execution for enemy earthquake. Strategic
# cadence, priority and reserve ownership remain in EnemySpellController.
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")

const EGG_STAGE_2 := 1
const INVALID_TILE := Vector2i(2147483647, 2147483647)

var controller = null
var last_earthquake_action_text := "ожидание выгодной кладки"
var last_earthquake_target_tile := INVALID_TILE
var last_earthquake_target_egg_count := 0
var last_earthquake_target_value := 0.0
var last_earthquake_target_stage_2_count := 0
var last_earthquake_candidate_center_count := 0


func setup(owner_controller: Node) -> void:
	controller = owner_controller


func try_cast() -> bool:
	if controller == null or not is_instance_valid(controller):
		return false
	return _try_cast_earthquake()


func get_debug_data() -> Dictionary:
	return {
		"earthquake_action_text": last_earthquake_action_text,
		"earthquake_energy_cost": _get_earthquake_cost(),
		"earthquake_target_tile": last_earthquake_target_tile,
		"earthquake_target_egg_count": last_earthquake_target_egg_count,
		"earthquake_target_value": last_earthquake_target_value,
		"earthquake_target_stage_2_count": last_earthquake_target_stage_2_count,
		"earthquake_candidate_center_count": last_earthquake_candidate_center_count
	}


func _format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]


func _try_cast_earthquake() -> bool:
	controller.refresh_runtime_references()
	_reset_last_earthquake_debug()

	if controller.world_grid == null or controller.nature_effects == null or controller.enemy_base == null:
		last_earthquake_action_text = "отложено: база или мировая система эффектов не найдена"
		return false
	if (
		not controller.nature_effects.has_method("can_apply_earthquake")
		or not controller.nature_effects.has_method("apply_earthquake")
		or not controller.nature_effects.has_method("get_earthquake_radius_tiles")
	):
		last_earthquake_action_text = "отложено: общий эффект землетрясения недоступен"
		return false

	var earthquake_cost := _get_earthquake_cost()

	if not controller.can_spend_combat_reserve(earthquake_cost):
		last_earthquake_action_text = "ожидание: в резерве меньше %d энки" % roundi(
			earthquake_cost
		)
		return false

	var egg_data := _collect_earthquake_egg_data()
	var player_eggs: Array = []

	for data: Dictionary in egg_data:
		if StringName(data.get("faction_id", &"")) == CREATURE_FACTION.PLAYER:
			player_eggs.append(data)

	var minimum_eggs := maxi(controller.minimum_earthquake_player_eggs, 2)

	if player_eggs.size() < minimum_eggs:
		last_earthquake_action_text = "ожидание: у игрока меньше %d яиц" % minimum_eggs
		return false

	var radius := maxi(int(controller.nature_effects.call("get_earthquake_radius_tiles")), 0)
	var base_anchor := _get_creature_or_base_anchor(controller.enemy_base)
	var candidate_centers := _build_earthquake_candidate_centers(
		egg_data,
		radius,
		base_anchor
	)
	var best_plan: Dictionary = {}
	var best_seen_plan: Dictionary = {}

	for center_variant: Variant in candidate_centers:
		if not (center_variant is Vector2i):
			continue

		var center: Vector2i = center_variant

		if controller.nature_effects.has_method("can_apply_at_tile") and not bool(
			controller.nature_effects.call("can_apply_at_tile", center)
		):
			continue

		last_earthquake_candidate_center_count += 1
		var plan := _evaluate_earthquake_center(center, egg_data, radius, base_anchor)

		if (
			int(plan.get("foreign_egg_count", 0)) == 0
			and int(plan.get("player_egg_count", 0)) >= minimum_eggs
			and _is_earthquake_plan_better(plan, best_seen_plan)
		):
			best_seen_plan = plan

		if not _is_earthquake_plan_profitable(plan):
			continue
		if _is_earthquake_plan_better(plan, best_plan):
			best_plan = plan

	PerformanceStats.add_counter(
		"enemy_earthquake_candidate_centers",
		last_earthquake_candidate_center_count
	)
	PerformanceStats.add_counter("enemy_earthquake_searches")

	if best_plan.is_empty():
		if best_seen_plan.is_empty():
			last_earthquake_action_text = (
				"ожидание: нет зоны минимум с %d яйцами игрока без своих"
				% minimum_eggs
			)
		else:
			_set_last_earthquake_target_debug(best_seen_plan)
			last_earthquake_action_text = (
				"невыгодно: лучшая зона %d яиц на %d, нужно больше %d"
				% [
					int(best_seen_plan.get("player_egg_count", 0)),
					roundi(float(best_seen_plan.get("total_value", 0.0))),
					roundi(earthquake_cost)
				]
			)
		return false

	var target_center: Vector2i = best_plan.get("center", INVALID_TILE)
	var current_plan := _evaluate_earthquake_center(
		target_center,
		_collect_earthquake_egg_data(),
		radius,
		base_anchor
	)

	if not _is_earthquake_plan_profitable(current_plan):
		last_earthquake_action_text = "отложено: выгодная кладка изменилась до удара"
		return false
	if not bool(controller.nature_effects.call("can_apply_earthquake", target_center)):
		last_earthquake_action_text = "отложено: выбранную область больше нельзя поразить"
		return false
	if not bool(controller.nature_effects.call("apply_earthquake", target_center)):
		last_earthquake_action_text = "не сработало: яйца не были уничтожены"
		return false
	if not controller.spend_combat_reserve_after_success(earthquake_cost):
		last_earthquake_action_text = "ошибка: землетрясение прошло без списания резерва"
		return false

	_set_last_earthquake_target_debug(current_plan)
	last_earthquake_action_text = "удар: %d яиц на %d энки, стадия 2: %d, центр %s" % [
		last_earthquake_target_egg_count,
		roundi(last_earthquake_target_value),
		last_earthquake_target_stage_2_count,
		_format_tile(last_earthquake_target_tile)
	]
	PerformanceStats.add_counter("enemy_earthquake_casts")
	PerformanceStats.add_counter(
		"enemy_earthquake_target_eggs",
		last_earthquake_target_egg_count
	)
	PerformanceStats.add_counter(
		"enemy_earthquake_target_value",
		roundi(last_earthquake_target_value)
	)
	return true


func _collect_earthquake_egg_data() -> Array:
	var result: Array = []

	for egg_variant: Variant in get_tree().get_nodes_in_group("eggs"):
		var egg := egg_variant as Node

		if egg == null or not is_instance_valid(egg) or egg.is_queued_for_deletion():
			continue

		var raw_anchor: Variant = egg.get("anchor_tile")

		if not (raw_anchor is Vector2i):
			continue

		var footprint := Vector2i.ONE

		if egg.has_method("get_current_footprint"):
			var raw_footprint: Variant = egg.call("get_current_footprint")

			if raw_footprint is Vector2i:
				footprint = raw_footprint

		var faction_id := CREATURE_FACTION.get_id(egg)
		var species_id := _get_earthquake_egg_species_id(egg)
		var value := 0.0

		if faction_id == CREATURE_FACTION.PLAYER:
			value = _get_player_egg_value(species_id)

		result.append({
			"egg": egg,
			"faction_id": faction_id,
			"species_id": species_id,
			"value": value,
			"stage_2": int(egg.get("current_stage")) == EGG_STAGE_2,
			"anchor": raw_anchor,
			"footprint": footprint
		})

	return result


func _build_earthquake_candidate_centers(
	egg_data: Array,
	radius: int,
	base_anchor: Vector2i
) -> Array:
	if controller.world_grid == null:
		return []

	var raw_map_min: Variant = controller.world_grid.get("map_min")
	var raw_map_max: Variant = controller.world_grid.get("map_max")

	if not (raw_map_min is Vector2i) or not (raw_map_max is Vector2i):
		return []

	var map_min: Vector2i = raw_map_min
	var map_max: Vector2i = raw_map_max
	var x_values := _build_earthquake_axis_candidates(
		egg_data,
		radius,
		0,
		base_anchor.x,
		map_min.x,
		map_max.x
	)
	var y_values := _build_earthquake_axis_candidates(
		egg_data,
		radius,
		1,
		base_anchor.y,
		map_min.y,
		map_max.y
	)
	var centers: Array = []

	for x: int in x_values:
		for y: int in y_values:
			centers.append(Vector2i(x, y))

	return centers


func _build_earthquake_axis_candidates(
	egg_data: Array,
	radius: int,
	axis: int,
	base_coordinate: int,
	map_minimum: int,
	map_maximum: int
) -> Array[int]:
	var breakpoints: Dictionary = {}
	breakpoints[map_minimum] = true
	breakpoints[map_maximum + 1] = true

	for data: Dictionary in egg_data:
		var anchor: Vector2i = data.get("anchor", Vector2i.ZERO)
		var footprint: Vector2i = data.get("footprint", Vector2i.ONE)
		var egg_max := anchor + footprint - Vector2i.ONE
		var egg_minimum := anchor.x if axis == 0 else anchor.y
		var egg_maximum := egg_max.x if axis == 0 else egg_max.y
		var interval_minimum := maxi(egg_minimum - radius, map_minimum)
		var interval_maximum := mini(egg_maximum + radius, map_maximum)

		if interval_minimum > interval_maximum:
			continue

		breakpoints[interval_minimum] = true
		breakpoints[interval_maximum + 1] = true

	var sorted_breakpoints: Array = breakpoints.keys()
	sorted_breakpoints.sort()
	var result: Array[int] = []

	for index in range(sorted_breakpoints.size() - 1):
		var segment_minimum := maxi(int(sorted_breakpoints[index]), map_minimum)
		var segment_maximum := mini(
			int(sorted_breakpoints[index + 1]) - 1,
			map_maximum
		)

		if segment_minimum > segment_maximum:
			continue

		# Every egg-overlap result is constant inside this segment. Use the point
		# nearest the enemy base so the final distance tie-break is exact, not an
		# approximation based only on egg interval edges.
		result.append(clampi(base_coordinate, segment_minimum, segment_maximum))

	return result


func _evaluate_earthquake_center(
	center: Vector2i,
	egg_data: Array,
	radius: int,
	base_anchor: Vector2i
) -> Dictionary:
	var player_egg_count := 0
	var foreign_egg_count := 0
	var stage_2_count := 0
	var total_value := 0.0

	for data: Dictionary in egg_data:
		if not _earthquake_area_overlaps_egg_data(center, radius, data):
			continue

		var faction_id := StringName(data.get("faction_id", &""))

		if faction_id != CREATURE_FACTION.PLAYER:
			foreign_egg_count += 1
			continue

		player_egg_count += 1
		total_value += maxf(float(data.get("value", 0.0)), 0.0)

		if bool(data.get("stage_2", false)):
			stage_2_count += 1

	return {
		"center": center,
		"player_egg_count": player_egg_count,
		"foreign_egg_count": foreign_egg_count,
		"stage_2_count": stage_2_count,
		"total_value": total_value,
		"base_distance": _tile_distance(base_anchor, center)
	}


func _earthquake_area_overlaps_egg_data(
	center: Vector2i,
	radius: int,
	data: Dictionary
) -> bool:
	var anchor: Vector2i = data.get("anchor", Vector2i.ZERO)
	var footprint: Vector2i = data.get("footprint", Vector2i.ONE)
	var egg_max := anchor + footprint - Vector2i.ONE
	var area_min := center - Vector2i.ONE * radius
	var area_max := center + Vector2i.ONE * radius
	return (
		anchor.x <= area_max.x
		and egg_max.x >= area_min.x
		and anchor.y <= area_max.y
		and egg_max.y >= area_min.y
	)


func _is_earthquake_plan_profitable(plan: Dictionary) -> bool:
	return (
		int(plan.get("foreign_egg_count", 0)) == 0
		and int(plan.get("player_egg_count", 0)) >= maxi(
			controller.minimum_earthquake_player_eggs,
			2
		)
		and float(plan.get("total_value", 0.0)) > _get_earthquake_cost() + 0.001
	)


func _is_earthquake_plan_better(candidate: Dictionary, current_best: Dictionary) -> bool:
	if current_best.is_empty():
		return true

	var candidate_value := float(candidate.get("total_value", 0.0))
	var best_value := float(current_best.get("total_value", 0.0))

	if not is_equal_approx(candidate_value, best_value):
		return candidate_value > best_value

	var candidate_stage_2 := int(candidate.get("stage_2_count", 0))
	var best_stage_2 := int(current_best.get("stage_2_count", 0))

	if candidate_stage_2 != best_stage_2:
		return candidate_stage_2 > best_stage_2

	var candidate_count := int(candidate.get("player_egg_count", 0))
	var best_count := int(current_best.get("player_egg_count", 0))

	if candidate_count != best_count:
		return candidate_count > best_count

	var candidate_distance := float(candidate.get("base_distance", INF))
	var best_distance := float(current_best.get("base_distance", INF))

	if not is_equal_approx(candidate_distance, best_distance):
		return candidate_distance < best_distance

	var candidate_center: Vector2i = candidate.get("center", Vector2i.ZERO)
	var best_center: Vector2i = current_best.get("center", Vector2i.ZERO)

	if candidate_center.y != best_center.y:
		return candidate_center.y < best_center.y
	return candidate_center.x < best_center.x


func _get_earthquake_egg_species_id(egg: Node) -> StringName:
	var hatch_species := egg.get("hatch_species_data") as CreatureSpeciesData

	if hatch_species != null:
		return StringName(hatch_species.species_id)

	return StringName(str(egg.get("species_id")))


func _get_player_egg_value(species_id: StringName) -> float:
	var entry: Dictionary = PLAYER_SPECIES_CATALOG.get_entry(species_id)
	return maxf(float(entry.get("egg_purchase_cost", 0.0)), 0.0)


func _get_earthquake_cost() -> float:
	return maxf(controller.earthquake_energy_cost, 0.0)


func _reset_last_earthquake_debug() -> void:
	last_earthquake_target_tile = INVALID_TILE
	last_earthquake_target_egg_count = 0
	last_earthquake_target_value = 0.0
	last_earthquake_target_stage_2_count = 0
	last_earthquake_candidate_center_count = 0


func _set_last_earthquake_target_debug(plan: Dictionary) -> void:
	last_earthquake_target_tile = plan.get("center", INVALID_TILE)
	last_earthquake_target_egg_count = int(plan.get("player_egg_count", 0))
	last_earthquake_target_value = float(plan.get("total_value", 0.0))
	last_earthquake_target_stage_2_count = int(plan.get("stage_2_count", 0))


func _get_creature_or_base_anchor(node: Node) -> Vector2i:
	if node == null or not is_instance_valid(node):
		return Vector2i.ZERO
	if node.has_method("get_navigation_anchor"):
		var navigation_anchor: Variant = node.call("get_navigation_anchor")
		if navigation_anchor is Vector2i:
			return navigation_anchor

	var raw_anchor: Variant = node.get("anchor_tile")
	return raw_anchor if raw_anchor is Vector2i else Vector2i.ZERO


func _tile_distance(from_tile: Vector2i, to_tile: Vector2i) -> float:
	return Vector2(from_tile).distance_to(Vector2(to_tile))
