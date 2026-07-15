extends "res://scripts/world/world_grid.gd"

# Camera bounds for the authored map.
# Grass may occupy and spread onto any normal walkable terrain except the
# fixed player-base footprint.

const PLAYER_BASE_SCENE := preload("res://scenes/world/player_base.tscn")
const PLAYER_BASE_NODE_NAME := "PlayerBase"


func _ready() -> void:
	super._ready()
	spawn_player_base_if_needed()


func can_host_grass(tile: Vector2i) -> bool:
	if not is_tile_walkable(tile):
		return false

	var occupant: Node = occupied_by_tile.get(tile, null)

	if occupant != null and is_instance_valid(occupant) and occupant.is_in_group("player_base"):
		return false

	return true


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


func spawn_player_base_if_needed() -> void:
	if get_node_or_null(PLAYER_BASE_NODE_NAME) != null:
		return

	var spawn_marker := get_node_or_null("CameraStart") as Node2D

	if spawn_marker == null:
		push_error("StartMapWorldGrid: CameraStart marker was not found for the player base.")
		return

	var player_base := PLAYER_BASE_SCENE.instantiate() as Node2D

	if player_base == null:
		push_error("StartMapWorldGrid: player-base scene could not be instantiated.")
		return

	player_base.name = PLAYER_BASE_NODE_NAME
	player_base.position = spawn_marker.position
	add_child(player_base)
