extends PanelContainer

# Player side-panel UI:
# - entity counters
# - time speed controls
#
# Keep this separate from creature_stats_ui.gd so the creature info window does
# not own unrelated player HUD logic.

const TIME_SPEED_VALUES := [1.0, 2.0, 3.0, 5.0]
const ENTITY_COUNTS_REFRESH_INTERVAL := 0.5

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


func _ready() -> void:
	add_to_group("player_ui")
	setup_time_speed_controls()
	update_entity_counts_text()
	entity_counts_refresh_timer = ENTITY_COUNTS_REFRESH_INTERVAL


func _process(delta: float) -> void:
	entity_counts_refresh_timer -= delta

	if entity_counts_refresh_timer <= 0.0:
		entity_counts_refresh_timer = ENTITY_COUNTS_REFRESH_INTERVAL
		update_entity_counts_text()


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
