extends PanelContainer

# Player side-panel UI:
# - terrain minimap
# - entity counters
# - time speed controls
#
# Keep this separate from creature_stats_ui.gd so the creature info window does
# not own unrelated player HUD logic.

const TIME_SPEED_VALUES := [1.0, 2.0, 3.0, 5.0]
const ENTITY_COUNTS_REFRESH_INTERVAL := 0.5
const MINIMAP_WORLD_RETRY_FRAMES := 12

const TERRAIN_GROUND := 0
const TERRAIN_WATER := 1
const TERRAIN_MOUNTAIN := 2
const TERRAIN_TREE := 3

const MINIMAP_EMPTY_COLOR := Color(0x04070cff)
const MINIMAP_GROUND_COLOR := Color(0x577e3dff)
const MINIMAP_WATER_COLOR := Color(0x306692ff)
const MINIMAP_MOUNTAIN_COLOR := Color(0x74695bff)
const MINIMAP_TREE_COLOR := Color(0x31572fff)
const MINIMAP_BORDER_COLOR := Color(0x2e3b52ff)

@onready var minimap_placeholder: PanelContainer = get_node_or_null("MarginContainer/VBoxContainer/MiniMapPlaceholder") as PanelContainer
@onready var player_herbivore_count_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EntityCountsPanel/MarginContainer/GridContainer/PlayerHerbivoreCountLabel")
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


func _ready() -> void:
	add_to_group("player_ui")
	setup_time_speed_controls()
	update_entity_counts_text()
	entity_counts_refresh_timer = ENTITY_COUNTS_REFRESH_INTERVAL
	call_deferred("initialize_terrain_minimap")


func _process(delta: float) -> void:
	entity_counts_refresh_timer -= delta

	if entity_counts_refresh_timer <= 0.0:
		entity_counts_refresh_timer = ENTITY_COUNTS_REFRESH_INTERVAL
		update_entity_counts_text()


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

	if ground == null:
		return false

	var used_rect := ground.get_used_rect()
	var map_min := used_rect.position
	var map_width := used_rect.size.x
	var map_height := used_rect.size.y

	if map_width <= 0 or map_height <= 0:
		return false

	var minimap_image := Image.create_empty(map_width + 2, map_height + 2, false, Image.FORMAT_RGBA8)
	minimap_image.fill(MINIMAP_BORDER_COLOR)

	for image_y in range(map_height):
		for image_x in range(map_width):
			var map_tile := map_min + Vector2i(image_x, image_y)
			var source_id := ground.get_cell_source_id(map_tile)
			minimap_image.set_pixel(image_x + 1, image_y + 1, get_minimap_terrain_color(source_id))

	terrain_minimap_texture = ImageTexture.create_from_image(minimap_image)

	if terrain_minimap_texture == null:
		return false

	terrain_minimap_style_box = StyleBoxTexture.new()
	terrain_minimap_style_box.texture = terrain_minimap_texture
	minimap_placeholder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap_placeholder.add_theme_stylebox_override("panel", terrain_minimap_style_box)
	minimap_placeholder.tooltip_text = "Миникарта мира"
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


func update_entity_counts_text() -> void:
	var herbivore_count := count_herbivore_creatures()
	var egg_count := count_eggs()

	if player_herbivore_count_label != null:
		player_herbivore_count_label.text = str(herbivore_count)

	if player_egg_count_label != null:
		player_egg_count_label.text = str(egg_count)

	if player_total_count_label != null:
		player_total_count_label.text = str(herbivore_count + egg_count)


func count_herbivore_creatures() -> int:
	var count := 0

	for creature in get_tree().get_nodes_in_group("creatures"):
		if not is_instance_valid(creature):
			continue

		if creature.is_queued_for_deletion():
			continue

		if is_herbivore_creature(creature):
			count += 1

	return count


func is_herbivore_creature(creature: Node) -> bool:
	var species_data: Resource = creature.get("species_data")

	if species_data == null:
		return false

	return not bool(species_data.get("is_predator"))


func count_eggs() -> int:
	var count := 0

	for egg in get_tree().get_nodes_in_group("eggs"):
		if not is_instance_valid(egg):
			continue

		if egg.is_queued_for_deletion():
			continue

		count += 1

	return count


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
