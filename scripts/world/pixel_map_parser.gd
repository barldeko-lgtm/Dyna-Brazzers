extends RefCounted

const MARKER_GROUND := "."
const MARKER_WATER := "W"
const MARKER_DRY_GROUND := "D"
const MARKER_GRASS := "G"
const MARKER_MOUNTAIN := "M"
const MARKER_TREE := "T"
const MARKER_BASE := "B"

const RGBA_TO_MARKER: Dictionary = {
	0x966805ff: MARKER_GROUND,
	0x0f128bff: MARKER_WATER,
	0x562e04ff: MARKER_DRY_GROUND,
	0x099605ff: MARKER_GRASS,
	0x000000ff: MARKER_MOUNTAIN,
	0xac62a1ff: MARKER_TREE,
	0x960905ff: MARKER_BASE
}

const MARKER_NAMES: Dictionary = {
	MARKER_GROUND: "ground",
	MARKER_WATER: "water",
	MARKER_DRY_GROUND: "dry_ground",
	MARKER_GRASS: "grass",
	MARKER_MOUNTAIN: "mountain",
	MARKER_TREE: "tree",
	MARKER_BASE: "base"
}


func parse_image(image: Image) -> Dictionary:
	var errors: Array[String] = []
	var rows: Array[String] = []
	var marker_counts: Dictionary = {
		"ground": 0,
		"water": 0,
		"dry_ground": 0,
		"grass": 0,
		"mountain": 0,
		"tree": 0,
		"base": 0
	}

	if image == null or image.is_empty():
		errors.append("Pixel map image is empty.")
		return _build_result(0, 0, rows, marker_counts, [], [], [], errors)

	for y in range(image.get_height()):
		var row := ""

		for x in range(image.get_width()):
			var rgba: int = image.get_pixel(x, y).to_rgba32()
			var marker: String = String(RGBA_TO_MARKER.get(rgba, ""))

			if marker.is_empty():
				errors.append(
					"Unknown pixel color 0x%08X at (%d, %d)." % [rgba, x, y]
				)
				row += "?"
				continue

			row += marker
			var marker_name: String = String(MARKER_NAMES[marker])
			marker_counts[marker_name] = int(marker_counts[marker_name]) + 1

		rows.append(row)

	var base_anchors: Array[Vector2i] = _extract_2x2_components(
		rows,
		MARKER_BASE,
		"Base",
		errors
	)
	var tree_anchors: Array[Vector2i] = _extract_2x2_components(
		rows,
		MARKER_TREE,
		"Tree",
		errors
	)
	var grass_tiles: Array[Vector2i] = _collect_marker_tiles(rows, MARKER_GRASS)

	if base_anchors.size() != 2:
		errors.append(
			"Pixel map must contain exactly two 2x2 bases; found %d." % base_anchors.size()
		)
	else:
		base_anchors.sort_custom(_sort_by_x_then_y)

	return _build_result(
		image.get_width(),
		image.get_height(),
		rows,
		marker_counts,
		base_anchors,
		tree_anchors,
		grass_tiles,
		errors
	)


func _build_result(
	width: int,
	height: int,
	rows: Array[String],
	marker_counts: Dictionary,
	base_anchors: Array,
	tree_anchors: Array,
	grass_tiles: Array,
	errors: Array[String]
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"width": width,
		"height": height,
		"rows": rows,
		"marker_counts": marker_counts,
		"base_anchors": base_anchors,
		"tree_anchors": tree_anchors,
		"grass_tiles": grass_tiles,
		"errors": errors
	}


func _extract_2x2_components(
	rows: Array[String],
	marker: String,
	label: String,
	errors: Array[String]
) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	var visited: Dictionary = {}

	for y in range(rows.size()):
		for x in range(rows[y].length()):
			var start := Vector2i(x, y)

			if visited.has(start) or _marker_at(rows, start) != marker:
				continue

			var component: Array[Vector2i] = _collect_component(rows, start, marker, visited)
			var min_x: int = component[0].x
			var min_y: int = component[0].y
			var max_x: int = component[0].x
			var max_y: int = component[0].y

			for tile in component:
				min_x = mini(min_x, tile.x)
				min_y = mini(min_y, tile.y)
				max_x = maxi(max_x, tile.x)
				max_y = maxi(max_y, tile.y)

			if component.size() != 4 or max_x - min_x != 1 or max_y - min_y != 1:
				errors.append(
					"%s pixels at (%d, %d) must form one complete 2x2 block." % [
						label,
						min_x,
						min_y
					]
				)
				continue

			anchors.append(Vector2i(min_x, min_y))

	return anchors


func _collect_component(
	rows: Array[String],
	start: Vector2i,
	marker: String,
	visited: Dictionary
) -> Array[Vector2i]:
	var component: Array[Vector2i] = []
	var pending: Array[Vector2i] = [start]
	var pending_index := 0
	visited[start] = true

	while pending_index < pending.size():
		var tile: Vector2i = pending[pending_index]
		pending_index += 1
		component.append(tile)

		for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor: Vector2i = tile + offset

			if visited.has(neighbor) or _marker_at(rows, neighbor) != marker:
				continue

			visited[neighbor] = true
			pending.append(neighbor)

	return component


func _collect_marker_tiles(rows: Array[String], marker: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	for y in range(rows.size()):
		for x in range(rows[y].length()):
			if rows[y].substr(x, 1) == marker:
				tiles.append(Vector2i(x, y))

	return tiles


func _marker_at(rows: Array[String], tile: Vector2i) -> String:
	if tile.y < 0 or tile.y >= rows.size():
		return ""

	if tile.x < 0 or tile.x >= rows[tile.y].length():
		return ""

	return rows[tile.y].substr(tile.x, 1)


func _sort_by_x_then_y(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y

	return left.x < right.x
