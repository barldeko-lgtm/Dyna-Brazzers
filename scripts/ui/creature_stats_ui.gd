extends CanvasLayer

# Debug creature HUD.
@onready var panel: PanelContainer = $CreatureStatsPanel

@onready var title_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/TitleLabel

@onready var age_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/AgeLabel

@onready var hunger_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerLabel

@onready var health_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthLabel

@onready var health_bar: ProgressBar = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthBar

@onready var health_value_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthBar/HealthValueLabel

@onready var hunger_bar: ProgressBar = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerBar

@onready var hunger_value_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerBar/HungerValueLabel

@onready var fps_label: Label = $FpsLabel

@onready var lightning_button: Button = $LightningPanel/MarginContainer/LightningButton

@onready var time_speed_option: OptionButton = $TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeedOption

# Time scale presets.
const TIME_SPEED_VALUES := [1.0, 2.0, 3.0]

var current_creature: Node = null

var hovered_creature: Node = null

var selected_creature: Node = null

var lightning_targeting_enabled := false


func _ready() -> void:
	add_to_group("creature_stats_ui")
	panel.visible = false
	setup_lightning_button()
	setup_time_speed_controls()


# Prefer selected creature over hover.
func _process(_delta: float) -> void:
	fps_label.text = build_debug_status_text()

	if not is_instance_valid(selected_creature):
		selected_creature = null

	if not is_instance_valid(hovered_creature):
		hovered_creature = null

	if is_instance_valid(selected_creature):
		current_creature = selected_creature
		panel.visible = true
		update_stats_text()
		return

	if is_instance_valid(hovered_creature):
		current_creature = hovered_creature
		panel.visible = true
		update_stats_text()
		return

	hide_creature_stats()



func build_debug_status_text() -> String:
	var world_grid := get_tree().get_first_node_in_group("world_grid")
	var mouse_screen := get_viewport().get_mouse_position()
	var mouse_world := get_mouse_world_position(mouse_screen)
	var mouse_tile_text := "?"
	var grass_count := 0
	var creature_count := 0

	if world_grid != null:
		grass_count = world_grid.grass_by_tile.size()
		creature_count = world_grid.creature_anchors.size()
		mouse_tile_text = format_tile(world_grid.world_to_map_tile(mouse_world))

	var elapsed_text := format_elapsed_time(PerformanceStats.get_elapsed_seconds())
	var memory_mb := PerformanceStats.get_static_memory_mb()

	var lines: Array[String] = []
	lines.append("FPS: %d | Time: %s | Mem: %.1f MB" % [Engine.get_frames_per_second(), elapsed_text, memory_mb])
	lines.append("Mouse: W%s | Tile: %s" % [format_vector2(mouse_world), mouse_tile_text])
	lines.append("World: creatures %d | grass %d | nodes %d | objects %d" % [creature_count, grass_count, PerformanceStats.get_node_count(), PerformanceStats.get_object_count()])
	lines.append("Grass/s: spread %d | checks %d | spawned %d" % [PerformanceStats.get_rate("grass_spread_events"), PerformanceStats.get_rate("grass_neighbor_checks"), PerformanceStats.get_rate("grass_spawned")])
	lines.append("Graze/s: searches %d | candidate tiles %d | footprint checks %d" % [PerformanceStats.get_rate("grazing_searches"), PerformanceStats.get_rate("grazing_candidate_checks"), PerformanceStats.get_rate("grazing_footprint_queries")])
	lines.append("Creature/s: physics %d | predator searches %d | candidates %d" % [PerformanceStats.get_rate("creature_physics_ticks"), PerformanceStats.get_rate("predator_prey_searches"), PerformanceStats.get_rate("predator_prey_candidates")])
	lines.append("Path/s: calls %d | expanded %d | success %d | failed %d" % [PerformanceStats.get_rate("path_calls"), PerformanceStats.get_rate("path_expanded_tiles"), PerformanceStats.get_rate("path_success"), PerformanceStats.get_rate("path_failed")])
	lines.append(PerformanceStats.get_csv_status_text())
	return "\n".join(lines)


func get_mouse_world_position(mouse_screen: Vector2) -> Vector2:
	var camera := get_node_or_null("../Camera2D") as Camera2D

	if camera == null:
		return mouse_screen

	var viewport_size := get_viewport().get_visible_rect().size
	return camera.get_screen_center_position() + (mouse_screen - viewport_size * 0.5) / camera.zoom


func format_vector2(value: Vector2) -> String:
	return "(%d, %d)" % [int(round(value.x)), int(round(value.y))]


func format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]


func format_elapsed_time(total_seconds: float) -> String:
	var seconds := int(total_seconds)
	var hours := int(seconds / 3600)
	var minutes := int((seconds % 3600) / 60)
	var remaining_seconds := seconds % 60

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]

	return "%02d:%02d" % [minutes, remaining_seconds]


func show_creature_stats(creature: Node) -> void:
	if creature == null:
		return

	hovered_creature = creature

	if is_instance_valid(selected_creature):
		return

	current_creature = creature
	panel.visible = true
	update_stats_text()


func hide_creature_stats() -> void:
	hovered_creature = null

	if is_instance_valid(selected_creature):
		return

	current_creature = null
	panel.visible = false


# UI refresh.
func update_stats_text() -> void:
	if not is_instance_valid(current_creature):
		return

	if current_creature.has_method("get_creature_name"):
		title_label.text = current_creature.get_creature_name()
	else:
		title_label.text = "Существо"

	if current_creature.has_method("get_age"):
		age_label.text = "Возраст: %d" % int(current_creature.get_age())
	else:
		age_label.text = "Возраст: ?"

	health_label.text = "Здоровье"
	hunger_label.text = "Сытость"

	if current_creature.has_method("get_health_percent"):
		health_bar.value = current_creature.get_health_percent()
	else:
		health_bar.value = 0.0

	health_value_label.text = build_bar_value_text("health", "get_max_health")

	if current_creature.has_method("get_hunger_percent"):
		hunger_bar.value = current_creature.get_hunger_percent()
		hunger_value_label.text = build_bar_value_text("hunger", "get_max_hunger")
		return

	hunger_bar.value = 0.0
	hunger_value_label.text = "0 / 0"


func build_bar_value_text(current_property: String, max_getter: String) -> String:
	if not is_instance_valid(current_creature):
		return "0 / 0"

	var current_value: float = float(current_creature.get(current_property))
	var max_value := 0.0

	if current_creature.has_method(max_getter):
		max_value = float(current_creature.call(max_getter))
	else:
		var species_data: Resource = current_creature.get("species_data")
		if species_data != null:
			var fallback_property := max_getter.replace("get_", "")
			max_value = float(species_data.get(fallback_property))

	return "%d / %d" % [int(round(current_value)), int(round(max_value))]


func setup_lightning_button() -> void:
	lightning_button.toggle_mode = true
	lightning_button.text = "Молния"
	lightning_button.button_pressed = false

	if not lightning_button.toggled.is_connected(_on_lightning_button_toggled):
		lightning_button.toggled.connect(_on_lightning_button_toggled)


func _on_lightning_button_toggled(toggled_on: bool) -> void:
	lightning_targeting_enabled = toggled_on


func is_lightning_targeting_enabled() -> bool:
	return lightning_targeting_enabled


func try_apply_lightning_to_creature(creature: Node) -> bool:
	if not lightning_targeting_enabled:
		return false

	if creature == null or not is_instance_valid(creature):
		return false

	if creature.has_method("take_direct_damage"):
		creature.take_direct_damage(50.0)
		cancel_lightning_targeting()
		return true

	return false


func cancel_lightning_targeting() -> void:
	lightning_targeting_enabled = false

	if lightning_button.button_pressed:
		lightning_button.set_pressed_no_signal(false)


func toggle_creature_selection(creature: Node) -> void:
	if creature == null:
		return

	if selected_creature == creature:
		clear_selected_creature()
		return

	selected_creature = creature
	current_creature = creature
	panel.visible = true
	update_stats_text()


func clear_selected_creature() -> void:
	selected_creature = null

	if is_instance_valid(hovered_creature):
		current_creature = hovered_creature
		panel.visible = true
		update_stats_text()
		return

	current_creature = null
	panel.visible = false


# Time controls.
func setup_time_speed_controls() -> void:
	time_speed_option.clear()

	for index in range(TIME_SPEED_VALUES.size()):
		var speed_value: float = TIME_SPEED_VALUES[index]
		time_speed_option.add_item("x%d" % int(speed_value), index)

	var selected_index := 0

	for index in range(TIME_SPEED_VALUES.size()):
		if is_equal_approx(Engine.time_scale, TIME_SPEED_VALUES[index]):
			selected_index = index
			break

	time_speed_option.select(selected_index)
	apply_time_speed_by_index(selected_index)

	if not time_speed_option.item_selected.is_connected(_on_time_speed_option_item_selected):
		time_speed_option.item_selected.connect(_on_time_speed_option_item_selected)


func apply_time_speed_by_index(index: int) -> void:
	if index < 0 or index >= TIME_SPEED_VALUES.size():
		return

	Engine.time_scale = TIME_SPEED_VALUES[index]


func _on_time_speed_option_item_selected(index: int) -> void:
	apply_time_speed_by_index(index)


# Clear selection on empty click.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	if lightning_targeting_enabled and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_lightning_targeting()
		return

	if lightning_targeting_enabled:
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if not is_instance_valid(selected_creature):
		return

	clear_selected_creature()
