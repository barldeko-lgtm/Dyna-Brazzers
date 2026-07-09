extends CanvasLayer

# Creature info window + creature selection.
# Keep this script focused on the selected/hovered creature panel only.

@onready var panel: PanelContainer = $CreatureStatsPanel
@onready var title_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var age_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/AgeLabel
@onready var hunger_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerLabel
@onready var health_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthLabel
@onready var health_bar: ProgressBar = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthBar
@onready var health_value_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HealthBar/HealthValueLabel
@onready var hunger_bar: ProgressBar = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerBar
@onready var hunger_value_label: Label = $CreatureStatsPanel/MarginContainer/VBoxContainer/HungerBar/HungerValueLabel

var current_creature: Node = null
var hovered_creature: Node = null
var selected_creature: Node = null


func _ready() -> void:
	add_to_group("creature_stats_ui")
	panel.visible = false


# Prefer selected creature over hover.
func _process(_delta: float) -> void:
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


# Compatibility hook for creature click input.
func try_apply_lightning_to_creature(creature: Node) -> bool:
	var player_nature_ui := get_tree().get_first_node_in_group("player_nature_ui")

	if player_nature_ui == null or not player_nature_ui.has_method("try_apply_lightning_to_creature"):
		return false

	return bool(player_nature_ui.try_apply_lightning_to_creature(creature))


func is_player_nature_targeting_enabled() -> bool:
	var player_nature_ui := get_tree().get_first_node_in_group("player_nature_ui")

	if player_nature_ui == null or not player_nature_ui.has_method("is_targeting_enabled"):
		return false

	return bool(player_nature_ui.is_targeting_enabled())


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


# Clear selection on empty click.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	if is_player_nature_targeting_enabled():
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if not is_instance_valid(selected_creature):
		return

	clear_selected_creature()
