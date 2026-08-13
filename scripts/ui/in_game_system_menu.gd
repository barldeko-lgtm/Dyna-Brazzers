extends Node

const BUTTON_TEXT_FITTER := preload("res://scripts/ui/button_text_fitter.gd")

const SLOT_COUNT := 3
const NATURE_MENU_ATTACH_RETRY_FRAMES := 16
const MENU_ROOT_POSITION := Vector2(-2.0, 94.0)
const MENU_ROOT_SIZE := Vector2(260.0, 218.0)
const LOAD_MENU_ROOT_POSITION := Vector2(-2.0, 84.0)
const LOAD_MENU_ROOT_SIZE := Vector2(260.0, 247.0)
const LOAD_MENU_BUTTON_HEIGHT := 47.0
const LOAD_MENU_BUTTON_SEPARATION := 3
const LANGUAGE_OPTIONS := [
	{"locale": "ru", "name": "Русский"},
	{"locale": "en", "name": "English"},
	{"locale": "fr", "name": "Français"},
	{"locale": "de", "name": "Deutsch"},
	{"locale": "uk", "name": "Українська"},
]
const INGAME_SETTINGS_ROW_SIZE := Vector2(260.0, 27.0)
const INGAME_SETTINGS_LABEL_SLOT_SIZE := Vector2(104.0, 27.0)
const INGAME_SETTINGS_CONTROL_SIZE := Vector2(150.0, 27.0)
const INGAME_SETTINGS_ROW_SEPARATION := 6
const INGAME_SETTINGS_LABEL_INSET_LEFT := 6
const INGAME_SETTINGS_LABEL_CONTENT_WIDTH := 98.0
const INGAME_SETTINGS_LABEL_FONT_SIZE := 14
const INGAME_SETTINGS_LABEL_MIN_FONT_SIZE := 10
const INGAME_SETTINGS_OPTION_FONT_SIZE := 14
const INGAME_SETTINGS_OUTLINE_SIZE := 2
const ACTION_MENU_ROOT_POSITION := Vector2(-2.0, 84.0)
const ACTION_MENU_ROOT_SIZE := Vector2(260.0, 255.0)
const ACTION_GRID_ROOT_POSITION := Vector2(-2.0, 96.0)
const ACTION_GRID_ROOT_SIZE := Vector2(260.0, 229.0)
const ACTION_MENU_BUTTON_SIZE := Vector2(126.0, 71.0)
const ACTION_MENU_BUTTON_SEPARATION := 8
const SETTINGS_MENU_ROW_SEPARATION := 3
const SETTINGS_BACK_BUTTON_HEIGHT := 45.0
const SETTINGS_BACK_SPACER_HEIGHT := 20.0

const CONFIRMATION_FRAME_TEXTURE := preload("res://assets/ui/tutorial/tutorial_choice_frame.png")
const CONFIRMATION_BUTTON_NORMAL := preload("res://assets/ui/buttons/dyna_button_normal.tres")
const CONFIRMATION_BUTTON_HOVER := preload("res://assets/ui/buttons/dyna_button_hover.tres")
const CONFIRMATION_FONT := preload("res://assets/fonts/philosopher/Philosopher-Bold.ttf")
const CONFIRM_ACTION_MAIN_MENU := &"main_menu"
const CONFIRM_ACTION_QUIT_GAME := &"quit_game"

var save_system: Node = null
var attached_scene_id := 0
var menu_button: Button = null
var main_menu_grid: Control = null
var menu_root: Control = null
var menu_vbox: VBoxContainer = null
var action_menu_grid: GridContainer = null
var button_template: Button = null
var menu_open := false
var menu_previous_time_scale := 1.0
var current_slot_mode := ""
var ingame_transparent_option_arrow: ImageTexture = null
var confirmation_layer: CanvasLayer = null
var confirmation_title_label: Label = null
var confirmation_yes_button: Button = null
var confirmation_back_button: Button = null
var pending_confirmation_action := StringName()


func setup(owner_save_system: Node) -> void:
	save_system = owner_save_system
	if save_system != null:
		save_system.set("system_menu", self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func is_open() -> bool:
	return menu_open


func get_previous_time_scale() -> float:
	return menu_previous_time_scale


func reset_session() -> void:
	attached_scene_id = 0
	_detach_menu_references()


func _process(_delta: float) -> void:
	if save_system == null or not is_instance_valid(save_system):
		return
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var current_scene_id := int(current_scene.get_instance_id())
	if current_scene_id == attached_scene_id:
		return
	attached_scene_id = current_scene_id
	_detach_menu_references()
	var level_path := String(save_system.call("get_level_scene_path", int(save_system.get("current_level_id"))))
	if not level_path.is_empty() and current_scene.scene_file_path == level_path:
		call_deferred("_attach_to_game_scene", current_scene)


func _attach_to_game_scene(scene: Node) -> void:
	for _attempt in range(NATURE_MENU_ATTACH_RETRY_FRAMES):
		if scene == null or not is_instance_valid(scene) or get_tree().current_scene != scene:
			return

		var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
		if (
			nature_ui != null
			and nature_ui.has_method("get_menu_content_root")
			and nature_ui.has_method("get_main_menu_grid")
			and nature_ui.has_method("get_menu_button")
		):
			var found_content_root := nature_ui.call("get_menu_content_root") as Control
			var found_main_grid := nature_ui.call("get_main_menu_grid") as Control
			var found_menu_button := nature_ui.call("get_menu_button", &"system") as Button
			if found_content_root != null and found_main_grid != null and found_menu_button != null:
				main_menu_grid = found_main_grid
				menu_button = found_menu_button
				button_template = found_menu_button
				if not menu_button.pressed.is_connected(_on_menu_button_pressed):
					menu_button.pressed.connect(_on_menu_button_pressed)
				_create_menu_root(found_content_root)
				_refresh_menu_tooltip()
				return
		await get_tree().process_frame

	push_warning("SaveSystem: nature-menu API or system-menu controls were not found.")


func _detach_menu_references() -> void:
	if menu_open:
		Engine.time_scale = menu_previous_time_scale
	menu_open = false
	_clear_confirmation_dialog()
	menu_button = null
	main_menu_grid = null
	menu_root = null
	menu_vbox = null
	action_menu_grid = null
	button_template = null
	current_slot_mode = ""


func _create_menu_root(content_root: Control) -> void:
	var existing_root: Control = content_root.get_node_or_null("SaveLoadMenuRoot") as Control

	if existing_root != null:
		menu_root = existing_root
		menu_vbox = existing_root.get_node_or_null("MenuVBox") as VBoxContainer
		action_menu_grid = existing_root.get_node_or_null("ActionMenuGrid") as GridContainer
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

	action_menu_grid = GridContainer.new()
	action_menu_grid.name = "ActionMenuGrid"
	action_menu_grid.columns = 2
	action_menu_grid.visible = false
	action_menu_grid.add_theme_constant_override("h_separation", ACTION_MENU_BUTTON_SEPARATION)
	action_menu_grid.add_theme_constant_override("v_separation", ACTION_MENU_BUTTON_SEPARATION)
	menu_root.add_child(action_menu_grid)
	action_menu_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_place_menu_root()

	if menu_root != null:
		menu_root.position = Vector2(0.0, 49.0)
		menu_root.size = Vector2(260.0, 235.0)
	if menu_vbox != null:
		menu_vbox.add_theme_constant_override("separation", 3)


func _on_menu_button_pressed() -> void:
	if menu_open:
		return
	_cancel_active_nature_targeting()
	menu_previous_time_scale = Engine.time_scale
	if menu_previous_time_scale <= 0.0:
		menu_previous_time_scale = 1.0
	Engine.time_scale = 0.0
	menu_open = true
	if main_menu_grid != null:
		main_menu_grid.visible = false
	if menu_root != null:
		menu_root.visible = true
	_show_action_menu()


func _show_action_menu() -> void:
	current_slot_mode = ""
	_clear_menu_vbox()
	_clear_action_menu_grid()
	menu_vbox.visible = false
	action_menu_grid.visible = true
	_add_action_menu_button("MENU_SAVE", _on_save_mode_pressed, "SaveButton")
	_add_action_menu_button("MENU_LOAD_ACTION", _on_load_mode_pressed, "LoadButton")
	_add_action_menu_button("MENU_SETTINGS", _on_audio_settings_pressed, "SettingsButton")
	_add_action_menu_button("MENU_MAIN_MENU", _on_main_menu_pressed, "MainMenuButton")
	_add_action_menu_button("MENU_BACK", _on_close_menu_pressed, "BackButton")
	_add_action_menu_button("MENU_QUIT_GAME", _on_quit_game_pressed, "QuitGameButton")
	_place_action_menu_root()


func _place_action_menu_root() -> void:
	if menu_root == null or not is_instance_valid(menu_root):
		return
	menu_root.size = ACTION_GRID_ROOT_SIZE
	menu_root.position = ACTION_GRID_ROOT_POSITION
	menu_root.set_deferred("size", ACTION_GRID_ROOT_SIZE)
	menu_root.set_deferred("position", ACTION_GRID_ROOT_POSITION)


func _on_save_mode_pressed() -> void:
	current_slot_mode = "save"
	_show_slot_menu()


func _on_load_mode_pressed() -> void:
	current_slot_mode = "load"
	_show_slot_menu()


func _show_slot_menu() -> void:
	_prepare_vbox_menu()
	_clear_menu_vbox()
	if current_slot_mode == "save":
		menu_vbox.add_theme_constant_override("separation", LOAD_MENU_BUTTON_SEPARATION)
		_add_save_menu_title()
	else:
		menu_vbox.add_theme_constant_override("separation", LOAD_MENU_BUTTON_SEPARATION)
		var autosave_button := _create_styled_button()
		autosave_button.custom_minimum_size = Vector2(260.0, LOAD_MENU_BUTTON_HEIGHT)
		autosave_button.disabled = not bool(save_system.call("has_autosave"))
		autosave_button.pressed.connect(_on_autosave_slot_pressed)
		menu_vbox.add_child(autosave_button)
		BUTTON_TEXT_FITTER.apply(autosave_button, String(save_system.call("get_autosave_button_text")), 18, 12)
	for slot_index: int in range(1, SLOT_COUNT + 1):
		var slot_button := _create_styled_button()
		slot_button.custom_minimum_size = Vector2(260.0, LOAD_MENU_BUTTON_HEIGHT)
		var slot_is_empty := not bool(save_system.call("has_save", slot_index))
		if current_slot_mode == "load":
			slot_button.disabled = slot_is_empty
		slot_button.pressed.connect(_on_slot_pressed.bind(slot_index))
		menu_vbox.add_child(slot_button)
		BUTTON_TEXT_FITTER.apply(slot_button, String(save_system.call("get_slot_button_text", slot_index)), 18, 12)
	var back_height := LOAD_MENU_BUTTON_HEIGHT
	_add_menu_button("MENU_BACK", _on_slots_back_pressed, back_height)
	_place_load_menu_root()


func _place_load_menu_root() -> void:
	if menu_root == null or not is_instance_valid(menu_root):
		return
	menu_root.size = LOAD_MENU_ROOT_SIZE
	menu_root.position = LOAD_MENU_ROOT_POSITION
	menu_root.set_deferred("size", LOAD_MENU_ROOT_SIZE)
	menu_root.set_deferred("position", LOAD_MENU_ROOT_POSITION)


func _place_menu_root() -> void:
	if menu_root == null or not is_instance_valid(menu_root):
		return
	menu_root.size = MENU_ROOT_SIZE
	menu_root.position = MENU_ROOT_POSITION
	menu_root.set_deferred("size", MENU_ROOT_SIZE)
	menu_root.set_deferred("position", MENU_ROOT_POSITION)


func _on_autosave_slot_pressed() -> void:
	if not bool(save_system.call("has_autosave")):
		return
	_show_slot_menu()
	var load_succeeded: bool = await save_system.call("load_autosave")
	if load_succeeded:
		_close_menu(false)
		return
	_show_slot_menu()


func _on_slots_back_pressed() -> void:
	_show_action_menu()


func _on_close_menu_pressed() -> void:
	_close_menu(true)


func _on_main_menu_pressed() -> void:
	_show_confirmation(CONFIRM_ACTION_MAIN_MENU)


func _on_quit_game_pressed() -> void:
	_show_confirmation(CONFIRM_ACTION_QUIT_GAME)


func _show_confirmation(action: StringName) -> void:
	if action != CONFIRM_ACTION_MAIN_MENU and action != CONFIRM_ACTION_QUIT_GAME:
		return

	if not _ensure_confirmation_dialog():
		return

	pending_confirmation_action = action
	confirmation_title_label.text = _get_confirmation_text()
	confirmation_yes_button.text = tr("TUTORIAL_CHOICE_YES")
	confirmation_back_button.text = tr("MENU_BACK")
	confirmation_yes_button.disabled = false
	confirmation_back_button.disabled = false
	# Show the dialog without assigning keyboard focus so neither action
	# appears preselected when the confirmation opens.
	confirmation_layer.visible = true


func _ensure_confirmation_dialog() -> bool:
	if confirmation_layer != null and is_instance_valid(confirmation_layer):
		return true

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	confirmation_layer = CanvasLayer.new()
	confirmation_layer.name = "SystemConfirmationDialog"
	confirmation_layer.layer = 100
	confirmation_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	current_scene.add_child(confirmation_layer)

	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	confirmation_layer.add_child(overlay)

	var center_container := CenterContainer.new()
	center_container.name = "CenterContainer"
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Unlike the startup tutorial prompt, the in-game confirmation must sit
	# on the exact geometric center of the screen.
	overlay.add_child(center_container)

	var choice_slot := Control.new()
	choice_slot.name = "ConfirmationChoiceSlot"
	choice_slot.custom_minimum_size = Vector2(400.0, 227.2)
	center_container.add_child(choice_slot)

	var choice_panel := Control.new()
	choice_panel.name = "ConfirmationChoicePanel"
	choice_panel.position = Vector2.ZERO
	choice_panel.size = Vector2(500.0, 284.0)
	choice_panel.scale = Vector2(0.8, 0.8)
	choice_slot.add_child(choice_panel)

	var frame_texture := TextureRect.new()
	frame_texture.name = "FrameTexture"
	frame_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_texture.texture = CONFIRMATION_FRAME_TEXTURE
	frame_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	choice_panel.add_child(frame_texture)

	confirmation_title_label = Label.new()
	confirmation_title_label.name = "TitleLabel"
	confirmation_title_label.position = Vector2(70.0, 66.0)
	confirmation_title_label.size = Vector2(360.0, 60.0)
	confirmation_title_label.add_theme_color_override("font_color", Color.WHITE)
	confirmation_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	confirmation_title_label.add_theme_constant_override("outline_size", 4)
	confirmation_title_label.add_theme_font_override("font", CONFIRMATION_FONT)
	confirmation_title_label.add_theme_font_size_override("font_size", 30)
	confirmation_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirmation_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	choice_panel.add_child(confirmation_title_label)

	confirmation_yes_button = _create_confirmation_button(
		"YesButton",
		Vector2(96.0, 151.0),
		Vector2(126.0, 57.0)
	)
	confirmation_yes_button.pressed.connect(_on_confirmation_yes_pressed)
	choice_panel.add_child(confirmation_yes_button)

	confirmation_back_button = _create_confirmation_button(
		"BackButton",
		Vector2(278.0, 151.0),
		Vector2(126.0, 57.0)
	)
	confirmation_back_button.pressed.connect(_on_confirmation_back_pressed)
	choice_panel.add_child(confirmation_back_button)

	confirmation_layer.visible = false
	return true


func _create_confirmation_button(
	button_name: String,
	button_position: Vector2,
	button_size: Vector2
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.position = button_position
	button.size = button_size
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_font_override("font", CONFIRMATION_FONT)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_stylebox_override("normal", CONFIRMATION_BUTTON_NORMAL)
	button.add_theme_stylebox_override("hover", CONFIRMATION_BUTTON_HOVER)
	button.add_theme_stylebox_override("pressed", CONFIRMATION_BUTTON_HOVER)
	button.add_theme_stylebox_override("focus", CONFIRMATION_BUTTON_HOVER)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_confirmation_back_pressed() -> void:
	pending_confirmation_action = StringName()
	if confirmation_layer != null and is_instance_valid(confirmation_layer):
		confirmation_layer.visible = false


func _on_confirmation_yes_pressed() -> void:
	var confirmed_action := pending_confirmation_action
	pending_confirmation_action = StringName()

	if confirmation_yes_button != null:
		confirmation_yes_button.disabled = true
	if confirmation_back_button != null:
		confirmation_back_button.disabled = true
	if confirmation_layer != null and is_instance_valid(confirmation_layer):
		confirmation_layer.visible = false

	match confirmed_action:
		CONFIRM_ACTION_MAIN_MENU:
			_confirm_return_to_main_menu()
		CONFIRM_ACTION_QUIT_GAME:
			Engine.time_scale = 1.0
			get_tree().quit()


func _confirm_return_to_main_menu() -> void:
	var scene_error: Error = save_system.call("return_to_main_menu") as Error
	if scene_error == OK:
		return

	menu_open = true
	Engine.time_scale = 0.0
	_show_action_menu()


func _get_confirmation_text() -> String:
	match LocalizationManager.get_current_locale():
		"en":
			return "Are you sure?"
		"fr":
			return "Êtes-vous sûr ?"
		"de":
			return "Bist du sicher?"
		"uk":
			return "Ви впевнені?"
		_:
			return "Вы уверены?"


func _clear_confirmation_dialog() -> void:
	pending_confirmation_action = StringName()
	if confirmation_layer != null and is_instance_valid(confirmation_layer):
		confirmation_layer.queue_free()
	confirmation_layer = null
	confirmation_title_label = null
	confirmation_yes_button = null
	confirmation_back_button = null


func _close_menu(restore_previous_speed: bool) -> void:
	menu_open = false
	current_slot_mode = ""
	if menu_root != null:
		menu_root.visible = false
	if main_menu_grid != null:
		main_menu_grid.visible = true
	if restore_previous_speed:
		Engine.time_scale = menu_previous_time_scale


func _on_slot_pressed(slot_index: int) -> void:
	if current_slot_mode == "save":
		save_system.call("save_game", slot_index)
		_show_slot_menu()
		return

	if current_slot_mode == "load":
		var load_succeeded: bool = await save_system.call("load_game", slot_index)
		if load_succeeded:
			_close_menu(false)
		else:
			_show_slot_menu()


func _add_save_menu_title() -> void:
	var title_label := Label.new()
	title_label.name = "SaveMenuTitle"
	title_label.theme_type_variation = &"HeaderLabel"
	title_label.custom_minimum_size = Vector2(260.0, LOAD_MENU_BUTTON_HEIGHT)
	title_label.text = tr("MENU_SAVE")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 19)
	menu_vbox.add_child(title_label)


func _add_title_label(title_text: String) -> void:
	var title_label := Label.new()
	title_label.theme_type_variation = &"HeaderLabel"
	title_label.custom_minimum_size = Vector2(260.0, 24.0)
	title_label.text = tr(title_text)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	menu_vbox.add_child(title_label)


func _add_menu_button(button_text: String, callback: Callable, height: float = 44.0) -> Button:
	var button := _create_styled_button()
	button.custom_minimum_size = Vector2(260.0, height)
	button.text = tr(button_text)
	button.pressed.connect(callback)
	menu_vbox.add_child(button)
	return button


func _add_action_menu_button(
	button_text: String,
	callback: Callable,
	button_name: String
) -> Button:
	var button := _create_styled_button()
	button.name = button_name
	button.custom_minimum_size = ACTION_MENU_BUTTON_SIZE
	button.text = _get_action_menu_button_text(button_text)
	button.pressed.connect(callback)
	action_menu_grid.add_child(button)
	return button


func _get_action_menu_button_text(translation_key: String) -> String:
	var translated_text := tr(translation_key)
	if translation_key != "MENU_MAIN_MENU" and translation_key != "MENU_QUIT_GAME":
		return translated_text
	var separator_index := translated_text.find(" ")
	if separator_index < 0:
		return translated_text
	return translated_text.left(separator_index) + "\n" + translated_text.substr(separator_index + 1)


func _create_styled_button() -> Button:
	if button_template != null and is_instance_valid(button_template):
		var duplicated_node: Node = button_template.duplicate()
		var duplicated_button := duplicated_node as Button
		if duplicated_button != null:
			duplicated_button.name = "DynamicMenuButton"
			duplicated_button.tooltip_text = ""
			duplicated_button.disabled = false
			duplicated_button.focus_mode = Control.FOCUS_ALL
			duplicated_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return duplicated_button
	var fallback_button := Button.new()
	fallback_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fallback_button.add_theme_font_size_override("font_size", 18)
	return fallback_button


func _clear_menu_vbox() -> void:
	if menu_vbox == null:
		return
	for child: Node in menu_vbox.get_children():
		menu_vbox.remove_child(child)
		child.queue_free()


func _clear_action_menu_grid() -> void:
	if action_menu_grid == null:
		return
	for child: Node in action_menu_grid.get_children():
		action_menu_grid.remove_child(child)
		child.queue_free()


func _prepare_vbox_menu() -> void:
	if action_menu_grid != null:
		action_menu_grid.visible = false
	if menu_vbox != null:
		menu_vbox.visible = true


func _on_audio_settings_pressed() -> void:
	_show_audio_settings_menu()

func _show_audio_settings_menu() -> void:
	_prepare_vbox_menu()
	_clear_menu_vbox()
	menu_vbox.add_theme_constant_override(
		"separation",
		SETTINGS_MENU_ROW_SEPARATION
	)
	_add_title_label("SETTINGS_TITLE")

	var title_label := menu_vbox.get_child(
		menu_vbox.get_child_count() - 1
	) as Label
	_apply_ingame_settings_label_style(
		title_label,
		18,
		260.0,
		HORIZONTAL_ALIGNMENT_CENTER
	)

	_add_language_control()
	_add_ingame_display_mode_control()
	_add_ingame_resolution_control()
	_add_audio_volume_control(
		"SETTINGS_MUSIC",
		AudioManager.get_music_volume(),
		"music"
	)
	_add_audio_volume_control(
		"SETTINGS_SOUNDS",
		AudioManager.get_sound_volume(),
		"sounds"
	)

	# Keep the Settings Back button 10 px higher than in the previous layout.
	# Button height stays unchanged; only the spacer above it is reduced by 10 px.
	var back_spacer := Control.new()
	back_spacer.name = "SettingsBackSpacer"
	back_spacer.custom_minimum_size = Vector2(260.0, SETTINGS_BACK_SPACER_HEIGHT)
	back_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_vbox.add_child(back_spacer)
	_add_menu_button(
		"MENU_BACK",
		_on_audio_settings_back_pressed,
		SETTINGS_BACK_BUTTON_HEIGHT
	)
	_place_settings_menu_root()


func _place_settings_menu_root() -> void:
	if menu_root == null or not is_instance_valid(menu_root):
		return
	menu_root.size = ACTION_MENU_ROOT_SIZE
	menu_root.position = ACTION_MENU_ROOT_POSITION
	menu_root.set_deferred("size", ACTION_MENU_ROOT_SIZE)
	menu_root.set_deferred("position", ACTION_MENU_ROOT_POSITION)

func _add_language_control() -> void:
	var row := _create_ingame_settings_row("InGameLanguageRow")
	_add_ingame_settings_label(
		row,
		"InGameLanguageLabel",
		tr("SETTINGS_LANGUAGE")
	)

	var language_option := OptionButton.new()
	language_option.name = "InGameLanguageOption"
	_configure_ingame_option_button(language_option)

	for option_data: Dictionary in LANGUAGE_OPTIONS:
		var item_index := language_option.item_count
		var locale := String(option_data["locale"])
		language_option.add_item(String(option_data["name"]))
		language_option.set_item_metadata(item_index, locale)

		if locale == LocalizationManager.get_current_locale():
			language_option.select(item_index)

	language_option.item_selected.connect(
		_on_ingame_language_selected.bind(language_option)
	)
	row.add_child(language_option)

func _on_ingame_language_selected(
	index: int,
	language_option: OptionButton
) -> void:
	if index < 0 or index >= language_option.item_count:
		return

	LocalizationManager.set_locale(
		String(language_option.get_item_metadata(index))
	)
	_show_audio_settings_menu()

func _add_ingame_display_mode_control() -> void:
	var row := _create_ingame_settings_row("InGameDisplayModeRow")
	_add_ingame_settings_label(
		row,
		"InGameDisplayModeLabel",
		tr("SETTINGS_SCREEN_MODE")
	)

	var mode_option := OptionButton.new()
	mode_option.name = "InGameDisplayModeOption"
	_configure_ingame_option_button(mode_option)
	mode_option.add_item(tr("SETTINGS_WINDOWED"))
	mode_option.add_item(tr("SETTINGS_FULLSCREEN"))
	mode_option.select(1 if DisplaySettings.is_fullscreen() else 0)
	mode_option.item_selected.connect(
		_on_ingame_display_mode_selected
	)
	row.add_child(mode_option)

func _on_ingame_display_mode_selected(index: int) -> void:
	DisplaySettings.set_fullscreen(index == 1)
	_show_audio_settings_menu()

func _add_ingame_resolution_control() -> void:
	var row := _create_ingame_settings_row("InGameResolutionRow")
	_add_ingame_settings_label(
		row,
		"InGameResolutionLabel",
		tr("SETTINGS_RESOLUTION")
	)

	var resolution_option := OptionButton.new()
	resolution_option.name = "InGameResolutionOption"
	_configure_ingame_option_button(resolution_option)

	for resolution: Vector2i in DisplaySettings.SUPPORTED_WINDOW_SIZES:
		resolution_option.add_item(
			"%d×%d" % [resolution.x, resolution.y]
		)

	resolution_option.select(
		clampi(
			DisplaySettings.get_resolution_index(),
			0,
			resolution_option.item_count - 1
		)
	)
	resolution_option.disabled = DisplaySettings.is_fullscreen()
	resolution_option.item_selected.connect(
		_on_ingame_resolution_selected
	)
	row.add_child(resolution_option)

func _on_ingame_resolution_selected(index: int) -> void:
	DisplaySettings.set_resolution_index(index)
	_show_audio_settings_menu()

func _add_audio_volume_control(
	label_prefix: String,
	initial_value: float,
	setting_name: String
) -> void:
	var row_name := (
		"InGameMusicVolumeRow"
		if setting_name == "music"
		else "InGameSoundVolumeRow"
	)
	var row := _create_ingame_settings_row(row_name)
	var value_label := _add_ingame_settings_label(
		row,
		"MusicVolumeLabel"
		if setting_name == "music"
		else "SoundVolumeLabel",
		""
	)
	_update_compact_audio_value_label(
		value_label,
		label_prefix,
		initial_value * 100.0
	)

	var slider := HSlider.new()
	slider.name = (
		"InGameMusicVolumeSlider"
		if setting_name == "music"
		else "InGameSoundVolumeSlider"
	)
	slider.custom_minimum_size = INGAME_SETTINGS_CONTROL_SIZE
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial_value * 100.0
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(
		_on_compact_audio_volume_changed.bind(
			value_label,
			label_prefix,
			setting_name
		)
	)
	row.add_child(slider)

func _on_compact_audio_volume_changed(
	value: float,
	value_label: Label,
	label_prefix: String,
	setting_name: String
) -> void:
	var normalized_value := clampf(value / 100.0, 0.0, 1.0)

	if setting_name == "music":
		AudioManager.set_music_volume(normalized_value)
	else:
		AudioManager.set_sound_volume(normalized_value)

	_update_compact_audio_value_label(
		value_label,
		label_prefix,
		value
	)

func _update_compact_audio_value_label(
	value_label: Label,
	label_prefix: String,
	value: float
) -> void:
	if value_label == null:
		return

	value_label.text = "%s: %d%%" % [
		tr(label_prefix),
		roundi(value)
	]
	_fit_ingame_settings_label(
		value_label,
		INGAME_SETTINGS_LABEL_FONT_SIZE,
		INGAME_SETTINGS_LABEL_CONTENT_WIDTH
	)

func _create_ingame_settings_row(
	row_name: String
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.custom_minimum_size = INGAME_SETTINGS_ROW_SIZE
	row.add_theme_constant_override(
		"separation",
		INGAME_SETTINGS_ROW_SEPARATION
	)
	menu_vbox.add_child(row)
	return row

func _add_ingame_settings_label(
	row: HBoxContainer,
	label_name: String,
	label_text: String
) -> Label:
	var label_slot := MarginContainer.new()
	label_slot.name = "%sArea" % label_name
	label_slot.custom_minimum_size = INGAME_SETTINGS_LABEL_SLOT_SIZE
	label_slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label_slot.add_theme_constant_override(
		"margin_left",
		INGAME_SETTINGS_LABEL_INSET_LEFT
	)
	label_slot.add_theme_constant_override("margin_top", 0)
	label_slot.add_theme_constant_override("margin_right", 0)
	label_slot.add_theme_constant_override("margin_bottom", 0)
	row.add_child(label_slot)

	var label := Label.new()
	label.name = label_name
	label.custom_minimum_size = Vector2(
		INGAME_SETTINGS_LABEL_CONTENT_WIDTH,
		INGAME_SETTINGS_ROW_SIZE.y
	)
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label_slot.add_child(label)

	_apply_ingame_settings_label_style(
		label,
		INGAME_SETTINGS_LABEL_FONT_SIZE,
		INGAME_SETTINGS_LABEL_CONTENT_WIDTH,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	return label

func _apply_ingame_settings_label_style(
	label: Label,
	preferred_font_size: int,
	maximum_width: float,
	alignment: HorizontalAlignment
) -> void:
	if label == null:
		return

	label.horizontal_alignment = alignment
	label.add_theme_color_override(
		"font_outline_color",
		Color.BLACK
	)
	label.add_theme_constant_override(
		"outline_size",
		INGAME_SETTINGS_OUTLINE_SIZE
	)
	_fit_ingame_settings_label(
		label,
		preferred_font_size,
		maximum_width
	)

func _fit_ingame_settings_label(
	label: Label,
	preferred_font_size: int,
	maximum_width: float
) -> void:
	if label == null:
		return

	var font := label.get_theme_font("font")
	if font == null:
		return

	for font_size: int in range(
		preferred_font_size,
		INGAME_SETTINGS_LABEL_MIN_FONT_SIZE - 1,
		-1
	):
		var text_width := font.get_string_size(
			label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		).x

		if text_width <= maximum_width:
			label.add_theme_font_size_override(
				"font_size",
				font_size
			)
			return

	label.add_theme_font_size_override(
		"font_size",
		INGAME_SETTINGS_LABEL_MIN_FONT_SIZE
	)

func _configure_ingame_option_button(
	option: OptionButton
) -> void:
	option.custom_minimum_size = INGAME_SETTINGS_CONTROL_SIZE
	option.focus_mode = Control.FOCUS_ALL
	option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	option.alignment = HORIZONTAL_ALIGNMENT_CENTER
	option.fit_to_longest_item = false
	option.add_theme_font_size_override(
		"font_size",
		INGAME_SETTINGS_OPTION_FONT_SIZE
	)
	option.add_theme_constant_override("arrow_margin", 0)
	option.add_theme_icon_override(
		"arrow",
		_get_ingame_transparent_option_arrow()
	)

func _get_ingame_transparent_option_arrow() -> Texture2D:
	if ingame_transparent_option_arrow != null:
		return ingame_transparent_option_arrow

	var image := Image.create_empty(
		1,
		1,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	ingame_transparent_option_arrow = (
		ImageTexture.create_from_image(image)
	)
	return ingame_transparent_option_arrow

func _on_audio_settings_back_pressed() -> void:
	_show_action_menu()

func _refresh_menu_tooltip() -> void:
	if menu_button == null:
		return

	menu_button.tooltip_text = tr("MENU_TOOLTIP_WITH_SETTINGS")

func _cancel_active_nature_targeting() -> void:
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	if nature_ui != null and nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")
	var player_flags := get_node_or_null("/root/PlayerFlags")
	if player_flags != null and player_flags.has_method("cancel_targeting"):
		player_flags.call("cancel_targeting")
