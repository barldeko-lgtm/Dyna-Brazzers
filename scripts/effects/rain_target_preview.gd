extends Node2D

const RAIN_CAST_EFFECT_SCENE := preload("res://scenes/effects/rain_cast_effect.tscn")

@export var radius := 1
@export var valid_fill_color := Color(0.2, 0.55, 1.0, 0.22)
@export var valid_border_color := Color(0.45, 0.8, 1.0, 0.9)
@export var invalid_fill_color := Color(1.0, 0.25, 0.2, 0.18)
@export var invalid_border_color := Color(1.0, 0.35, 0.25, 0.85)

var tile_size := Vector2(128.0, 128.0)
var world_grid: Node = null
var center_tile := Vector2i.ZERO
var is_valid_target := true

func configure(grid: Node, target_radius: int) -> void:
	world_grid = grid
	radius = target_radius
	_update_tile_size()
	hide_preview()


func set_center_tile(tile: Vector2i, valid_target: bool = true) -> void:
	center_tile = tile
	is_valid_target = valid_target

	if world_grid != null and world_grid.has_method("map_to_world_center"):
		global_position = world_grid.call("map_to_world_center", center_tile)

	visible = true
	queue_redraw()


func hide_preview() -> void:
	visible = false
	queue_redraw()


func play_cast_effect(tile: Vector2i) -> void:
	_spawn_rain_effect(tile)


func _spawn_rain_effect(tile: Vector2i) -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		return

	if not world_grid.has_method("map_to_world_center"):
		return

	var effect := RAIN_CAST_EFFECT_SCENE.instantiate() as Node2D

	if effect == null:
		return

	world_grid.add_child(effect)
	effect.global_position = world_grid.call("map_to_world_center", tile)

	PerformanceStats.add_counter("rain_visual_effect_spawned")


func _update_tile_size() -> void:
	if world_grid == null:
		return

	var raw_tile_size = world_grid.get("tile_size")

	if raw_tile_size is Vector2i:
		tile_size = Vector2(float(raw_tile_size.x), float(raw_tile_size.y))
	elif raw_tile_size is Vector2:
		tile_size = raw_tile_size


func _draw() -> void:
	if not visible:
		return

	var fill_color := valid_fill_color if is_valid_target else invalid_fill_color
	var border_color := valid_border_color if is_valid_target else invalid_border_color
	var half_tile := tile_size * 0.5

	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var offset := Vector2(float(x) * tile_size.x, float(y) * tile_size.y)
			var rect := Rect2(offset - half_tile, tile_size)
			draw_rect(rect, fill_color, true)
			draw_rect(rect, border_color, false, 2.0)
