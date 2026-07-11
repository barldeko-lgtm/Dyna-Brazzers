extends "res://scripts/world/world_grid.gd"

# Grass is intentionally restricted to the green cells of the authored map.
var grass_allowed_tiles: Dictionary = {}


func set_grass_allowed_tiles(tiles: Array) -> void:
	grass_allowed_tiles.clear()

	for tile in tiles:
		grass_allowed_tiles[tile] = true


func can_host_grass(tile: Vector2i) -> bool:
	if not is_tile_walkable(tile):
		return false

	if grass_allowed_tiles.is_empty():
		return true

	return grass_allowed_tiles.has(tile)


func get_world_bounds_rect() -> Rect2:
	ensure_initialized()

	if ground == null:
		return Rect2()

	var half_tile := Vector2(tile_size) * 0.5
	var min_center := map_to_world_center(map_min)
	var max_center := map_to_world_center(map_max)
	var min_edge := min_center - half_tile
	var max_edge := max_center + half_tile

	return Rect2(min_edge, max_edge - min_edge)
