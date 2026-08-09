extends Control

const BUTTON_TEXT_FITTER := preload("res://scripts/ui/button_text_fitter.gd")

const SLOT_COUNT: int = 3
const LANGUAGE_OPTIONS := [
	{"locale": "ru", "name": "Русский"},
	{"locale": "en", "name": "English"},
	{"locale": "fr", "name": "Français"},
	{"locale": "de", "name": "Deutsch"},
	{"locale": "uk", "name": "Українська"},
]

@onready var menu_vbox: VBoxContainer = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer
@onready var menu_margin: MarginContainer = $CenterContainer/MenuPanel/MarginContainer
@onready var new_game_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/NewGameButton
@onready var continue_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/ContinueButton
@onready var load_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadButton
@onready var menu_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/MenuButton
@onready var exit_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/ExitButton
@onready var level_select_title: Label = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LevelSelectTitle
@onready var level_1_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/Level1Button
@onready var level_2_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/Level2Button
@onready var level_3_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/Level3Button
@onready var level_4_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/Level4Button
@onready var level_back_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LevelBackButton
@onready var autosave_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/AutosaveButton
@onready var load_slot_1_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot1Button
@onready var load_slot_2_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot2Button
@onready var load_slot_3_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot3Button
@onready var load_back_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadBackButton
@onready var load_status_area: Control = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadStatusArea
@onready var load_status_label: Label = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadStatusArea/LoadStatusLabel
@onready var status_label: Label = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var main_menu_center: CenterContainer = $CenterContainer
@onready var tutorial_choice_layer: Control = $TutorialChoiceLayer
@onready var tutorial_choice_title: Label = $TutorialChoiceLayer/CenterContainer/TutorialChoiceSlot/TutorialChoicePanel/TitleLabel
@onready var tutorial_yes_button: Button = $TutorialChoiceLayer/CenterContainer/TutorialChoiceSlot/TutorialChoicePanel/YesButton
@onready var tutorial_no_button: Button = $TutorialChoiceLayer/CenterContainer/TutorialChoiceSlot/TutorialChoicePanel/NoButton
@onready var loading_layer: Control = $LoadingLayer
@onready var loading_label: Label = $LoadingLayer/CenterContainer/LoadingSlot/LoadingPanel/LoadingLabel
@onready var loading_progress: ProgressBar = $LoadingLayer/CenterContainer/LoadingSlot/LoadingPanel/LoadingProgress

var load_slot_buttons: Array[Button] = []
var level_selection_controls: Array[Control] = []
var settings_controls: Array[Control] = []
var language_row: HBoxContainer = null
var language_label: Label = null
var language_option: OptionButton = null
var music_volume_label: Label = null
var music_volume_slider: HSlider = null
var sound_volume_label: Label = null
var sound_volume_slider: HSlider = null
var settings_back_button: Button = null
var pending_new_game_level_id := 0


func _ready() -> void:
	load_slot_buttons = [
		load_slot_1_button,
		load_slot_2_button,
		load_slot_3_button
	]
	level_selection_controls = [
		level_select_title,
		level_1_button,
		level_2_button,
		level_3_button,
		level_4_button,
		level_back_button
	]

	_create_audio_settings_controls()
	_compact_menu_buttons()
	_configure_load_menu_buttons()
	_refresh_localized_text()

	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	level_1_button.pressed.connect(_on_level_1_pressed)
	level_2_button.pressed.connect(_on_level_2_pressed)
	tutorial_yes_button.pressed.connect(_on_tutorial_yes_pressed)
	tutorial_no_button.pressed.connect(_on_tutorial_no_pressed)
	level_back_button.pressed.connect(_on_level_back_pressed)
	load_button.pressed.connect(_on_load_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	load_back_button.pressed.connect(_on_load_back_pressed)
	autosave_button.pressed.connect(_on_autosave_pressed)
	settings_back_button.pressed.connect(_on_settings_back_pressed)
	language_option.item_selected.connect(_on_language_selected)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	sound_volume_slider.value_changed.connect(_on_sound_volume_changed)
	LocalizationManager.locale_changed.connect(_on_locale_changed)

	for slot_index: int in range(SLOT_COUNT):
		load_slot_buttons[slot_index].pressed.connect(
			_on_load_slot_pressed.bind(slot_index + 1)
		)

	_show_main_buttons()


func _on_new_game_pressed() -> void:
	_show_level_selection()


func _on_level_1_pressed() -> void:
	_show_tutorial_choice(1)


func _on_level_2_pressed() -> void:
	_show_tutorial_choice(2)


func _on_tutorial_yes_pressed() -> void:
	TutorialManager.request_tutorial_start()
	_start_pending_new_game()


func _on_tutorial_no_pressed() -> void:
	TutorialManager.cancel_tutorial_start()
	_start_pending_new_game()


func _show_tutorial_choice(level_id: int) -> void:
	pending_new_game_level_id = level_id
	main_menu_center.visible = false
	tutorial_choice_layer.visible = true
	tutorial_yes_button.disabled = false
	tutorial_no_button.disabled = false


func _start_pending_new_game() -> void:
	if pending_new_game_level_id <= 0:
		return

	tutorial_yes_button.disabled = true
	tutorial_no_button.disabled = true
	var level_scene_path: String = SaveSystem.get_level_scene_path(pending_new_game_level_id)
	var packed_scene: PackedScene = await _load_packed_scene(level_scene_path)

	if packed_scene == null:
		_restore_level_selection_after_failed_start()
		return

	var error: Error = SaveSystem.start_new_game(pending_new_game_level_id, packed_scene)

	if error == OK:
		return

	_restore_level_selection_after_failed_start()


func _restore_level_selection_after_failed_start() -> void:
	TutorialManager.cancel_tutorial_start()
	_hide_loading_screen()
	_show_level_selection()
	status_label.visible = true
	status_label.text = tr("STATUS_NEW_GAME_FAILED")


func _on_level_back_pressed() -> void:
	_show_main_buttons()


func _on_load_pressed() -> void:
	_show_load_slots()


func _on_continue_pressed() -> void:
	if not SaveSystem.has_continue_save():
		return

	_set_main_buttons_disabled(true)
	var level_id: int = SaveSystem.get_most_recent_save_level_id()
	var packed_scene: PackedScene = await _load_packed_scene(
		SaveSystem.get_level_scene_path(level_id)
	)
	var load_succeeded := false

	if packed_scene != null:
		load_succeeded = await SaveSystem.load_most_recent_save(packed_scene)

	if load_succeeded:
		return

	_hide_loading_screen()
	main_menu_center.visible = true
	status_label.visible = true
	status_label.text = tr("STATUS_LOAD_LATEST_FAILED")
	_set_main_buttons_disabled(false)


func _on_menu_pressed() -> void:
	_show_audio_settings()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_load_back_pressed() -> void:
	_show_main_buttons()


func _on_settings_back_pressed() -> void:
	_show_main_buttons()


func _on_language_selected(index: int) -> void:
	if index < 0 or index >= language_option.item_count:
		return
	LocalizationManager.set_locale(String(language_option.get_item_metadata(index)))


func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_text()
	if level_1_button.visible:
		BUTTON_TEXT_FITTER.apply(level_1_button, level_1_button.text, 22, 13)
		BUTTON_TEXT_FITTER.apply(level_2_button, level_2_button.text, 22, 13)
		BUTTON_TEXT_FITTER.apply(level_3_button, level_3_button.text, 22, 13)
		BUTTON_TEXT_FITTER.apply(level_4_button, level_4_button.text, 22, 13)


func _on_music_volume_changed(value: float) -> void:
	var normalized_value: float = clampf(value / 100.0, 0.0, 1.0)
	AudioManager.set_music_volume(normalized_value)
	_update_volume_label(music_volume_label, "SETTINGS_MUSIC", value)


func _on_sound_volume_changed(value: float) -> void:
	var normalized_value: float = clampf(value / 100.0, 0.0, 1.0)
	AudioManager.set_sound_volume(normalized_value)
	_update_volume_label(sound_volume_label, "SETTINGS_SOUNDS", value)


func _on_load_slot_pressed(slot_index: int) -> void:
	if not SaveSystem.has_save(slot_index):
		return

	_set_load_slot_buttons_disabled(true)
	var level_id: int = SaveSystem.get_save_slot_level_id(slot_index)
	var packed_scene: PackedScene = await _load_packed_scene(
		SaveSystem.get_level_scene_path(level_id)
	)
	var load_succeeded := false

	if packed_scene != null:
		load_succeeded = await SaveSystem.load_game(slot_index, packed_scene)

	if load_succeeded:
		return

	_hide_loading_screen()
	main_menu_center.visible = true
	load_status_label.text = tr("STATUS_LOAD_SLOT_FAILED") % slot_index
	_set_load_slot_buttons_disabled(false)
	load_back_button.grab_focus()


func _on_autosave_pressed() -> void:
	if not SaveSystem.has_autosave():
		return

	_set_load_slot_buttons_disabled(true)
	var level_id: int = SaveSystem.get_autosave_level_id()
	var packed_scene: PackedScene = await _load_packed_scene(
		SaveSystem.get_level_scene_path(level_id)
	)
	var load_succeeded := false

	if packed_scene != null:
		load_succeeded = await SaveSystem.load_autosave(packed_scene)

	if load_succeeded:
		return

	_hide_loading_screen()
	main_menu_center.visible = true
	load_status_label.text = tr("STATUS_LOAD_AUTOSAVE_FAILED")
	_set_load_slot_buttons_disabled(false)
	load_back_button.grab_focus()


func _load_packed_scene(scene_path: String) -> PackedScene:
	if scene_path.is_empty():
		return null

	_show_loading_screen()
	await get_tree().process_frame

	var request_error: Error = ResourceLoader.load_threaded_request(
		scene_path,
		"PackedScene",
		true
	)
	if request_error != OK:
		return null

	var progress: Array = []
	while true:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			scene_path,
			progress
		)
		if not progress.is_empty():
			loading_progress.value = clampf(float(progress[0]) * 100.0, 0.0, 100.0)

		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				loading_progress.value = 100.0
				await get_tree().process_frame
				return ResourceLoader.load_threaded_get(scene_path) as PackedScene
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return null

		await get_tree().process_frame

	return null


func _show_loading_screen() -> void:
	main_menu_center.visible = false
	tutorial_choice_layer.visible = false
	loading_label.text = tr("LOADING_TITLE")
	loading_progress.value = 0.0
	loading_layer.visible = true


func _hide_loading_screen() -> void:
	loading_layer.visible = false


func _show_main_buttons() -> void:
	main_menu_center.visible = true
	tutorial_choice_layer.visible = false
	pending_new_game_level_id = 0
	menu_margin.add_theme_constant_override("margin_top", 58)
	load_status_area.visible = false
	new_game_button.visible = true
	continue_button.visible = true
	load_button.visible = true
	menu_button.visible = true
	exit_button.visible = true
	status_label.visible = false
	autosave_button.visible = false

	for slot_button: Button in load_slot_buttons:
		slot_button.visible = false

	load_back_button.visible = false
	_set_level_selection_visible(false)
	_set_settings_controls_visible(false)
	status_label.text = ""
	_set_main_buttons_disabled(false)


func _show_level_selection() -> void:
	main_menu_center.visible = true
	tutorial_choice_layer.visible = false
	menu_margin.add_theme_constant_override("margin_top", 33)
	new_game_button.visible = false
	continue_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false
	load_back_button.visible = false
	status_label.visible = false
	status_label.text = ""
	autosave_button.visible = false

	for slot_button: Button in load_slot_buttons:
		slot_button.visible = false

	_set_settings_controls_visible(false)
	_set_level_selection_visible(true)
	BUTTON_TEXT_FITTER.apply(level_1_button, level_1_button.text, 22, 13)
	BUTTON_TEXT_FITTER.apply(level_2_button, level_2_button.text, 22, 13)
	BUTTON_TEXT_FITTER.apply(level_3_button, level_3_button.text, 22, 13)
	BUTTON_TEXT_FITTER.apply(level_4_button, level_4_button.text, 22, 13)
	level_1_button.grab_focus()


func _show_load_slots() -> void:
	menu_margin.add_theme_constant_override("margin_top", 57)
	new_game_button.visible = false
	continue_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false
	status_label.visible = false
	load_status_area.visible = true
	_set_level_selection_visible(false)
	_set_settings_controls_visible(false)

	var has_any_save: bool = false
	var autosave_exists: bool = SaveSystem.has_autosave()
	autosave_button.visible = true
	autosave_button.disabled = not autosave_exists
	BUTTON_TEXT_FITTER.apply(
		autosave_button,
		SaveSystem.get_autosave_button_text(),
		19,
		13
	)

	if autosave_exists:
		has_any_save = true

	for slot_index: int in range(SLOT_COUNT):
		var slot_number: int = slot_index + 1
		var slot_button: Button = load_slot_buttons[slot_index]
		var slot_has_save: bool = SaveSystem.has_save(slot_number)
		slot_button.visible = true
		slot_button.disabled = not slot_has_save
		BUTTON_TEXT_FITTER.apply(
			slot_button,
			SaveSystem.get_slot_button_text(slot_number),
			21,
			13
		)

		if slot_has_save:
			has_any_save = true

	load_back_button.visible = true
	load_back_button.disabled = false

	if has_any_save:
		load_status_label.text = tr("STATUS_SELECT_LOAD_SLOT")
		_focus_first_available_slot()
	else:
		load_status_label.text = tr("STATUS_NO_SAVES")
		load_back_button.grab_focus()


func _show_audio_settings() -> void:
	new_game_button.visible = false
	continue_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false
	load_back_button.visible = false
	status_label.visible = false
	autosave_button.visible = false
	_set_level_selection_visible(false)

	for slot_button: Button in load_slot_buttons:
		slot_button.visible = false

	_sync_audio_settings_controls()
	_set_settings_controls_visible(true)
	language_option.grab_focus()


func _focus_first_available_slot() -> void:
	if not autosave_button.disabled:
		autosave_button.grab_focus()
		return

	for slot_button: Button in load_slot_buttons:
		if not slot_button.disabled:
			slot_button.grab_focus()
			return

	load_back_button.grab_focus()


func _set_load_slot_buttons_disabled(disabled: bool) -> void:
	autosave_button.disabled = disabled

	for slot_button: Button in load_slot_buttons:
		slot_button.disabled = disabled

	load_back_button.disabled = disabled


func _set_main_buttons_disabled(disabled: bool) -> void:
	new_game_button.disabled = disabled
	load_button.disabled = disabled
	menu_button.disabled = disabled
	exit_button.disabled = disabled
	continue_button.disabled = disabled or not SaveSystem.has_continue_save()


func _compact_menu_buttons() -> void:
	for child: Node in menu_vbox.get_children():
		var button := child as Button
		if button == null:
			continue
		button.custom_minimum_size.x = 250.0
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _configure_load_menu_buttons() -> void:
	var buttons: Array[Button] = [
		autosave_button,
		load_slot_1_button,
		load_slot_2_button,
		load_slot_3_button,
		load_back_button,
	]
	for button: Button in buttons:
		button.custom_minimum_size.x = 250.0


func _create_audio_settings_controls() -> void:
	var title_label := Label.new()
	title_label.name = "AudioSettingsTitle"
	title_label.custom_minimum_size = Vector2(286.0, 36.0)
	title_label.text = "SETTINGS_TITLE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", new_game_button.get_theme_font("font"))
	title_label.add_theme_font_size_override("font_size", 24)
	menu_vbox.add_child(title_label)
	settings_controls.append(title_label)

	language_row = _create_language_row()
	menu_vbox.add_child(language_row)
	settings_controls.append(language_row)

	music_volume_label = _create_volume_label("SETTINGS_MUSIC")
	music_volume_label.name = "MusicVolumeLabel"
	menu_vbox.add_child(music_volume_label)
	settings_controls.append(music_volume_label)

	music_volume_slider = _create_volume_slider()
	music_volume_slider.name = "MusicVolumeSlider"
	menu_vbox.add_child(music_volume_slider)
	settings_controls.append(music_volume_slider)

	sound_volume_label = _create_volume_label("SETTINGS_SOUNDS")
	sound_volume_label.name = "SoundVolumeLabel"
	menu_vbox.add_child(sound_volume_label)
	settings_controls.append(sound_volume_label)

	sound_volume_slider = _create_volume_slider()
	sound_volume_slider.name = "SoundVolumeSlider"
	menu_vbox.add_child(sound_volume_slider)
	settings_controls.append(sound_volume_slider)

	settings_back_button = _create_settings_back_button()
	menu_vbox.add_child(settings_back_button)
	settings_controls.append(settings_back_button)

	_set_settings_controls_visible(false)


func _create_language_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "LanguageRow"
	row.custom_minimum_size = Vector2(286.0, 38.0)
	row.add_theme_constant_override("separation", 8)

	language_label = Label.new()
	language_label.name = "LanguageLabel"
	language_label.text = "SETTINGS_LANGUAGE"
	language_label.custom_minimum_size = Vector2(96.0, 38.0)
	language_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	language_label.add_theme_font_size_override("font_size", 19)
	row.add_child(language_label)

	language_option = OptionButton.new()
	language_option.name = "LanguageOption"
	language_option.custom_minimum_size = Vector2(160.0, 38.0)
	language_option.focus_mode = Control.FOCUS_ALL
	language_option.add_theme_font_size_override("font_size", 17)
	row.add_child(language_option)
	for option_data: Dictionary in LANGUAGE_OPTIONS:
		var item_index := language_option.item_count
		language_option.add_item(String(option_data["name"]))
		language_option.set_item_metadata(item_index, String(option_data["locale"]))
	_sync_language_selection()
	return row


func _create_volume_label(label_text: String) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(286.0, 24.0)
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 19)
	return label


func _create_volume_slider() -> HSlider:
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(286.0, 28.0)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _create_settings_back_button() -> Button:
	var button := Button.new()
	button.name = "AudioSettingsBackButton"
	button.custom_minimum_size = Vector2(286.0, 40.0)
	button.text = "MENU_BACK"
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override(
		"font_size",
		menu_button.get_theme_font_size("font_size")
	)

	for style_name: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		button.add_theme_stylebox_override(
			style_name,
			menu_button.get_theme_stylebox(style_name)
		)

	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color"
	]:
		button.add_theme_color_override(
			color_name,
			menu_button.get_theme_color(color_name)
		)

	return button


func _sync_audio_settings_controls() -> void:
	var music_percent: float = AudioManager.get_music_volume() * 100.0
	var sound_percent: float = AudioManager.get_sound_volume() * 100.0

	music_volume_slider.set_value_no_signal(music_percent)
	sound_volume_slider.set_value_no_signal(sound_percent)
	_sync_language_selection()
	_update_volume_label(music_volume_label, "SETTINGS_MUSIC", music_percent)
	_update_volume_label(sound_volume_label, "SETTINGS_SOUNDS", sound_percent)


func _refresh_localized_text() -> void:
	new_game_button.text = tr("MENU_NEW_GAME")
	continue_button.text = tr("MENU_CONTINUE")
	load_button.text = tr("MENU_LOAD")
	menu_button.text = tr("MENU_SETTINGS")
	exit_button.text = tr("MENU_EXIT")
	level_select_title.text = tr("MENU_LEVEL_SELECT")
	level_1_button.text = tr("LEVEL_1")
	level_2_button.text = tr("LEVEL_2")
	level_3_button.text = tr("LEVEL_3")
	level_4_button.text = tr("LEVEL_4")
	level_back_button.text = tr("MENU_BACK")
	tutorial_choice_title.text = tr("TUTORIAL_CHOICE_TITLE")
	tutorial_yes_button.text = tr("TUTORIAL_CHOICE_YES")
	tutorial_no_button.text = tr("TUTORIAL_CHOICE_NO")
	loading_label.text = tr("LOADING_TITLE")
	load_back_button.text = tr("MENU_BACK")
	var settings_title := menu_vbox.get_node_or_null("AudioSettingsTitle") as Label
	if settings_title != null:
		settings_title.text = tr("SETTINGS_TITLE")
	if language_label != null:
		language_label.text = tr("SETTINGS_LANGUAGE")
	if settings_back_button != null:
		settings_back_button.text = tr("MENU_BACK")
	_sync_audio_settings_controls()


func _sync_language_selection() -> void:
	if language_option == null:
		return
	var current_locale := LocalizationManager.get_current_locale()
	for index: int in range(language_option.item_count):
		if String(language_option.get_item_metadata(index)) == current_locale:
			language_option.select(index)
			return


func _update_volume_label(label: Label, prefix_key: String, value: float) -> void:
	if label != null:
		label.text = "%s: %d%%" % [tr(prefix_key), roundi(value)]


func _set_settings_controls_visible(should_show: bool) -> void:
	for control: Control in settings_controls:
		control.visible = should_show


func _set_level_selection_visible(should_show: bool) -> void:
	for control: Control in level_selection_controls:
		control.visible = should_show
