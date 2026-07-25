extends Node2D
class_name EnemySpellController

# Enemy spell decisions stay separate from population production. The first
# spell listens to the four-second enemy-AI snapshot and casts shared world rain
# only when adult enemy herbivore satiety falls below the snapshot threshold.
#
# Rain targeting intentionally starts small: it ignores DryGround, herd distance,
# and young-grass growth. It searches only the visible map-clipped contour around
# the enemy base and scores how many unique grass cells mature grass can create
# immediately after one 5x5 rain cast.
const MATURE_GRASS_STAGE := 3
const INITIALIZATION_RETRY_FRAMES := 12
const INVALID_TILE := Vector2i(2147483647, 2147483647)
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.UP,
	Vector2i.DOWN
]

@export var rain_energy_cost := 50.0
@export var minimum_predicted_new_grass := 1
@export var rain_search_radius_tiles := 30
@export var rain_area_frame_duration_seconds := 4.0
@export var search_area_frame_color := Color(1.0, 0.48, 0.12, 0.82)
@export var rain_area_frame_color := Color(0.20, 0.78, 1.0, 0.95)
@export var search_area_frame_line_width := 8.0
@export var rain_area_frame_line_width := 10.0

var world_grid: Node = null
var nature_effects: Node = null
var enemy_ai: Node = null
var enemy_energy: Node = null
var enemy_base: Node2D = null

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
var last_candidate_center_count := 0
var last_best_predicted_new_grass := 0
var last_actual_new_grass := 0
var last_search_duration_usec := 0
var max_search_duration_usec := 0
var total_search_count := 0
var last_apply_duration_usec := 0
var max_apply_duration_usec := 0
var total_apply_count := 0


func _ready() -> void:
	add_to_group("enemy_spell_controller")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 500
	call_deferred("_initialize_runtime")


func _process(delta: float) -> void:
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

	# Do not perform the grass scan when the spell cannot be afforded.
	if not bool(enemy_energy.call("can_spend", safe_cost)):
		last_action_text = "дождь отложен: не хватает энки"
		PerformanceStats.add_counter("enemy_rain_wait_energy")
		return false

	var target_data := _find_best_immediate_spread_target()

	if target_data.is_empty():
		last_action_text = "дождь отложен: зрелая трава не может размножиться"
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

	if not bool(enemy_energy.call("spend", safe_cost)):
		last_action_text = "дождь отложен: энку не удалось списать"
		return false

	var grass_count_before := _get_registered_grass_count()
	var apply_start_usec := Time.get_ticks_usec()
	var rain_applied := bool(nature_effects.call("apply_rain", target_tile))
	_finish_apply_measurement(apply_start_usec)
	var grass_count_after := _get_registered_grass_count()
	last_actual_new_grass = maxi(grass_count_after - grass_count_before, 0)

	if not rain_applied:
		enemy_energy.call("add_energy", safe_cost)
		last_action_text = "дождь не сработал: энка возвращена"
		PerformanceStats.add_counter("enemy_rain_failed_refunded")
		return false

	last_rain_target_tile = target_tile
	_show_rain_area_frame(target_tile)
	last_action_text = "дождь: %s, прогноз +%d / реально +%d" % [
		_format_tile(target_tile),
		last_best_predicted_new_grass,
		last_actual_new_grass
	]
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
	return true


func _find_best_immediate_spread_target() -> Dictionary:
	var search_start_usec := Time.get_ticks_usec()
	var result: Dictionary = {}

	if not _can_scan_grass_registry():
		_finish_search_measurement(search_start_usec)
		return result

	var rain_radius := _get_rain_radius_tiles()

	if rain_radius <= 0:
		_finish_search_measurement(search_start_usec)
		return result

	var grass_registry_variant: Variant = world_grid.get("grass_by_tile")
	var grass_registry: Dictionary = grass_registry_variant as Dictionary
	var source_tiles_by_spawn_target: Dictionary = {}

	# First map each unique cell that could receive new grass to the mature grass
	# sources capable of creating it. A target can have several sources, but it
	# must count only once in a candidate rain score.
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
	var candidate_scores: Dictionary = {}

	# For each unique future grass cell, find all rain centers that cover at least
	# one of its mature sources, then add exactly one point to those centers.
	for source_set_variant: Variant in source_tiles_by_spawn_target.values():
		if not (source_set_variant is Dictionary):
			continue

		var source_set: Dictionary = source_set_variant as Dictionary
		var covered_centers: Dictionary = {}

		for source_tile_variant: Variant in source_set.keys():
			if source_tile_variant is Vector2i:
				_append_source_centers(covered_centers, source_tile_variant, rain_radius)

		for center_variant: Variant in covered_centers.keys():
			if center_variant is Vector2i:
				candidate_scores[center_variant] = int(
					candidate_scores.get(center_variant, 0)
				) + 1

	last_candidate_center_count = candidate_scores.size()
	var best_center := INVALID_TILE
	var best_predicted_new_grass := 0

	for center_variant: Variant in candidate_scores.keys():
		if not (center_variant is Vector2i):
			continue

		var center_tile: Vector2i = center_variant
		var predicted_new_grass := int(candidate_scores.get(center_tile, 0))

		if _is_better_candidate(
			center_tile,
			predicted_new_grass,
			best_center,
			best_predicted_new_grass
		):
			best_center = center_tile
			best_predicted_new_grass = predicted_new_grass

	last_best_predicted_new_grass = best_predicted_new_grass
	_finish_search_measurement(search_start_usec)

	if (
		best_center == INVALID_TILE
		or best_predicted_new_grass < maxi(minimum_predicted_new_grass, 1)
	):
		return result

	return {
		"tile": best_center,
		"predicted_new_grass": best_predicted_new_grass
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
	PerformanceStats.set_max_value(
		"enemy_rain_search_max_usec",
		last_search_duration_usec
	)
	PerformanceStats.set_max_value(
		"enemy_rain_best_spread_max",
		last_best_predicted_new_grass
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


func _can_scan_grass_registry() -> bool:
	if world_grid == null or not is_instance_valid(world_grid):
		return false
	if not world_grid.has_method("is_tile_inside_map"):
		return false
	if not world_grid.has_method("can_host_grass"):
		return false
	if not world_grid.has_method("has_grass_at_tile"):
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


func _append_source_centers(
	covered_centers: Dictionary,
	grass_tile: Vector2i,
	rain_radius: int
) -> void:
	for center_y in range(grass_tile.y - rain_radius, grass_tile.y + rain_radius + 1):
		for center_x in range(grass_tile.x - rain_radius, grass_tile.x + rain_radius + 1):
			var center_tile := Vector2i(center_x, center_y)

			if (
				bool(world_grid.call("is_tile_inside_map", center_tile))
				and _is_rain_center_inside_search_area(center_tile, rain_radius)
			):
				covered_centers[center_tile] = true


func _is_better_candidate(
	candidate_tile: Vector2i,
	candidate_score: int,
	best_tile: Vector2i,
	best_score: int
) -> bool:
	if candidate_score > best_score:
		return true
	if candidate_score < best_score:
		return false
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


func _reset_last_search_stats() -> void:
	last_rain_target_tile = INVALID_TILE
	last_grass_entries_scanned = 0
	last_mature_grass_count = 0
	last_spread_ready_grass_count = 0
	last_productive_grass_count = 0
	last_unique_spawn_target_count = 0
	last_candidate_center_count = 0
	last_best_predicted_new_grass = 0
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


func get_rain_debug_data() -> Dictionary:
	return {
		"action_text": last_action_text,
		"grass_entries_scanned": last_grass_entries_scanned,
		"mature_grass_count": last_mature_grass_count,
		"spread_ready_grass_count": last_spread_ready_grass_count,
		"productive_grass_count": last_productive_grass_count,
		"unique_spawn_target_count": last_unique_spawn_target_count,
		"candidate_center_count": last_candidate_center_count,
		"best_predicted_new_grass": last_best_predicted_new_grass,
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
