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

@onready var time_speed_option: OptionButton = $TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeedOption

# Time scale presets.
const TIME_SPEED_VALUES := [1.0, 2.0, 3.0]

var current_creature: Node = null

var hovered_creature: Node = null

var selected_creature: Node = null


func _ready() -> void:
	add_to_group("creature_stats_ui")
	panel.visible = false
	setup_time_speed_controls()


# Prefer selected creature over hover.
func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

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

	health_value_label.text = build_bar_value_text("health", "max_health")

	if current_creature.has_method("get_hunger_percent"):
		hunger_bar.value = current_creature.get_hunger_percent()
		hunger_value_label.text = build_bar_value_text("hunger", "max_hunger")
		return

	hunger_bar.value = 0.0
	hunger_value_label.text = "0 / 0"


func build_bar_value_text(current_property: String, max_property: String) -> String:
	if not is_instance_valid(current_creature):
		return "0 / 0"

	var current_value: float = float(current_creature.get(current_property))
	var max_value: float = float(current_creature.get(max_property))
	return "%d / %d" % [int(round(current_value)), int(round(max_value))]


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

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if not is_instance_valid(selected_creature):
		return

	clear_selected_creature()
