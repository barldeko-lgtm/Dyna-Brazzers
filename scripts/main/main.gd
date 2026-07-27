extends Node2D

const GAME_WORLD_VISIBILITY_LAYER := 1 << 1

@onready var game_viewport_container: SubViewportContainer = $GameViewportCanvas/GameViewportContainer
@onready var game_viewport: SubViewport = $GameViewportCanvas/GameViewportContainer/GameViewport
@onready var game_camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var grid_debug_overlay: Node2D = $GridDebugOverlay
@onready var player_side_panel: Control = $UI/PlayerSidePanel


func _ready() -> void:
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
