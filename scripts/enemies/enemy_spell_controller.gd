extends Node2D
class_name EnemySpellController

# Enemy spell decisions stay separate from population production. The first
# spell listens to the four-second enemy-AI snapshot and casts shared world rain
# only when adult enemy herbivore satiety falls below the snapshot threshold.
#
# Rain targeting stays local to the visible map-clipped contour around the enemy
# base. It scores immediate unique grass spread plus DryGround recovery, but only
# when that DryGround is cardinally adjacent to existing grass. The ecological
# score is then adjusted by nearby adult enemy-herbivore demand. Isolated desert
# and young-grass growth remain intentionally ignored.
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const ENEMY_SPECIES_CATALOG := preload("res://scripts/catalogs/enemy_species_catalog.gd")

const MATURE_GRASS_STAGE := 3
const INITIALIZATION_RETRY_FRAMES := 12
const COMBAT_RESERVE_SAVE_VERSION := 2
const RAIN_PAYMENT_NONE := &"none"
const RAIN_PAYMENT_ORDINARY := &"ordinary"
const RAIN_PAYMENT_RESERVE := &"reserve"
const INVALID_TILE := Vector2i(2147483647, 2147483647)
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.UP,
	Vector2i.DOWN
]

@export var rain_energy_cost := 50.0
@export var minimum_rain_target_score := 1
@export var new_grass_score := 10
@export var dry_ground_zero_hit_score := 5
@export var dry_ground_one_hit_score := 7
@export var dry_ground_two_hit_score := 9
@export var empty_area_score_multiplier := 0.5
@export var herbivore_demand_multiplier_step := 0.2
@export var maximum_herbivore_score_multiplier := 2.0
@export var herbivore_near_distance_tiles := 3
@export var herbivore_medium_distance_tiles := 6
@export var herbivore_far_distance_tiles := 10
@export_range(0.0, 1.0, 0.05) var herbivore_medium_demand_weight := 0.5
@export_range(0.0, 1.0, 0.05) var herbivore_far_demand_weight := 0.25
@export var rain_search_radius_tiles := 20
@export var base_proximity_reference_distance_tiles := 20
@export var base_proximity_multiplier_step := 0.005
@export var rain_area_frame_duration_seconds := 4.0
@export var search_area_frame_color := Color(1.0, 0.48, 0.12, 0.82)
@export var rain_area_frame_color := Color(0.20, 0.78, 1.0, 0.95)
@export var search_area_frame_line_width := 8.0
@export var rain_area_frame_line_width := 10.0

# Match time grows only the reserve capacity. Actual reserve energy is diverted
# from real enemy-creature income by EnemyEnergy and never appears from time alone.
@export var combat_reserve_unlock_minutes := 10
@export var combat_reserve_late_rate_after_minutes := 20
@export var combat_reserve_capacity_gain_per_minute := 100.0
@export var combat_reserve_capacity_late_gain_per_minute := 200.0
@export var combat_reserve_maximum := 3000.0
@export var combat_reserve_minimum_after_cast := 500.0

var world_grid: Node = null
var nature_effects: Node = null
var enemy_ai: Node = null
var enemy_energy: Node = null
var enemy_base: Node2D = null

var combat_reserve := 0.0
var combat_reserve_capacity := 0.0
var next_combat_reserve_capacity_tick_minute := 0
var last_combat_reserve_income_deposit := 0.0

var search_area_bounds := Rect2i()
var has_search_area_bounds := false
var visible_rain_frame_tile := INVALID_TILE
var rain_frame_remaining_seconds := 0.0

var last_action_text := "ожидание первого решения по спеллам"
var last_rain_target_tile := INVALID_TILE
var last_grass_entries_scanned := 0
var last_mature_grass_count := 0
var last_spread_ready_grass_count := 0
var last_productive_grass_count := 0
var last_unique_spawn_target_count := 0
var last_adjacent_dry_ground_count := 0
var last_candidate_center_count := 0
var last_best_predicted_new_grass := 0
var last_best_dry_ground_zero_hit_count := 0
var last_best_dry_ground_one_hit_count := 0
var last_best_dry_ground_two_hit_count := 0
var last_best_dry_ground_score := 0
var last_eligible_herbivore_count := 0
var last_best_near_herbivore_count := 0
var last_best_medium_herbivore_count := 0
var last_best_far_herbivore_count := 0
var last_best_herbivore_demand := 0.0
var last_best_demand_multiplier := 0.5
var last_best_base_distance_tiles := 20
var last_best_base_proximity_multiplier := 1.0
var last_best_base_score := 0
var last_best_total_score := 0.0
var last_actual_new_grass := 0
var last_search_duration_usec := 0
var max_search_duration_usec := 0
var total_search_count := 0
var last_apply_duration_usec := 0
var max_apply_duration_usec := 0
var total_apply_count := 0


func _ready() -> void:
	add_to_group("enemy_spell_controller")
	_reset_combat_reserve_for_new_session()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 500
	call_deferred("_initialize_runtime")


func _process(delta: float) -> void:
	_update_combat_reserve_capacity_from_match_time()

	if not has_search_area_bounds:
		_refresh_runtime_references()
		if _refresh_search_area_bounds():
			queue_redraw()

	if rain_frame_remaining_seconds <= 0.0:
		return

	# The result outline uses real seconds while gameplay is running, but this
	# PAUSABLE node receives no process ticks while the in-game menu pauses the
	# SceneTree. Dividing by time_scale keeps 1x/2x/4x simulation speeds from
	# shortening the four-second inspection window.
	var safe_time_scale := maxf(Engine.time_scale, 0.0001)
	rain_frame_remaining_seconds = maxf(
		rain_frame_remaining_seconds - delta / safe_time_scale,
		0.0
	)

	if rain_frame_remaining_seconds > 0.0:
		return

	visible_rain_frame_tile = INVALID_TILE
	queue_redraw()


func _draw() -> void:
	if has_search_area_bounds:
		var search_rect := _tile_bounds_to_local_rect(search_area_bounds)

		if search_rect.size.x > 0.0 and search_rect.size.y > 0.0:
			draw_rect(
				search_rect,
				search_area_frame_color,
				false,
				maxf(search_area_frame_line_width, 1.0),
				true
			)

	if (
		visible_rain_frame_tile == INVALID_TILE
		or rain_frame_remaining_seconds <= 0.0
	):
		return

	var rain_radius := _get_rain_radius_tiles()
	if rain_radius <= 0:
		return

	var rain_size := rain_radius * 2 + 1
	var rain_bounds := Rect2i(
		visible_rain_frame_tile - Vector2i(rain_radius, rain_radius),
		Vector2i(rain_size, rain_size)
	)
	var rain_rect := _tile_bounds_to_local_rect(rain_bounds)

	if rain_rect.size.x > 0.0 and rain_rect.size.y > 0.0:
		draw_rect(
			rain_rect,
			rain_area_frame_color,
			false,
			maxf(rain_area_frame_line_width, 1.0),
			true
		)


func _exit_tree() -> void:
	_disconnect_enemy_ai()


func _initialize_runtime() -> void:
	for _attempt in range(INITIALIZATION_RETRY_FRAMES):
		_refresh_runtime_references()

		if _connect_enemy_ai():
			_update_combat_reserve_capacity_from_match_time()
			_refresh_search_area_bounds()
			queue_redraw()
			return

		await get_tree().process_frame

	push_warning("EnemySpellController: enemy AI turn signal was not found.")


func _connect_enemy_ai() -> bool:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		return false
	if not enemy_ai.has_signal("turn_completed"):
		return false

	var turn_callable := Callable(self, "_on_enemy_turn_completed")

	if not enemy_ai.is_connected("turn_completed", turn_callable):
		enemy_ai.connect("turn_completed", turn_callable)

	return true


func _disconnect_enemy_ai() -> void:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		return

	var turn_callable := Callable(self, "_on_enemy_turn_completed")

	if enemy_ai.has_signal("turn_completed") and enemy_ai.is_connected(
		"turn_completed", turn_callable
	):
		enemy_ai.disconnect("turn_completed", turn_callable)


func _on_enemy_turn_completed(snapshot: Dictionary) -> void:
	var adult_herbivore_count := int(snapshot.get("adult_herbivore_count", 0))
	var average_satiety := float(
		snapshot.get("average_adult_herbivore_satiety_percent", -1.0)
	)
	var satiety_threshold := clampf(
		float(snapshot.get("minimum_average_herbivore_satiety_percent", 40.0)),
		0.0,
		100.0
	)

	if adult_herbivore_count <= 0 or average_satiety < 0.0:
		return
	if average_satiety >= satiety_threshold:
		return

	_try_cast_rain_for_hungry_herd()


func _try_cast_rain_for_hungry_herd() -> bool:
	_refresh_runtime_references()
	_reset_last_search_stats()

	if world_grid == null or nature_effects == null:
		last_action_text = "дождь отложен: мировая система эффектов не найдена"
		return false

	if not _refresh_search_area_bounds():
		last_action_text = "дождь отложен: область вокруг базы не найдена"
		return false

	if (
		enemy_energy == null
		or not enemy_energy.has_method("can_spend")
		or not enemy_energy.has_method("spend")
		or not enemy_energy.has_method("add_energy")
	):
		last_action_text = "дождь отложен: хранилище энки противника не найдено"
		return false

	var safe_cost := maxf(rain_energy_cost, 0.0)
	var rain_payment_source := _get_rain_payment_source(safe_cost)

	# Ordinary energy has priority. The reserve is a full-cost fallback only; the
	# two stores are never combined for one rain cast.
	if rain_payment_source == RAIN_PAYMENT_NONE:
		last_action_text = "дождь отложен: не хватает обычной энки и резерва"
		PerformanceStats.add_counter("enemy_rain_wait_energy")
		return false

	var target_data := _find_best_rain_target()

	if target_data.is_empty():
		last_action_text = "дождь отложен: рядом с травой нет полезной цели"
		PerformanceStats.add_counter("enemy_rain_no_target")
		return false

	var target_variant: Variant = target_data.get("tile", INVALID_TILE)

	if not (target_variant is Vector2i):
		last_action_text = "дождь отложен: рассчитана неверная цель"
		return false

	var target_tile: Vector2i = target_variant

	if (
		not nature_effects.has_method("can_apply_rain")
		or not nature_effects.has_method("apply_rain")
		or not bool(nature_effects.call("can_apply_rain", target_tile))
	):
		last_action_text = "дождь отложен: выбранная область больше не подходит"
		return false

	if not _spend_rain_energy(rain_payment_source, safe_cost):
		last_action_text = "дождь отложен: источник оплаты изменился"
		return false

	var grass_count_before := _get_registered_grass_count()
	var apply_start_usec := Time.get_ticks_usec()
	var rain_applied := bool(nature_effects.call("apply_rain", target_tile))
	_finish_apply_measurement(apply_start_usec)
	var grass_count_after := _get_registered_grass_count()
	last_actual_new_grass = maxi(grass_count_after - grass_count_before, 0)

	if not rain_applied:
		_refund_rain_energy(rain_payment_source, safe_cost)
		last_action_text = "дождь не сработал: энка возвращена в источник оплаты"
		PerformanceStats.add_counter("enemy_rain_failed_refunded")
		return false

	last_rain_target_tile = target_tile
	_show_rain_area_frame(target_tile)
	last_action_text = (
		"дождь (%s): %s, балл %.1f = база %d × спрос %.2f × близость %.3f; прогноз +%d / реально +%d"
		% [
			_format_rain_payment_source(rain_payment_source),
			_format_tile(target_tile),
			last_best_total_score,
			last_best_base_score,
			last_best_demand_multiplier,
			last_best_base_proximity_multiplier,
			last_best_predicted_new_grass,
			last_actual_new_grass
		]
	)
	PerformanceStats.add_counter("enemy_rain_casts")
	PerformanceStats.add_counter(
		"enemy_rain_predicted_new_grass",
		last_best_predicted_new_grass
	)
	PerformanceStats.add_counter(
		"enemy_rain_actual_new_grass",
		last_actual_new_grass
	)
	PerformanceStats.add_counter(
		"enemy_rain_prediction_gap",
		last_best_predicted_new_grass - last_actual_new_grass
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_zero_hit",
		last_best_dry_ground_zero_hit_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_one_hit",
		last_best_dry_ground_one_hit_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_two_hit",
		last_best_dry_ground_two_hit_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_dry_ground_score",
		last_best_dry_ground_score
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_total_score",
		roundi(last_best_total_score)
	)
	PerformanceStats.add_counter(
		"enemy_rain_selected_eligible_herbivores",
		last_eligible_herbivore_count
	)
	PerformanceStats.set_max_value(
		"enemy_rain_selected_demand_multiplier_max",
		last_best_demand_multiplier
	)
	return true


func _find_best_rain_target() -> Dictionary:
	var search_start_usec := Time.get_ticks_usec()
	var result: Dictionary = {}

	if not _can_scan_rain_target_data():
		_finish_search_measurement(search_start_usec)
		return result

	var rain_radius := _get_rain_radius_tiles()

	if rain_radius <= 0:
		_finish_search_measurement(search_start_usec)
		return result

	var grass_registry_variant: Variant = world_grid.get("grass_by_tile")
	var grass_registry: Dictionary = grass_registry_variant as Dictionary
	var source_tiles_by_spawn_target: Dictionary = {}

	# Map each unique cell that can receive new grass to all mature sources able
	# to create it. The future cell counts once even when several sources share it.
	for grass_tile_variant: Variant in grass_registry.keys():
		last_grass_entries_scanned += 1

		if not (grass_tile_variant is Vector2i):
			continue

		var grass_tile: Vector2i = grass_tile_variant

		if not _is_tile_inside_search_area(grass_tile):
			continue

		var grass := grass_registry.get(grass_tile, null) as Node

		if not _is_mature_grass(grass):
			continue

		last_mature_grass_count += 1

		if bool(grass.get("has_tried_to_spread")):
			continue

		last_spread_ready_grass_count += 1
		var immediate_spawn_tiles := _get_immediate_spawn_tiles(grass_tile)

		if immediate_spawn_tiles.is_empty():
			continue

		last_productive_grass_count += 1

		for spawn_tile: Vector2i in immediate_spawn_tiles:
			var source_set_variant: Variant = source_tiles_by_spawn_target.get(
				spawn_tile, null
			)
			var source_set: Dictionary = {}

			if source_set_variant is Dictionary:
				source_set = source_set_variant as Dictionary

			source_set[grass_tile] = true
			source_tiles_by_spawn_target[spawn_tile] = source_set

	last_unique_spawn_target_count = source_tiles_by_spawn_target.size()

	var candidate_new_grass: Dictionary = {}
	var candidate_dry_ground_score: Dictionary = {}
	var candidate_dry_ground_zero_hit: Dictionary = {}
	var candidate_dry_ground_one_hit: Dictionary = {}
	var candidate_dry_ground_two_hit: Dictionary = {}

	# Each unique future grass cell adds its weight once to every center that
	# covers at least one mature source capable of creating that cell.
	for source_set_variant: Variant in source_tiles_by_spawn_target.values():
		if not (source_set_variant is Dictionary):
			continue

		var source_set: Dictionary = source_set_variant as Dictionary
		var covered_centers: Dictionary = {}

		for source_tile_variant: Variant in source_set.keys():
			if source_tile_variant is Vector2i:
				_append_covering_centers(
					covered_centers,
					source_tile_variant,
					rain_radius
				)

		for center_variant: Variant in covered_centers.keys():
			if center_variant is Vector2i:
				candidate_new_grass[center_variant] = int(
					candidate_new_grass.get(center_variant, 0)
				) + 1

	# DryGround is useful only when grass can eventually occupy it. Therefore an
	# isolated desert cell is ignored, while a cardinal grass neighbour makes it
	# eligible even when no immediate spread is currently possible.
	var dry_ground_hit_lookup := _get_dry_ground_hit_lookup()
	var search_min := search_area_bounds.position
	var search_max := (
		search_area_bounds.position
		+ search_area_bounds.size
		- Vector2i.ONE
	)

	for tile_y in range(search_min.y, search_max.y + 1):
		for tile_x in range(search_min.x, search_max.x + 1):
			var dry_tile := Vector2i(tile_x, tile_y)

			if not bool(world_grid.call("has_dry_ground_at_tile", dry_tile)):
				continue
			if not _has_cardinal_grass_neighbor(dry_tile):
				continue

			last_adjacent_dry_ground_count += 1
			var rain_hits := clampi(int(dry_ground_hit_lookup.get(dry_tile, 0)), 0, 2)
			var dry_weight := _get_dry_ground_score_for_hits(rain_hits)
			var dry_covered_centers: Dictionary = {}
			_append_covering_centers(dry_covered_centers, dry_tile, rain_radius)

			for center_variant: Variant in dry_covered_centers.keys():
				if not (center_variant is Vector2i):
					continue

				candidate_dry_ground_score[center_variant] = int(
					candidate_dry_ground_score.get(center_variant, 0)
				) + dry_weight

				match rain_hits:
					0:
						candidate_dry_ground_zero_hit[center_variant] = int(
							candidate_dry_ground_zero_hit.get(center_variant, 0)
						) + 1
					1:
						candidate_dry_ground_one_hit[center_variant] = int(
							candidate_dry_ground_one_hit.get(center_variant, 0)
						) + 1
					2:
						candidate_dry_ground_two_hit[center_variant] = int(
							candidate_dry_ground_two_hit.get(center_variant, 0)
						) + 1

	var candidate_centers: Dictionary = {}

	for center_variant: Variant in candidate_new_grass.keys():
		if center_variant is Vector2i:
			candidate_centers[center_variant] = true

	for center_variant: Variant in candidate_dry_ground_score.keys():
		if center_variant is Vector2i:
			candidate_centers[center_variant] = true

	last_candidate_center_count = candidate_centers.size()
	var herbivore_footprints := _collect_eligible_enemy_herbivore_footprints()
	last_eligible_herbivore_count = herbivore_footprints.size()
	var herbivore_demand_by_center := _build_herbivore_demand_map(
		herbivore_footprints,
		candidate_centers,
		rain_radius
	)
	var best_center := INVALID_TILE
	var best_total_score := -1.0
	var best_base_score := 0
	var best_predicted_new_grass := 0
	var best_dry_ground_zero_hit_count := 0
	var best_dry_ground_one_hit_count := 0
	var best_dry_ground_two_hit_count := 0
	var best_dry_ground_score := 0
	var best_herbivore_demand := 0.0
	var best_demand_multiplier := _get_herbivore_demand_multiplier(0.0)
	var best_base_distance_tiles := _get_base_proximity_reference_distance_tiles()
	var best_base_proximity_multiplier := 1.0
	var safe_new_grass_score := maxi(new_grass_score, 0)

	for center_variant: Variant in candidate_centers.keys():
		if not (center_variant is Vector2i):
			continue

		var center_tile: Vector2i = center_variant
		var predicted_new_grass := int(candidate_new_grass.get(center_tile, 0))
		var dry_score := int(candidate_dry_ground_score.get(center_tile, 0))
		var base_score := predicted_new_grass * safe_new_grass_score + dry_score
		var herbivore_demand := float(herbivore_demand_by_center.get(center_tile, 0.0))
		var demand_multiplier := _get_herbivore_demand_multiplier(herbivore_demand)
		var base_distance_tiles := _get_distance_from_rain_area_to_enemy_base(
			center_tile,
			rain_radius
		)
		var base_proximity_multiplier := _get_base_proximity_multiplier(
			base_distance_tiles
		)
		var total_score := (
			float(base_score)
			* demand_multiplier
			* base_proximity_multiplier
		)

		if _is_better_candidate(
			center_tile,
			total_score,
			best_center,
			best_total_score
		):
			best_center = center_tile
			best_total_score = total_score
			best_base_score = base_score
			best_predicted_new_grass = predicted_new_grass
			best_dry_ground_zero_hit_count = int(
				candidate_dry_ground_zero_hit.get(center_tile, 0)
			)
			best_dry_ground_one_hit_count = int(
				candidate_dry_ground_one_hit.get(center_tile, 0)
			)
			best_dry_ground_two_hit_count = int(
				candidate_dry_ground_two_hit.get(center_tile, 0)
			)
			best_dry_ground_score = dry_score
			best_herbivore_demand = herbivore_demand
			best_demand_multiplier = demand_multiplier
			best_base_distance_tiles = base_distance_tiles
			best_base_proximity_multiplier = base_proximity_multiplier

	var best_demand_breakdown := _get_herbivore_demand_breakdown(
		best_center,
		herbivore_footprints,
		rain_radius
	)
	last_best_predicted_new_grass = best_predicted_new_grass
	last_best_dry_ground_zero_hit_count = best_dry_ground_zero_hit_count
	last_best_dry_ground_one_hit_count = best_dry_ground_one_hit_count
	last_best_dry_ground_two_hit_count = best_dry_ground_two_hit_count
	last_best_dry_ground_score = best_dry_ground_score
	last_best_near_herbivore_count = int(best_demand_breakdown.get("near", 0))
	last_best_medium_herbivore_count = int(best_demand_breakdown.get("medium", 0))
	last_best_far_herbivore_count = int(best_demand_breakdown.get("far", 0))
	last_best_herbivore_demand = best_herbivore_demand
	last_best_demand_multiplier = best_demand_multiplier
	last_best_base_distance_tiles = best_base_distance_tiles
	last_best_base_proximity_multiplier = best_base_proximity_multiplier
	last_best_base_score = best_base_score
	last_best_total_score = maxf(best_total_score, 0.0)
	_finish_search_measurement(search_start_usec)

	if (
		best_center == INVALID_TILE
		or best_total_score < float(maxi(minimum_rain_target_score, 1))
	):
		return result

	return {
		"tile": best_center,
		"predicted_new_grass": best_predicted_new_grass,
		"dry_ground_zero_hit_count": best_dry_ground_zero_hit_count,
		"dry_ground_one_hit_count": best_dry_ground_one_hit_count,
		"dry_ground_two_hit_count": best_dry_ground_two_hit_count,
		"dry_ground_score": best_dry_ground_score,
		"near_herbivore_count": last_best_near_herbivore_count,
		"medium_herbivore_count": last_best_medium_herbivore_count,
		"far_herbivore_count": last_best_far_herbivore_count,
		"herbivore_demand": best_herbivore_demand,
		"demand_multiplier": best_demand_multiplier,
		"base_distance_tiles": best_base_distance_tiles,
		"base_proximity_multiplier": best_base_proximity_multiplier,
		"base_score": best_base_score,
		"total_score": best_total_score
	}


func _finish_search_measurement(search_start_usec: int) -> void:
	last_search_duration_usec = maxi(Time.get_ticks_usec() - search_start_usec, 0)
	max_search_duration_usec = maxi(max_search_duration_usec, last_search_duration_usec)
	total_search_count += 1

	PerformanceStats.add_counter("enemy_rain_searches")
	PerformanceStats.add_counter("enemy_rain_search_usec", last_search_duration_usec)
	PerformanceStats.add_counter("enemy_rain_grass_scanned", last_grass_entries_scanned)
	PerformanceStats.add_counter("enemy_rain_mature_grass", last_mature_grass_count)
	PerformanceStats.add_counter(
		"enemy_rain_spread_ready_grass",
		last_spread_ready_grass_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_productive_grass",
		last_productive_grass_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_unique_spawn_targets",
		last_unique_spawn_target_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_candidate_centers",
		last_candidate_center_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_adjacent_dry_ground",
		last_adjacent_dry_ground_count
	)
	PerformanceStats.add_counter(
		"enemy_rain_best_dry_ground_score",
		last_best_dry_ground_score
	)
	PerformanceStats.add_counter(
		"enemy_rain_best_total_score",
		roundi(last_best_total_score)
	)
	PerformanceStats.add_counter(
		"enemy_rain_eligible_herbivores",
		last_eligible_herbivore_count
	)
	PerformanceStats.set_max_value(
		"enemy_rain_search_max_usec",
		last_search_duration_usec
	)
	PerformanceStats.set_max_value(
		"enemy_rain_best_spread_max",
		last_best_predicted_new_grass
	)
	PerformanceStats.set_max_value(
		"enemy_rain_best_total_score_max",
		last_best_total_score
	)
	PerformanceStats.set_max_value(
		"enemy_rain_demand_multiplier_max",
		last_best_demand_multiplier
	)


func _finish_apply_measurement(apply_start_usec: int) -> void:
	last_apply_duration_usec = maxi(Time.get_ticks_usec() - apply_start_usec, 0)
	max_apply_duration_usec = maxi(max_apply_duration_usec, last_apply_duration_usec)
	total_apply_count += 1

	PerformanceStats.add_counter("enemy_rain_apply_calls")
	PerformanceStats.add_counter("enemy_rain_apply_usec", last_apply_duration_usec)
	PerformanceStats.set_max_value(
		"enemy_rain_apply_max_usec",
		last_apply_duration_usec
	)


func _can_scan_rain_target_data() -> bool:
	if world_grid == null or not is_instance_valid(world_grid):
		return false
	if not world_grid.has_method("is_tile_inside_map"):
		return false
	if not world_grid.has_method("can_host_grass"):
		return false
	if not world_grid.has_method("has_grass_at_tile"):
		return false
	if not world_grid.has_method("has_dry_ground_at_tile"):
		return false
	if not world_grid.has_method("get_dry_ground_rain_hit_data"):
		return false

	var grass_registry_variant: Variant = world_grid.get("grass_by_tile")
	return grass_registry_variant is Dictionary


func _is_mature_grass(grass: Node) -> bool:
	return (
		grass != null
		and is_instance_valid(grass)
		and not grass.is_queued_for_deletion()
		and int(grass.get("current_stage")) == MATURE_GRASS_STAGE
	)


func _get_immediate_spawn_tiles(grass_tile: Vector2i) -> Array[Vector2i]:
	var spawn_tiles: Array[Vector2i] = []

	for offset: Vector2i in CARDINAL_OFFSETS:
		var target_tile := grass_tile + offset

		if not bool(world_grid.call("is_tile_inside_map", target_tile)):
			continue
		if not _is_tile_inside_search_area(target_tile):
			continue
		if bool(world_grid.call("has_grass_at_tile", target_tile)):
			continue
		if not bool(world_grid.call("can_host_grass", target_tile)):
			continue

		spawn_tiles.append(target_tile)

	return spawn_tiles


func _has_cardinal_grass_neighbor(tile: Vector2i) -> bool:
	for offset: Vector2i in CARDINAL_OFFSETS:
		var neighbor_tile := tile + offset

		if not bool(world_grid.call("is_tile_inside_map", neighbor_tile)):
			continue
		if bool(world_grid.call("has_grass_at_tile", neighbor_tile)):
			return true

	return false


func _get_dry_ground_hit_lookup() -> Dictionary:
	var hit_lookup: Dictionary = {}
	var hit_data_variant: Variant = world_grid.call("get_dry_ground_rain_hit_data")

	if not (hit_data_variant is Array):
		return hit_lookup

	var hit_data: Array = hit_data_variant as Array

	for record_variant: Variant in hit_data:
		if not (record_variant is Dictionary):
			continue

		var record: Dictionary = record_variant as Dictionary
		var tile := Vector2i(
			int(record.get("x", 0)),
			int(record.get("y", 0))
		)
		var hits := clampi(int(record.get("hits", 0)), 0, 2)

		if hits > 0 and bool(world_grid.call("has_dry_ground_at_tile", tile)):
			hit_lookup[tile] = hits

	return hit_lookup


func _get_dry_ground_score_for_hits(rain_hits: int) -> int:
	match clampi(rain_hits, 0, 2):
		1:
			return maxi(dry_ground_one_hit_score, 0)
		2:
			return maxi(dry_ground_two_hit_score, 0)
		_:
			return maxi(dry_ground_zero_hit_score, 0)


func _collect_eligible_enemy_herbivore_footprints() -> Array[Rect2i]:
	var footprints: Array[Rect2i] = []

	for creature_variant: Variant in get_tree().get_nodes_in_group("creatures"):
		var creature := creature_variant as Node

		if not _is_eligible_enemy_herbivore(creature):
			continue

		var anchor_variant: Variant = creature.get("anchor_tile")
		var footprint_variant: Variant = creature.get("footprint_size")

		if not (anchor_variant is Vector2i and footprint_variant is Vector2i):
			continue

		var anchor_tile: Vector2i = anchor_variant
		var footprint_size: Vector2i = footprint_variant
		footprints.append(Rect2i(
			anchor_tile,
			Vector2i(maxi(footprint_size.x, 1), maxi(footprint_size.y, 1))
		))

	return footprints


func _is_eligible_enemy_herbivore(creature: Node) -> bool:
	if (
		creature == null
		or not is_instance_valid(creature)
		or creature.is_queued_for_deletion()
		or CREATURE_FACTION.get_id(creature) != CREATURE_FACTION.ENEMY
	):
		return false

	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null or not species_data.is_herbivore():
		return false

	return ENEMY_SPECIES_CATALOG.get_species_data(species_data.species_id) == species_data


func _build_herbivore_demand_map(
	herbivore_footprints: Array[Rect2i],
	candidate_centers: Dictionary,
	rain_radius: int
) -> Dictionary:
	var demand_by_center: Dictionary = {}
	var far_distance := _get_far_herbivore_distance_tiles()
	var safe_rain_radius := maxi(rain_radius, 0)
	var expansion := safe_rain_radius + far_distance

	for footprint: Rect2i in herbivore_footprints:
		var footprint_max := footprint.position + footprint.size - Vector2i.ONE

		for center_y in range(
			footprint.position.y - expansion,
			footprint_max.y + expansion + 1
		):
			for center_x in range(
				footprint.position.x - expansion,
				footprint_max.x + expansion + 1
			):
				var center_tile := Vector2i(center_x, center_y)

				if not candidate_centers.has(center_tile):
					continue

				var distance := _get_distance_from_footprint_to_rain_area(
					footprint,
					center_tile,
					safe_rain_radius
				)
				var demand_weight := _get_herbivore_demand_weight(distance)

				if demand_weight <= 0.0:
					continue

				demand_by_center[center_tile] = float(
					demand_by_center.get(center_tile, 0.0)
				) + demand_weight

	return demand_by_center


func _get_herbivore_demand_breakdown(
	center_tile: Vector2i,
	herbivore_footprints: Array[Rect2i],
	rain_radius: int
) -> Dictionary:
	var breakdown := {
		"near": 0,
		"medium": 0,
		"far": 0
	}

	if center_tile == INVALID_TILE:
		return breakdown

	var near_distance := _get_near_herbivore_distance_tiles()
	var medium_distance := _get_medium_herbivore_distance_tiles()
	var far_distance := _get_far_herbivore_distance_tiles()

	for footprint: Rect2i in herbivore_footprints:
		var distance := _get_distance_from_footprint_to_rain_area(
			footprint,
			center_tile,
			rain_radius
		)

		if distance <= near_distance:
			breakdown["near"] = int(breakdown["near"]) + 1
		elif distance <= medium_distance:
			breakdown["medium"] = int(breakdown["medium"]) + 1
		elif distance <= far_distance:
			breakdown["far"] = int(breakdown["far"]) + 1

	return breakdown


func _get_distance_from_footprint_to_rain_area(
	footprint: Rect2i,
	center_tile: Vector2i,
	rain_radius: int
) -> int:
	var safe_radius := maxi(rain_radius, 0)
	var rain_min := center_tile - Vector2i(safe_radius, safe_radius)
	var rain_max := center_tile + Vector2i(safe_radius, safe_radius)
	var footprint_min := footprint.position
	var footprint_max := footprint.position + footprint.size - Vector2i.ONE
	var gap_x := maxi(
		maxi(footprint_min.x - rain_max.x, rain_min.x - footprint_max.x),
		0
	)
	var gap_y := maxi(
		maxi(footprint_min.y - rain_max.y, rain_min.y - footprint_max.y),
		0
	)
	return maxi(gap_x, gap_y)


func _get_herbivore_demand_weight(distance_tiles: int) -> float:
	if distance_tiles <= _get_near_herbivore_distance_tiles():
		return 1.0
	if distance_tiles <= _get_medium_herbivore_distance_tiles():
		return clampf(herbivore_medium_demand_weight, 0.0, 1.0)
	if distance_tiles <= _get_far_herbivore_distance_tiles():
		return clampf(herbivore_far_demand_weight, 0.0, 1.0)

	return 0.0


func _get_herbivore_demand_multiplier(weighted_demand: float) -> float:
	var base_multiplier := maxf(empty_area_score_multiplier, 0.0)
	var maximum_multiplier := maxf(maximum_herbivore_score_multiplier, base_multiplier)
	return clampf(
		base_multiplier
		+ maxf(herbivore_demand_multiplier_step, 0.0) * maxf(weighted_demand, 0.0),
		base_multiplier,
		maximum_multiplier
	)


func _get_near_herbivore_distance_tiles() -> int:
	return maxi(herbivore_near_distance_tiles, 0)


func _get_medium_herbivore_distance_tiles() -> int:
	return maxi(herbivore_medium_distance_tiles, _get_near_herbivore_distance_tiles())


func _get_far_herbivore_distance_tiles() -> int:
	return maxi(herbivore_far_distance_tiles, _get_medium_herbivore_distance_tiles())


func _get_distance_from_rain_area_to_enemy_base(
	center_tile: Vector2i,
	rain_radius: int
) -> int:
	if enemy_base == null or not is_instance_valid(enemy_base):
		return _get_base_proximity_reference_distance_tiles()

	var anchor_variant: Variant = enemy_base.get("anchor_tile")
	var footprint_variant: Variant = enemy_base.get("footprint_size")

	if not (anchor_variant is Vector2i and footprint_variant is Vector2i):
		return _get_base_proximity_reference_distance_tiles()

	var anchor_tile: Vector2i = anchor_variant
	var footprint_size: Vector2i = footprint_variant
	var base_footprint := Rect2i(
		anchor_tile,
		Vector2i(maxi(footprint_size.x, 1), maxi(footprint_size.y, 1))
	)
	return _get_distance_from_footprint_to_rain_area(
		base_footprint,
		center_tile,
		rain_radius
	)


func _get_base_proximity_multiplier(distance_tiles: int) -> float:
	var reference_distance := _get_base_proximity_reference_distance_tiles()
	var clamped_distance := clampi(distance_tiles, 0, reference_distance)
	return (
		1.0
		+ float(reference_distance - clamped_distance)
		* maxf(base_proximity_multiplier_step, 0.0)
	)


func _get_base_proximity_reference_distance_tiles() -> int:
	return maxi(base_proximity_reference_distance_tiles, 0)


func _append_covering_centers(
	covered_centers: Dictionary,
	covered_tile: Vector2i,
	rain_radius: int
) -> void:
	for center_y in range(covered_tile.y - rain_radius, covered_tile.y + rain_radius + 1):
		for center_x in range(covered_tile.x - rain_radius, covered_tile.x + rain_radius + 1):
			var center_tile := Vector2i(center_x, center_y)

			if (
				bool(world_grid.call("is_tile_inside_map", center_tile))
				and _is_rain_center_inside_search_area(center_tile, rain_radius)
			):
				covered_centers[center_tile] = true


func _is_better_candidate(
	candidate_tile: Vector2i,
	candidate_score: float,
	best_tile: Vector2i,
	best_score: float
) -> bool:
	if not is_equal_approx(candidate_score, best_score):
		return candidate_score > best_score
	if best_tile == INVALID_TILE:
		return true

	# Stable tie-break keeps identical worlds deterministic.
	if candidate_tile.y != best_tile.y:
		return candidate_tile.y < best_tile.y

	return candidate_tile.x < best_tile.x


func _refresh_search_area_bounds() -> bool:
	if world_grid == null or not is_instance_valid(world_grid):
		has_search_area_bounds = false
		return false

	if enemy_base == null or not is_instance_valid(enemy_base):
		enemy_base = world_grid.get_node_or_null("EnemyBase") as Node2D

	if enemy_base == null:
		has_search_area_bounds = false
		return false

	var anchor_variant: Variant = enemy_base.get("anchor_tile")
	var footprint_variant: Variant = enemy_base.get("footprint_size")
	var map_min_variant: Variant = world_grid.get("map_min")
	var map_max_variant: Variant = world_grid.get("map_max")

	if not (anchor_variant is Vector2i and footprint_variant is Vector2i):
		has_search_area_bounds = false
		return false
	if not (map_min_variant is Vector2i and map_max_variant is Vector2i):
		has_search_area_bounds = false
		return false

	var anchor_tile: Vector2i = anchor_variant
	var footprint_size: Vector2i = footprint_variant
	var map_min: Vector2i = map_min_variant
	var map_max: Vector2i = map_max_variant
	var radius := maxi(rain_search_radius_tiles, 0)
	var min_tile := anchor_tile - Vector2i(radius, radius)
	var max_tile := (
		anchor_tile
		+ Vector2i(maxi(footprint_size.x, 1), maxi(footprint_size.y, 1))
		- Vector2i.ONE
		+ Vector2i(radius, radius)
	)
	min_tile = Vector2i(maxi(min_tile.x, map_min.x), maxi(min_tile.y, map_min.y))
	max_tile = Vector2i(mini(max_tile.x, map_max.x), mini(max_tile.y, map_max.y))

	if min_tile.x > max_tile.x or min_tile.y > max_tile.y:
		has_search_area_bounds = false
		return false

	var next_bounds := Rect2i(min_tile, max_tile - min_tile + Vector2i.ONE)
	var bounds_changed := not has_search_area_bounds or next_bounds != search_area_bounds
	search_area_bounds = next_bounds
	has_search_area_bounds = true

	if bounds_changed:
		queue_redraw()

	return true


func _is_tile_inside_search_area(tile: Vector2i) -> bool:
	return has_search_area_bounds and search_area_bounds.has_point(tile)


func _is_rain_center_inside_search_area(center_tile: Vector2i, rain_radius: int) -> bool:
	if not has_search_area_bounds:
		return false

	var safe_radius := maxi(rain_radius, 0)
	var min_allowed := search_area_bounds.position
	var max_allowed := search_area_bounds.position + search_area_bounds.size - Vector2i.ONE
	return (
		center_tile.x - safe_radius >= min_allowed.x
		and center_tile.y - safe_radius >= min_allowed.y
		and center_tile.x + safe_radius <= max_allowed.x
		and center_tile.y + safe_radius <= max_allowed.y
	)


func _show_rain_area_frame(target_tile: Vector2i) -> void:
	visible_rain_frame_tile = target_tile
	rain_frame_remaining_seconds = maxf(rain_area_frame_duration_seconds, 0.0)
	queue_redraw()


func _tile_bounds_to_local_rect(tile_bounds: Rect2i) -> Rect2:
	if (
		world_grid == null
		or not is_instance_valid(world_grid)
		or tile_bounds.size.x <= 0
		or tile_bounds.size.y <= 0
		or not world_grid.has_method("map_to_world_center")
	):
		return Rect2()

	var min_tile := tile_bounds.position
	var max_tile := tile_bounds.position + tile_bounds.size - Vector2i.ONE
	var min_center_global: Vector2 = world_grid.call("map_to_world_center", min_tile)
	var max_center_global: Vector2 = world_grid.call("map_to_world_center", max_tile)
	var min_center := to_local(min_center_global)
	var max_center := to_local(max_center_global)
	var tile_size_variant: Variant = world_grid.get("tile_size")
	var tile_size_pixels := Vector2(128.0, 128.0)

	if tile_size_variant is Vector2i:
		var tile_size_grid: Vector2i = tile_size_variant
		tile_size_pixels = Vector2(tile_size_grid)

	var left := minf(min_center.x, max_center.x) - tile_size_pixels.x * 0.5
	var top := minf(min_center.y, max_center.y) - tile_size_pixels.y * 0.5
	var right := maxf(min_center.x, max_center.x) + tile_size_pixels.x * 0.5
	var bottom := maxf(min_center.y, max_center.y) + tile_size_pixels.y * 0.5
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _get_registered_grass_count() -> int:
	if world_grid == null or not is_instance_valid(world_grid):
		return 0

	var grass_registry_variant: Variant = world_grid.get("grass_by_tile")

	if not (grass_registry_variant is Dictionary):
		return 0

	var grass_registry: Dictionary = grass_registry_variant as Dictionary
	return grass_registry.size()


func _get_rain_radius_tiles() -> int:
	if nature_effects != null and nature_effects.has_method("get_rain_radius_tiles"):
		return maxi(int(nature_effects.call("get_rain_radius_tiles")), 0)

	return 0


func _refresh_runtime_references() -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		var parent_grid := get_parent() as Node

		if parent_grid != null and parent_grid.has_method("is_tile_inside_map"):
			world_grid = parent_grid
		else:
			world_grid = get_tree().get_first_node_in_group("world_grid")

	if nature_effects == null or not is_instance_valid(nature_effects):
		nature_effects = get_tree().get_first_node_in_group("nature_effects_system")

	if enemy_ai == null or not is_instance_valid(enemy_ai):
		enemy_ai = get_tree().get_first_node_in_group("enemy_ai")

	if enemy_energy == null or not is_instance_valid(enemy_energy):
		enemy_energy = get_tree().get_first_node_in_group("enemy_energy")

	if enemy_base == null or not is_instance_valid(enemy_base):
		if world_grid != null and is_instance_valid(world_grid):
			enemy_base = world_grid.get_node_or_null("EnemyBase") as Node2D


func _get_rain_payment_source(amount: float) -> StringName:
	var safe_cost := maxf(amount, 0.0)

	if (
		enemy_energy != null
		and is_instance_valid(enemy_energy)
		and enemy_energy.has_method("can_spend")
		and bool(enemy_energy.call("can_spend", safe_cost))
	):
		return RAIN_PAYMENT_ORDINARY

	if can_spend_combat_reserve(safe_cost):
		return RAIN_PAYMENT_RESERVE

	return RAIN_PAYMENT_NONE


func _spend_rain_energy(payment_source: StringName, amount: float) -> bool:
	var safe_cost := maxf(amount, 0.0)

	match payment_source:
		RAIN_PAYMENT_ORDINARY:
			return (
				enemy_energy != null
				and is_instance_valid(enemy_energy)
				and enemy_energy.has_method("spend")
				and bool(enemy_energy.call("spend", safe_cost))
			)
		RAIN_PAYMENT_RESERVE:
			if not can_spend_combat_reserve(safe_cost):
				return false
			combat_reserve = maxf(combat_reserve - safe_cost, 0.0)
			PerformanceStats.add_counter("enemy_rain_reserve_spent", roundi(safe_cost))
			return true

	return false


func _refund_rain_energy(payment_source: StringName, amount: float) -> void:
	var safe_amount := maxf(amount, 0.0)

	match payment_source:
		RAIN_PAYMENT_ORDINARY:
			if enemy_energy != null and enemy_energy.has_method("add_energy"):
				enemy_energy.call("add_energy", safe_amount)
		RAIN_PAYMENT_RESERVE:
			combat_reserve = minf(
				combat_reserve + safe_amount,
				_get_combat_reserve_capacity()
			)


func _format_rain_payment_source(payment_source: StringName) -> String:
	if payment_source == RAIN_PAYMENT_RESERVE:
		return "резерв"
	return "обычная энка"


func _reset_combat_reserve_for_new_session() -> void:
	combat_reserve = 0.0
	combat_reserve_capacity = 0.0
	next_combat_reserve_capacity_tick_minute = _get_first_combat_reserve_capacity_tick_minute()
	last_combat_reserve_income_deposit = 0.0


func _update_combat_reserve_capacity_from_match_time() -> void:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		_refresh_runtime_references()

	_advance_combat_reserve_capacity_to_elapsed(_get_enemy_elapsed_simulation_seconds())


func _advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds: float) -> void:
	var first_tick_minute := _get_first_combat_reserve_capacity_tick_minute()

	if next_combat_reserve_capacity_tick_minute < first_tick_minute:
		next_combat_reserve_capacity_tick_minute = first_tick_minute

	var elapsed_full_minutes := maxi(
		int(floor(maxf(elapsed_simulation_seconds, 0.0) / 60.0)),
		0
	)
	var safe_maximum := _get_combat_reserve_maximum()

	while next_combat_reserve_capacity_tick_minute <= elapsed_full_minutes:
		var gain := _get_combat_reserve_capacity_gain_for_tick(
			next_combat_reserve_capacity_tick_minute
		)
		combat_reserve_capacity = minf(
			combat_reserve_capacity + gain,
			safe_maximum
		)
		next_combat_reserve_capacity_tick_minute += 1

	combat_reserve = minf(combat_reserve, combat_reserve_capacity)


func _get_enemy_elapsed_simulation_seconds() -> float:
	if (
		enemy_ai != null
		and is_instance_valid(enemy_ai)
		and enemy_ai.has_method("get_elapsed_simulation_seconds")
	):
		return maxf(
			float(enemy_ai.call("get_elapsed_simulation_seconds")),
			0.0
		)

	return 0.0


func _get_first_combat_reserve_capacity_tick_minute() -> int:
	return maxi(combat_reserve_unlock_minutes, 0)


func _get_combat_reserve_capacity_gain_for_tick(tick_minute: int) -> float:
	var late_rate_after := maxi(
		combat_reserve_late_rate_after_minutes,
		maxi(combat_reserve_unlock_minutes, 0)
	)

	if tick_minute > late_rate_after:
		return maxf(combat_reserve_capacity_late_gain_per_minute, 0.0)

	return maxf(combat_reserve_capacity_gain_per_minute, 0.0)


func _get_combat_reserve_maximum() -> float:
	return maxf(combat_reserve_maximum, 0.0)


func _get_combat_reserve_capacity() -> float:
	return clampf(
		combat_reserve_capacity,
		0.0,
		_get_combat_reserve_maximum()
	)


func _get_combat_reserve_minimum_after_cast() -> float:
	return clampf(
		combat_reserve_minimum_after_cast,
		0.0,
		_get_combat_reserve_maximum()
	)


func get_save_data() -> Dictionary:
	_update_combat_reserve_capacity_from_match_time()
	return {
		"combat_reserve_save_version": COMBAT_RESERVE_SAVE_VERSION,
		"combat_reserve": get_combat_reserve(),
		"combat_reserve_capacity": get_combat_reserve_capacity(),
		"next_combat_reserve_capacity_tick_minute": next_combat_reserve_capacity_tick_minute
	}


func restore_save_data(saved_data: Dictionary) -> void:
	_refresh_runtime_references()
	var elapsed_simulation_seconds := _get_enemy_elapsed_simulation_seconds()
	var saved_version := int(saved_data.get("combat_reserve_save_version", 0))

	_reset_combat_reserve_for_new_session()

	if saved_version >= COMBAT_RESERVE_SAVE_VERSION:
		combat_reserve_capacity = clampf(
			float(saved_data.get("combat_reserve_capacity", 0.0)),
			0.0,
			_get_combat_reserve_maximum()
		)
		var default_next_tick := maxi(
			int(floor(elapsed_simulation_seconds / 60.0)) + 1,
			_get_first_combat_reserve_capacity_tick_minute()
		)
		next_combat_reserve_capacity_tick_minute = maxi(
			int(saved_data.get(
				"next_combat_reserve_capacity_tick_minute",
				default_next_tick
			)),
			_get_first_combat_reserve_capacity_tick_minute()
		)
		_advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds)
		combat_reserve = clampf(
			float(saved_data.get("combat_reserve", 0.0)),
			0.0,
			_get_combat_reserve_capacity()
		)
	else:
		# The previous reserve prototype created energy from elapsed time. Its saved
		# amount is intentionally discarded; only the capacity is rebuilt.
		_advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds)
		combat_reserve = 0.0


func deposit_combat_reserve_income(amount: float) -> float:
	_update_combat_reserve_capacity_from_match_time()
	last_combat_reserve_income_deposit = 0.0
	var safe_amount := maxf(amount, 0.0)
	var available_space := maxf(
		_get_combat_reserve_capacity() - combat_reserve,
		0.0
	)

	if safe_amount <= 0.0 or available_space <= 0.0:
		return 0.0

	last_combat_reserve_income_deposit = minf(safe_amount, available_space)
	combat_reserve += last_combat_reserve_income_deposit
	PerformanceStats.add_counter(
		"enemy_combat_reserve_income",
		roundi(last_combat_reserve_income_deposit)
	)
	return last_combat_reserve_income_deposit


func get_combat_reserve() -> float:
	return clampf(combat_reserve, 0.0, _get_combat_reserve_capacity())


func get_combat_reserve_capacity() -> float:
	_update_combat_reserve_capacity_from_match_time()
	return _get_combat_reserve_capacity()


func get_combat_reserve_maximum() -> float:
	return _get_combat_reserve_maximum()


func get_combat_reserve_minimum_after_cast() -> float:
	return _get_combat_reserve_minimum_after_cast()


func get_next_combat_reserve_capacity_tick_minute() -> int:
	return maxi(
		next_combat_reserve_capacity_tick_minute,
		_get_first_combat_reserve_capacity_tick_minute()
	)


func get_next_combat_reserve_capacity_gain() -> float:
	return _get_combat_reserve_capacity_gain_for_tick(
		get_next_combat_reserve_capacity_tick_minute()
	)


func get_seconds_until_next_combat_reserve_capacity_tick() -> float:
	var next_tick_seconds := float(
		get_next_combat_reserve_capacity_tick_minute()
	) * 60.0
	return maxf(next_tick_seconds - _get_enemy_elapsed_simulation_seconds(), 0.0)


func is_combat_reserve_unlocked() -> bool:
	return _get_enemy_elapsed_simulation_seconds() >= (
		float(maxi(combat_reserve_unlock_minutes, 0)) * 60.0
	)


func can_spend_combat_reserve(amount: float) -> bool:
	_update_combat_reserve_capacity_from_match_time()
	var safe_cost := maxf(amount, 0.0)
	return combat_reserve + 0.001 >= safe_cost


# Call this only after a combat spell has applied successfully. A failed target
# or failed shared effect must leave the reserve untouched.
func spend_combat_reserve_after_success(amount: float) -> bool:
	var safe_cost := maxf(amount, 0.0)

	if safe_cost <= 0.0 or not can_spend_combat_reserve(safe_cost):
		return false

	combat_reserve = clampf(
		maxf(
			combat_reserve - safe_cost,
			_get_combat_reserve_minimum_after_cast()
		),
		0.0,
		_get_combat_reserve_capacity()
	)
	PerformanceStats.add_counter("enemy_combat_reserve_spent", roundi(safe_cost))
	PerformanceStats.add_counter("enemy_combat_spell_casts")
	return true


func _reset_last_search_stats() -> void:
	last_rain_target_tile = INVALID_TILE
	last_grass_entries_scanned = 0
	last_mature_grass_count = 0
	last_spread_ready_grass_count = 0
	last_productive_grass_count = 0
	last_unique_spawn_target_count = 0
	last_adjacent_dry_ground_count = 0
	last_candidate_center_count = 0
	last_best_predicted_new_grass = 0
	last_best_dry_ground_zero_hit_count = 0
	last_best_dry_ground_one_hit_count = 0
	last_best_dry_ground_two_hit_count = 0
	last_best_dry_ground_score = 0
	last_eligible_herbivore_count = 0
	last_best_near_herbivore_count = 0
	last_best_medium_herbivore_count = 0
	last_best_far_herbivore_count = 0
	last_best_herbivore_demand = 0.0
	last_best_demand_multiplier = _get_herbivore_demand_multiplier(0.0)
	last_best_base_distance_tiles = _get_base_proximity_reference_distance_tiles()
	last_best_base_proximity_multiplier = 1.0
	last_best_base_score = 0
	last_best_total_score = 0.0
	last_actual_new_grass = 0
	last_search_duration_usec = 0
	last_apply_duration_usec = 0


func get_last_action_text() -> String:
	return last_action_text


func get_last_rain_target_tile() -> Vector2i:
	return last_rain_target_tile


func get_last_grass_entries_scanned() -> int:
	return last_grass_entries_scanned


func get_last_mature_grass_count() -> int:
	return last_mature_grass_count


func get_last_spread_ready_grass_count() -> int:
	return last_spread_ready_grass_count


func get_last_productive_grass_count() -> int:
	return last_productive_grass_count


func get_last_unique_spawn_target_count() -> int:
	return last_unique_spawn_target_count


func get_last_candidate_center_count() -> int:
	return last_candidate_center_count


func get_last_best_predicted_new_grass() -> int:
	return last_best_predicted_new_grass


func get_last_search_duration_msec() -> float:
	return float(last_search_duration_usec) / 1000.0


func get_max_search_duration_msec() -> float:
	return float(max_search_duration_usec) / 1000.0


func get_total_search_count() -> int:
	return total_search_count


func _get_enemy_energy_debug_value(method_name: StringName) -> float:
	if (
		enemy_energy != null
		and is_instance_valid(enemy_energy)
		and enemy_energy.has_method(method_name)
	):
		return maxf(float(enemy_energy.call(method_name)), 0.0)
	return 0.0


func get_rain_debug_data() -> Dictionary:
	_update_combat_reserve_capacity_from_match_time()
	return {
		"action_text": last_action_text,
		"combat_reserve": get_combat_reserve(),
		"combat_reserve_capacity": get_combat_reserve_capacity(),
		"combat_reserve_maximum": get_combat_reserve_maximum(),
		"combat_reserve_minimum_after_cast": get_combat_reserve_minimum_after_cast(),
		"combat_reserve_unlocked": is_combat_reserve_unlocked(),
		"combat_reserve_next_capacity_tick_minute": get_next_combat_reserve_capacity_tick_minute(),
		"combat_reserve_next_capacity_gain": get_next_combat_reserve_capacity_gain(),
		"combat_reserve_seconds_until_next_capacity_tick": get_seconds_until_next_combat_reserve_capacity_tick(),
		"combat_reserve_last_income_deposit": last_combat_reserve_income_deposit,
		"enemy_income_per_second": _get_enemy_energy_debug_value("get_income_per_second"),
		"combat_reserve_income_threshold_per_second": _get_enemy_energy_debug_value("get_combat_reserve_income_threshold_per_second"),
		"combat_reserve_income_share": _get_enemy_energy_debug_value("get_combat_reserve_income_share"),
		"enemy_last_income_to_ordinary_energy": _get_enemy_energy_debug_value("get_last_income_to_ordinary_energy"),
		"grass_entries_scanned": last_grass_entries_scanned,
		"mature_grass_count": last_mature_grass_count,
		"spread_ready_grass_count": last_spread_ready_grass_count,
		"productive_grass_count": last_productive_grass_count,
		"unique_spawn_target_count": last_unique_spawn_target_count,
		"adjacent_dry_ground_count": last_adjacent_dry_ground_count,
		"candidate_center_count": last_candidate_center_count,
		"best_predicted_new_grass": last_best_predicted_new_grass,
		"best_dry_ground_zero_hit_count": last_best_dry_ground_zero_hit_count,
		"best_dry_ground_one_hit_count": last_best_dry_ground_one_hit_count,
		"best_dry_ground_two_hit_count": last_best_dry_ground_two_hit_count,
		"best_dry_ground_score": last_best_dry_ground_score,
		"eligible_herbivore_count": last_eligible_herbivore_count,
		"best_near_herbivore_count": last_best_near_herbivore_count,
		"best_medium_herbivore_count": last_best_medium_herbivore_count,
		"best_far_herbivore_count": last_best_far_herbivore_count,
		"best_herbivore_demand": last_best_herbivore_demand,
		"best_demand_multiplier": last_best_demand_multiplier,
		"best_base_distance_tiles": last_best_base_distance_tiles,
		"best_base_proximity_multiplier": last_best_base_proximity_multiplier,
		"best_base_score": last_best_base_score,
		"best_total_score": last_best_total_score,
		"new_grass_score": maxi(new_grass_score, 0),
		"dry_ground_zero_hit_score": maxi(dry_ground_zero_hit_score, 0),
		"dry_ground_one_hit_score": maxi(dry_ground_one_hit_score, 0),
		"dry_ground_two_hit_score": maxi(dry_ground_two_hit_score, 0),
		"empty_area_score_multiplier": maxf(empty_area_score_multiplier, 0.0),
		"herbivore_demand_multiplier_step": maxf(herbivore_demand_multiplier_step, 0.0),
		"maximum_herbivore_score_multiplier": maxf(
			maximum_herbivore_score_multiplier,
			maxf(empty_area_score_multiplier, 0.0)
		),
		"herbivore_near_distance_tiles": _get_near_herbivore_distance_tiles(),
		"herbivore_medium_distance_tiles": _get_medium_herbivore_distance_tiles(),
		"herbivore_far_distance_tiles": _get_far_herbivore_distance_tiles(),
		"base_proximity_reference_distance_tiles": _get_base_proximity_reference_distance_tiles(),
		"base_proximity_multiplier_step": maxf(base_proximity_multiplier_step, 0.0),
		"actual_new_grass": last_actual_new_grass,
		"prediction_gap": last_best_predicted_new_grass - last_actual_new_grass,
		"search_duration_msec": get_last_search_duration_msec(),
		"max_search_duration_msec": get_max_search_duration_msec(),
		"total_search_count": total_search_count,
		"apply_duration_msec": float(last_apply_duration_usec) / 1000.0,
		"max_apply_duration_msec": float(max_apply_duration_usec) / 1000.0,
		"total_apply_count": total_apply_count,
		"search_radius_tiles": maxi(rain_search_radius_tiles, 0),
		"rain_frame_duration_seconds": maxf(rain_area_frame_duration_seconds, 0.0)
	}


func get_rain_energy_cost() -> float:
	return maxf(rain_energy_cost, 0.0)


func _format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]
