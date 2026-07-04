extends Node2D

# Grid authority for tiles, occupancy and grazing.
const CREATURE_SCENE := preload("res://scenes/creatures/creature.tscn")
const PREDATOR_SPECIES_DATA := preload("res://data/species/predator.tres")
const PREDATOR_SPAWN_DELAY := 10.0
const PREDATOR_SPAWN_ENABLED := false
const TERRAIN_GROUND := 0
const TERRAIN_WATER := 1
const TERRAIN_MOUNTAIN := 2
const BLOCKED_TERRAIN_SOURCES := {TERRAIN_WATER: true, TERRAIN_MOUNTAIN: true}

# Hard cap on how many tiles a single find_path call is allowed to expand before
# giving up. Without this, a path search toward an unreachable or heavily
# contested target keeps exploring the whole reachable area (potentially
# thousands of tiles) before it fails. The cap bounds the worst-case cost of a
# single call to a constant, regardless of map size or population.
const DEFAULT_MAX_PATH_EXPANDED_TILES := 300

var ground: TileMapLayer = null

var tile_size := Vector2i(128, 128)

var map_min := Vector2i.ZERO

var map_max := Vector2i.ZERO

# Runtime registries.
var grass_by_tile: Dictionary = {}

var creature_anchors: Dictionary = {}

var blocker_anchors: Dictionary = {}

var occupied_by_tile: Dictionary = {}

var is_initialized := false

var grass_render_offset := Vector2.ZERO

var has_grass_render_offset := false
var predator_spawn_done := false

# 8-way movement.
const DIRECTIONS_8 := [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i(-1, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(1, 1)
]


# Setup.
func _ready() -> void:
	add_to_group("world_grid")
	ensure_initialized()
	call_deferred("schedule_predator_spawn")


func schedule_predator_spawn() -> void:
	if predator_spawn_done or not PREDATOR_SPAWN_ENABLED:
		return

	await get_tree().create_timer(PREDATOR_SPAWN_DELAY).timeout
	spawn_predator_if_needed()


func spawn_predator_if_needed() -> void:
	if predator_spawn_done or not PREDATOR_SPAWN_ENABLED:
		return

	var creatures_root := get_node_or_null("Creatures")
	var spawn_marker := creatures_root.get_node_or_null("PredatorSpawn") if creatures_root != null else null

	if creatures_root == null or spawn_marker == null:
		return

	for creature in creature_anchors.keys():
		if is_instance_valid(creature) and creature.has_method("get_is_predator") and creature.get_is_predator():
			predator_spawn_done = true
			return

	var predator: Node = CREATURE_SCENE.instantiate()
	predator.species_data = PREDATOR_SPECIES_DATA
	predator.health = -1.0
	predator.hunger = -1.0
	predator.global_position = spawn_marker.global_position
	creatures_root.add_child(predator)
	predator.health = PREDATOR_SPECIES_DATA.max_health
	predator.hunger = PREDATOR_SPECIES_DATA.max_hunger
	predator_spawn_done = true


func ensure_initialized() -> void:
	if ground == null:
		ground = get_node_or_null("Ground") as TileMapLayer

	if ground == null:
		return

	if is_initialized:
		return

	if ground.tile_set != null:
		tile_size = ground.tile_set.tile_size

	_cache_map_bounds()
	is_initialized = true


func _cache_map_bounds() -> void:
	var used_cells := ground.get_used_cells()

	if used_cells.is_empty():
		map_min = Vector2i.ZERO
		map_max = Vector2i.ZERO
		return

	var min_x := used_cells[0].x
	var min_y := used_cells[0].y
	var max_x := used_cells[0].x
	var max_y := used_cells[0].y

	for tile in used_cells:
		min_x = min(min_x, tile.x)
		min_y = min(min_y, tile.y)
		max_x = max(max_x, tile.x)
		max_y = max(max_y, tile.y)

	map_min = Vector2i(min_x, min_y)
	map_max = Vector2i(max_x, max_y)


# World <-> grid helpers.
func world_to_map_tile(world_position: Vector2) -> Vector2i:
	ensure_initialized()
	var local_position := ground.to_local(world_position)
	return ground.local_to_map(local_position)


func world_to_anchor_tile(world_position: Vector2, footprint_size: Vector2i) -> Vector2i:
	var anchor_offset := Vector2(
		float(max(footprint_size.x - 1, 0)) * float(tile_size.x) * 0.5,
		float(max(footprint_size.y - 1, 0)) * float(tile_size.y) * 0.5
	)
	return world_to_map_tile(world_position - anchor_offset)


func map_to_world_center(tile: Vector2i) -> Vector2:
	ensure_initialized()
	return ground.to_global(ground.map_to_local(tile))


func anchor_to_world_position(anchor_tile: Vector2i, footprint_size: Vector2i) -> Vector2:
	var world_center := map_to_world_center(anchor_tile)
	var offset := Vector2(
		float(max(footprint_size.x - 1, 0)) * float(tile_size.x) * 0.5,
		float(max(footprint_size.y - 1, 0)) * float(tile_size.y) * 0.5
	)
	return world_center + offset


func grass_tile_to_world_position(tile: Vector2i) -> Vector2:
	return map_to_world_center(tile)


func get_footprint_tiles(anchor_tile: Vector2i, footprint_size: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	for y in range(footprint_size.y):
		for x in range(footprint_size.x):
			tiles.append(anchor_tile + Vector2i(x, y))

	return tiles


func is_tile_inside_map(tile: Vector2i) -> bool:
	ensure_initialized()
	return tile.x >= map_min.x and tile.x <= map_max.x and tile.y >= map_min.y and tile.y <= map_max.y


func get_tile_source_id(tile: Vector2i) -> int:
	ensure_initialized()

	if not is_tile_inside_map(tile):
		return -1

	return ground.get_cell_source_id(tile)


func is_tile_blocked_terrain(tile: Vector2i) -> bool:
	var source_id := get_tile_source_id(tile)
	return BLOCKED_TERRAIN_SOURCES.has(source_id)


func is_tile_walkable(tile: Vector2i) -> bool:
	var source_id := get_tile_source_id(tile)

	if source_id == -1:
		return false

	return not BLOCKED_TERRAIN_SOURCES.has(source_id)


func can_host_grass(tile: Vector2i) -> bool:
	return is_tile_walkable(tile)


# Placement helpers.
func can_place_footprint(anchor_tile: Vector2i, footprint_size: Vector2i, creature: Node = null) -> bool:
	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		if not is_tile_walkable(tile):
			return false

		if occupied_by_tile.has(tile) and occupied_by_tile[tile] != creature:
			return false

	return true


func find_nearest_valid_anchor(preferred_anchor: Vector2i, footprint_size: Vector2i, creature: Node = null, max_radius: int = 12) -> Vector2i:
	if can_place_footprint(preferred_anchor, footprint_size, creature):
		return preferred_anchor

	for radius in range(1, max_radius + 1):
		for y in range(preferred_anchor.y - radius, preferred_anchor.y + radius + 1):
			for x in range(preferred_anchor.x - radius, preferred_anchor.x + radius + 1):
				var candidate := Vector2i(x, y)

				if can_place_footprint(candidate, footprint_size, creature):
					return candidate

	return preferred_anchor


# Grass registry.
func register_grass(grass: Node, tile: Vector2i) -> void:
	ensure_initialized()
	grass_by_tile[tile] = grass


func unregister_grass(grass: Node, tile: Vector2i) -> void:
	if grass_by_tile.get(tile) == grass:
		grass_by_tile.erase(tile)


func get_grass_at_tile(tile: Vector2i) -> Node:
	return grass_by_tile.get(tile)


func has_grass_at_tile(tile: Vector2i) -> bool:
	var grass: Node = grass_by_tile.get(tile, null)
	return is_instance_valid(grass)


# Creature occupancy.
func register_creature(creature: Node, anchor_tile: Vector2i, footprint_size: Vector2i) -> bool:
	ensure_initialized()

	if not can_place_footprint(anchor_tile, footprint_size, creature):
		return false

	creature_anchors[creature] = anchor_tile
	_reserve_tiles(anchor_tile, footprint_size, creature)
	return true


func unregister_creature(creature: Node, footprint_size: Vector2i) -> void:
	if not creature_anchors.has(creature):
		return

	var anchor_tile: Vector2i = creature_anchors[creature]
	_release_tiles(anchor_tile, footprint_size, creature)
	creature_anchors.erase(creature)


func move_creature(creature: Node, new_anchor_tile: Vector2i, footprint_size: Vector2i) -> bool:
	if not creature_anchors.has(creature):
		return register_creature(creature, new_anchor_tile, footprint_size)

	var previous_anchor: Vector2i = creature_anchors[creature]
	_release_tiles(previous_anchor, footprint_size, creature)

	if not can_place_footprint(new_anchor_tile, footprint_size, creature):
		_reserve_tiles(previous_anchor, footprint_size, creature)
		return false

	creature_anchors[creature] = new_anchor_tile
	_reserve_tiles(new_anchor_tile, footprint_size, creature)
	return true


# Extra blocking objects, e.g. eggs.
func register_blocker(blocker: Node, anchor_tile: Vector2i, footprint_size: Vector2i) -> bool:
	ensure_initialized()

	if not can_place_footprint(anchor_tile, footprint_size, blocker):
		return false

	blocker_anchors[blocker] = anchor_tile
	_reserve_tiles(anchor_tile, footprint_size, blocker)
	return true


func unregister_blocker(blocker: Node, footprint_size: Vector2i) -> void:
	if not blocker_anchors.has(blocker):
		return

	var anchor_tile: Vector2i = blocker_anchors[blocker]
	_release_tiles(anchor_tile, footprint_size, blocker)
	blocker_anchors.erase(blocker)


# Pathfinding.
func get_neighbors(anchor_tile: Vector2i, footprint_size: Vector2i, creature: Node = null) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []

	for direction in DIRECTIONS_8:
		var candidate: Vector2i = anchor_tile + direction

		if not can_place_footprint(candidate, footprint_size, creature):
			continue

		if direction.x != 0 and direction.y != 0:
			var horizontal_candidate := anchor_tile + Vector2i(direction.x, 0)
			var vertical_candidate := anchor_tile + Vector2i(0, direction.y)

			if not can_place_footprint(horizontal_candidate, footprint_size, creature):
				continue

			if not can_place_footprint(vertical_candidate, footprint_size, creature):
				continue

		neighbors.append(candidate)

	return neighbors


func find_path(start_anchor: Vector2i, goal_anchor: Vector2i, footprint_size: Vector2i, creature: Node = null, max_expanded_tiles: int = DEFAULT_MAX_PATH_EXPANDED_TILES) -> Array[Vector2i]:
	PerformanceStats.add_counter("path_calls")

	if start_anchor == goal_anchor:
		PerformanceStats.add_counter("path_same_tile")
		return []

	if not can_place_footprint(goal_anchor, footprint_size, creature):
		PerformanceStats.add_counter("path_blocked_goal")
		return []

	var expanded_tiles := 0
	var open_set: Array[Vector2i] = [start_anchor]
	var open_lookup := {start_anchor: true}
	var came_from: Dictionary = {}
	var g_score := {start_anchor: 0.0}
	var f_score := {start_anchor: _estimate_path_cost(start_anchor, goal_anchor)}

	while not open_set.is_empty():
		if expanded_tiles >= max_expanded_tiles:
			PerformanceStats.add_counter("path_capped")
			break

		var current := _pop_lowest_score(open_set, f_score)
		expanded_tiles += 1
		open_lookup.erase(current)

		if current == goal_anchor:
			PerformanceStats.add_counter("path_success")
			PerformanceStats.add_counter("path_expanded_tiles", expanded_tiles)
			return _reconstruct_path(came_from, current, start_anchor)

		for neighbor in get_neighbors(current, footprint_size, creature):
			var tentative_g_score := float(g_score.get(current, INF)) + _step_cost(current, neighbor)

			if tentative_g_score >= float(g_score.get(neighbor, INF)):
				continue

			came_from[neighbor] = current
			g_score[neighbor] = tentative_g_score
			f_score[neighbor] = tentative_g_score + _estimate_path_cost(neighbor, goal_anchor)

			if not open_lookup.has(neighbor):
				open_set.append(neighbor)
				open_lookup[neighbor] = true

	PerformanceStats.add_counter("path_failed")
	PerformanceStats.add_counter("path_expanded_tiles", expanded_tiles)
	return []


# Grazing queries.
# Returns only the single best grazing candidate. Kept for callers that only
# ever want one target (e.g. the periodic hysteresis recheck).
func find_best_grazing_target(origin_anchor: Vector2i, footprint_size: Vector2i, min_adult_grass: int, search_radius: int = -1, creature: Node = null, grass_weight: float = 10.0, distance_penalty: float = 2.5) -> Dictionary:
	var ranked_results := find_best_grazing_targets(origin_anchor, footprint_size, min_adult_grass, search_radius, creature, grass_weight, distance_penalty, 1)

	if ranked_results.is_empty():
		return {}

	return ranked_results[0]


# Returns up to max_results grazing candidates, best first. This lets a
# creature try the next-best patch immediately if the top one turns out to be
# physically unreachable, instead of re-scanning the whole map again.
#
# Candidate generation is driven by the grass registry (grass_by_tile) rather
# than by iterating every coordinate in the search rectangle. Each registered
# grass tile can be covered by a small, fixed number of footprint anchors
# (footprint_size.x * footprint_size.y at most), so the scan cost now scales
# with how much grass exists, not with map size. This matters most exactly
# when grass is scarce (e.g. early game): previously that was the worst case
# for this function (empty local search -> full map fallback scanning every
# tile), now it is the cheapest case (few or no grass tiles to visit at all).
func find_best_grazing_targets(origin_anchor: Vector2i, footprint_size: Vector2i, min_adult_grass: int, search_radius: int = -1, creature: Node = null, grass_weight: float = 10.0, distance_penalty: float = 2.5, max_results: int = 1) -> Array[Dictionary]:
	ensure_initialized()
	PerformanceStats.add_counter("grazing_searches")

	var ranked_results: Array[Dictionary] = []
	var candidate_checks := 0
	var valid_footprint_checks := 0
	var start_x := map_min.x
	var start_y := map_min.y
	var end_x := map_max.x - footprint_size.x + 1
	var end_y := map_max.y - footprint_size.y + 1

	if search_radius >= 0:
		start_x = origin_anchor.x - search_radius
		start_y = origin_anchor.y - search_radius
		end_x = origin_anchor.x + search_radius
		end_y = origin_anchor.y + search_radius

	# Anchors are deduplicated because a single grass tile can be reached by
	# up to footprint_size.x * footprint_size.y different anchor offsets, and
	# neighboring grass tiles can map to the same anchor.
	var checked_anchors: Dictionary = {}

	for grass_tile in grass_by_tile.keys():
		for offset_x in range(footprint_size.x):
			for offset_y in range(footprint_size.y):
				var candidate := Vector2i(grass_tile.x - offset_x, grass_tile.y - offset_y)

				if candidate.x < start_x or candidate.x > end_x or candidate.y < start_y or candidate.y > end_y:
					continue

				if checked_anchors.has(candidate):
					continue

				checked_anchors[candidate] = true
				candidate_checks += 1

				if not can_place_footprint(candidate, footprint_size, creature):
					continue

				valid_footprint_checks += 1
				var adult_count := count_adult_grass_under_footprint(candidate, footprint_size)

				if adult_count < min_adult_grass:
					continue

				var distance := estimate_path_steps(origin_anchor, candidate)
				var score := float(adult_count) * grass_weight - float(distance) * distance_penalty
				var candidate_result := {
					"anchor": candidate,
					"adult_count": adult_count,
					"distance": distance,
					"score": score
				}

				_insert_ranked_grazing_result(ranked_results, candidate_result, max_results)

	PerformanceStats.add_counter("grazing_candidate_checks", candidate_checks)
	PerformanceStats.add_counter("grazing_valid_footprints", valid_footprint_checks)

	if ranked_results.is_empty():
		PerformanceStats.add_counter("grazing_search_misses")
	else:
		PerformanceStats.add_counter("grazing_search_hits")

	return ranked_results


# Inserts a candidate into a small best-first ranked list, keeping only the
# top max_results entries. With max_results being a small constant (e.g. 5),
# this costs nothing meaningful compared to the surrounding map scan.
func _insert_ranked_grazing_result(ranked_results: Array[Dictionary], candidate_result: Dictionary, max_results: int) -> void:
	if max_results <= 0:
		return

	var insert_index := ranked_results.size()

	for index in range(ranked_results.size()):
		if _is_grazing_result_better(candidate_result, ranked_results[index]):
			insert_index = index
			break

	if insert_index >= max_results:
		return

	ranked_results.insert(insert_index, candidate_result)

	if ranked_results.size() > max_results:
		ranked_results.resize(max_results)


func count_adult_grass_under_footprint(anchor_tile: Vector2i, footprint_size: Vector2i) -> int:
	PerformanceStats.add_counter("grazing_footprint_queries")
	PerformanceStats.add_counter("grazing_footprint_tiles", footprint_size.x * footprint_size.y)
	var adult_count := 0

	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		var grass: Node = grass_by_tile.get(tile, null)

		if not is_instance_valid(grass):
			continue

		if grass.has_method("can_be_eaten") and grass.can_be_eaten():
			adult_count += 1

	return adult_count


func consume_adult_grass_under_footprint(anchor_tile: Vector2i, footprint_size: Vector2i) -> int:
	PerformanceStats.add_counter("grass_consume_queries")
	var consumed_count := 0

	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		var grass: Node = grass_by_tile.get(tile, null)

		if not is_instance_valid(grass):
			continue

		if not grass.has_method("consume"):
			continue

		if grass.consume():
			consumed_count += 1

	PerformanceStats.add_counter("grass_consumed", consumed_count)
	return consumed_count


func estimate_path_steps(from_anchor: Vector2i, to_anchor: Vector2i) -> int:
	return max(abs(to_anchor.x - from_anchor.x), abs(to_anchor.y - from_anchor.y))


# Internal helpers.
func _reserve_tiles(anchor_tile: Vector2i, footprint_size: Vector2i, creature: Node) -> void:
	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		occupied_by_tile[tile] = creature


func _release_tiles(anchor_tile: Vector2i, footprint_size: Vector2i, creature: Node) -> void:
	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		if occupied_by_tile.get(tile) == creature:
			occupied_by_tile.erase(tile)


func _pop_lowest_score(open_set: Array[Vector2i], score_map: Dictionary) -> Vector2i:
	var best_index := 0
	var best_tile := open_set[0]
	var best_score := float(score_map.get(best_tile, INF))

	for index in range(1, open_set.size()):
		var tile := open_set[index]
		var tile_score := float(score_map.get(tile, INF))

		if tile_score < best_score:
			best_index = index
			best_tile = tile
			best_score = tile_score

	open_set.remove_at(best_index)
	return best_tile


func _reconstruct_path(came_from: Dictionary, current_tile: Vector2i, start_tile: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := current_tile

	while cursor != start_tile:
		path.push_front(cursor)
		cursor = came_from[cursor]

	return path


func _step_cost(from_tile: Vector2i, to_tile: Vector2i) -> float:
	var delta := to_tile - from_tile

	if delta.x != 0 and delta.y != 0:
		return 1.41421356

	return 1.0


func _estimate_path_cost(from_tile: Vector2i, to_tile: Vector2i) -> float:
	var dx: int = abs(to_tile.x - from_tile.x)
	var dy: int = abs(to_tile.y - from_tile.y)
	var diagonal_steps: int = min(dx, dy)
	var straight_steps: int = max(dx, dy) - diagonal_steps
	return float(diagonal_steps) * 1.41421356 + float(straight_steps)


func _is_grazing_result_better(candidate: Dictionary, current_best: Dictionary) -> bool:
	var candidate_score := float(candidate.get("score", -INF))
	var current_score := float(current_best.get("score", -INF))

	if not is_equal_approx(candidate_score, current_score):
		return candidate_score > current_score

	if int(candidate.get("distance", 0)) != int(current_best.get("distance", 0)):
		return int(candidate.get("distance", 0)) < int(current_best.get("distance", 0))

	return int(candidate.get("adult_count", 0)) > int(current_best.get("adult_count", 0))
