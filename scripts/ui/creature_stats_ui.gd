extends PanelContainer

# Creature info window + creature selection.
# Keep this script focused on the selected/hovered creature panel only.

const HEALTH_ICON_TEXTURE := preload("res://assets/ui/creature_health_icon.svg")
const HUNGER_ICON_TEXTURE := preload("res://assets/ui/creature_hunger_icon.svg")

@onready var panel: PanelContainer = self
@onready var stats_vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var age_label: Label = $MarginContainer/VBoxContainer/AgeLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel
@onready var hunger_label: Label = $MarginContainer/VBoxContainer/HungerLabel
@onready var legacy_health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var legacy_health_value_label: Label = $MarginContainer/VBoxContainer/HealthBar/HealthValueLabel
@onready var legacy_hunger_bar: ProgressBar = $MarginContainer/VBoxContainer/HungerBar
@onready var legacy_hunger_value_label: Label = $MarginContainer/VBoxContainer/HungerBar/HungerValueLabel

var health_bar: ProgressBar
var health_percent_label: Label
var hunger_bar: ProgressBar
var hunger_percent_label: Label

var current_creature: Node = null
var hovered_creature: Node = null
var selected_creature: Node = null

var last_hover_highlighted: Node = null
var last_selected_highlighted: Node = null


func _ready() -> void:
	add_to_group("creature_stats_ui")
	configure_compact_stats_layout()
	panel.visible = false


func configure_compact_stats_layout() -> void:
	title_label.visible = false
	health_label.visible = false
	hunger_label.visible = false
	legacy_health_bar.visible = false
	legacy_hunger_bar.visible = false
	legacy_health_value_label.visible = false
	legacy_hunger_value_label.visible = false

	stats_vbox.add_theme_constant_override("separation", 7)
	panel.custom_minimum_size = Vector2(268.0, 0.0)
	panel.size = Vector2(268.0, 122.0)
	apply_panel_style()

	age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	age_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88, 1.0))
	age_label.add_theme_font_size_override("font_size", 13)

	var health_row_data := create_stat_row(HEALTH_ICON_TEXTURE, legacy_health_bar)
	var health_row := health_row_data["row"] as HBoxContainer
	health_bar = health_row_data["bar"] as ProgressBar
	health_percent_label = health_row_data["label"] as Label

	var hunger_row_data := create_stat_row(HUNGER_ICON_TEXTURE, legacy_hunger_bar)
	var hunger_row := hunger_row_data["row"] as HBoxContainer
	hunger_bar = hunger_row_data["bar"] as ProgressBar
	hunger_percent_label = hunger_row_data["label"] as Label

	stats_vbox.move_child(health_row, 0)
	stats_vbox.move_child(hunger_row, 1)
	stats_vbox.move_child(age_label, 2)


func create_stat_row(icon_texture: Texture2D, template_bar: ProgressBar) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 30.0)
	row.add_theme_constant_override("separation", 8)
	stats_vbox.add_child(row)

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(28.0, 28.0)
	icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_theme_stylebox_override("panel", create_icon_frame_style())
	row.add_child(icon_frame)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(20.0, 20.0)
	icon.texture = icon_texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(icon)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(134.0, 18.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy_bar_style(template_bar, bar)
	row.add_child(bar)

	var percent_label := Label.new()
	percent_label.custom_minimum_size = Vector2(52.0, 18.0)
	percent_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	percent_label.text = "100%"
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	percent_label.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0, 1.0))
	percent_label.add_theme_font_size_override("font_size", 14)
	percent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(percent_label)

	return {"row": row, "bar": bar, "label": percent_label}


func apply_panel_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.045, 0.075, 0.94)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.22, 0.32, 0.46, 0.95)
	panel_style.corner_radius_top_left = 9
	panel_style.corner_radius_top_right = 9
	panel_style.corner_radius_bottom_right = 9
	panel_style.corner_radius_bottom_left = 9
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	panel_style.shadow_size = 6
	panel_style.shadow_offset = Vector2(2.0, 3.0)
	panel.add_theme_stylebox_override("panel", panel_style)


func create_icon_frame_style() -> StyleBoxFlat:
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.075, 0.095, 0.135, 0.98)
	icon_style.border_width_left = 1
	icon_style.border_width_top = 1
	icon_style.border_width_right = 1
	icon_style.border_width_bottom = 1
	icon_style.border_color = Color(0.25, 0.34, 0.46, 0.9)
	icon_style.corner_radius_top_left = 14
	icon_style.corner_radius_top_right = 14
	icon_style.corner_radius_bottom_right = 14
	icon_style.corner_radius_bottom_left = 14
	icon_style.content_margin_left = 4.0
	icon_style.content_margin_top = 4.0
	icon_style.content_margin_right = 4.0
	icon_style.content_margin_bottom = 4.0
	return icon_style


func copy_bar_style(source_bar: ProgressBar, target_bar: ProgressBar) -> void:
	var background_style := source_bar.get_theme_stylebox("background")
	if background_style != null:
		target_bar.add_theme_stylebox_override("background", background_style.duplicate())

	var fill_style := source_bar.get_theme_stylebox("fill")
	if fill_style != null:
		target_bar.add_theme_stylebox_override("fill", fill_style.duplicate())


# Prefer selected creature over hover.
func _process(_delta: float) -> void:
	if not is_instance_valid(selected_creature):
		selected_creature = null

	if not is_instance_valid(hovered_creature):
		hovered_creature = null

	sync_creature_highlights()

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
	sync_creature_highlights()

	if is_instance_valid(selected_creature):
		return

	current_creature = creature
	panel.visible = true
	update_stats_text()


func hide_creature_stats() -> void:
	hovered_creature = null
	sync_creature_highlights()

	if is_instance_valid(selected_creature):
		return

	current_creature = null
	panel.visible = false


func sync_creature_highlights() -> void:
	var desired_selected: Node = selected_creature if is_instance_valid(selected_creature) else null
	var desired_hover: Node = hovered_creature if is_instance_valid(hovered_creature) else null

	if desired_hover == desired_selected:
		desired_hover = null

	if last_hover_highlighted != desired_hover:
		apply_highlight_flag(last_hover_highlighted, "set_hover_highlighted", false)
		last_hover_highlighted = desired_hover
		apply_highlight_flag(last_hover_highlighted, "set_hover_highlighted", true)

	if last_selected_highlighted != desired_selected:
		apply_highlight_flag(last_selected_highlighted, "set_selected_highlighted", false)
		last_selected_highlighted = desired_selected
		apply_highlight_flag(last_selected_highlighted, "set_selected_highlighted", true)


func apply_highlight_flag(creature: Node, method_name: String, enabled: bool) -> void:
	if not is_instance_valid(creature):
		return

	if creature.has_method(method_name):
		creature.call(method_name, enabled)


func update_stats_text() -> void:
	if not is_instance_valid(current_creature):
		return

	if current_creature.has_method("get_age"):
		age_label.text = "Возраст: %d" % int(current_creature.get_age())
	else:
		age_label.text = "Возраст: ?"

	var health_percent := 0.0
	if current_creature.has_method("get_health_percent"):
		health_percent = float(current_creature.get_health_percent())

	health_bar.value = health_percent
	health_percent_label.text = "%d%%" % int(round(health_percent))

	var hunger_percent := 0.0
	if current_creature.has_method("get_hunger_percent"):
		hunger_percent = float(current_creature.get_hunger_percent())

	hunger_bar.value = hunger_percent
	hunger_percent_label.text = "%d%%" % int(round(hunger_percent))


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
	sync_creature_highlights()
	current_creature = creature
	panel.visible = true
	update_stats_text()


func clear_selected_creature() -> void:
	selected_creature = null
	sync_creature_highlights()

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
