extends Node

const START_SCREEN_SCENE_PATH := "res://scenes/ui/start_screen.tscn"
const SLOT_COUNT := 3
const NATURE_MENU_ATTACH_RETRY_FRAMES := 16
const MENU_ROOT_POSITION := Vector2(-2.0, 94.0)
const MENU_ROOT_SIZE := Vector2(260.0, 218.0)
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

var save_system: Node = null
var attached_scene_id := 0
var menu_button: Button = null
var main_menu_grid: Control = null
var menu_root: Control = null
var menu_vbox: VBoxContainer = null
var button_template: Button = null
var menu_open := false
var menu_previous_time_scale := 1.0
var current_slot_mode := ""
var status_message := ""
var ingame_transparent_option_arrow: ImageTexture = null


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
	_add_menu_button("MENU_SAVE", _on_save_mode_pressed, 27.0)
	_add_menu_button("MENU_LOAD_ACTION", _on_load_mode_pressed, 27.0)
	_add_menu_button("MENU_SETTINGS", _on_audio_settings_pressed, 27.0)
	_add_menu_button("MENU_MAIN_MENU", _on_main_menu_pressed, 27.0)
	_add_menu_button("MENU_QUIT_GAME", _on_quit_game_pressed, 27.0)
	_add_menu_button("MENU_BACK", _on_close_menu_pressed, 27.0)

	if not status_message.is_empty():
		_add_status_label(status_message)

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
		autosave_button.disabled = not bool(save_system.call("has_autosave"))
		autosave_button.pressed.connect(_on_autosave_slot_pressed)
		menu_vbox.add_child(autosave_button)
		apply_save_button_text(autosave_button, String(save_system.call("get_autosave_button_text")), 18, 12)

	for slot_index: int in range(1, SLOT_COUNT + 1):
		var slot_button: Button = _create_styled_button()
		slot_button.custom_minimum_size = Vector2(260.0, 40.0)

		var slot_is_empty: bool = not bool(save_system.call("has_save", slot_index))

		if current_slot_mode == "load":
			slot_button.disabled = slot_is_empty

		slot_button.pressed.connect(_on_slot_pressed.bind(slot_index))
		menu_vbox.add_child(slot_button)
		apply_save_button_text(slot_button, String(save_system.call("get_slot_button_text", slot_index)), 18, 12)

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
	if not bool(save_system.call("has_autosave")):
		return

	status_message = tr("STATUS_LOADING_AUTOSAVE")
	_show_slot_menu()
	var load_succeeded: bool = await save_system.call("load_autosave")

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
	save_system.call("_reset_active_game_session")

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
		var save_succeeded: bool = bool(save_system.call("save_game", slot_index))

		if save_succeeded:
			status_message = tr("STATUS_SAVE_OK") % slot_index
		else:
			status_message = tr("STATUS_SAVE_FAILED") % slot_index

		_show_slot_menu()
		return

	if current_slot_mode == "load":
		var load_succeeded: bool = await save_system.call("load_game", slot_index)

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

func _on_audio_settings_pressed() -> void:
	status_message = ""
	_show_audio_settings_menu()

func _show_audio_settings_menu() -> void:
	_clear_menu_vbox()
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
	_add_menu_button("MENU_BACK", _on_audio_settings_back_pressed, 27.0)

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

func _cancel_active_nature_targeting() -> void:
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	if nature_ui != null and nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")
	var player_flags := get_node_or_null("/root/PlayerFlags")
	if player_flags != null and player_flags.has_method("cancel_targeting"):
		player_flags.call("cancel_targeting")
