extends RefCounted

# Owns all flag-menu presentation and mouse targeting. The gameplay system
# remains the source of truth for placed flags and validates every requested
# placement/removal through its public facade methods.

var owner: Node
var nature_ui: Node = null
var nature_content: Control = null
var main_menu_grid: GridContainer = null
var flag_menu_button: Button = null
var flag_menu_grid: GridContainer = null
var status_label: Label = null
var current_status_key := ""
var current_status_value := -1

var targeting_species_id := StringName()
var removal_targeting_enabled := false
var species_buttons: Dictionary = {}
var preview_tile_override_enabled := false
var preview_tile_override := Vector2i.ZERO


func _init(owner_system: Node) -> void:
	owner = owner_system


func attach(
	found_nature_ui: Node,
	found_content: Control,
	found_main_grid: GridContainer,
	found_flag_button: Button,
	menu_entries: Array[Dictionary]
) -> void:
	detach()
	nature_ui = found_nature_ui
	nature_content = found_content
	main_menu_grid = found_main_grid
	flag_menu_button = found_flag_button
	_build_flag_menu(menu_entries)

	if flag_menu_button != null:
		flag_menu_button.tooltip_text = tr("FLAG_MENU_TOOLTIP")

		if not flag_menu_button.pressed.is_connected(_on_flag_menu_button_pressed):
			flag_menu_button.pressed.connect(_on_flag_menu_button_pressed)

	var locale_callable := Callable(self, "_on_locale_changed")
	if not LocalizationManager.locale_changed.is_connected(locale_callable):
		LocalizationManager.locale_changed.connect(locale_callable)


func detach() -> void:
	cancel_targeting()
	var locale_callable := Callable(self, "_on_locale_changed")
	if LocalizationManager.locale_changed.is_connected(locale_callable):
		LocalizationManager.locale_changed.disconnect(locale_callable)
	nature_ui = null
	nature_content = null
	main_menu_grid = null
	flag_menu_button = null
	flag_menu_grid = null
	status_label = null
	species_buttons.clear()


func handle_unhandled_input(event: InputEvent) -> bool:
	if not is_targeting() or not (event is InputEventMouseButton):
		return false

	return _handle_targeting_mouse(event as InputEventMouseButton)


func handle_game_subviewport_input(event: InputEvent) -> bool:
	if not is_targeting():
		return false
	if not (event is InputEventMouseMotion) and not (event is InputEventMouseButton):
		return false
	var world_grid: Node = owner.call("get_world_grid")
	var camera := owner.get_tree().get_first_node_in_group("game_camera") as Camera2D
	if world_grid == null or camera == null or not camera.has_method("game_screen_to_world"):
		return false
	var world_position: Vector2 = camera.call("game_screen_to_world", event.position)
	var target_tile: Vector2i = world_grid.call("world_to_map_tile", world_position)
	preview_tile_override = target_tile
	preview_tile_override_enabled = true
	if event is InputEventMouseMotion:
		update_targeting_preview()
		return false
	return _handle_targeting_mouse_at_tile(event as InputEventMouseButton, target_tile)


func update_targeting_preview() -> void:
	if not is_targeting():
		return

	var world_grid: Node = owner.call("get_world_grid")

	if world_grid == null or not is_instance_valid(world_grid):
		return

	if removal_targeting_enabled:
		_hide_preview()
		return

	owner.call("ensure_flag_visual")
	var flag_visual := owner.call("get_flag_visual") as Node2D

	if flag_visual == null or not is_instance_valid(flag_visual):
		return

	var target_tile := preview_tile_override
	if not preview_tile_override_enabled:
		target_tile = world_grid.call(
			"world_to_map_tile",
			owner.call("get_flag_mouse_world_position")
		)
	var is_valid := bool(owner.call("is_valid_flag_tile", target_tile))

	if flag_visual.has_method("set_preview"):
		flag_visual.call("set_preview", target_tile, is_valid, targeting_species_id)


func cancel_targeting() -> void:
	targeting_species_id = StringName()
	removal_targeting_enabled = false
	preview_tile_override_enabled = false
	_hide_preview()


func is_targeting() -> bool:
	return targeting_species_id != StringName() or removal_targeting_enabled


func get_species_button(species_id: StringName) -> Button:
	return species_buttons.get(species_id) as Button


func refresh_status() -> void:
	if int(owner.call("get_flag_count")) <= 0:
		_set_status_key("FLAG_NONE")
		return

	_set_status_key("FLAG_COUNT", int(owner.call("get_flag_count")))


func _build_flag_menu(menu_entries: Array[Dictionary]) -> void:
	if nature_content == null or flag_menu_button == null:
		return

	flag_menu_grid = GridContainer.new()
	flag_menu_grid.name = "SpeciesFlagMenu"
	flag_menu_grid.position = Vector2(-2.0, 84.0)
	flag_menu_grid.size = Vector2(260.0, 245.0)
	flag_menu_grid.columns = 2
	flag_menu_grid.add_theme_constant_override("h_separation", 8)
	flag_menu_grid.add_theme_constant_override("v_separation", 7)
	flag_menu_grid.visible = false
	nature_content.add_child(flag_menu_grid)
	species_buttons.clear()

	for entry: Dictionary in menu_entries:
		var species_id := StringName(String(entry.get("species_id", "")))

		if species_id == StringName():
			continue

		var species_button := _duplicate_menu_button()
		species_button.name = "%sFlagButton" % String(species_id).capitalize()
		species_button.custom_minimum_size = Vector2(126.0, 56.0)
		var species_name_key := "SPECIES_%s" % String(species_id).to_upper()
		var tooltip_key := String(entry.get("tooltip_key", "FLAG_DEFAULT_TOOLTIP"))
		species_button.set_meta(&"translation_key", species_name_key)
		species_button.set_meta(&"tooltip_translation_key", tooltip_key)
		species_button.text = tr(species_name_key)
		species_button.tooltip_text = tr(tooltip_key)
		species_button.add_theme_font_size_override("font_size", 14)
		species_button.pressed.connect(_on_species_flag_pressed.bind(species_id))
		flag_menu_grid.add_child(species_button)
		species_buttons[species_id] = species_button

	# Fourth row matches the egg menu: Back on the left, remove flag on the right.
	var back_button := _duplicate_menu_button()
	back_button.name = "FlagMenuBackButton"
	back_button.custom_minimum_size = Vector2(126.0, 56.0)
	back_button.set_meta(&"translation_key", "BACK_ARROW")
	back_button.set_meta(&"tooltip_translation_key", "BACK_TOOLTIP")
	back_button.text = tr("BACK_ARROW")
	back_button.tooltip_text = tr("BACK_TOOLTIP")
	back_button.add_theme_font_size_override("font_size", 14)
	back_button.pressed.connect(_on_back_button_pressed)
	flag_menu_grid.add_child(back_button)

	var remove_button := _duplicate_menu_button()
	remove_button.name = "RemoveSpeciesFlagButton"
	remove_button.custom_minimum_size = Vector2(126.0, 56.0)
	remove_button.set_meta(&"translation_key", "FLAG_REMOVE_BUTTON")
	remove_button.set_meta(&"tooltip_translation_key", "FLAG_REMOVE_TOOLTIP")
	remove_button.text = tr("FLAG_REMOVE_BUTTON")
	remove_button.tooltip_text = tr("FLAG_REMOVE_TOOLTIP")
	remove_button.add_theme_font_size_override("font_size", 12)
	remove_button.pressed.connect(_on_remove_flag_pressed)
	flag_menu_grid.add_child(remove_button)

	# Status is still tracked internally for targeting logic/tutorial flow, but
	# no standalone status label is shown in the compact HUD menu.
	status_label = null
	refresh_status()


func _duplicate_menu_button() -> Button:
	var duplicated_button := flag_menu_button.duplicate() as Button

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


func _on_flag_menu_button_pressed() -> void:
	_cancel_other_nature_targeting()
	_refresh_localized_text()

	if main_menu_grid != null:
		main_menu_grid.visible = false

	if flag_menu_grid != null:
		flag_menu_grid.visible = true

	refresh_status()


func _on_species_flag_pressed(species_id: StringName) -> void:
	var world_grid: Node = owner.call("get_world_grid")

	if world_grid == null or not is_instance_valid(world_grid):
		_set_status_key("FLAG_WORLD_NOT_FOUND")
		return

	_cancel_other_nature_targeting()
	removal_targeting_enabled = false
	targeting_species_id = species_id
	_set_status_key("FLAG_PLACE_HINT")
	update_targeting_preview()
	owner.call("notify_flag_targeting_started", species_id)


func _on_remove_flag_pressed() -> void:
	cancel_targeting()
	removal_targeting_enabled = true
	_set_status_key("FLAG_REMOVE_HINT")


func _on_back_button_pressed() -> void:
	cancel_targeting()

	if flag_menu_grid != null:
		flag_menu_grid.visible = false

	if main_menu_grid != null:
		main_menu_grid.visible = true


func _handle_targeting_mouse(mouse_event: InputEventMouseButton) -> bool:
	if not mouse_event.pressed:
		return false

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		return _cancel_targeting_from_mouse()

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false

	return _apply_left_click_targeting()


func _handle_targeting_mouse_at_tile(mouse_event: InputEventMouseButton, target_tile: Vector2i) -> bool:
	if not mouse_event.pressed:
		return false
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		return _cancel_targeting_from_mouse()
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	return _apply_left_click_targeting_at_tile(target_tile)


func _cancel_targeting_from_mouse() -> bool:
	cancel_targeting()
	_set_status_key("FLAG_CANCELLED")
	return true


func _apply_left_click_targeting() -> bool:
	var world_grid: Node = owner.call("get_world_grid")

	if world_grid == null or not is_instance_valid(world_grid):
		return false

	var target_tile: Vector2i = world_grid.call(
		"world_to_map_tile",
		owner.call("get_flag_mouse_world_position")
	)

	return _apply_left_click_targeting_at_tile(target_tile)


func _apply_left_click_targeting_at_tile(target_tile: Vector2i) -> bool:
	if removal_targeting_enabled:
		return _try_remove_flag_at(target_tile)
	return _try_place_flag_at(target_tile)


func _try_remove_flag_at(target_tile: Vector2i) -> bool:
	var species_id := StringName(owner.call("get_species_flag_at_tile", target_tile))

	if species_id == StringName():
		_set_status_key("FLAG_CENTER_REQUIRED")
		return false

	owner.call("remove_flag", species_id)
	cancel_targeting()
	_set_status_key("FLAG_REMOVED")
	return true


func _try_place_flag_at(target_tile: Vector2i) -> bool:
	if not bool(owner.call("is_valid_flag_tile", target_tile)):
		_set_status_key("FLAG_FREE_TILE_REQUIRED")
		return false

	var placed_species_id := targeting_species_id
	owner.call("set_flag", placed_species_id, target_tile)
	owner.call("notify_flag_placed", placed_species_id, target_tile)
	cancel_targeting()
	_set_status_key("FLAG_PLACED")
	return true


func _cancel_other_nature_targeting() -> void:
	if nature_ui != null and nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")


func _hide_preview() -> void:
	if owner == null:
		return

	var flag_visual := owner.call("get_flag_visual") as Node2D

	if (
		flag_visual != null
		and is_instance_valid(flag_visual)
		and flag_visual.has_method("hide_preview")
	):
		flag_visual.call("hide_preview")


func _set_status(message: String) -> void:
	if status_label != null and is_instance_valid(status_label):
		status_label.text = message


func _set_status_key(key: String, value: int = -1) -> void:
	current_status_key = key
	current_status_value = value
	var message := tr(key)
	if value >= 0:
		message = message % value
	_set_status(message)


func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_text()


func _refresh_localized_text() -> void:
	if flag_menu_button != null and is_instance_valid(flag_menu_button):
		flag_menu_button.tooltip_text = tr("FLAG_MENU_TOOLTIP")
	if flag_menu_grid != null and is_instance_valid(flag_menu_grid):
		for child: Node in flag_menu_grid.get_children():
			var button := child as Button
			if button == null:
				continue
			if button.has_meta(&"translation_key"):
				button.text = tr(String(button.get_meta(&"translation_key")))
			if button.has_meta(&"tooltip_translation_key"):
				button.tooltip_text = tr(String(button.get_meta(&"tooltip_translation_key")))
	if not current_status_key.is_empty():
		_set_status_key(current_status_key, current_status_value)
