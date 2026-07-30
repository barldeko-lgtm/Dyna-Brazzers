extends Control

const SLOT_COUNT: int = 3
const LANGUAGE_OPTIONS := [
	{"locale": "ru", "name": "Русский"},
	{"locale": "en", "name": "English"},
	{"locale": "fr", "name": "Français"},
	{"locale": "de", "name": "Deutsch"},
	{"locale": "uk", "name": "Українська"},
]

@onready var menu_vbox: VBoxContainer = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer
@onready var new_game_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/NewGameButton
@onready var continue_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/ContinueButton
@onready var load_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadButton
@onready var menu_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/MenuButton
@onready var exit_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/ExitButton
@onready var level_select_title: Label = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LevelSelectTitle
@onready var level_1_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/Level1Button
@onready var level_2_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/Level2Button
@onready var level_back_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LevelBackButton
@onready var autosave_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/AutosaveButton
@onready var load_slot_1_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot1Button
@onready var load_slot_2_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot2Button
@onready var load_slot_3_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot3Button
@onready var load_back_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadBackButton
@onready var status_label: Label = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/StatusLabel

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
		level_back_button
	]

	_create_audio_settings_controls()
	_compact_menu_buttons()
	_refresh_localized_text()

	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	level_1_button.pressed.connect(_on_level_1_pressed)
	level_2_button.pressed.connect(_on_level_2_pressed)
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
	new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	_show_level_selection()


func _on_level_1_pressed() -> void:
	var error: Error = SaveSystem.start_new_game(1)

	if error != OK:
		status_label.text = tr("STATUS_NEW_GAME_FAILED")


func _on_level_2_pressed() -> void:
	var error: Error = SaveSystem.start_new_game(2)

	if error != OK:
		status_label.text = tr("STATUS_NEW_GAME_FAILED")


func _on_level_back_pressed() -> void:
	_show_main_buttons()
	new_game_button.grab_focus()


func _on_load_pressed() -> void:
	_show_load_slots()


func _on_continue_pressed() -> void:
	if not SaveSystem.has_continue_save():
		return

	status_label.visible = true
	status_label.text = tr("STATUS_LOADING_LATEST")
	_set_main_buttons_disabled(true)
	var load_succeeded: bool = await SaveSystem.load_most_recent_save()

	if load_succeeded:
		return

	status_label.text = tr("STATUS_LOAD_LATEST_FAILED")
	_set_main_buttons_disabled(false)


func _on_menu_pressed() -> void:
	_show_audio_settings()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_load_back_pressed() -> void:
	_show_main_buttons()
	load_button.grab_focus()


func _on_settings_back_pressed() -> void:
	_show_main_buttons()
	menu_button.grab_focus()


func _on_language_selected(index: int) -> void:
	if index < 0 or index >= language_option.item_count:
		return
	LocalizationManager.set_locale(String(language_option.get_item_metadata(index)))


func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_text()
	if level_1_button.visible:
		SaveSystem.apply_save_button_text(level_1_button, level_1_button.text, 22, 13)
		SaveSystem.apply_save_button_text(level_2_button, level_2_button.text, 20, 13)


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

	status_label.text = tr("STATUS_LOADING_SLOT") % slot_index
	_set_load_slot_buttons_disabled(true)

	var load_succeeded: bool = await SaveSystem.load_game(slot_index)

	if load_succeeded:
		return

	status_label.text = tr("STATUS_LOAD_SLOT_FAILED") % slot_index
	_set_load_slot_buttons_disabled(false)
	load_back_button.grab_focus()


func _on_autosave_pressed() -> void:
	if not SaveSystem.has_autosave():
		return

	status_label.text = tr("STATUS_LOADING_AUTOSAVE")
	_set_load_slot_buttons_disabled(true)
	var load_succeeded: bool = await SaveSystem.load_autosave()

	if load_succeeded:
		return

	status_label.text = tr("STATUS_LOAD_AUTOSAVE_FAILED")
	_set_load_slot_buttons_disabled(false)
	load_back_button.grab_focus()


func _show_main_buttons() -> void:
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
	new_game_button.visible = false
	continue_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false
	load_back_button.visible = false
	status_label.visible = true
	status_label.text = tr("STATUS_SELECT_LEVEL")
	autosave_button.visible = false

	for slot_button: Button in load_slot_buttons:
		slot_button.visible = false

	_set_settings_controls_visible(false)
	_set_level_selection_visible(true)
	SaveSystem.apply_save_button_text(level_1_button, level_1_button.text, 22, 13)
	SaveSystem.apply_save_button_text(level_2_button, level_2_button.text, 20, 13)
	level_1_button.grab_focus()


func _show_load_slots() -> void:
	new_game_button.visible = false
	continue_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false
	status_label.visible = true
	_set_level_selection_visible(false)
	_set_settings_controls_visible(false)

	var has_any_save: bool = false
	var autosave_exists: bool = SaveSystem.has_autosave()
	autosave_button.visible = true
	autosave_button.disabled = not autosave_exists
	SaveSystem.apply_save_button_text(
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
		SaveSystem.apply_save_button_text(
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
		status_label.text = tr("STATUS_SELECT_LOAD_SLOT")
		_focus_first_available_slot()
	else:
		status_label.text = tr("STATUS_NO_SAVES")
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
		button.custom_minimum_size.x = 260.0
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


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
	level_1_button.text = tr("LEVEL_1_CURRENT")
	level_2_button.text = tr("LEVEL_2_NEW")
	level_back_button.text = tr("MENU_BACK")
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
