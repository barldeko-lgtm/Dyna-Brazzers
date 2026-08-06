extends Node

signal display_settings_changed

const CONFIG_PATH := "user://display_settings.cfg"
const CONFIG_SECTION := "display"
const BASE_CONTENT_SIZE := Vector2i(1366, 768)
const SUPPORTED_WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const DEFAULT_RESOLUTION_INDEX := 0
const TARGET_ASPECT := 16.0 / 9.0
const ASPECT_EPSILON := 0.01
const SETTINGS_ROW_SIZE := Vector2(286.0, 38.0)
const SETTINGS_LABEL_SIZE := Vector2(118.0, 38.0)
const SETTINGS_OPTION_SIZE := Vector2(140.0, 38.0)
const SETTINGS_OUTLINE_SIZE := 2
const SETTINGS_LABEL_INSET_LEFT := 10
const SETTINGS_LABEL_MIN_FONT_SIZE := 13
const SETTINGS_LABEL_CONTENT_WIDTH := 108.0
const VOLUME_ROW_SIZE := Vector2(286.0, 28.0)
const VOLUME_LABEL_SIZE := Vector2(104.0, 28.0)
const VOLUME_SLIDER_SIZE := Vector2(174.0, 28.0)
const LOAD_MENU_BUTTON_SIZE := Vector2(250.0, 55.0)
const START_MENU_TOP_MARGIN := 58

var fullscreen_enabled := false
var resolution_index := DEFAULT_RESOLUTION_INDEX

var injected_start_screen: Control = null
var mode_row: HBoxContainer = null
var mode_label: Label = null
var mode_option: OptionButton = null
var resolution_row: HBoxContainer = null
var resolution_label: Label = null
var resolution_option: OptionButton = null
var music_volume_row: HBoxContainer = null
var sound_volume_row: HBoxContainer = null
var transparent_option_arrow: ImageTexture = null
var window_geometry_revision := 0


func _ready() -> void:
	_load_settings()
	_apply_content_scaling()
	_apply_current_settings()
	get_tree().scene_changed.connect(_on_scene_changed)
	LocalizationManager.locale_changed.connect(_on_locale_changed)
	call_deferred("_try_inject_start_screen_controls")


func is_fullscreen() -> bool:
	return fullscreen_enabled


func get_resolution_index() -> int:
	return resolution_index


func set_fullscreen(enabled: bool) -> void:
	if fullscreen_enabled == enabled:
		_sync_injected_controls()
		return

	fullscreen_enabled = enabled
	_apply_current_settings()
	_save_settings()
	_sync_injected_controls()
	display_settings_changed.emit()


func set_resolution_index(index: int) -> void:
	var safe_index := clampi(index, 0, SUPPORTED_WINDOW_SIZES.size() - 1)
	if resolution_index == safe_index:
		_sync_injected_controls()
		return

	resolution_index = safe_index
	if not fullscreen_enabled:
		_apply_windowed_mode()
	_save_settings()
	_sync_injected_controls()
	display_settings_changed.emit()


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		fullscreen_enabled = false
		resolution_index = DEFAULT_RESOLUTION_INDEX
		return

	fullscreen_enabled = bool(config.get_value(CONFIG_SECTION, "fullscreen", false))
	resolution_index = clampi(
		int(config.get_value(CONFIG_SECTION, "resolution_index", DEFAULT_RESOLUTION_INDEX)),
		0,
		SUPPORTED_WINDOW_SIZES.size() - 1
	)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(CONFIG_SECTION, "fullscreen", fullscreen_enabled)
	config.set_value(CONFIG_SECTION, "resolution_index", resolution_index)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("DisplaySettings: could not save display settings (%d)." % error)


func _apply_content_scaling() -> void:
	var root_window := get_tree().root
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root_window.content_scale_size = BASE_CONTENT_SIZE


func _apply_current_settings() -> void:
	if fullscreen_enabled:
		_apply_fullscreen_mode()
	else:
		_apply_windowed_mode()


func _apply_fullscreen_mode() -> void:
	window_geometry_revision += 1

	var root_window := get_tree().root
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_index)
	root_window.content_scale_aspect = (
		Window.CONTENT_SCALE_ASPECT_EXPAND
		if _is_near_target_aspect(screen_size)
		else Window.CONTENT_SCALE_ASPECT_KEEP
	)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _apply_windowed_mode() -> void:
	window_geometry_revision += 1
	var geometry_revision := window_geometry_revision

	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	call_deferred("_apply_windowed_geometry", geometry_revision)


func _apply_windowed_geometry(geometry_revision: int) -> void:
	await get_tree().process_frame
	if not _is_current_windowed_geometry_request(geometry_revision):
		return

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MAXIMIZE_DISABLED, true)

	var requested_client_size := SUPPORTED_WINDOW_SIZES[resolution_index]
	DisplayServer.window_set_size(requested_client_size)

	await get_tree().process_frame
	if not _is_current_windowed_geometry_request(geometry_revision):
		return

	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	var current_client_size := DisplayServer.window_get_size()
	var decorated_size := DisplayServer.window_get_size_with_decorations()
	var decoration_size := Vector2i(
		maxi(decorated_size.x - current_client_size.x, 0),
		maxi(decorated_size.y - current_client_size.y, 0)
	)
	var maximum_client_size := Vector2i(
		maxi(usable_rect.size.x - decoration_size.x, 64),
		maxi(usable_rect.size.y - decoration_size.y, 64)
	)
	var fitted_client_size := _fit_size_inside(requested_client_size, maximum_client_size)

	if current_client_size != fitted_client_size:
		DisplayServer.window_set_size(fitted_client_size)
		await get_tree().process_frame
		if not _is_current_windowed_geometry_request(geometry_revision):
			return

	_center_decorated_window_in_usable_rect(usable_rect)


func _is_current_windowed_geometry_request(geometry_revision: int) -> bool:
	return (
		not fullscreen_enabled
		and geometry_revision == window_geometry_revision
		and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
	)


func _fit_size_inside(requested_size: Vector2i, maximum_size: Vector2i) -> Vector2i:
	if requested_size.x <= maximum_size.x and requested_size.y <= maximum_size.y:
		return requested_size

	var scale_factor := minf(
		float(maximum_size.x) / float(maxi(requested_size.x, 1)),
		float(maximum_size.y) / float(maxi(requested_size.y, 1))
	)
	scale_factor = clampf(scale_factor, 0.01, 1.0)
	return Vector2i(
		maxi(int(floor(float(requested_size.x) * scale_factor)), 64),
		maxi(int(floor(float(requested_size.y) * scale_factor)), 64)
	)


func _center_decorated_window_in_usable_rect(usable_rect: Rect2i) -> void:
	var client_position := DisplayServer.window_get_position()
	var decorated_position := DisplayServer.window_get_position_with_decorations()
	var decoration_offset := client_position - decorated_position
	var decorated_size := DisplayServer.window_get_size_with_decorations()
	var target_decorated_position := (
		usable_rect.position + (usable_rect.size - decorated_size) / 2
	)
	DisplayServer.window_set_position(target_decorated_position + decoration_offset)


func _is_near_target_aspect(size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	return absf(float(size.x) / float(size.y) - TARGET_ASPECT) <= ASPECT_EPSILON


func _on_scene_changed() -> void:
	injected_start_screen = null
	mode_row = null
	mode_label = null
	mode_option = null
	resolution_row = null
	resolution_label = null
	resolution_option = null
	music_volume_row = null
	sound_volume_row = null
	call_deferred("_try_inject_start_screen_controls")


func _try_inject_start_screen_controls() -> void:
	var scene_root := get_tree().current_scene as Control
	if scene_root == null:
		return

	var menu_vbox := scene_root.get_node_or_null(
		"CenterContainer/MenuPanel/MarginContainer/VBoxContainer"
	) as VBoxContainer
	if menu_vbox == null:
		return

	var language_row := menu_vbox.get_node_or_null("LanguageRow") as HBoxContainer
	var language_label := _find_named_label(language_row, "LanguageLabel")
	var language_option := _find_named_option(language_row, "LanguageOption")
	if language_row == null or language_label == null or language_option == null:
		call_deferred("_try_inject_start_screen_controls")
		return

	injected_start_screen = scene_root
	var existing_mode_row := menu_vbox.get_node_or_null("DisplayModeRow") as HBoxContainer
	if existing_mode_row != null:
		mode_row = existing_mode_row
		mode_label = _find_named_label(mode_row, "DisplayModeLabel")
		mode_option = _find_named_option(mode_row, "DisplayModeOption")
		resolution_row = menu_vbox.get_node_or_null("ResolutionRow") as HBoxContainer
		if resolution_row != null:
			resolution_label = _find_named_label(resolution_row, "ResolutionLabel")
			resolution_option = _find_named_option(resolution_row, "ResolutionOption")
	else:
		mode_row = _create_option_row(
			"DisplayModeRow",
			"DisplayModeLabel",
			"DisplayModeOption",
			language_option
		)
		resolution_row = _create_option_row(
			"ResolutionRow",
			"ResolutionLabel",
			"ResolutionOption",
			language_option
		)
		menu_vbox.add_child(mode_row)
		menu_vbox.add_child(resolution_row)
		menu_vbox.move_child(mode_row, language_row.get_index() + 1)
		menu_vbox.move_child(resolution_row, mode_row.get_index() + 1)

		mode_label = _find_named_label(mode_row, "DisplayModeLabel")
		mode_option = _find_named_option(mode_row, "DisplayModeOption")
		resolution_label = _find_named_label(resolution_row, "ResolutionLabel")
		resolution_option = _find_named_option(resolution_row, "ResolutionOption")

		mode_row.visible = false
		resolution_row.visible = false
		_register_with_start_screen_settings(scene_root, mode_row)
		_register_with_start_screen_settings(scene_root, resolution_row)

		mode_option.item_selected.connect(_on_mode_selected)
		resolution_option.item_selected.connect(_on_resolution_selected)

	_configure_volume_rows(scene_root, menu_vbox)
	_configure_settings_menu_visuals(
		menu_vbox,
		language_row,
		language_label,
		language_option
	)
	_configure_load_menu_layout(scene_root, menu_vbox)
	_configure_settings_menu_open_refresh(menu_vbox)
	_refresh_injected_text()
	_sync_injected_controls()
	call_deferred("_refresh_settings_label_fitting")


func _create_option_row(
	row_name: String,
	label_name: String,
	option_name: String,
	style_source: OptionButton
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.custom_minimum_size = SETTINGS_ROW_SIZE
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.name = label_name
	label.custom_minimum_size = SETTINGS_LABEL_SIZE
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var option := OptionButton.new()
	option.name = option_name
	option.focus_mode = Control.FOCUS_ALL
	option.add_theme_font_override("font", style_source.get_theme_font("font"))
	option.add_theme_font_size_override("font_size", 16)
	_configure_settings_option_button(option)
	row.add_child(option)
	return row


func _configure_settings_menu_visuals(
	menu_vbox: VBoxContainer,
	language_row: HBoxContainer,
	language_label: Label,
	language_option: OptionButton
) -> void:
	language_row.custom_minimum_size = SETTINGS_ROW_SIZE
	_ensure_settings_label_slot(
		language_row,
		language_label,
		"LanguageLabelArea"
	)
	_configure_settings_option_button(language_option)

	if mode_row != null and mode_label != null:
		mode_row.custom_minimum_size = SETTINGS_ROW_SIZE
		_ensure_settings_label_slot(
			mode_row,
			mode_label,
			"DisplayModeLabelArea"
		)
	if resolution_row != null and resolution_label != null:
		resolution_row.custom_minimum_size = SETTINGS_ROW_SIZE
		_ensure_settings_label_slot(
			resolution_row,
			resolution_label,
			"ResolutionLabelArea"
		)
	if mode_option != null:
		_configure_settings_option_button(mode_option)
	if resolution_option != null:
		_configure_settings_option_button(resolution_option)

	_apply_settings_label_outline(
		_find_named_label(menu_vbox, "AudioSettingsTitle")
	)
	_apply_settings_label_outline(language_label)
	_apply_settings_label_outline(mode_label)
	_apply_settings_label_outline(resolution_label)
	_apply_settings_label_outline(
		_find_named_label(menu_vbox, "MusicVolumeLabel")
	)
	_apply_settings_label_outline(
		_find_named_label(menu_vbox, "SoundVolumeLabel")
	)


func _ensure_settings_label_slot(
	row: HBoxContainer,
	label: Label,
	slot_name: String
) -> void:
	if row == null or label == null:
		return

	var slot := label.get_parent() as MarginContainer
	if slot == null or slot.name != slot_name:
		var insertion_index := label.get_index()
		var previous_parent := label.get_parent()
		if previous_parent != null:
			previous_parent.remove_child(label)

		slot = MarginContainer.new()
		slot.name = slot_name
		row.add_child(slot)
		row.move_child(
			slot,
			clampi(insertion_index, 0, row.get_child_count() - 1)
		)
		slot.add_child(label)

	slot.custom_minimum_size = SETTINGS_LABEL_SIZE
	slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slot.add_theme_constant_override(
		"margin_left",
		SETTINGS_LABEL_INSET_LEFT
	)
	slot.add_theme_constant_override("margin_top", 0)
	slot.add_theme_constant_override("margin_right", 0)
	slot.add_theme_constant_override("margin_bottom", 0)

	label.custom_minimum_size = Vector2(
		SETTINGS_LABEL_CONTENT_WIDTH,
		SETTINGS_LABEL_SIZE.y
	)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true


func _configure_volume_rows(
	scene_root: Control,
	menu_vbox: VBoxContainer
) -> void:
	music_volume_row = _ensure_volume_row(
		scene_root,
		menu_vbox,
		"MusicVolumeRow",
		"MusicVolumeLabel",
		"MusicVolumeSlider"
	)
	sound_volume_row = _ensure_volume_row(
		scene_root,
		menu_vbox,
		"SoundVolumeRow",
		"SoundVolumeLabel",
		"SoundVolumeSlider"
	)


func _ensure_volume_row(
	scene_root: Control,
	menu_vbox: VBoxContainer,
	row_name: String,
	label_name: String,
	slider_name: String
) -> HBoxContainer:
	var label := _find_named_label(menu_vbox, label_name)
	var slider := _find_named_slider(menu_vbox, slider_name)
	if label == null or slider == null:
		push_warning(
			"DisplaySettings: volume controls '%s'/'%s' were not found."
			% [label_name, slider_name]
		)
		return null

	var row := menu_vbox.get_node_or_null(row_name) as HBoxContainer
	if row == null:
		var insertion_index := mini(label.get_index(), slider.get_index())

		var label_parent := label.get_parent()
		var slider_parent := slider.get_parent()
		if label_parent != null:
			label_parent.remove_child(label)
		if slider_parent != null:
			slider_parent.remove_child(slider)

		row = HBoxContainer.new()
		row.name = row_name
		menu_vbox.add_child(row)
		menu_vbox.move_child(
			row,
			clampi(insertion_index, 0, menu_vbox.get_child_count() - 1)
		)
		row.add_child(label)
		row.add_child(slider)
		row.visible = false

	row.custom_minimum_size = VOLUME_ROW_SIZE
	row.add_theme_constant_override("separation", 8)

	label.custom_minimum_size = VOLUME_LABEL_SIZE
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.visible = true

	slider.custom_minimum_size = VOLUME_SLIDER_SIZE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.visible = true

	var value_changed_callable := Callable(
		self,
		"_on_volume_value_changed"
	)
	if not slider.value_changed.is_connected(value_changed_callable):
		slider.value_changed.connect(value_changed_callable)

	_replace_start_screen_settings_controls(
		scene_root,
		[label, slider],
		row
	)
	return row


func _replace_start_screen_settings_controls(
	scene_root: Control,
	old_controls: Array,
	replacement: Control
) -> void:
	var settings_controls_variant: Variant = scene_root.get(
		"settings_controls"
	)
	if not (settings_controls_variant is Array):
		push_warning(
			"DisplaySettings: start-screen settings list was not found."
		)
		return

	var settings_controls: Array = settings_controls_variant
	for control: Control in old_controls:
		settings_controls.erase(control)
	if not settings_controls.has(replacement):
		settings_controls.append(replacement)
	scene_root.set("settings_controls", settings_controls)


func _configure_settings_menu_open_refresh(
	menu_vbox: VBoxContainer
) -> void:
	var settings_button := menu_vbox.get_node_or_null(
		"MenuButton"
	) as Button
	if settings_button == null:
		return

	var pressed_callable := Callable(
		self,
		"_on_start_screen_settings_pressed"
	)
	if not settings_button.pressed.is_connected(pressed_callable):
		settings_button.pressed.connect(pressed_callable)


func _on_start_screen_settings_pressed() -> void:
	call_deferred("_refresh_settings_label_fitting")


func _configure_load_menu_layout(
	scene_root: Control,
	menu_vbox: VBoxContainer
) -> void:
	var load_button := menu_vbox.get_node_or_null("LoadButton") as Button
	if load_button != null:
		var pressed_callable := Callable(
			self,
			"_on_start_screen_load_pressed"
		)
		if not load_button.pressed.is_connected(pressed_callable):
			load_button.pressed.connect(pressed_callable)

	_configure_load_menu_buttons(menu_vbox)
	var load_status_area := menu_vbox.get_node_or_null(
		"LoadStatusArea"
	) as Control
	if load_status_area != null:
		load_status_area.visible = false


func _configure_load_menu_buttons(menu_vbox: VBoxContainer) -> void:
	for button_name: String in [
		"AutosaveButton",
		"LoadSlot1Button",
		"LoadSlot2Button",
		"LoadSlot3Button",
		"LoadBackButton",
	]:
		var button := menu_vbox.get_node_or_null(button_name) as Button
		if button == null:
			continue
		button.custom_minimum_size = LOAD_MENU_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _on_start_screen_load_pressed() -> void:
	call_deferred("_apply_load_menu_layout")


func _apply_load_menu_layout() -> void:
	if injected_start_screen == null or not is_instance_valid(
		injected_start_screen
	):
		return

	var menu_margin := injected_start_screen.get_node_or_null(
		"CenterContainer/MenuPanel/MarginContainer"
	) as MarginContainer
	var menu_vbox := injected_start_screen.get_node_or_null(
		"CenterContainer/MenuPanel/MarginContainer/VBoxContainer"
	) as VBoxContainer
	if menu_margin == null or menu_vbox == null:
		return

	menu_margin.add_theme_constant_override(
		"margin_top",
		START_MENU_TOP_MARGIN
	)
	_configure_load_menu_buttons(menu_vbox)

	var load_status_area := menu_vbox.get_node_or_null(
		"LoadStatusArea"
	) as Control
	if load_status_area != null:
		load_status_area.visible = false
		load_status_area.custom_minimum_size = Vector2.ZERO

	var load_status_label := _find_named_label(
		menu_vbox,
		"LoadStatusLabel"
	)
	if load_status_label != null:
		load_status_label.text = ""


func _find_named_label(root: Node, node_name: String) -> Label:
	if root == null:
		return null
	return root.find_child(node_name, true, false) as Label


func _find_named_option(
	root: Node,
	node_name: String
) -> OptionButton:
	if root == null:
		return null
	return root.find_child(node_name, true, false) as OptionButton


func _find_named_slider(root: Node, node_name: String) -> HSlider:
	if root == null:
		return null
	return root.find_child(node_name, true, false) as HSlider


func _on_volume_value_changed(_value: float) -> void:
	call_deferred("_refresh_settings_label_fitting")


func _refresh_settings_label_fitting() -> void:
	if injected_start_screen == null or not is_instance_valid(
		injected_start_screen
	):
		return

	_fit_settings_label(
		_find_named_label(injected_start_screen, "LanguageLabel"),
		19,
		SETTINGS_LABEL_CONTENT_WIDTH
	)
	_fit_settings_label(mode_label, 17, SETTINGS_LABEL_CONTENT_WIDTH)
	_fit_settings_label(
		resolution_label,
		17,
		SETTINGS_LABEL_CONTENT_WIDTH
	)
	_fit_settings_label(
		_find_named_label(injected_start_screen, "MusicVolumeLabel"),
		17,
		VOLUME_LABEL_SIZE.x
	)
	_fit_settings_label(
		_find_named_label(injected_start_screen, "SoundVolumeLabel"),
		17,
		VOLUME_LABEL_SIZE.x
	)


func _fit_settings_label(
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
		SETTINGS_LABEL_MIN_FONT_SIZE - 1,
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
		SETTINGS_LABEL_MIN_FONT_SIZE
	)


func _configure_settings_option_button(option: OptionButton) -> void:
	if option == null:
		return

	option.custom_minimum_size = SETTINGS_OPTION_SIZE
	option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	option.alignment = HORIZONTAL_ALIGNMENT_CENTER
	option.fit_to_longest_item = false
	option.add_theme_constant_override("arrow_margin", 0)
	option.add_theme_icon_override("arrow", _get_transparent_option_arrow())


func _get_transparent_option_arrow() -> Texture2D:
	if transparent_option_arrow != null:
		return transparent_option_arrow

	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	transparent_option_arrow = ImageTexture.create_from_image(image)
	return transparent_option_arrow


func _apply_settings_label_outline(label: Label) -> void:
	if label == null:
		return

	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", SETTINGS_OUTLINE_SIZE)


func _register_with_start_screen_settings(
	scene_root: Control,
	control: Control
) -> void:
	var settings_controls_variant: Variant = scene_root.get(
		"settings_controls"
	)
	if not (settings_controls_variant is Array):
		push_warning("DisplaySettings: start-screen settings list was not found.")
		return

	var settings_controls: Array = settings_controls_variant
	if not settings_controls.has(control):
		settings_controls.append(control)
	scene_root.set("settings_controls", settings_controls)


func _on_mode_selected(index: int) -> void:
	set_fullscreen(index == 1)


func _on_resolution_selected(index: int) -> void:
	set_resolution_index(index)


func _on_locale_changed(_locale: String) -> void:
	_refresh_injected_text()
	call_deferred("_refresh_settings_label_fitting")


func _refresh_injected_text() -> void:
	if mode_label == null or mode_option == null:
		return

	mode_label.text = tr("SETTINGS_SCREEN_MODE")
	resolution_label.text = tr("SETTINGS_RESOLUTION")

	var selected_mode := 1 if fullscreen_enabled else 0
	mode_option.clear()
	mode_option.add_item(tr("SETTINGS_WINDOWED"))
	mode_option.add_item(tr("SETTINGS_FULLSCREEN"))
	mode_option.select(selected_mode)

	var selected_resolution := resolution_index
	resolution_option.clear()
	for resolution: Vector2i in SUPPORTED_WINDOW_SIZES:
		resolution_option.add_item("%d×%d" % [resolution.x, resolution.y])
	resolution_option.select(selected_resolution)
	call_deferred("_refresh_settings_label_fitting")


func _sync_injected_controls() -> void:
	if mode_option == null or resolution_option == null:
		return

	mode_option.select(1 if fullscreen_enabled else 0)
	resolution_option.select(resolution_index)
	resolution_option.disabled = fullscreen_enabled
