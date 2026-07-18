extends Node

# Player egg-purchase submenu. The UI spends player energy only after the
# player base successfully creates a real species egg near its footprint.

const EGG_OPTIONS := [
	{
		"species": preload("res://data/species/stegosaurus.tres"),
		"cost": 350.0
	},
	{
		"species": preload("res://data/species/triceratops.tres"),
		"cost": 450.0
	},
	{
		"species": preload("res://data/species/egg_eater.tres"),
		"cost": 1200.0
	},
	{
		"species": preload("res://data/species/raptor.tres"),
		"cost": 1000.0
	},
	{
		"species": preload("res://data/species/pterodactyl.tres"),
		"cost": 1000.0
	},
	{
		"species": preload("res://data/species/tyrannosaurus.tres"),
		"cost": 1300.0
	}
]

const NATURE_PANEL_PATH := "MarginContainer/VBoxContainer/PlayerNaturePanel"
const NATURE_CONTENT_PATH := NATURE_PANEL_PATH + "/MarginContainer/VBoxContainer"
const MAIN_MENU_GRID_PATH := NATURE_CONTENT_PATH + "/MainMenuGrid"
const EGG_MENU_BUTTON_PATH := MAIN_MENU_GRID_PATH + "/MainPlaceholder1"

var player_side_panel: Control = null
var nature_ui: Node = null
var player_energy: Node = null
var nature_content: Control = null
var main_menu_grid: GridContainer = null
var egg_menu_button: Button = null
var egg_menu_grid: GridContainer = null
var status_label: Label = null
var egg_buttons: Dictionary = {}


func _ready() -> void:
	player_side_panel = get_parent() as Control

	if player_side_panel == null:
		push_error("PlayerEggCreationUI: player side panel was not found.")
		return

	nature_ui = player_side_panel.get_node_or_null(NATURE_PANEL_PATH)
	player_energy = get_tree().get_first_node_in_group("player_energy")
	nature_content = player_side_panel.get_node_or_null(NATURE_CONTENT_PATH) as Control
	main_menu_grid = player_side_panel.get_node_or_null(MAIN_MENU_GRID_PATH) as GridContainer
	egg_menu_button = player_side_panel.get_node_or_null(EGG_MENU_BUTTON_PATH) as Button

	if (
		nature_ui == null
		or nature_content == null
		or main_menu_grid == null
		or egg_menu_button == null
	):
		push_error("PlayerEggCreationUI: required player UI nodes were not found.")
		return

	_build_egg_menu()
	egg_menu_button.tooltip_text = "Создание яиц"

	if not egg_menu_button.pressed.is_connected(_on_egg_menu_button_pressed):
		egg_menu_button.pressed.connect(_on_egg_menu_button_pressed)

	set_process(true)
	_update_species_buttons()


func _process(_delta: float) -> void:
	if player_energy == null:
		player_energy = get_tree().get_first_node_in_group("player_energy")

	_update_species_buttons()


func _build_egg_menu() -> void:
	if egg_menu_grid != null and is_instance_valid(egg_menu_grid):
		return

	egg_menu_grid = GridContainer.new()
	egg_menu_grid.name = "EggCreationMenu"
	egg_menu_grid.position = Vector2(0.0, 66.0)
	egg_menu_grid.size = Vector2(260.0, 218.0)
	egg_menu_grid.columns = 2
	egg_menu_grid.add_theme_constant_override("h_separation", 8)
	egg_menu_grid.add_theme_constant_override("v_separation", 8)
	egg_menu_grid.visible = false
	nature_content.add_child(egg_menu_grid)

	for option: Dictionary in EGG_OPTIONS:
		var species_data := option.get("species") as CreatureSpeciesData
		var energy_cost := float(option.get("cost", 0.0))

		if species_data == null:
			continue

		var species_button := _duplicate_menu_button()
		species_button.name = "%sEggButton" % species_data.species_id.to_pascal_case()
		species_button.custom_minimum_size = Vector2(126.0, 46.0)
		species_button.text = "%s\n%d энки" % [species_data.species_name, floori(energy_cost)]
		species_button.tooltip_text = "Создать яйцо: %s" % species_data.species_name
		species_button.add_theme_font_size_override("font_size", 14)
		species_button.pressed.connect(_on_species_button_pressed.bind(species_data, energy_cost))
		egg_menu_grid.add_child(species_button)
		egg_buttons[species_button] = energy_cost

	var back_button := _duplicate_menu_button()
	back_button.name = "EggMenuBackButton"
	back_button.custom_minimum_size = Vector2(126.0, 46.0)
	back_button.text = "← Назад"
	back_button.tooltip_text = "Вернуться в основное меню"
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(_on_back_button_pressed)
	egg_menu_grid.add_child(back_button)

	status_label = Label.new()
	status_label.name = "EggCreationStatusLabel"
	status_label.custom_minimum_size = Vector2(126.0, 46.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.text = "Выберите вид"
	egg_menu_grid.add_child(status_label)


func _duplicate_menu_button() -> Button:
	var duplicated_button := egg_menu_button.duplicate() as Button

	if duplicated_button == null:
		duplicated_button = Button.new()

	duplicated_button.toggle_mode = false
	duplicated_button.button_pressed = false
	duplicated_button.focus_mode = Control.FOCUS_NONE
	duplicated_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return duplicated_button


func _on_egg_menu_button_pressed() -> void:
	if nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")

	main_menu_grid.visible = false
	egg_menu_grid.visible = true
	_set_status("Выберите вид")
	_update_species_buttons()


func _on_back_button_pressed() -> void:
	egg_menu_grid.visible = false
	main_menu_grid.visible = true


func _on_species_button_pressed(species_data: CreatureSpeciesData, energy_cost: float) -> void:
	if species_data == null:
		return

	if not _can_spend_energy(energy_cost):
		_set_status("Не хватает энки")
		return

	var player_base := get_tree().get_first_node_in_group("player_base")

	if player_base == null or not player_base.has_method("create_player_egg"):
		_set_status("База не найдена")
		return

	var created_egg := player_base.call("create_player_egg", species_data) as Node2D

	if created_egg == null:
		_set_status("Нет места у базы")
		return

	if player_energy == null or not bool(player_energy.call("spend", energy_cost)):
		created_egg.queue_free()
		_set_status("Не хватает энки")
		return

	_set_status("Создано: %s" % species_data.species_name)
	_update_species_buttons()


func _can_spend_energy(energy_cost: float) -> bool:
	return player_energy != null and bool(player_energy.call("can_spend", energy_cost))


func _update_species_buttons() -> void:
	if nature_ui == null:
		return

	for button_variant in egg_buttons.keys():
		var button := button_variant as Button

		if button == null or not is_instance_valid(button):
			continue

		var energy_cost := float(egg_buttons.get(button, 0.0))
		button.disabled = not _can_spend_energy(energy_cost)


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
