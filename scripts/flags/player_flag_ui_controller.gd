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

var targeting_species_id := StringName()
var removal_targeting_enabled := false


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
		flag_menu_button.tooltip_text = "Флаги видов"

		if not flag_menu_button.pressed.is_connected(_on_flag_menu_button_pressed):
			flag_menu_button.pressed.connect(_on_flag_menu_button_pressed)


func detach() -> void:
	cancel_targeting()
	nature_ui = null
	nature_content = null
	main_menu_grid = null
	flag_menu_button = null
	flag_menu_grid = null
	status_label = null


func handle_unhandled_input(event: InputEvent) -> bool:
	if not is_targeting() or not (event is InputEventMouseButton):
		return false

	return _handle_targeting_mouse(event as InputEventMouseButton)


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

	var target_tile: Vector2i = world_grid.call(
		"world_to_map_tile",
		owner.call("get_flag_mouse_world_position")
	)
	var is_valid := bool(owner.call("is_valid_flag_tile", target_tile))

	if flag_visual.has_method("set_preview"):
		flag_visual.call("set_preview", target_tile, is_valid)


func cancel_targeting() -> void:
	targeting_species_id = StringName()
	removal_targeting_enabled = false
	_hide_preview()


func is_targeting() -> bool:
	return targeting_species_id != StringName() or removal_targeting_enabled


func refresh_status() -> void:
	if int(owner.call("get_flag_count")) <= 0:
		_set_status("Флагов нет")
		return

	_set_status("Флагов: %d" % int(owner.call("get_flag_count")))


func set_status(message: String) -> void:
	_set_status(message)


func _build_flag_menu(menu_entries: Array[Dictionary]) -> void:
	if nature_content == null or flag_menu_button == null:
		return

	flag_menu_grid = GridContainer.new()
	flag_menu_grid.name = "SpeciesFlagMenu"
	flag_menu_grid.position = Vector2(0.0, 66.0)
	flag_menu_grid.size = Vector2(260.0, 218.0)
	flag_menu_grid.columns = 3
	flag_menu_grid.add_theme_constant_override("h_separation", 6)
	flag_menu_grid.add_theme_constant_override("v_separation", 6)
	flag_menu_grid.visible = false
	nature_content.add_child(flag_menu_grid)

	for entry: Dictionary in menu_entries:
		var species_id := StringName(String(entry.get("species_id", "")))

		if species_id == StringName():
			continue

		var species_button := _duplicate_menu_button()
		species_button.name = "%sFlagButton" % String(species_id).capitalize()
		species_button.custom_minimum_size = Vector2(80.0, 52.0)
		species_button.text = String(entry.get("button_text", "Флаг\nвида"))
		species_button.tooltip_text = String(
			entry.get("tooltip", "Поставить или перенести флаг вида")
		)
		species_button.add_theme_font_size_override("font_size", 11)
		species_button.pressed.connect(_on_species_flag_pressed.bind(species_id))
		flag_menu_grid.add_child(species_button)

	var remove_button := _duplicate_menu_button()
	remove_button.name = "RemoveSpeciesFlagButton"
	remove_button.custom_minimum_size = Vector2(80.0, 52.0)
	remove_button.text = "Удалить\nфлаг"
	remove_button.tooltip_text = "Выбрать флаг на карте для удаления"
	remove_button.add_theme_font_size_override("font_size", 12)
	remove_button.pressed.connect(_on_remove_flag_pressed)
	flag_menu_grid.add_child(remove_button)

	var back_button := _duplicate_menu_button()
	back_button.name = "FlagMenuBackButton"
	back_button.custom_minimum_size = Vector2(80.0, 52.0)
	back_button.text = "← Назад"
	back_button.tooltip_text = "Вернуться в основное меню"
	back_button.add_theme_font_size_override("font_size", 14)
	back_button.pressed.connect(_on_back_button_pressed)
	flag_menu_grid.add_child(back_button)

	status_label = Label.new()
	status_label.name = "FlagStatusLabel"
	status_label.custom_minimum_size = Vector2(80.0, 52.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	flag_menu_grid.add_child(status_label)
	refresh_status()


func _duplicate_menu_button() -> Button:
	var duplicated_button := flag_menu_button.duplicate() as Button

	if duplicated_button == null:
		duplicated_button = Button.new()

	duplicated_button.toggle_mode = false
	duplicated_button.button_pressed = false
	duplicated_button.focus_mode = Control.FOCUS_NONE
	duplicated_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return duplicated_button


func _on_flag_menu_button_pressed() -> void:
	_cancel_other_nature_targeting()

	if main_menu_grid != null:
		main_menu_grid.visible = false

	if flag_menu_grid != null:
		flag_menu_grid.visible = true

	refresh_status()


func _on_species_flag_pressed(species_id: StringName) -> void:
	var world_grid: Node = owner.call("get_world_grid")

	if world_grid == null or not is_instance_valid(world_grid):
		_set_status("Мир не найден")
		return

	_cancel_other_nature_targeting()
	removal_targeting_enabled = false
	targeting_species_id = species_id
	_set_status("ЛКМ по карте\nПКМ — отмена")
	update_targeting_preview()


func _on_remove_flag_pressed() -> void:
	cancel_targeting()
	removal_targeting_enabled = true
	_set_status("ЛКМ по флагу\nПКМ — отмена")


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


func _cancel_targeting_from_mouse() -> bool:
	cancel_targeting()
	_set_status("Установка отменена")
	return true


func _apply_left_click_targeting() -> bool:
	var world_grid: Node = owner.call("get_world_grid")

	if world_grid == null or not is_instance_valid(world_grid):
		return false

	var target_tile: Vector2i = world_grid.call(
		"world_to_map_tile",
		owner.call("get_flag_mouse_world_position")
	)

	if removal_targeting_enabled:
		return _try_remove_flag_at(target_tile)

	return _try_place_flag_at(target_tile)


func _try_remove_flag_at(target_tile: Vector2i) -> bool:
	var species_id := StringName(owner.call("get_species_flag_at_tile", target_tile))

	if species_id == StringName():
		_set_status("Нужен центр\nфлага")
		return false

	owner.call("remove_flag", species_id)
	cancel_targeting()
	_set_status("Флаг удалён")
	return true


func _try_place_flag_at(target_tile: Vector2i) -> bool:
	if not bool(owner.call("is_valid_flag_tile", target_tile)):
		_set_status("Нужен свободный\nтайл земли")
		return false

	owner.call("set_flag", targeting_species_id, target_tile)
	cancel_targeting()
	_set_status("Флаг поставлен")
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
