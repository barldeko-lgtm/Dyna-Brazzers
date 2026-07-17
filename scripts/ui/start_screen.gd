extends Control

const GAME_SCENE_PATH: String = "res://scenes/main/main.tscn"
const SLOT_COUNT: int = 3

@onready var menu_vbox: VBoxContainer = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer
@onready var new_game_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/NewGameButton
@onready var load_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadButton
@onready var menu_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/MenuButton
@onready var exit_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/ExitButton
@onready var load_slot_1_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot1Button
@onready var load_slot_2_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot2Button
@onready var load_slot_3_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadSlot3Button
@onready var load_back_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadBackButton
@onready var status_label: Label = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/StatusLabel

var load_slot_buttons: Array[Button] = []
var settings_controls: Array[Control] = []
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

	menu_button.text = "Настройки"
	_create_audio_settings_controls()

	new_game_button.pressed.connect(_on_new_game_pressed)
	load_button.pressed.connect(_on_load_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	load_back_button.pressed.connect(_on_load_back_pressed)
	settings_back_button.pressed.connect(_on_settings_back_pressed)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	sound_volume_slider.value_changed.connect(_on_sound_volume_changed)

	for slot_index: int in range(SLOT_COUNT):
		load_slot_buttons[slot_index].pressed.connect(
			_on_load_slot_pressed.bind(slot_index + 1)
		)

	_show_main_buttons()
	new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file(GAME_SCENE_PATH)

	if error != OK:
		status_label.text = "Не удалось запустить новую игру."


func _on_load_pressed() -> void:
	_show_load_slots()


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


func _on_music_volume_changed(value: float) -> void:
	var normalized_value: float = clampf(value / 100.0, 0.0, 1.0)
	AudioManager.set_music_volume(normalized_value)
	_update_volume_label(music_volume_label, "Музыка", value)


func _on_sound_volume_changed(value: float) -> void:
	var normalized_value: float = clampf(value / 100.0, 0.0, 1.0)
	AudioManager.set_sound_volume(normalized_value)
	_update_volume_label(sound_volume_label, "Звуки", value)


func _on_load_slot_pressed(slot_index: int) -> void:
	if not SaveSystem.has_save(slot_index):
		return

	status_label.text = "Загрузка слота %d..." % slot_index
	_set_load_slot_buttons_disabled(true)

	# SaveSystem is an autoload and owns the asynchronous scene switch.
	# The start screen does not need to wait for a return value.
	SaveSystem.load_game(slot_index)


func _show_main_buttons() -> void:
	new_game_button.visible = true
	load_button.visible = true
	menu_button.visible = true
	exit_button.visible = true
	status_label.visible = true

	for slot_button: Button in load_slot_buttons:
		slot_button.visible = false

	load_back_button.visible = false
	_set_settings_controls_visible(false)
	status_label.text = ""


func _show_load_slots() -> void:
	new_game_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false
	status_label.visible = true
	_set_settings_controls_visible(false)

	var has_any_save: bool = false

	for slot_index: int in range(SLOT_COUNT):
		var slot_number: int = slot_index + 1
		var slot_button: Button = load_slot_buttons[slot_index]
		var slot_has_save: bool = SaveSystem.has_save(slot_number)

		slot_button.visible = true
		slot_button.disabled = not slot_has_save
		slot_button.text = SaveSystem.get_slot_button_text(slot_number)

		if slot_has_save:
			has_any_save = true

	load_back_button.visible = true
	load_back_button.disabled = false

	if has_any_save:
		status_label.text = "Выберите слот для загрузки."
		_focus_first_available_slot()
	else:
		status_label.text = "Сохранений пока нет."
		load_back_button.grab_focus()


func _show_audio_settings() -> void:
	new_game_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false
	load_back_button.visible = false
	status_label.visible = false

	for slot_button: Button in load_slot_buttons:
		slot_button.visible = false

	_sync_audio_settings_controls()
	_set_settings_controls_visible(true)
	music_volume_slider.grab_focus()


func _focus_first_available_slot() -> void:
	for slot_button: Button in load_slot_buttons:
		if not slot_button.disabled:
			slot_button.grab_focus()
			return

	load_back_button.grab_focus()


func _set_load_slot_buttons_disabled(disabled: bool) -> void:
	for slot_button: Button in load_slot_buttons:
		slot_button.disabled = disabled

	load_back_button.disabled = disabled


func _create_audio_settings_controls() -> void:
	var title_label := Label.new()
	title_label.name = "AudioSettingsTitle"
	title_label.custom_minimum_size = Vector2(290.0, 42.0)
	title_label.text = "Настройки"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	menu_vbox.add_child(title_label)
	settings_controls.append(title_label)

	music_volume_label = _create_volume_label("Музыка")
	menu_vbox.add_child(music_volume_label)
	settings_controls.append(music_volume_label)

	music_volume_slider = _create_volume_slider()
	menu_vbox.add_child(music_volume_slider)
	settings_controls.append(music_volume_slider)

	sound_volume_label = _create_volume_label("Звуки")
	menu_vbox.add_child(sound_volume_label)
	settings_controls.append(sound_volume_label)

	sound_volume_slider = _create_volume_slider()
	menu_vbox.add_child(sound_volume_slider)
	settings_controls.append(sound_volume_slider)

	settings_back_button = _create_settings_back_button()
	menu_vbox.add_child(settings_back_button)
	settings_controls.append(settings_back_button)

	_set_settings_controls_visible(false)


func _create_volume_label(label_text: String) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(290.0, 30.0)
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 19)
	return label


func _create_volume_slider() -> HSlider:
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(290.0, 34.0)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _create_settings_back_button() -> Button:
	var button := Button.new()
	button.name = "AudioSettingsBackButton"
	button.custom_minimum_size = Vector2(290.0, 52.0)
	button.text = "Назад"
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
	_update_volume_label(music_volume_label, "Музыка", music_percent)
	_update_volume_label(sound_volume_label, "Звуки", sound_percent)


func _update_volume_label(label: Label, prefix: String, value: float) -> void:
	if label != null:
		label.text = "%s: %d%%" % [prefix, roundi(value)]


func _set_settings_controls_visible(should_show: bool) -> void:
	for control: Control in settings_controls:
		control.visible = should_show
