extends Node

# World-side application of player nature powers.
const LIGHTNING_EFFECT_SCENE := preload("res://scenes/effects/lightning_strike_effect.tscn")
const RAIN_CAST_EFFECT_SCENE := preload("res://scenes/effects/rain_cast_effect.tscn")

@export var lightning_damage := 50.0
@export var rain_radius_tiles := 2
@export var sun_radius_tiles := 3
@export var sun_spread_reset_radius_tiles := 4
@export var sun_remove_grass_count := 20

var world_grid: Node = null


func _ready() -> void:
	add_to_group("nature_effects_system")
	world_grid = get_parent()

	if world_grid == null or not world_grid.has_method("is_tile_inside_map"):
		world_grid = get_tree().get_first_node_in_group("world_grid")


func can_apply_at_tile(center_tile: Vector2i) -> bool:
	return world_grid != null and is_instance_valid(world_grid) and bool(
		world_grid.call("is_tile_inside_map", center_tile)
	)


func get_rain_radius_tiles() -> int:
	return rain_radius_tiles


func get_sun_radius_tiles() -> int:
	return sun_radius_tiles


func can_apply_lightning(creature: Node) -> bool:
	return (
		creature != null
		and is_instance_valid(creature)
		and creature.has_method("take_direct_damage")
	)


func apply_lightning(creature: Node) -> bool:
	if not can_apply_lightning(creature):
		return false

	_spawn_lightning_effect(creature)
	creature.call("take_direct_damage", lightning_damage)
	return true


func apply_rain(center_tile: Vector2i) -> bool:
	if not can_apply_at_tile(center_tile):
		return false

	var checked_tiles := 0
	var affected_grass := 0

	for y in range(center_tile.y - rain_radius_tiles, center_tile.y + rain_radius_tiles + 1):
		for x in range(center_tile.x - rain_radius_tiles, center_tile.x + rain_radius_tiles + 1):
			checked_tiles += 1
			var tile := Vector2i(x, y)

			if not bool(world_grid.call("can_host_grass", tile)):
				continue

			var grass: Node = world_grid.call("get_grass_at_tile", tile)

			if not is_instance_valid(grass) or not grass.has_method("apply_rain"):
				continue

			if grass.call("apply_rain"):
				affected_grass += 1

	PerformanceStats.add_counter("rain_tiles_checked", checked_tiles)
	PerformanceStats.add_counter("rain_grass_affected", affected_grass)
	_spawn_rain_cast_effect(center_tile)
	return true


func apply_sun(center_tile: Vector2i) -> bool:
	if not can_apply_at_tile(center_tile):
		return false

	var checked_tiles := 0
	var reverted_grass := 0
	var grass_nodes: Array[Node] = []

	for y in range(center_tile.y - sun_radius_tiles, center_tile.y + sun_radius_tiles + 1):
		for x in range(center_tile.x - sun_radius_tiles, center_tile.x + sun_radius_tiles + 1):
			checked_tiles += 1
			var tile := Vector2i(x, y)

			if not bool(world_grid.call("can_host_grass", tile)):
				continue

			var grass: Node = world_grid.call("get_grass_at_tile", tile)

			if not is_instance_valid(grass):
				continue

			grass_nodes.append(grass)

			if grass.has_method("apply_sun") and grass.call("apply_sun"):
				reverted_grass += 1

	grass_nodes.shuffle()
	var removed_grass := 0
	var target_remove_count: int = min(sun_remove_grass_count, grass_nodes.size())

	for index in range(target_remove_count):
		var grass_to_remove := grass_nodes[index]

		if not is_instance_valid(grass_to_remove):
			continue

		grass_to_remove.queue_free()
		removed_grass += 1

	var reset_spread_grass := _reset_spread_attempts_in_area(
		center_tile, sun_spread_reset_radius_tiles
	)
	PerformanceStats.add_counter("sun_tiles_checked", checked_tiles)
	PerformanceStats.add_counter("sun_grass_reverted", reverted_grass)
	PerformanceStats.add_counter("sun_grass_removed", removed_grass)
	PerformanceStats.add_counter("sun_grass_spread_reset", reset_spread_grass)
	return true


func _reset_spread_attempts_in_area(center_tile: Vector2i, radius: int) -> int:
	var reset_count := 0

	for y in range(center_tile.y - radius, center_tile.y + radius + 1):
		for x in range(center_tile.x - radius, center_tile.x + radius + 1):
			var tile := Vector2i(x, y)

			if not bool(world_grid.call("can_host_grass", tile)):
				continue

			var grass: Node = world_grid.call("get_grass_at_tile", tile)

			if not is_instance_valid(grass) or grass.is_queued_for_deletion():
				continue

			if grass.has_method("reset_spread_attempt") and grass.call("reset_spread_attempt"):
				reset_count += 1

	return reset_count


func _spawn_lightning_effect(target: Node) -> void:
	if not (target is Node2D):
		return

	var effect_parent := target.get_parent()

	if effect_parent == null:
		effect_parent = world_grid

	if effect_parent == null:
		return

	var effect := LIGHTNING_EFFECT_SCENE.instantiate() as Node2D

	if effect == null:
		return

	effect_parent.add_child(effect)
	effect.global_position = (target as Node2D).global_position


func _spawn_rain_cast_effect(center_tile: Vector2i) -> void:
	var effect := RAIN_CAST_EFFECT_SCENE.instantiate() as Node2D

	if effect == null:
		return

	world_grid.add_child(effect)
	effect.global_position = world_grid.call("map_to_world_center", center_tile)
	PerformanceStats.add_counter("rain_visual_effect_spawned")
