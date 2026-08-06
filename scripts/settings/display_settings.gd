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

var fullscreen_enabled := false
var resolution_index := DEFAULT_RESOLUTION_INDEX

var injected_start_screen: Control = null
var mode_row: HBoxContainer = null
var mode_label: Label = null
var mode_option: OptionButton = null
var resolution_row: HBoxContainer = null
var resolution_label: Label = null
var resolution_option: OptionButton = null


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
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	call_deferred("_apply_windowed_geometry")


func _apply_windowed_geometry() -> void:
	if fullscreen_enabled:
		return

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MAXIMIZE_DISABLED, true)

	var window_size := SUPPORTED_WINDOW_SIZES[resolution_index]
	DisplayServer.window_set_size(window_size)

	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)
	var centered_position := usable_rect.position + (usable_rect.size - window_size) / 2
	DisplayServer.window_set_position(centered_position)


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
	var language_option := menu_vbox.get_node_or_null("LanguageRow/LanguageOption") as OptionButton
	if language_row == null or language_option == null:
		call_deferred("_try_inject_start_screen_controls")
		return

	var existing_mode_row := menu_vbox.get_node_or_null("DisplayModeRow") as HBoxContainer
	if existing_mode_row != null:
		injected_start_screen = scene_root
		mode_row = existing_mode_row
		mode_label = mode_row.get_node_or_null("DisplayModeLabel") as Label
		mode_option = mode_row.get_node_or_null("DisplayModeOption") as OptionButton
		resolution_row = menu_vbox.get_node_or_null("ResolutionRow") as HBoxContainer
		if resolution_row != null:
			resolution_label = resolution_row.get_node_or_null("ResolutionLabel") as Label
			resolution_option = resolution_row.get_node_or_null("ResolutionOption") as OptionButton
		_refresh_injected_text()
		_sync_injected_controls()
		return

	injected_start_screen = scene_root
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

	mode_label = mode_row.get_node("DisplayModeLabel") as Label
	mode_option = mode_row.get_node("DisplayModeOption") as OptionButton
	resolution_label = resolution_row.get_node("ResolutionLabel") as Label
	resolution_option = resolution_row.get_node("ResolutionOption") as OptionButton

	mode_row.visible = false
	resolution_row.visible = false
	_register_with_start_screen_settings(scene_root, mode_row)
	_register_with_start_screen_settings(scene_root, resolution_row)

	mode_option.item_selected.connect(_on_mode_selected)
	resolution_option.item_selected.connect(_on_resolution_selected)
	_refresh_injected_text()
	_sync_injected_controls()


func _create_option_row(
	row_name: String,
	label_name: String,
	option_name: String,
	style_source: OptionButton
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.custom_minimum_size = Vector2(286.0, 38.0)
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.name = label_name
	label.custom_minimum_size = Vector2(118.0, 38.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	row.add_child(label)

	var option := OptionButton.new()
	option.name = option_name
	option.custom_minimum_size = Vector2(160.0, 38.0)
	option.focus_mode = Control.FOCUS_ALL
	option.add_theme_font_override("font", style_source.get_theme_font("font"))
	option.add_theme_font_size_override("font_size", 16)
	row.add_child(option)
	return row


func _register_with_start_screen_settings(scene_root: Control, control: Control) -> void:
	var settings_controls_variant: Variant = scene_root.get("settings_controls")
	if not (settings_controls_variant is Array):
		push_warning("DisplaySettings: start-screen settings list was not found.")
		return

	var settings_controls: Array = settings_controls_variant
	if not settings_controls.has(control):
		settings_controls.append(control)


func _on_mode_selected(index: int) -> void:
	set_fullscreen(index == 1)


func _on_resolution_selected(index: int) -> void:
	set_resolution_index(index)


func _on_locale_changed(_locale: String) -> void:
	_refresh_injected_text()


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


func _sync_injected_controls() -> void:
	if mode_option == null or resolution_option == null:
		return

	mode_option.select(1 if fullscreen_enabled else 0)
	resolution_option.select(resolution_index)
	resolution_option.disabled = fullscreen_enabled
