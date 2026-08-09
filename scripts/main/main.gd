extends Node2D

const GAME_WORLD_VISIBILITY_LAYER := 1 << 1

@onready var game_viewport_container: SubViewportContainer = $GameViewportCanvas/GameViewportContainer
@onready var game_viewport: SubViewport = $GameViewportCanvas/GameViewportContainer/GameViewport
@onready var game_camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var grid_debug_overlay: Node2D = $GridDebugOverlay
@onready var player_side_panel: Control = $UI/PlayerSidePanel


func _ready() -> void:
	add_to_group("main_game")
	_configure_game_viewport()
	_sync_game_viewport_to_side_panel()

	if not player_side_panel.resized.is_connected(_sync_game_viewport_to_side_panel):
		player_side_panel.resized.connect(_sync_game_viewport_to_side_panel)

	var root_viewport := get_viewport()
	if not root_viewport.size_changed.is_connected(_sync_game_viewport_to_side_panel):
		root_viewport.size_changed.connect(_sync_game_viewport_to_side_panel)


func _configure_game_viewport() -> void:
	var root_viewport := get_viewport()
	game_viewport.world_2d = root_viewport.world_2d
	game_camera.enabled = false
	game_camera.custom_viewport = game_viewport
	game_camera.enabled = true
	game_camera.make_current()
	world.visibility_layer = GAME_WORLD_VISIBILITY_LAYER
	grid_debug_overlay.visibility_layer = GAME_WORLD_VISIBILITY_LAYER
	root_viewport.canvas_cull_mask &= ~GAME_WORLD_VISIBILITY_LAYER
	game_viewport.canvas_cull_mask |= GAME_WORLD_VISIBILITY_LAYER
	game_viewport.add_to_group("game_viewport")


func _sync_game_viewport_to_side_panel() -> void:
	var root_width := get_viewport().get_visible_rect().size.x
	game_viewport_container.offset_right = player_side_panel.position.x - root_width


func world_rect_to_root_viewport_rect(world_rect: Rect2) -> Rect2:
	var canvas_transform := game_viewport.get_canvas_transform()
	var container_rect := game_viewport_container.get_global_rect()
	var viewport_size := Vector2(game_viewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Rect2()

	var viewport_corners: Array[Vector2] = [
		canvas_transform * world_rect.position,
		canvas_transform * Vector2(world_rect.end.x, world_rect.position.y),
		canvas_transform * world_rect.end,
		canvas_transform * Vector2(world_rect.position.x, world_rect.end.y),
	]
	var scale_to_container := container_rect.size / viewport_size
	var minimum := container_rect.position + viewport_corners[0] * scale_to_container
	var maximum := minimum
	for viewport_corner: Vector2 in viewport_corners:
		var root_position := container_rect.position + viewport_corner * scale_to_container
		minimum = minimum.min(root_position)
		maximum = maximum.max(root_position)
	return Rect2(minimum, maximum - minimum)


func get_game_viewport_root_rect() -> Rect2:
	return game_viewport_container.get_global_rect()
