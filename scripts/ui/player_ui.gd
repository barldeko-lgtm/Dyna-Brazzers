extends PanelContainer

# Player side-panel UI:
# - interactive terrain minimap
# - entity counters
# - time speed controls
# - player egg-creation UI bootstrap
#
# Keep this separate from creature_stats_ui.gd so the creature info window does
# not own unrelated player HUD logic.

class MinimapOverlay:
	extends Control

	var owner_ui: Node = null

	func _draw() -> void:
		if owner_ui != null and owner_ui.has_method("draw_minimap_overlay"):
			owner_ui.draw_minimap_overlay(self)


const PLAYER_EGG_CREATION_UI_SCRIPT := preload("res://scripts/ui/player_egg_creation_ui.gd")

const TIME_SPEED_VALUES := [1.0, 2.0, 3.0, 5.0]
const ENTITY_COUNTS_REFRESH_INTERVAL := 0.5
const MINIMAP_WORLD_RETRY_FRAMES := 12
const MINIMAP_CAMERA_MIN_PIXEL_SIZE := 2
const MINIMAP_ENTITY_REFRESH_INTERVAL := 0.10
const MINIMAP_CREATURE_MARKER_SIZE := 6
const MINIMAP_CREATURE_MARKER_HALF_SIZE := 3.0

const TERRAIN_GROUND := 0
const TERRAIN_WATER := 1
const TERRAIN_MOUNTAIN := 2
const TERRAIN_TREE := 3

const MINIMAP_EMPTY_COLOR := Color(0x04070cff)
const MINIMAP_GROUND_COLOR := Color(0xc7a978ff)
const MINIMAP_WATER_COLOR := Color(0x67cfeeff)
const MINIMAP_MOUNTAIN_COLOR := Color(0x41464eff)
const MINIMAP_TREE_COLOR := Color(0x31572fff)
const MINIMAP_DRY_GROUND_COLOR := Color(0x9a6642ff)
const MINIMAP_BORDER_COLOR := Color(0x2e3b52ff)
const MINIMAP_CAMERA_COLOR := Color(0xfff1a3ff)
const MINIMAP_HERBIVORE_COLOR := Color(0x9be26aff)
const MINIMAP_PREDATOR_COLOR := Color(0xe25757ff)
const MINIMAP_EGG_EATER_COLOR := Color(0x2b63ffff)

@onready var minimap_placeholder: PanelContainer = get_node_or_null("MarginContainer/VBoxContainer/MiniMapPlaceholder") as PanelContainer
@onready var player_herbivore_count_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EntityCountsPanel/MarginContainer/GridContainer/PlayerHerbivoreCountLabel")
@onready var player_predator_count_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EntityCountsPanel/MarginContainer/GridContainer/PlayerPredatorCountLabel")
@onready var player_egg_eater_count_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EntityCountsPanel/MarginContainer/GridContainer/PlayerEggEaterCountLabel")
@onready var player_egg_count_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EntityCountsPanel/MarginContainer/GridContainer/PlayerEggCountLabel")
@onready var player_total_count_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EntityCountsPanel/MarginContainer/GridContainer/PlayerTotalCountLabel")

@onready var time_speed_buttons: Array[Button] = [
	get_node_or_null("MarginContainer/VBoxContainer/PlayerNaturePanel/MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed1Button"),
	get_node_or_null("MarginContainer/VBoxContainer/PlayerNaturePanel/MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed2Button"),
	get_node_or_null("MarginContainer/VBoxContainer/PlayerNaturePanel/MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed3Button"),
	get_node_or_null("MarginContainer/VBoxContainer/PlayerNaturePanel/MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed5Button"),
]

var entity_counts_refresh_timer := 0.0
var terrain_minimap_texture: ImageTexture = null
var terrain_minimap_style_box: StyleBoxTexture = null
var minimap_overlay: MinimapOverlay = null
var terrain_minimap_base_image: Image = null
var minimap_map_min := Vector2i.ZERO
var minimap_map_size := Vector2i.ZERO
var minimap_world_bounds := Rect2()
var last_minimap_camera_position := Vector2.ZERO
var last_minimap_camera_zoom := Vector2.ZERO
var has_minimap_camera_state := false
var minimap_entity_refresh_timer := 0.0
var dry_ground_signal_source: Node = null


func _ready() -> void:
	add_to_group("player_ui")
	setup_time_speed_controls()
	setup_player_egg_creation_ui()
	update_entity_counts_text()
	entity_counts_refresh_timer = ENTITY_COUNTS_REFRESH_INTERVAL
	minimap_entity_refresh_timer = 0.0
	call_deferred("initialize_terrain_minimap")


func _process(delta: float) -> void:
	entity_counts_refresh_timer -= delta

	if entity_counts_refresh_timer <= 0.0:
		entity_counts_refresh_timer = ENTITY_COUNTS_REFRESH_INTERVAL
		update_entity_counts_text()

	var force_minimap_update := false
	minimap_entity_refresh_timer -= delta

	if minimap_entity_refresh_timer <= 0.0:
		minimap_entity_refresh_timer = MINIMAP_ENTITY_REFRESH_INTERVAL
		force_minimap_update = true

	update_minimap_camera_view(force_minimap_update)


func initialize_terrain_minimap() -> void:
	for _attempt in range(MINIMAP_WORLD_RETRY_FRAMES):
		if rebuild_terrain_minimap():
			return

		await get_tree().process_frame

	push_warning("Terrain minimap could not find the active Ground TileMapLayer.")


func rebuild_terrain_minimap() -> bool:
	if minimap_placeholder == null:
		return false

	var ground := find_ground_tile_map()
	var dry_ground := find_dry_ground_tile_map()

	if ground == null:
		return false

	var used_rect := ground.get_used_rect()
	minimap_map_min = used_rect.position
	minimap_map_size = used_rect.size

	if minimap_map_size.x <= 0 or minimap_map_size.y <= 0:
		return false

	minimap_world_bounds = get_minimap_world_bounds(ground)

	if minimap_world_bounds.size.x <= 0.0 or minimap_world_bounds.size.y <= 0.0:
		return false

	var minimap_image := Image.create_empty(minimap_map_size.x + 2, minimap_map_size.y + 2, false, Image.FORMAT_RGBA8)
	minimap_image.fill(MINIMAP_BORDER_COLOR)

	for image_y in range(minimap_map_size.y):
		for image_x in range(minimap_map_size.x):
			var map_tile := minimap_map_min + Vector2i(image_x, image_y)
			var source_id := ground.get_cell_source_id(map_tile)
			var terrain_color := get_minimap_terrain_color(source_id)

			if dry_ground != null and dry_ground.tile_set != null and dry_ground.get_cell_source_id(map_tile) != -1:
				terrain_color = MINIMAP_DRY_GROUND_COLOR

			minimap_image.set_pixel(image_x + 1, image_y + 1, terrain_color)

	terrain_minimap_base_image = minimap_image
	terrain_minimap_texture = ImageTexture.create_from_image(minimap_image)

	if terrain_minimap_texture == null:
		return false

	terrain_minimap_style_box = StyleBoxTexture.new()
	terrain_minimap_style_box.texture = terrain_minimap_texture
	minimap_placeholder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap_placeholder.add_theme_stylebox_override("panel", terrain_minimap_style_box)
	minimap_placeholder.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap_placeholder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	minimap_placeholder.tooltip_text = "Миникарта мира — ЛКМ: переместить камеру"
	ensure_minimap_overlay()

	var minimap_input_callable := Callable(self, "_on_minimap_gui_input")

	if not minimap_placeholder.gui_input.is_connected(minimap_input_callable):
		minimap_placeholder.gui_input.connect(minimap_input_callable)

	has_minimap_camera_state = false
	minimap_entity_refresh_timer = 0.0
	_bind_dry_ground_changes()
	update_minimap_camera_view(true)
	return true


func find_ground_tile_map() -> TileMapLayer:
	var world_grid := get_tree().get_first_node_in_group("world_grid")

	if world_grid != null:
		var grouped_ground := world_grid.get_node_or_null("Ground") as TileMapLayer

		if grouped_ground != null:
			return grouped_ground

	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.get_node_or_null("World/Ground") as TileMapLayer


func find_dry_ground_tile_map() -> TileMapLayer:
	var world_grid := get_tree().get_first_node_in_group("world_grid")

	if world_grid != null:
		return world_grid.get_node_or_null("DryGround") as TileMapLayer

	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.get_node_or_null("World/DryGround") as TileMapLayer


func _bind_dry_ground_changes() -> void:
	var world_grid := get_tree().get_first_node_in_group("world_grid")

	if world_grid == null or world_grid == dry_ground_signal_source:
		return

	dry_ground_signal_source = world_grid
	var changed_callable := Callable(self, "_on_dry_ground_changed")

	if world_grid.has_signal("dry_ground_changed") and not world_grid.is_connected(
		"dry_ground_changed", changed_callable
	):
		world_grid.connect("dry_ground_changed", changed_callable)


func _on_dry_ground_changed() -> void:
	rebuild_terrain_minimap()


func get_minimap_world_bounds(ground: TileMapLayer) -> Rect2:
	var world_grid := get_tree().get_first_node_in_group("world_grid")

	if world_grid != null and world_grid.has_method("get_world_bounds_rect"):
		var world_bounds: Rect2 = world_grid.get_world_bounds_rect()

		if world_bounds.size.x > 0.0 and world_bounds.size.y > 0.0:
			return world_bounds

	var tile_size := Vector2(128.0, 128.0)

	if ground.tile_set != null:
		tile_size = Vector2(ground.tile_set.tile_size)

	var max_tile := minimap_map_min + minimap_map_size - Vector2i.ONE
	var min_center := ground.to_global(ground.map_to_local(minimap_map_min))
	var max_center := ground.to_global(ground.map_to_local(max_tile))
	var min_edge := min_center - tile_size * 0.5
	var max_edge := max_center + tile_size * 0.5
	return Rect2(min_edge, max_edge - min_edge)


func get_minimap_terrain_color(source_id: int) -> Color:
	match source_id:
		TERRAIN_GROUND:
			return MINIMAP_GROUND_COLOR
		TERRAIN_WATER:
			return MINIMAP_WATER_COLOR
		TERRAIN_MOUNTAIN:
			return MINIMAP_MOUNTAIN_COLOR
		TERRAIN_TREE:
			return MINIMAP_TREE_COLOR
		_:
			return MINIMAP_EMPTY_COLOR


func update_minimap_camera_view(force_update := false) -> void:
	if terrain_minimap_base_image == null or terrain_minimap_texture == null:
		return

	var camera := find_active_camera()

	if camera == null:
		return

	if not force_update and has_minimap_camera_state:
		if camera.global_position.is_equal_approx(last_minimap_camera_position) and camera.zoom.is_equal_approx(last_minimap_camera_zoom):
			return

	last_minimap_camera_position = camera.global_position
	last_minimap_camera_zoom = camera.zoom
	has_minimap_camera_state = true

	if minimap_overlay != null and is_instance_valid(minimap_overlay):
		minimap_overlay.queue_redraw()


func find_active_camera() -> Camera2D:
	var active_camera := get_viewport().get_camera_2d()

	if active_camera != null:
		return active_camera

	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.get_node_or_null("Camera2D") as Camera2D


func ensure_minimap_overlay() -> void:
	if minimap_placeholder == null:
		return

	if minimap_overlay != null and is_instance_valid(minimap_overlay):
		return

	minimap_overlay = MinimapOverlay.new()
	minimap_overlay.name = "MinimapOverlay"
	minimap_overlay.owner_ui = self
	minimap_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_overlay.offset_left = 0.0
	minimap_overlay.offset_top = 0.0
	minimap_overlay.offset_right = 0.0
	minimap_overlay.offset_bottom = 0.0
	minimap_placeholder.add_child(minimap_overlay)


func draw_minimap_overlay(overlay: Control) -> void:
	if overlay == null:
		return

	draw_creature_markers_on_overlay(overlay)

	var camera := find_active_camera()

	if camera != null:
		draw_camera_rect_on_overlay(overlay, get_camera_world_rect(camera))


func draw_creature_markers_on_overlay(overlay: Control) -> void:
	for creature in get_tree().get_nodes_in_group("creatures"):
		if not is_instance_valid(creature):
			continue

		if creature.is_queued_for_deletion() or not (creature is Node2D):
			continue

		var creature_node := creature as Node2D
		var overlay_position := world_to_minimap_overlay_position(creature_node.global_position, overlay.size)

		if overlay_position.x < 0.0 or overlay_position.y < 0.0:
			continue

		draw_triangle_marker_on_overlay(overlay, overlay_position, get_minimap_creature_color(creature))


func get_minimap_creature_color(creature: Node) -> Color:
	var species_data: Resource = creature.get("species_data")

	if species_data != null:
		var resource_path := species_data.resource_path.to_lower()

		if resource_path.contains("egg_eater"):
			return MINIMAP_EGG_EATER_COLOR

		if bool(species_data.get("is_predator")):
			return MINIMAP_PREDATOR_COLOR

	return MINIMAP_HERBIVORE_COLOR


func get_minimap_content_rect(draw_size: Vector2) -> Rect2:
	var image_size := Vector2(minimap_map_size + Vector2i(2, 2))

	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return Rect2()

	var border_size := Vector2(
		draw_size.x / image_size.x,
		draw_size.y / image_size.y
	)
	return Rect2(border_size, draw_size - border_size * 2.0)


func world_to_minimap_overlay_position(world_position: Vector2, draw_size: Vector2) -> Vector2:
	if minimap_map_size.x <= 0 or minimap_map_size.y <= 0:
		return Vector2(-1.0, -1.0)

	if minimap_world_bounds.size.x <= 0.0 or minimap_world_bounds.size.y <= 0.0:
		return Vector2(-1.0, -1.0)

	var content_rect := get_minimap_content_rect(draw_size)

	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		return Vector2(-1.0, -1.0)

	var normalized_x := clampf((world_position.x - minimap_world_bounds.position.x) / minimap_world_bounds.size.x, 0.0, 1.0)
	var normalized_y := clampf((world_position.y - minimap_world_bounds.position.y) / minimap_world_bounds.size.y, 0.0, 1.0)
	return content_rect.position + Vector2(normalized_x * content_rect.size.x, normalized_y * content_rect.size.y)


func draw_triangle_marker_on_overlay(overlay: Control, center_position: Vector2, marker_color: Color) -> void:
	var top_left := Vector2(
		floor(center_position.x - MINIMAP_CREATURE_MARKER_HALF_SIZE),
		floor(center_position.y - MINIMAP_CREATURE_MARKER_HALF_SIZE)
	)

	for pixel_offset in get_triangle_marker_pixels():
		overlay.draw_rect(Rect2(top_left + pixel_offset, Vector2.ONE), marker_color, true)


func get_triangle_marker_pixels() -> Array[Vector2]:
	return [
		Vector2(2, 0), Vector2(3, 0),
		Vector2(1, 1), Vector2(2, 1), Vector2(3, 1), Vector2(4, 1),
		Vector2(1, 2), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2),
		Vector2(0, 3), Vector2(1, 3), Vector2(2, 3), Vector2(3, 3), Vector2(4, 3), Vector2(5, 3),
		Vector2(0, 4), Vector2(1, 4), Vector2(2, 4), Vector2(3, 4), Vector2(4, 4), Vector2(5, 4)
	]


func get_camera_world_rect(camera: Camera2D) -> Rect2:
	var viewport_size := camera.get_viewport_rect().size
	var safe_zoom := Vector2(maxf(camera.zoom.x, 0.001), maxf(camera.zoom.y, 0.001))
	var visible_size := viewport_size / safe_zoom
	return Rect2(camera.global_position - visible_size * 0.5, visible_size)


func draw_camera_rect_on_overlay(overlay: Control, camera_world_rect: Rect2) -> void:
	var clipped_rect := camera_world_rect.intersection(minimap_world_bounds)

	if clipped_rect.size.x <= 0.0 or clipped_rect.size.y <= 0.0:
		return

	var content_rect := get_minimap_content_rect(overlay.size)

	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		return

	var normalized_left := clampf((clipped_rect.position.x - minimap_world_bounds.position.x) / minimap_world_bounds.size.x, 0.0, 1.0)
	var normalized_top := clampf((clipped_rect.position.y - minimap_world_bounds.position.y) / minimap_world_bounds.size.y, 0.0, 1.0)
	var normalized_right := clampf((clipped_rect.end.x - minimap_world_bounds.position.x) / minimap_world_bounds.size.x, 0.0, 1.0)
	var normalized_bottom := clampf((clipped_rect.end.y - minimap_world_bounds.position.y) / minimap_world_bounds.size.y, 0.0, 1.0)

	var left := int(floor(content_rect.position.x + normalized_left * content_rect.size.x))
	var top := int(floor(content_rect.position.y + normalized_top * content_rect.size.y))
	var right := int(ceil(content_rect.position.x + normalized_right * content_rect.size.x)) - 1
	var bottom := int(ceil(content_rect.position.y + normalized_bottom * content_rect.size.y)) - 1

	var min_x := int(floor(content_rect.position.x))
	var min_y := int(floor(content_rect.position.y))
	var max_x := int(ceil(content_rect.end.x)) - 1
	var max_y := int(ceil(content_rect.end.y)) - 1

	left = clampi(left, min_x, max_x)
	top = clampi(top, min_y, max_y)
	right = clampi(right, min_x, max_x)
	bottom = clampi(bottom, min_y, max_y)

	var horizontal_edges := ensure_minimap_pixel_span(left, right, min_x, max_x)
	var vertical_edges := ensure_minimap_pixel_span(top, bottom, min_y, max_y)
	left = horizontal_edges.x
	right = horizontal_edges.y
	top = vertical_edges.x
	bottom = vertical_edges.y

	var rect_position := Vector2(left, top)
	var rect_size := Vector2(right - left + 1, bottom - top + 1)
	overlay.draw_rect(Rect2(rect_position, rect_size), MINIMAP_CAMERA_COLOR, false, 1.0)


func ensure_minimap_pixel_span(start_pixel: int, end_pixel: int, minimum_pixel: int, maximum_pixel: int) -> Vector2i:
	while end_pixel - start_pixel + 1 < MINIMAP_CAMERA_MIN_PIXEL_SIZE:
		if end_pixel < maximum_pixel:
			end_pixel += 1
		elif start_pixel > minimum_pixel:
			start_pixel -= 1
		else:
			break

	return Vector2i(start_pixel, end_pixel)


func _on_minimap_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton

	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	move_camera_to_minimap_position(mouse_event.position)
	minimap_placeholder.accept_event()


func move_camera_to_minimap_position(local_position: Vector2) -> void:
	if minimap_placeholder == null:
		return

	if minimap_placeholder.size.x <= 0.0 or minimap_placeholder.size.y <= 0.0:
		return

	if minimap_map_size.x <= 0 or minimap_map_size.y <= 0:
		return

	var camera := find_active_camera()

	if camera == null:
		return

	var content_rect := get_minimap_content_rect(minimap_placeholder.size)

	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		return

	var normalized_position := Vector2(
		clampf((local_position.x - content_rect.position.x) / content_rect.size.x, 0.0, 1.0),
		clampf((local_position.y - content_rect.position.y) / content_rect.size.y, 0.0, 1.0)
	)

	camera.global_position = minimap_world_bounds.position + normalized_position * minimap_world_bounds.size
	has_minimap_camera_state = false
	minimap_entity_refresh_timer = 0.0
	update_minimap_camera_view(true)


func update_entity_counts_text() -> void:
	var herbivore_count := count_creatures_by_category("herbivore")
	var predator_count := count_creatures_by_category("predator")
	var egg_eater_count := count_creatures_by_category("egg_eater")
	var egg_count := count_eggs()

	if player_herbivore_count_label != null:
		player_herbivore_count_label.text = str(herbivore_count)

	if player_predator_count_label != null:
		player_predator_count_label.text = str(predator_count)

	if player_egg_eater_count_label != null:
		player_egg_eater_count_label.text = str(egg_eater_count)

	if player_egg_count_label != null:
		player_egg_count_label.text = str(egg_count)

	if player_total_count_label != null:
		player_total_count_label.text = str(herbivore_count + predator_count + egg_eater_count)


func count_creatures_by_category(category: StringName) -> int:
	var count := 0

	for creature in get_tree().get_nodes_in_group("creatures"):
		if not is_instance_valid(creature) or creature.is_queued_for_deletion():
			continue

		if get_creature_category(creature) == category:
			count += 1

	return count


func get_creature_category(creature: Node) -> StringName:
	var species_data: Resource = creature.get("species_data")

	if species_data == null:
		return &""

	if species_data.resource_path.to_lower().contains("egg_eater"):
		return &"egg_eater"

	if bool(species_data.get("is_predator")):
		return &"predator"

	return &"herbivore"


func count_eggs() -> int:
	var count := 0

	for egg in get_tree().get_nodes_in_group("eggs"):
		if not is_instance_valid(egg):
			continue

		if egg.is_queued_for_deletion():
			continue

		count += 1

	return count


func setup_player_egg_creation_ui() -> void:
	if get_node_or_null("PlayerEggCreationUI") != null:
		return

	var egg_creation_ui := PLAYER_EGG_CREATION_UI_SCRIPT.new() as Node
	egg_creation_ui.name = "PlayerEggCreationUI"
	add_child(egg_creation_ui)


func setup_time_speed_controls() -> void:
	var selected_index := 0

	for index in range(TIME_SPEED_VALUES.size()):
		if is_equal_approx(Engine.time_scale, TIME_SPEED_VALUES[index]):
			selected_index = index
			break

	for index in range(time_speed_buttons.size()):
		var button := time_speed_buttons[index]

		if button == null:
			continue

		button.toggle_mode = true
		button.text = "x%d" % int(TIME_SPEED_VALUES[index])
		button.focus_mode = Control.FOCUS_NONE

		var pressed_callable := Callable(self, "_on_time_speed_button_pressed").bind(index)

		if not button.pressed.is_connected(pressed_callable):
			button.pressed.connect(pressed_callable)

	apply_time_speed_by_index(selected_index)


func apply_time_speed_by_index(index: int) -> void:
	if index < 0 or index >= TIME_SPEED_VALUES.size():
		return

	Engine.time_scale = TIME_SPEED_VALUES[index]

	for button_index in range(time_speed_buttons.size()):
		var button := time_speed_buttons[button_index]

		if button != null:
			button.set_pressed_no_signal(button_index == index)


func _on_time_speed_button_pressed(index: int) -> void:
	apply_time_speed_by_index(index)
