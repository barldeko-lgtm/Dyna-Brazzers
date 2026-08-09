extends Node

const GAME_SCENE_PATH: String = "res://scenes/main/main.tscn"
const START_SCREEN_SCENE_PATH: String = "res://scenes/ui/start_screen.tscn"
const SAVE_VERSION: int = 1
const SLOT_COUNT: int = 3
const AUTOSAVE_INTERVAL_SECONDS := 300.0
const AUTOSAVE_FILE_PATH := "user://dyna_autosave.json"
const DEFAULT_LEVEL_ID: int = 1
const LEVEL_SCENE_PATHS: Dictionary = {
	1: GAME_SCENE_PATH,
	2: GAME_SCENE_PATH
}

const CONTENT_ROOT_PATH: NodePath = NodePath(
	"UI/PlayerSidePanel/MarginContainer/VBoxContainer/PlayerNaturePanel/MarginContainer/VBoxContainer"
)
const MAIN_MENU_GRID_PATH: NodePath = NodePath(
	"UI/PlayerSidePanel/MarginContainer/VBoxContainer/PlayerNaturePanel/MarginContainer/VBoxContainer/MainMenuGrid"
)
const MENU_BUTTON_PATH: NodePath = NodePath(
	"UI/PlayerSidePanel/MarginContainer/VBoxContainer/PlayerNaturePanel/MarginContainer/VBoxContainer/MainMenuGrid/SystemMenuButton"
)
const MENU_ROOT_POSITION := Vector2(-2.0, 94.0)
const MENU_ROOT_SIZE := Vector2(260.0, 218.0)

const DEFAULT_CREATURE_SCENE_PATH: String = "res://scenes/creatures/creature.tscn"
const DEFAULT_GRASS_SCENE_PATH: String = "res://scenes/resources/grass.tscn"
const DEFAULT_EGG_SCENE_PATH: String = "res://scenes/resources/egg.tscn"

var attached_scene_id: int = 0
var menu_button: Button = null
var main_menu_grid: Control = null
var menu_root: Control = null
var menu_vbox: VBoxContainer = null
var button_template: Button = null

var menu_open: bool = false
var menu_previous_time_scale: float = 1.0
var current_slot_mode: String = ""
var status_message: String = ""
var current_level_id: int = DEFAULT_LEVEL_ID
var autosave_elapsed := 0.0
var autosave_in_progress := false
var load_in_progress := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(delta: float) -> void:
	var current_scene: Node = get_tree().current_scene

	if current_scene == null:
		return

	_update_autosave(delta, current_scene)

	var current_scene_id: int = int(current_scene.get_instance_id())

	if current_scene_id == attached_scene_id:
		return

	attached_scene_id = current_scene_id
	_detach_menu_references()

	if not get_level_scene_path(current_level_id).is_empty() and (
		current_scene.scene_file_path == get_level_scene_path(current_level_id)
	):
		call_deferred("_attach_to_game_scene", current_scene)


func _update_autosave(delta: float, current_scene: Node) -> void:
	if not _can_advance_autosave(current_scene):
		return

	if not advance_autosave_timer(delta):
		return

	autosave_in_progress = true
	var save_succeeded := save_autosave()
	autosave_in_progress = false

	if not save_succeeded:
		push_error("SaveSystem: automatic save failed.")


func _can_advance_autosave(current_scene: Node) -> bool:
	var active_level_scene_path := get_level_scene_path(current_level_id)

	if (
		current_scene == null
		or active_level_scene_path.is_empty()
		or current_scene.scene_file_path != active_level_scene_path
	):
		return false

	if menu_open or autosave_in_progress or load_in_progress or Engine.time_scale <= 0.0:
		return false

	var game_end_controller := get_tree().get_first_node_in_group("game_end_controller")

	if game_end_controller != null and int(game_end_controller.get("match_result")) != 0:
		return false

	return true


func advance_autosave_timer(simulation_delta: float) -> bool:
	autosave_elapsed += maxf(simulation_delta, 0.0)

	if autosave_elapsed < AUTOSAVE_INTERVAL_SECONDS:
		return false

	autosave_elapsed = 0.0
	return true


func _attach_to_game_scene(scene: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		return

	var found_content_root: Control = scene.get_node_or_null(CONTENT_ROOT_PATH) as Control
	var found_main_grid: Control = scene.get_node_or_null(MAIN_MENU_GRID_PATH) as Control
	var found_menu_button: Button = scene.get_node_or_null(MENU_BUTTON_PATH) as Button

	if found_content_root == null or found_main_grid == null or found_menu_button == null:
		push_warning("SaveSystem: right-side Menu button was not found.")
		return

	main_menu_grid = found_main_grid
	menu_button = found_menu_button
	button_template = found_menu_button

	if not menu_button.pressed.is_connected(_on_menu_button_pressed):
		menu_button.pressed.connect(_on_menu_button_pressed)

	_create_menu_root(found_content_root)
	_refresh_menu_tooltip()


func _detach_menu_references() -> void:
	if menu_open:
		Engine.time_scale = menu_previous_time_scale

	menu_open = false
	menu_button = null
	main_menu_grid = null
	menu_root = null
	menu_vbox = null
	button_template = null
	current_slot_mode = ""
	status_message = ""


func _create_menu_root(content_root: Control) -> void:
	var existing_root: Control = content_root.get_node_or_null("SaveLoadMenuRoot") as Control

	if existing_root != null:
		menu_root = existing_root
		menu_vbox = existing_root.get_node_or_null("MenuVBox") as VBoxContainer
		menu_root.grow_horizontal = Control.GROW_DIRECTION_END
		menu_root.grow_vertical = Control.GROW_DIRECTION_END
		_place_menu_root()
		menu_root.visible = false
		return

	menu_root = Control.new()
	menu_root.name = "SaveLoadMenuRoot"
	menu_root.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_root.visible = false
	menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	content_root.add_child(menu_root)
	menu_root.grow_horizontal = Control.GROW_DIRECTION_END
	menu_root.grow_vertical = Control.GROW_DIRECTION_END
	menu_root.position = MENU_ROOT_POSITION
	menu_root.size = MENU_ROOT_SIZE

	menu_vbox = VBoxContainer.new()
	menu_vbox.name = "MenuVBox"
	menu_root.add_child(menu_vbox)
	menu_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_vbox.add_theme_constant_override("separation", 6)
	_place_menu_root()


func _on_menu_button_pressed() -> void:
	if menu_open:
		return

	_cancel_active_nature_targeting()

	menu_previous_time_scale = Engine.time_scale

	if menu_previous_time_scale <= 0.0:
		menu_previous_time_scale = 1.0

	Engine.time_scale = 0.0
	menu_open = true
	status_message = ""

	if main_menu_grid != null:
		main_menu_grid.visible = false

	if menu_root != null:
		menu_root.visible = true

	_show_action_menu()


func _show_action_menu() -> void:
	current_slot_mode = ""
	_clear_menu_vbox()
	_add_title_label("MENU_TITLE")
	_add_menu_button("MENU_SAVE", _on_save_mode_pressed, 34.0)
	_add_menu_button("MENU_LOAD_ACTION", _on_load_mode_pressed, 34.0)
	_add_menu_button("MENU_MAIN_MENU", _on_main_menu_pressed, 34.0)
	_add_menu_button("MENU_QUIT_GAME", _on_quit_game_pressed, 34.0)
	_add_menu_button("MENU_BACK", _on_close_menu_pressed, 34.0)

	if not status_message.is_empty():
		_add_status_label(status_message)

	_place_menu_root()


func _on_save_mode_pressed() -> void:
	current_slot_mode = "save"
	status_message = ""
	_show_slot_menu()


func _on_load_mode_pressed() -> void:
	current_slot_mode = "load"
	status_message = ""
	_show_slot_menu()


func _show_slot_menu() -> void:
	_clear_menu_vbox()

	if current_slot_mode == "save":
		_add_title_label("MENU_SAVE")
	else:
		_add_title_label("MENU_LOAD_ACTION")
		var autosave_button := _create_styled_button()
		autosave_button.custom_minimum_size = Vector2(260.0, 34.0)
		autosave_button.disabled = not has_autosave()
		autosave_button.pressed.connect(_on_autosave_slot_pressed)
		menu_vbox.add_child(autosave_button)
		apply_save_button_text(autosave_button, get_autosave_button_text(), 18, 12)

	for slot_index: int in range(1, SLOT_COUNT + 1):
		var slot_button: Button = _create_styled_button()
		slot_button.custom_minimum_size = Vector2(260.0, 40.0)

		var slot_is_empty: bool = not has_save(slot_index)

		if current_slot_mode == "load":
			slot_button.disabled = slot_is_empty

		slot_button.pressed.connect(_on_slot_pressed.bind(slot_index))
		menu_vbox.add_child(slot_button)
		apply_save_button_text(slot_button, _get_slot_button_text(slot_index), 18, 12)

	_add_menu_button("MENU_BACK", _on_slots_back_pressed, 40.0)
	_place_menu_root()


func _place_menu_root() -> void:
	if menu_root == null or not is_instance_valid(menu_root):
		return

	menu_root.size = MENU_ROOT_SIZE
	menu_root.position = MENU_ROOT_POSITION
	# VBox minimum-size propagation is deferred by Godot. Reapply the approved
	# top-left corner after that pass so the Menu page does not jump upward.
	menu_root.set_deferred("size", MENU_ROOT_SIZE)
	menu_root.set_deferred("position", MENU_ROOT_POSITION)


func _on_autosave_slot_pressed() -> void:
	if not has_autosave():
		return

	status_message = tr("STATUS_LOADING_AUTOSAVE")
	_show_slot_menu()
	var load_succeeded: bool = await load_autosave()

	if load_succeeded:
		_close_menu(false)
		return

	status_message = tr("STATUS_LOAD_AUTOSAVE_FAILED")
	_show_slot_menu()


func _on_slots_back_pressed() -> void:
	status_message = ""
	_show_action_menu()


func _on_close_menu_pressed() -> void:
	_close_menu(true)


func _on_main_menu_pressed() -> void:
	_reset_active_game_session()

	var scene_error: Error = get_tree().change_scene_to_file(
		START_SCREEN_SCENE_PATH
	)

	if scene_error == OK:
		return

	# If the scene switch failed, restore the in-game menu.
	menu_open = true
	Engine.time_scale = 0.0
	status_message = tr("STATUS_MAIN_MENU_FAILED")
	_show_action_menu()


func _reset_active_game_session() -> void:
	# The current game scene will be freed by change_scene_to_file().
	# Clear every SaveSystem reference as well, so no runtime state survives.
	Engine.time_scale = 1.0
	menu_open = false
	menu_previous_time_scale = 1.0
	current_slot_mode = ""
	status_message = ""
	attached_scene_id = 0
	current_level_id = DEFAULT_LEVEL_ID
	autosave_elapsed = 0.0
	autosave_in_progress = false
	load_in_progress = false

	menu_button = null
	main_menu_grid = null
	menu_root = null
	menu_vbox = null
	button_template = null


func _on_quit_game_pressed() -> void:
	Engine.time_scale = 1.0
	get_tree().quit()


func _close_menu(restore_previous_speed: bool) -> void:
	menu_open = false
	current_slot_mode = ""
	status_message = ""

	if menu_root != null:
		menu_root.visible = false

	if main_menu_grid != null:
		main_menu_grid.visible = true

	if restore_previous_speed:
		Engine.time_scale = menu_previous_time_scale


func _on_slot_pressed(slot_index: int) -> void:
	if current_slot_mode == "save":
		var save_succeeded: bool = save_game(slot_index)

		if save_succeeded:
			status_message = tr("STATUS_SAVE_OK") % slot_index
		else:
			status_message = tr("STATUS_SAVE_FAILED") % slot_index

		_show_slot_menu()
		return

	if current_slot_mode == "load":
		var load_succeeded: bool = await load_game(slot_index)

		if load_succeeded:
			_close_menu(false)
		else:
			status_message = tr("STATUS_LOAD_SLOT_FAILED") % slot_index
			_show_slot_menu()


func _add_title_label(title_text: String) -> void:
	var title_label: Label = Label.new()
	title_label.theme_type_variation = &"HeaderLabel"
	title_label.custom_minimum_size = Vector2(260.0, 24.0)
	title_label.text = tr(title_text)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	menu_vbox.add_child(title_label)


func _add_status_label(message: String) -> void:
	var status_label: Label = Label.new()
	status_label.custom_minimum_size = Vector2(260.0, 28.0)
	status_label.text = message
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	menu_vbox.add_child(status_label)


func _add_menu_button(
	button_text: String,
	callback: Callable,
	height: float = 44.0
) -> Button:
	var button: Button = _create_styled_button()
	button.custom_minimum_size = Vector2(260.0, height)
	button.text = tr(button_text)
	button.pressed.connect(callback)
	menu_vbox.add_child(button)
	return button


func _create_styled_button() -> Button:
	if button_template != null and is_instance_valid(button_template):
		var duplicated_node: Node = button_template.duplicate()
		var duplicated_button: Button = duplicated_node as Button

		if duplicated_button != null:
			duplicated_button.name = "DynamicMenuButton"
			duplicated_button.tooltip_text = ""
			duplicated_button.disabled = false
			duplicated_button.focus_mode = Control.FOCUS_ALL
			duplicated_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return duplicated_button

	var fallback_button: Button = Button.new()
	fallback_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fallback_button.add_theme_font_size_override("font_size", 18)
	return fallback_button


func _clear_menu_vbox() -> void:
	if menu_vbox == null:
		return

	for child: Node in menu_vbox.get_children():
		menu_vbox.remove_child(child)
		child.queue_free()


func _cancel_active_nature_targeting() -> void:
	var nature_ui: Node = get_tree().get_first_node_in_group("player_nature_ui")

	if nature_ui != null and nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")


func _refresh_menu_tooltip() -> void:
	if menu_button == null:
		return

	menu_button.tooltip_text = tr("MENU_TOOLTIP")


# ---------------------------------------------------------------------------
# Save files and slot metadata.
# ---------------------------------------------------------------------------

func get_slot_path(slot_index: int) -> String:
	return "user://dyna_save_slot_%d.json" % slot_index


func get_autosave_path() -> String:
	return AUTOSAVE_FILE_PATH


func get_autosave_temp_path() -> String:
	return "%s.tmp" % get_autosave_path()


func get_autosave_backup_path() -> String:
	return "%s.bak" % get_autosave_path()


func get_slot_temp_path(slot_index: int) -> String:
	return "%s.tmp" % get_slot_path(slot_index)


func get_slot_backup_path(slot_index: int) -> String:
	return "%s.bak" % get_slot_path(slot_index)


func has_save(slot_index: int) -> bool:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return false

	_recover_slot_backup(slot_index)
	return _is_valid_save_data(_read_save_dictionary_at_path(get_slot_path(slot_index)))


func has_autosave() -> bool:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	return _is_valid_save_data(_read_save_dictionary_at_path(get_autosave_path()))


func get_most_recent_save_candidate() -> Dictionary:
	var candidates: Array[Dictionary] = []
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	var autosave_data := _read_save_dictionary_at_path(get_autosave_path())

	if _is_valid_save_data(autosave_data):
		candidates.append({
			"kind": "autosave",
			"saved_at": int(autosave_data.get("saved_at", 0)),
			"valid": true
		})

	for slot_index: int in range(1, SLOT_COUNT + 1):
		var slot_data := _read_save_dictionary(slot_index)

		if not _is_valid_save_data(slot_data):
			continue

		candidates.append({
			"kind": "slot",
			"slot_index": slot_index,
			"saved_at": int(slot_data.get("saved_at", 0)),
			"valid": true
		})

	return select_most_recent_save_candidate(candidates)


func select_most_recent_save_candidate(candidates: Array) -> Dictionary:
	var selected: Dictionary = {}
	var selected_timestamp := -1

	for candidate_variant: Variant in candidates:
		if not candidate_variant is Dictionary:
			continue

		var candidate := candidate_variant as Dictionary

		if not bool(candidate.get("valid", false)):
			continue

		var kind := String(candidate.get("kind", ""))

		if kind == "slot":
			var slot_index := int(candidate.get("slot_index", 0))

			if slot_index < 1 or slot_index > SLOT_COUNT:
				continue
		elif kind != "autosave":
			continue

		var timestamp := maxi(int(candidate.get("saved_at", 0)), 0)
		var wins_timestamp := timestamp > selected_timestamp
		var wins_autosave_tie := (
			timestamp == selected_timestamp
			and kind == "autosave"
			and String(selected.get("kind", "")) != "autosave"
		)

		if selected.is_empty() or wins_timestamp or wins_autosave_tie:
			selected = candidate.duplicate(true)
			selected_timestamp = timestamp

	return selected


func has_continue_save() -> bool:
	return not get_most_recent_save_candidate().is_empty()


func load_most_recent_save(preloaded_scene: PackedScene = null) -> bool:
	var selected := get_most_recent_save_candidate()

	if selected.is_empty():
		return false

	if String(selected.get("kind", "")) == "autosave":
		return await load_autosave(preloaded_scene)

	return await load_game(int(selected.get("slot_index", 0)), preloaded_scene)


func get_most_recent_save_level_id() -> int:
	var selected := get_most_recent_save_candidate()
	if selected.is_empty():
		return 0
	if String(selected.get("kind", "")) == "autosave":
		return get_autosave_level_id()
	return get_save_slot_level_id(int(selected.get("slot_index", 0)))


func get_save_slot_level_id(slot_index: int) -> int:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return 0
	var save_data := _read_save_dictionary(slot_index)
	if not _is_valid_save_data(save_data):
		return 0
	return get_saved_level_id(save_data)


func get_autosave_level_id() -> int:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	var save_data := _read_save_dictionary_at_path(get_autosave_path())
	if not _is_valid_save_data(save_data):
		return 0
	return get_saved_level_id(save_data)


func get_slot_button_text(slot_index: int) -> String:
	return _get_slot_button_text(slot_index)


func get_autosave_button_text() -> String:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())

	if not FileAccess.file_exists(get_autosave_path()):
		return "%s - %s" % [tr("SAVE_AUTOSAVE_SHORT"), tr("SAVE_EMPTY")]

	var metadata := _read_save_dictionary_at_path(get_autosave_path())

	if not _is_valid_save_data(metadata):
		return "%s - %s" % [tr("SAVE_AUTOSAVE_SHORT"), tr("SAVE_CORRUPTED")]

	return format_autosave_metadata(metadata)


func _get_slot_button_text(slot_index: int) -> String:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return tr("SAVE_SLOT_UNAVAILABLE")

	_recover_slot_backup(slot_index)
	var slot_path := get_slot_path(slot_index)

	if not FileAccess.file_exists(slot_path):
		return tr("SAVE_SLOT_EMPTY") % slot_index

	var metadata := _read_save_dictionary_at_path(slot_path)

	if not _is_valid_save_data(metadata):
		return tr("SAVE_SLOT_CORRUPTED") % slot_index

	return format_slot_metadata(slot_index, metadata)


func format_slot_metadata(_slot_index: int, metadata: Dictionary) -> String:
	return _format_save_metadata("", metadata)


func format_autosave_metadata(metadata: Dictionary) -> String:
	return _format_save_metadata(tr("SAVE_AUTOSAVE_SHORT"), metadata)


func _format_save_metadata(label: String, metadata: Dictionary) -> String:
	var level_id: int = get_saved_level_id(metadata)
	var map_label := tr("SAVE_MAP_LABEL") % level_id
	var label_prefix := "%s - " % label if not label.is_empty() else ""
	var saved_at: int = int(metadata.get("saved_at", 0))

	if saved_at <= 0:
		return tr("SAVE_WITHOUT_TIME") % [label_prefix, map_label]

	var offset_variant: Variant = metadata.get("saved_at_utc_offset_minutes", null)
	var offset_minutes: int

	if offset_variant is int or offset_variant is float:
		offset_minutes = int(offset_variant)
	else:
		var time_zone: Dictionary = Time.get_time_zone_from_system()
		offset_minutes = int(time_zone.get("bias", 0))

	var local_saved_at: int = saved_at + offset_minutes * 60
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(local_saved_at)
	var month: int = int(date.get("month", 0))
	var day: int = int(date.get("day", 0))
	var hour: int = int(date.get("hour", 0))
	var minute: int = int(date.get("minute", 0))

	return "%s%s - %02d.%02d %02d:%02d" % [
		label_prefix,
		map_label,
		day,
		month,
		hour,
		minute
	]


func apply_save_button_text(
	button: Button,
	text: String,
	preferred_font_size: int,
	minimum_font_size: int
) -> void:
	if button == null:
		return

	button.text = text
	var preferred_size := maxi(preferred_font_size, 1)
	var minimum_size := clampi(minimum_font_size, 1, preferred_size)
	var font := button.get_theme_font("font")
	var stylebox := button.get_theme_stylebox("normal")
	var horizontal_padding := stylebox.get_minimum_size().x if stylebox != null else 0.0
	var available_width := maxf(button.custom_minimum_size.x - horizontal_padding - 8.0, 1.0)
	var fitted_size := preferred_size

	while (
		fitted_size > minimum_size
		and font.get_string_size(
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			fitted_size
		).x > available_width
	):
		fitted_size -= 1

	button.add_theme_font_size_override("font_size", fitted_size)


func save_game(slot_index: int) -> bool:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return false

	_recover_slot_backup(slot_index)
	return _write_current_save(
		get_slot_path(slot_index),
		get_slot_temp_path(slot_index),
		get_slot_backup_path(slot_index),
		"slot %d" % slot_index
	)


func save_autosave() -> bool:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	return _write_current_save(
		get_autosave_path(),
		get_autosave_temp_path(),
		get_autosave_backup_path(),
		"autosave"
	)


func _write_current_save(
	save_path: String,
	temp_path: String,
	backup_path: String,
	save_label: String
) -> bool:
	var save_data := _collect_save_data()

	if not _is_valid_save_data(save_data):
		push_error("SaveSystem: refused to write incomplete %s data." % save_label)
		return false

	var saves_directory := DirAccess.open("user://")

	if saves_directory == null:
		push_error("SaveSystem: failed to open the save directory.")
		return false

	if FileAccess.file_exists(temp_path):
		saves_directory.remove(temp_path.get_file())

	var temp_file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)

	if temp_file == null:
		push_error("SaveSystem: failed to open temporary %s for writing." % save_label)
		return false

	temp_file.store_string(JSON.stringify(save_data, "	"))
	temp_file.flush()
	var write_error := temp_file.get_error()
	temp_file.close()

	if write_error != OK or not _is_valid_save_data(_read_save_dictionary_at_path(temp_path)):
		saves_directory.remove(temp_path.get_file())
		push_error("SaveSystem: temporary %s could not be verified." % save_label)
		return false

	if FileAccess.file_exists(backup_path) and saves_directory.remove(backup_path.get_file()) != OK:
		saves_directory.remove(temp_path.get_file())
		push_error("SaveSystem: failed to clear the previous backup for %s." % save_label)
		return false

	if FileAccess.file_exists(save_path) and saves_directory.rename(save_path.get_file(), backup_path.get_file()) != OK:
		saves_directory.remove(temp_path.get_file())
		push_error("SaveSystem: failed to protect the previous %s." % save_label)
		return false

	if saves_directory.rename(temp_path.get_file(), save_path.get_file()) != OK:
		if FileAccess.file_exists(backup_path):
			saves_directory.rename(backup_path.get_file(), save_path.get_file())
		push_error("SaveSystem: failed to replace %s." % save_label)
		return false

	if FileAccess.file_exists(backup_path):
		saves_directory.remove(backup_path.get_file())

	return true


func _recover_slot_backup(slot_index: int) -> void:
	_recover_save_backup(get_slot_path(slot_index), get_slot_backup_path(slot_index))


func _recover_save_backup(save_path: String, backup_path: String) -> void:

	if FileAccess.file_exists(save_path) or not FileAccess.file_exists(backup_path):
		return

	var saves_directory := DirAccess.open("user://")

	if saves_directory != null:
		saves_directory.rename(backup_path.get_file(), save_path.get_file())


func _read_save_dictionary(slot_index: int) -> Dictionary:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return {}

	_recover_slot_backup(slot_index)
	return _read_save_dictionary_at_path(get_slot_path(slot_index))


func _read_save_dictionary_at_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var save_file: FileAccess = FileAccess.open(path, FileAccess.READ)

	if save_file == null:
		return {}

	var raw_text: String = save_file.get_as_text()
	save_file.close()

	var parsed: Variant = JSON.parse_string(raw_text)

	if parsed is Dictionary:
		return parsed as Dictionary

	return {}


func _is_valid_save_data(save_data: Dictionary) -> bool:
	if save_data.is_empty() or int(save_data.get("version", 0)) != SAVE_VERSION:
		return false

	var creatures: Variant = save_data.get("creatures", null)
	var grass: Variant = save_data.get("grass", null)
	var eggs: Variant = save_data.get("eggs", null)
	var camera: Variant = save_data.get("camera", null)
	var player_energy: Variant = save_data.get("player_energy", null)
	var time_scale: Variant = save_data.get("time_scale", null)
	var level_id: Variant = save_data.get("level_id", DEFAULT_LEVEL_ID)

	return (
		creatures is Array
		and grass is Array
		and eggs is Array
		and camera is Dictionary
		and (player_energy is int or player_energy is float)
		and (time_scale is int or time_scale is float)
		and (level_id is int or level_id is float)
		and int(level_id) >= 1
	)


func get_level_scene_path(level_id: int) -> String:
	return String(LEVEL_SCENE_PATHS.get(level_id, ""))


func get_saved_level_id(save_data: Dictionary) -> int:
	var level_id: Variant = save_data.get("level_id", DEFAULT_LEVEL_ID)

	if not (level_id is int or level_id is float):
		return DEFAULT_LEVEL_ID

	return maxi(int(level_id), 1)


func start_new_game(level_id: int, preloaded_scene: PackedScene = null) -> Error:
	var level_scene_path: String = get_level_scene_path(level_id)

	if level_scene_path.is_empty():
		return ERR_DOES_NOT_EXIST

	var previous_level_id: int = current_level_id
	current_level_id = level_id
	autosave_elapsed = 0.0
	Engine.time_scale = 1.0
	var scene_error: Error = _change_scene_to_level(level_scene_path, preloaded_scene)

	if scene_error != OK:
		current_level_id = previous_level_id

	return scene_error


func load_game(slot_index: int, preloaded_scene: PackedScene = null) -> bool:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return false

	var save_data := _read_save_dictionary(slot_index)

	if not _is_valid_save_data(save_data):
		push_error("SaveSystem: slot %d is missing or invalid." % slot_index)
		return false

	return await _load_save_data(save_data, preloaded_scene)


func load_autosave(preloaded_scene: PackedScene = null) -> bool:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	var save_data := _read_save_dictionary_at_path(get_autosave_path())

	if not _is_valid_save_data(save_data):
		push_error("SaveSystem: autosave is missing or invalid.")
		return false

	return await _load_save_data(save_data, preloaded_scene)


func _load_save_data(save_data: Dictionary, preloaded_scene: PackedScene = null) -> bool:
	load_in_progress = true
	autosave_elapsed = 0.0
	var saved_level_id: int = get_saved_level_id(save_data)
	var level_scene_path: String = get_level_scene_path(saved_level_id)

	if level_scene_path.is_empty():
		load_in_progress = false
		push_error("SaveSystem: level %d is unavailable." % saved_level_id)
		return false

	var current_scene: Node = get_tree().current_scene

	if (
		current_scene == null
		or current_scene.scene_file_path != level_scene_path
		or current_level_id != saved_level_id
	):
		var previous_level_id: int = current_level_id
		current_level_id = saved_level_id
		var scene_error: Error = _change_scene_to_level(level_scene_path, preloaded_scene)

		if scene_error != OK:
			current_level_id = previous_level_id
			load_in_progress = false
			return false

		await get_tree().process_frame
		await get_tree().process_frame

	else:
		current_level_id = saved_level_id

	var load_succeeded: bool = await _apply_save_data(save_data)

	if load_succeeded:
		_reset_loaded_time_speed()

	load_in_progress = false
	return load_succeeded


func _change_scene_to_level(
	level_scene_path: String,
	preloaded_scene: PackedScene = null
) -> Error:
	if (
		preloaded_scene != null
		and preloaded_scene.resource_path == level_scene_path
	):
		return get_tree().change_scene_to_packed(preloaded_scene)
	return get_tree().change_scene_to_file(level_scene_path)


func _reset_loaded_time_speed() -> void:
	Engine.time_scale = 1.0
	menu_previous_time_scale = 1.0
	var player_ui := get_tree().get_first_node_in_group("player_ui")

	if player_ui != null and player_ui.has_method("reset_time_speed_after_load"):
		player_ui.call("reset_time_speed_after_load")


# ---------------------------------------------------------------------------
# Collect current simulation.
# ---------------------------------------------------------------------------

func _collect_save_data() -> Dictionary:
	var saved_time_scale: float = Engine.time_scale
	var time_zone: Dictionary = Time.get_time_zone_from_system()

	if menu_open:
		saved_time_scale = menu_previous_time_scale

	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"saved_at_utc_offset_minutes": int(time_zone.get("bias", 0)),
		"level_id": current_level_id,
		"time_scale": saved_time_scale,
		"camera": _collect_camera_data(),
		"player_energy": _collect_player_energy(),
		"creatures": _collect_creature_data(),
		"grass": _collect_grass_data(),
		"eggs": _collect_egg_data(),
		"cleared_dry_ground_tiles": _collect_cleared_dry_ground_tiles(),
		"dry_ground_rain_hits": _collect_dry_ground_rain_hits()
	}

	return save_data


func _collect_camera_data() -> Dictionary:
	var camera := _get_game_camera()

	if camera == null:
		return {}

	return {
		"x": camera.global_position.x,
		"y": camera.global_position.y,
		"zoom_x": camera.zoom.x,
		"zoom_y": camera.zoom.y
	}


func _collect_player_energy() -> float:
	var player_energy: Node = get_tree().get_first_node_in_group("player_energy")

	if player_energy == null or not player_energy.has_method("get_energy"):
		return 0.0

	return float(player_energy.call("get_energy"))


func _collect_cleared_dry_ground_tiles() -> Array:
	var world_grid: Node = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null or not world_grid.has_method("get_cleared_dry_ground_tiles"):
		return []

	return world_grid.call("get_cleared_dry_ground_tiles") as Array


func _collect_dry_ground_rain_hits() -> Array:
	var world_grid: Node = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null or not world_grid.has_method("get_dry_ground_rain_hit_data"):
		return []

	return world_grid.call("get_dry_ground_rain_hit_data") as Array


func _collect_creature_data() -> Array[Dictionary]:
	var creatures_data: Array[Dictionary] = []

	for creature_node: Node in get_tree().get_nodes_in_group("creatures"):
		if not is_instance_valid(creature_node):
			continue

		if creature_node.is_queued_for_deletion():
			continue

		var creature_state: int = int(creature_node.get("state"))

		# Dead creatures are temporary corpse visuals and are not persisted.
		if creature_state == Creature.State.DEAD:
			continue

		var species_data: Resource = creature_node.get("species_data") as Resource

		if species_data == null or species_data.resource_path.is_empty():
			continue

		var anchor_tile: Vector2i = creature_node.get("anchor_tile")
		var scene_path: String = creature_node.scene_file_path

		if scene_path.is_empty():
			scene_path = DEFAULT_CREATURE_SCENE_PATH

		var creature_record: Dictionary = {
			"scene_path": scene_path,
			"species_path": species_data.resource_path,
			"anchor_x": anchor_tile.x,
			"anchor_y": anchor_tile.y,
			"health": float(creature_node.get("health")),
			"hunger": float(creature_node.get("hunger")),
			"age": float(creature_node.get("age")),
			"age_tick_elapsed": float(creature_node.get("age_tick_elapsed")),
			"reproduction_cooldown": float(
				creature_node.get("reproduction_cooldown_remaining")
			),
			"reproduction_progress": float(creature_node.get("reproduction_progress"))
		}
		_enrich_creature_save_record(creature_record, creature_node)
		creatures_data.append(creature_record)

	return creatures_data


func _enrich_creature_save_record(_record: Dictionary, _creature: Node) -> void:
	pass


func _collect_grass_data() -> Array[Dictionary]:
	var grass_data: Array[Dictionary] = []

	for grass_node: Node in get_tree().get_nodes_in_group("grass"):
		if not is_instance_valid(grass_node):
			continue

		if grass_node.is_queued_for_deletion():
			continue

		var tile: Vector2i = grass_node.get("tile_position")
		var growth_timer: Timer = grass_node.get_node_or_null("GrowthTimer") as Timer
		var spread_timer: Timer = grass_node.get_node_or_null("SpreadTimer") as Timer
		var scene_path: String = grass_node.scene_file_path

		if scene_path.is_empty():
			scene_path = DEFAULT_GRASS_SCENE_PATH

		grass_data.append({
			"scene_path": scene_path,
			"tile_x": tile.x,
			"tile_y": tile.y,
			"stage": int(grass_node.get("current_stage")),
			"has_tried_to_spread": bool(grass_node.get("has_tried_to_spread")),
			"growth_time_left": growth_timer.time_left if growth_timer != null else 0.0,
			"spread_time_left": spread_timer.time_left if spread_timer != null else 0.0
		})

	return grass_data


func _collect_egg_data() -> Array[Dictionary]:
	var eggs_data: Array[Dictionary] = []

	for egg_node: Node in get_tree().get_nodes_in_group("eggs"):
		if not is_instance_valid(egg_node):
			continue

		if egg_node.is_queued_for_deletion():
			continue

		var anchor: Vector2i = egg_node.get("anchor_tile")
		var stage_1_timer: Timer = egg_node.get_node_or_null("Stage1Timer") as Timer
		var retry_timer: Timer = egg_node.get_node_or_null("ExpandRetryTimer") as Timer
		var hatch_timer: Timer = egg_node.get_node_or_null("HatchTimer") as Timer
		var hatch_species: Resource = egg_node.get("hatch_species_data") as Resource
		var hatch_species_path: String = ""

		if hatch_species != null:
			hatch_species_path = hatch_species.resource_path

		var hatch_creature_scene: PackedScene = egg_node.get("hatch_creature_scene") as PackedScene
		var hatch_creature_scene_path := DEFAULT_CREATURE_SCENE_PATH

		if hatch_creature_scene != null and not hatch_creature_scene.resource_path.is_empty():
			hatch_creature_scene_path = hatch_creature_scene.resource_path

		var scene_path: String = egg_node.scene_file_path

		if scene_path.is_empty():
			scene_path = DEFAULT_EGG_SCENE_PATH

		var egg_record: Dictionary = {
			"scene_path": scene_path,
			"species_id": String(egg_node.get("species_id")),
			"hatch_species_path": hatch_species_path,
			"hatch_creature_scene_path": hatch_creature_scene_path,
			"anchor_x": anchor.x,
			"anchor_y": anchor.y,
			"stage": int(egg_node.get("current_stage")),
			"stage_1_time_left": stage_1_timer.time_left if stage_1_timer != null else 0.0,
			"retry_time_left": retry_timer.time_left if retry_timer != null else 0.0,
			"hatch_time_left": hatch_timer.time_left if hatch_timer != null else 0.0
		}
		_enrich_egg_save_record(egg_record, egg_node)
		eggs_data.append(egg_record)

	return eggs_data


func _enrich_egg_save_record(_record: Dictionary, _egg: Node) -> void:
	pass


# ---------------------------------------------------------------------------
# Restore simulation.
# ---------------------------------------------------------------------------

func _apply_save_data(save_data: Dictionary) -> bool:
	var world_grid: Node = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null:
		await get_tree().process_frame
		world_grid = get_tree().get_first_node_in_group("world_grid")

	if world_grid == null:
		return false

	var creatures_container: Node2D = world_grid.get_node_or_null("Creatures") as Node2D
	var grasses_container: Node2D = world_grid.get_node_or_null("Grasses") as Node2D
	var eggs_container: Node2D = world_grid.get_node_or_null("Eggs") as Node2D

	if creatures_container == null or grasses_container == null or eggs_container == null:
		return false

	Engine.time_scale = 0.0
	_clear_dynamic_simulation_nodes()
	await get_tree().process_frame
	await get_tree().process_frame

	_restore_cleared_dry_ground_tiles(
		save_data.get("cleared_dry_ground_tiles", []) as Array,
		world_grid
	)
	_restore_dry_ground_rain_hits(
		save_data.get("dry_ground_rain_hits", []) as Array,
		world_grid
	)
	_restore_grass(
		save_data.get("grass", []) as Array,
		world_grid,
		grasses_container
	)
	_restore_eggs(
		save_data.get("eggs", []) as Array,
		world_grid,
		eggs_container
	)
	_restore_creatures(
		save_data.get("creatures", []) as Array,
		world_grid,
		creatures_container
	)

	await get_tree().process_frame

	_restore_player_energy(float(save_data.get("player_energy", 0.0)))
	_restore_camera(save_data.get("camera", {}) as Dictionary)

	var restored_time_scale: float = float(save_data.get("time_scale", 1.0))

	if restored_time_scale <= 0.0:
		restored_time_scale = 1.0

	Engine.time_scale = restored_time_scale
	return true


func _clear_dynamic_simulation_nodes() -> void:
	var group_names: Array[String] = ["creatures", "eggs", "grass"]

	for group_name: String in group_names:
		for simulation_node: Node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(simulation_node):
				simulation_node.queue_free()


func _restore_cleared_dry_ground_tiles(saved_tiles: Array, world_grid: Node) -> void:
	if world_grid.has_method("restore_cleared_dry_ground_tiles"):
		world_grid.call("restore_cleared_dry_ground_tiles", saved_tiles)


func _restore_dry_ground_rain_hits(saved_hits: Array, world_grid: Node) -> void:
	if world_grid.has_method("restore_dry_ground_rain_hit_data"):
		world_grid.call("restore_dry_ground_rain_hit_data", saved_hits)


func _restore_grass(
	saved_grass: Array,
	world_grid: Node,
	container: Node2D
) -> void:
	for grass_variant: Variant in saved_grass:
		if not (grass_variant is Dictionary):
			continue

		var grass_record: Dictionary = grass_variant as Dictionary
		var scene_path: String = String(
			grass_record.get("scene_path", DEFAULT_GRASS_SCENE_PATH)
		)
		var grass_scene: PackedScene = load(scene_path) as PackedScene

		if grass_scene == null:
			continue

		var grass_node: Node2D = grass_scene.instantiate() as Node2D

		if grass_node == null:
			continue

		var stage: int = clampi(int(grass_record.get("stage", 0)), 0, 3)
		var tile: Vector2i = Vector2i(
			int(grass_record.get("tile_x", 0)),
			int(grass_record.get("tile_y", 0))
		)
		var world_position: Vector2 = world_grid.call(
			"grass_tile_to_world_position",
			tile
		)

		grass_node.set("start_stage", stage)
		grass_node.position = container.to_local(world_position)
		container.add_child(grass_node)

		grass_node.set(
			"has_tried_to_spread",
			bool(grass_record.get("has_tried_to_spread", false))
		)

		var growth_timer: Timer = grass_node.get_node_or_null("GrowthTimer") as Timer
		var spread_timer: Timer = grass_node.get_node_or_null("SpreadTimer") as Timer

		if growth_timer != null:
			growth_timer.stop()

		if spread_timer != null:
			spread_timer.stop()

		if stage < 3 and growth_timer != null:
			var growth_left: float = float(
				grass_record.get("growth_time_left", 0.0)
			)

			if growth_left <= 0.0:
				growth_left = float(grass_node.get("growth_time"))

			growth_timer.start(growth_left)
		elif stage == 3 and spread_timer != null:
			var has_spread: bool = bool(
				grass_record.get("has_tried_to_spread", false)
			)

			if not has_spread:
				var spread_left: float = float(
					grass_record.get("spread_time_left", 0.0)
				)

				if spread_left <= 0.0:
					spread_left = float(grass_node.get("spread_delay"))

				spread_timer.start(spread_left)


func _restore_eggs(
	saved_eggs: Array,
	world_grid: Node,
	container: Node2D
) -> void:
	for egg_variant: Variant in saved_eggs:
		if not (egg_variant is Dictionary):
			continue

		var egg_record: Dictionary = egg_variant as Dictionary
		var scene_path: String = String(
			egg_record.get("scene_path", DEFAULT_EGG_SCENE_PATH)
		)
		var egg_scene: PackedScene = load(scene_path) as PackedScene

		if egg_scene == null:
			continue

		var egg_node: Node2D = egg_scene.instantiate() as Node2D

		if egg_node == null:
			continue

		var anchor: Vector2i = Vector2i(
			int(egg_record.get("anchor_x", 0)),
			int(egg_record.get("anchor_y", 0))
		)
		var hatch_species_path: String = String(
			egg_record.get("hatch_species_path", "")
		)
		var hatch_creature_scene_path: String = String(
			egg_record.get("hatch_creature_scene_path", DEFAULT_CREATURE_SCENE_PATH)
		)
		var hatch_creature_scene: PackedScene = load(hatch_creature_scene_path) as PackedScene

		if hatch_creature_scene == null:
			hatch_creature_scene = load(DEFAULT_CREATURE_SCENE_PATH) as PackedScene

		if hatch_creature_scene == null:
			egg_node.queue_free()
			continue

		egg_node.set("species_id", String(egg_record.get("species_id", "stegosaurus")))
		egg_node.set("hatch_creature_scene", hatch_creature_scene)

		if not hatch_species_path.is_empty():
			var hatch_species: CreatureSpeciesData = load(hatch_species_path) as CreatureSpeciesData

			if hatch_species != null:
				egg_node.set("hatch_species_data", hatch_species)
				egg_node.set("species_id", hatch_species.species_id)

				if hatch_species.egg_stage_1_texture != null:
					egg_node.set("stage_1_texture", hatch_species.egg_stage_1_texture)

				if hatch_species.egg_stage_2_texture != null:
					egg_node.set("stage_2_texture", hatch_species.egg_stage_2_texture)

		var stage_1_world_position: Vector2 = world_grid.call(
			"anchor_to_world_position",
			anchor,
			Vector2i(1, 2)
		)
		egg_node.position = container.to_local(stage_1_world_position)
		container.add_child(egg_node)

		var stage_1_timer: Timer = egg_node.get_node_or_null("Stage1Timer") as Timer
		var retry_timer: Timer = egg_node.get_node_or_null("ExpandRetryTimer") as Timer
		var hatch_timer: Timer = egg_node.get_node_or_null("HatchTimer") as Timer

		if stage_1_timer != null:
			stage_1_timer.stop()

		if retry_timer != null:
			retry_timer.stop()

		if hatch_timer != null:
			hatch_timer.stop()

		var stage: int = clampi(int(egg_record.get("stage", 0)), 0, 1)
		egg_node.set("current_stage", stage)

		if egg_node.has_method("apply_current_stage_visual"):
			egg_node.call("apply_current_stage_visual")

		if stage == 0:
			var retry_left: float = float(egg_record.get("retry_time_left", 0.0))

			if retry_left > 0.0 and retry_timer != null:
				retry_timer.start(retry_left)
			elif stage_1_timer != null:
				var stage_1_left: float = float(
					egg_record.get("stage_1_time_left", 0.0)
				)

				if stage_1_left <= 0.0:
					stage_1_left = Egg.STAGE_1_DURATION

				stage_1_timer.start(stage_1_left)
		else:
			var blocker_registered: bool = bool(world_grid.call(
				"register_blocker",
				egg_node,
				anchor,
				Vector2i(2, 2)
			))
			if not blocker_registered:
				push_warning(
					"SaveSystem: skipped a stage-two egg at %s because its blocker could not be restored."
					% [anchor]
				)
				egg_node.queue_free()
				continue
			egg_node.set("is_registered_as_blocker", true)

			var stage_2_world_position: Vector2 = world_grid.call(
				"anchor_to_world_position",
				anchor,
				Vector2i(2, 2)
			)
			egg_node.global_position = stage_2_world_position

			if hatch_timer != null:
				var hatch_left: float = float(
					egg_record.get("hatch_time_left", 0.0)
				)

				if hatch_left <= 0.0:
					hatch_left = Egg.STAGE_2_DURATION

				hatch_timer.start(hatch_left)


func _restore_creatures(
	saved_creatures: Array,
	world_grid: Node,
	container: Node2D
) -> void:
	for creature_variant: Variant in saved_creatures:
		if not (creature_variant is Dictionary):
			continue

		var creature_record: Dictionary = creature_variant as Dictionary
		var scene_path: String = String(
			creature_record.get("scene_path", DEFAULT_CREATURE_SCENE_PATH)
		)
		var species_path: String = String(
			creature_record.get("species_path", "")
		)
		var creature_scene: PackedScene = load(scene_path) as PackedScene
		var species_data: Resource = load(species_path) as Resource

		if creature_scene == null or species_data == null:
			continue

		var creature_node: Node2D = creature_scene.instantiate() as Node2D

		if creature_node == null:
			continue

		var anchor: Vector2i = Vector2i(
			int(creature_record.get("anchor_x", 0)),
			int(creature_record.get("anchor_y", 0))
		)
		var footprint: Vector2i = creature_node.get("footprint_size")
		var world_position: Vector2 = world_grid.call(
			"anchor_to_world_position",
			anchor,
			footprint
		)

		creature_node.set("species_data", species_data)
		creature_node.set("health", float(creature_record.get("health", 1.0)))
		creature_node.set("hunger", float(creature_record.get("hunger", 1.0)))
		creature_node.position = container.to_local(world_position)
		container.add_child(creature_node)

		creature_node.set("age", float(creature_record.get("age", 0.0)))
		creature_node.set(
			"age_tick_elapsed",
			float(creature_record.get("age_tick_elapsed", 0.0))
		)
		creature_node.set(
			"reproduction_cooldown_remaining",
			float(creature_record.get("reproduction_cooldown", 0.0))
		)
		creature_node.set(
			"reproduction_progress",
			clampf(
				float(creature_record.get("reproduction_progress", 0.0)),
				0.0,
				float(species_data.get("reproduction_progress_max"))
			)
		)


func _restore_player_energy(saved_energy: float) -> void:
	var player_energy: Node = get_tree().get_first_node_in_group("player_energy")

	if player_energy == null or not player_energy.has_method("restore_energy"):
		return

	player_energy.call("restore_energy", saved_energy)


func _restore_camera(camera_data: Dictionary) -> void:
	if camera_data.is_empty():
		return

	var camera := _get_game_camera()

	if camera == null:
		return

	camera.global_position = Vector2(
		float(camera_data.get("x", 0.0)),
		float(camera_data.get("y", 0.0))
	)
	camera.zoom = Vector2(
		float(camera_data.get("zoom_x", 1.0)),
		float(camera_data.get("zoom_y", 1.0))
	)


func _get_game_camera() -> Camera2D:
	var camera := get_tree().get_first_node_in_group("game_camera") as Camera2D

	if camera != null:
		return camera

	return get_viewport().get_camera_2d()
