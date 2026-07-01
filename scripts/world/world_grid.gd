extends Node2D

# Ссылка на слой тайлов земли, который задаёт геометрию мира.
var ground: TileMapLayer = null

# Размер одного тайла карты.
var tile_size := Vector2i(128, 128)

# Минимальная занятая координата тайла на карте.
var map_min := Vector2i.ZERO

# Максимальная занятая координата тайла на карте.
var map_max := Vector2i.ZERO

# Все кусты травы по их тайловым координатам.
var grass_by_tile: Dictionary = {}

# Опорные тайлы существ, зарегистрированных на сетке.
var creature_anchors: Dictionary = {}

# Опорные тайлы прочих блокирующих объектов, например яиц второй стадии.
var blocker_anchors: Dictionary = {}

# Каким существом сейчас занят каждый тайл.
var occupied_by_tile: Dictionary = {}

# Флаг ленивой инициализации сетки.
var is_initialized := false

# Общий визуальный сдвиг для всех кустов травы, чтобы не ломать уже выставленную вручную геометрию.
var grass_render_offset := Vector2.ZERO

# Был ли уже вычислен общий визуальный сдвиг травы.
var has_grass_render_offset := false

# Все 8 допустимых направлений движения по сетке.
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


# Подготавливает сетку мира и кэширует границы карты.
func _ready() -> void:
	add_to_group("world_grid")
	ensure_initialized()


# Гарантирует, что границы карты и размер тайла уже вычислены.
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


# Находит реальный прямоугольник тайлов по заполненным клеткам слоя земли.
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


# Переводит мировую позицию в координату тайла.
func world_to_map_tile(world_position: Vector2) -> Vector2i:
	ensure_initialized()
	var local_position := ground.to_local(world_position)
	return ground.local_to_map(local_position)


# Переводит мировую позицию центра существа в его опорный тайл.
func world_to_anchor_tile(world_position: Vector2, footprint_size: Vector2i) -> Vector2i:
	var anchor_offset := Vector2(
		float(max(footprint_size.x - 1, 0)) * float(tile_size.x) * 0.5,
		float(max(footprint_size.y - 1, 0)) * float(tile_size.y) * 0.5
	)
	return world_to_map_tile(world_position - anchor_offset)


# Возвращает мировую позицию центра указанного тайла.
func map_to_world_center(tile: Vector2i) -> Vector2:
	ensure_initialized()
	return ground.to_global(ground.map_to_local(tile))


# Возвращает мировую позицию центра существа по его опорному тайлу и размеру footprint.
func anchor_to_world_position(anchor_tile: Vector2i, footprint_size: Vector2i) -> Vector2:
	var world_center := map_to_world_center(anchor_tile)
	var offset := Vector2(
		float(max(footprint_size.x - 1, 0)) * float(tile_size.x) * 0.5,
		float(max(footprint_size.y - 1, 0)) * float(tile_size.y) * 0.5
	)
	return world_center + offset


# Возвращает мировую позицию куста травы по центру указанного тайла.
func grass_tile_to_world_position(tile: Vector2i) -> Vector2:
	return map_to_world_center(tile)


# Возвращает все тайлы, которые занимает footprint с данным опорным тайлом.
func get_footprint_tiles(anchor_tile: Vector2i, footprint_size: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	for y in range(footprint_size.y):
		for x in range(footprint_size.x):
			tiles.append(anchor_tile + Vector2i(x, y))

	return tiles


# Проверяет, лежит ли тайл внутри прямоугольника карты.
func is_tile_inside_map(tile: Vector2i) -> bool:
	ensure_initialized()
	return tile.x >= map_min.x and tile.x <= map_max.x and tile.y >= map_min.y and tile.y <= map_max.y


# Проверяет, существует ли на этом тайле земля.
func is_tile_walkable(tile: Vector2i) -> bool:
	ensure_initialized()

	if not is_tile_inside_map(tile):
		return false

	return ground.get_cell_source_id(tile) != -1


# Проверяет, можно ли поставить footprint в указанный опорный тайл.
func can_place_footprint(anchor_tile: Vector2i, footprint_size: Vector2i, creature: Node = null) -> bool:
	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		if not is_tile_walkable(tile):
			return false

		if occupied_by_tile.has(tile) and occupied_by_tile[tile] != creature:
			return false

	return true


# Возвращает ближайший валидный опорный тайл к желаемой позиции.
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


# Регистрирует траву на указанном тайле.
func register_grass(grass: Node, tile: Vector2i) -> void:
	ensure_initialized()
	grass_by_tile[tile] = grass


# Удаляет траву из реестра тайла.
func unregister_grass(grass: Node, tile: Vector2i) -> void:
	if grass_by_tile.get(tile) == grass:
		grass_by_tile.erase(tile)


# Возвращает траву на указанном тайле, если она есть.
func get_grass_at_tile(tile: Vector2i) -> Node:
	return grass_by_tile.get(tile)


# Проверяет, есть ли уже трава на этом тайле.
func has_grass_at_tile(tile: Vector2i) -> bool:
	var grass: Node = grass_by_tile.get(tile, null)
	return is_instance_valid(grass)


# Регистрирует существо и резервирует тайлы под его footprint.
func register_creature(creature: Node, anchor_tile: Vector2i, footprint_size: Vector2i) -> bool:
	ensure_initialized()

	if not can_place_footprint(anchor_tile, footprint_size, creature):
		return false

	creature_anchors[creature] = anchor_tile
	_reserve_tiles(anchor_tile, footprint_size, creature)
	return true


# Освобождает тайлы, занятые существом.
func unregister_creature(creature: Node, footprint_size: Vector2i) -> void:
	if not creature_anchors.has(creature):
		return

	var anchor_tile: Vector2i = creature_anchors[creature]
	_release_tiles(anchor_tile, footprint_size, creature)
	creature_anchors.erase(creature)


# Переносит существо в новый опорный тайл, если он валиден.
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


# Регистрирует произвольный блокирующий объект и резервирует тайлы под его footprint.
func register_blocker(blocker: Node, anchor_tile: Vector2i, footprint_size: Vector2i) -> bool:
	ensure_initialized()

	if not can_place_footprint(anchor_tile, footprint_size, blocker):
		return false

	blocker_anchors[blocker] = anchor_tile
	_reserve_tiles(anchor_tile, footprint_size, blocker)
	return true


# Освобождает тайлы, занятые блокирующим объектом.
func unregister_blocker(blocker: Node, footprint_size: Vector2i) -> void:
	if not blocker_anchors.has(blocker):
		return

	var anchor_tile: Vector2i = blocker_anchors[blocker]
	_release_tiles(anchor_tile, footprint_size, blocker)
	blocker_anchors.erase(blocker)


# Возвращает все соседние опорные тайлы, куда можно шагнуть с учётом диагоналей.
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


# Строит путь по сетке от стартового опорного тайла к целевому.
func find_path(start_anchor: Vector2i, goal_anchor: Vector2i, footprint_size: Vector2i, creature: Node = null) -> Array[Vector2i]:
	if start_anchor == goal_anchor:
		return []

	if not can_place_footprint(goal_anchor, footprint_size, creature):
		return []

	var open_set: Array[Vector2i] = [start_anchor]
	var open_lookup := {start_anchor: true}
	var came_from: Dictionary = {}
	var g_score := {start_anchor: 0.0}
	var f_score := {start_anchor: _estimate_path_cost(start_anchor, goal_anchor)}

	while not open_set.is_empty():
		var current := _pop_lowest_score(open_set, f_score)
		open_lookup.erase(current)

		if current == goal_anchor:
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

	return []


# Ищет лучшую точку пастьбы, где под footprint есть минимум нужное число взрослых кустов.
func find_best_grazing_target(origin_anchor: Vector2i, footprint_size: Vector2i, min_adult_grass: int, search_radius: int = -1, creature: Node = null, grass_weight: float = 10.0, distance_penalty: float = 2.5) -> Dictionary:
	ensure_initialized()

	var best_result: Dictionary = {}
	var start_x := map_min.x
	var start_y := map_min.y
	var end_x := map_max.x - footprint_size.x + 1
	var end_y := map_max.y - footprint_size.y + 1

	if search_radius >= 0:
		start_x = origin_anchor.x - search_radius
		start_y = origin_anchor.y - search_radius
		end_x = origin_anchor.x + search_radius
		end_y = origin_anchor.y + search_radius

	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var candidate := Vector2i(x, y)

			if not can_place_footprint(candidate, footprint_size, creature):
				continue

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

			if best_result.is_empty() or _is_grazing_result_better(candidate_result, best_result):
				best_result = candidate_result

	return best_result


# Считает число взрослых кустов травы под footprint.
func count_adult_grass_under_footprint(anchor_tile: Vector2i, footprint_size: Vector2i) -> int:
	var adult_count := 0

	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		var grass: Node = grass_by_tile.get(tile, null)

		if not is_instance_valid(grass):
			continue

		if grass.has_method("can_be_eaten") and grass.can_be_eaten():
			adult_count += 1

	return adult_count


# Съедает всю взрослую траву под footprint и возвращает число реально съеденных кустов.
func consume_adult_grass_under_footprint(anchor_tile: Vector2i, footprint_size: Vector2i) -> int:
	var consumed_count := 0

	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		var grass: Node = grass_by_tile.get(tile, null)

		if not is_instance_valid(grass):
			continue

		if not grass.has_method("consume"):
			continue

		if grass.consume():
			consumed_count += 1

	return consumed_count


# Возвращает оценку длины пути в тайлах для быстрой переоценки цели.
func estimate_path_steps(from_anchor: Vector2i, to_anchor: Vector2i) -> int:
	return max(abs(to_anchor.x - from_anchor.x), abs(to_anchor.y - from_anchor.y))


# Резервирует все тайлы footprint за существом.
func _reserve_tiles(anchor_tile: Vector2i, footprint_size: Vector2i, creature: Node) -> void:
	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		occupied_by_tile[tile] = creature


# Освобождает все тайлы footprint у существа.
func _release_tiles(anchor_tile: Vector2i, footprint_size: Vector2i, creature: Node) -> void:
	for tile in get_footprint_tiles(anchor_tile, footprint_size):
		if occupied_by_tile.get(tile) == creature:
			occupied_by_tile.erase(tile)


# Достаёт из открытого списка тайл с минимальной оценкой пути.
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


# Восстанавливает найденный путь из таблицы родителей.
func _reconstruct_path(came_from: Dictionary, current_tile: Vector2i, start_tile: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := current_tile

	while cursor != start_tile:
		path.push_front(cursor)
		cursor = came_from[cursor]

	return path


# Возвращает стоимость одного шага: диагональ чуть дороже прямого движения.
func _step_cost(from_tile: Vector2i, to_tile: Vector2i) -> float:
	var delta := to_tile - from_tile

	if delta.x != 0 and delta.y != 0:
		return 1.41421356

	return 1.0


# Эвристика для движения по 8 направлениям.
func _estimate_path_cost(from_tile: Vector2i, to_tile: Vector2i) -> float:
	var dx: int = abs(to_tile.x - from_tile.x)
	var dy: int = abs(to_tile.y - from_tile.y)
	var diagonal_steps: int = min(dx, dy)
	var straight_steps: int = max(dx, dy) - diagonal_steps
	return float(diagonal_steps) * 1.41421356 + float(straight_steps)


# Сравнивает две точки пастьбы по score: больше — лучше. При равенстве ближе, потом травянистее.
func _is_grazing_result_better(candidate: Dictionary, current_best: Dictionary) -> bool:
	var candidate_score := float(candidate.get("score", -INF))
	var current_score := float(current_best.get("score", -INF))

	if not is_equal_approx(candidate_score, current_score):
		return candidate_score > current_score

	if int(candidate.get("distance", 0)) != int(current_best.get("distance", 0)):
		return int(candidate.get("distance", 0)) < int(current_best.get("distance", 0))

	return int(candidate.get("adult_count", 0)) > int(current_best.get("adult_count", 0))
