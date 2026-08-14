extends Node

signal egg_created(species_id: StringName, egg: Node2D)

# Player egg-purchase submenu. The UI spends player energy only after the
# player base successfully creates a real species egg near its footprint.
const PLAYER_SPECIES_CATALOG := preload("res://scripts/catalogs/player_species_catalog.gd")

const EGG_MENU_POSITION := Vector2(-2.0, 84.0)
const EGG_MENU_SIZE := Vector2(260.0, 245.0)
const EGG_MENU_BUTTON_SIZE := Vector2(126.0, 56.0)
const EGG_MENU_H_SEPARATION := 8
const EGG_MENU_V_SEPARATION := 7

var nature_ui: Node = null
var player_energy: Node = null
var nature_content: Control = null
var main_menu_grid: GridContainer = null
var egg_menu_button: Button = null
var egg_menu_grid: GridContainer = null
var egg_buttons: Dictionary = {}
var egg_button_by_species_id: Dictionary = {}


func _ready() -> void:
	add_to_group("player_egg_creation_ui")
	nature_ui = get_tree().get_first_node_in_group("player_nature_ui")
	player_energy = get_tree().get_first_node_in_group("player_energy")

	if (
		nature_ui == null
		or not nature_ui.has_method("get_menu_content_root")
		or not nature_ui.has_method("get_main_menu_grid")
		or not nature_ui.has_method("get_menu_button")
	):
		push_error("PlayerEggCreationUI: nature-menu API was not found.")
		return

	nature_content = nature_ui.call("get_menu_content_root") as Control
	main_menu_grid = nature_ui.call("get_main_menu_grid") as GridContainer
	egg_menu_button = nature_ui.call("get_menu_button", &"eggs") as Button

	if nature_content == null or main_menu_grid == null or egg_menu_button == null:
		push_error("PlayerEggCreationUI: required nature-menu controls were not found.")
		return

	_build_egg_menu()
	_refresh_localized_text()
	LocalizationManager.locale_changed.connect(_on_locale_changed)

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
	egg_menu_grid.position = EGG_MENU_POSITION
	egg_menu_grid.size = EGG_MENU_SIZE
	egg_menu_grid.columns = 2
	egg_menu_grid.add_theme_constant_override(
		"h_separation",
		EGG_MENU_H_SEPARATION
	)
	egg_menu_grid.add_theme_constant_override(
		"v_separation",
		EGG_MENU_V_SEPARATION
	)
	egg_menu_grid.visible = false
	nature_content.add_child(egg_menu_grid)

	for option: Dictionary in PLAYER_SPECIES_CATALOG.get_egg_entries():
		var species_data := option.get("species_data") as CreatureSpeciesData
		var species_name_key := String(option.get("species_name_key", ""))
		var energy_cost := float(option.get("egg_purchase_cost", 0.0))

		if species_data == null:
			continue

		var species_button := _duplicate_menu_button()
		species_button.name = "%sEggButton" % species_data.species_id.to_pascal_case()
		species_button.custom_minimum_size = EGG_MENU_BUTTON_SIZE
		species_button.set_meta(&"species_name_key", species_name_key)
		species_button.set_meta(&"energy_cost", energy_cost)
		_update_species_button_text(species_button)
		species_button.add_theme_font_size_override("font_size", 14)
		species_button.pressed.connect(
			_on_species_button_pressed.bind(species_data, energy_cost)
		)
		egg_menu_grid.add_child(species_button)
		egg_buttons[species_button] = energy_cost
		egg_button_by_species_id[species_data.species_id] = species_button

	var back_button := _duplicate_menu_button()
	back_button.name = "EggMenuBackButton"
	back_button.custom_minimum_size = EGG_MENU_BUTTON_SIZE
	back_button.text = tr("MENU_BACK")
	back_button.tooltip_text = tr("BACK_TOOLTIP")
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.pressed.connect(_on_back_button_pressed)
	egg_menu_grid.add_child(back_button)

	# Intentionally leave the lower-right grid cell empty. The old status label
	# was removed so the egg submenu contains buttons only.


func _duplicate_menu_button() -> Button:
	var duplicated_button := egg_menu_button.duplicate() as Button

	if duplicated_button == null:
		duplicated_button = Button.new()

	var decorative_icon := duplicated_button.get_node_or_null("IconTexture")
	if decorative_icon != null:
		decorative_icon.free()

	duplicated_button.toggle_mode = false
	duplicated_button.button_pressed = false
	duplicated_button.focus_mode = Control.FOCUS_NONE
	duplicated_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return duplicated_button


func get_species_button(species_id: StringName) -> Button:
	return egg_button_by_species_id.get(species_id) as Button


func return_to_main_menu() -> void:
	_on_back_button_pressed()


func _on_egg_menu_button_pressed() -> void:
	if nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")

	main_menu_grid.visible = false
	egg_menu_grid.visible = true
	_update_species_buttons()


func _on_back_button_pressed() -> void:
	egg_menu_grid.visible = false
	main_menu_grid.visible = true


func _on_species_button_pressed(
	species_data: CreatureSpeciesData,
	energy_cost: float
) -> void:
	if species_data == null:
		return

	if not _can_spend_energy(energy_cost):
		return

	var player_base := get_tree().get_first_node_in_group("player_base")

	if player_base == null or not player_base.has_method("create_player_egg"):
		return

	var created_egg := player_base.call(
		"create_player_egg",
		species_data
	) as Node2D

	if created_egg == null:
		return

	if player_energy == null or not bool(player_energy.call("spend", energy_cost)):
		created_egg.queue_free()
		return

	_update_species_buttons()
	egg_created.emit(species_data.species_id, created_egg)


func _can_spend_energy(energy_cost: float) -> bool:
	return (
		player_energy != null
		and bool(player_energy.call("can_spend", energy_cost))
	)


func _update_species_buttons() -> void:
	if nature_ui == null:
		return

	for button_variant in egg_buttons.keys():
		var button := button_variant as Button

		if button == null or not is_instance_valid(button):
			continue

		var energy_cost := float(egg_buttons.get(button, 0.0))
		button.disabled = not _can_spend_energy(energy_cost)


func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_text()


func _refresh_localized_text() -> void:
	if egg_menu_button != null:
		egg_menu_button.tooltip_text = tr("EGG_MENU_TOOLTIP")

	for button_variant: Variant in egg_buttons.keys():
		var button := button_variant as Button
		if button != null and is_instance_valid(button):
			_update_species_button_text(button)

	if egg_menu_grid != null:
		var back_button := egg_menu_grid.get_node_or_null(
			"EggMenuBackButton"
		) as Button
		if back_button != null:
			back_button.text = tr("MENU_BACK")
			back_button.tooltip_text = tr("BACK_TOOLTIP")


func _update_species_button_text(button: Button) -> void:
	var species_name_key := String(
		button.get_meta(&"species_name_key", "")
	)
	var energy_cost := float(button.get_meta(&"energy_cost", 0.0))
	var species_name := (
		tr(species_name_key)
		if not species_name_key.is_empty()
		else "?"
	)
	button.text = "%s\n%s" % [
		species_name,
		tr("EGG_ENERGY_COST") % floori(energy_cost)
	]
	button.tooltip_text = tr("EGG_CREATE_TOOLTIP") % species_name
