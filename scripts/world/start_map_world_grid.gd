extends "res://scripts/world/world_grid.gd"

# Camera bounds for the authored map.
# Grass may occupy and spread onto any normal walkable terrain.


func can_host_grass(tile: Vector2i) -> bool:
	return is_tile_walkable(tile)


func get_world_bounds_rect() -> Rect2:
	ensure_initialized()

	if ground == null:
		return Rect2()

	var half_tile: Vector2 = Vector2(tile_size) * 0.5
	var min_center: Vector2 = map_to_world_center(map_min)
	var max_center: Vector2 = map_to_world_center(map_max)
	var min_edge: Vector2 = min_center - half_tile
	var max_edge: Vector2 = max_center + half_tile

	return Rect2(min_edge, max_edge - min_edge)
