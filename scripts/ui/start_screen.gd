extends Control

const GAME_SCENE_PATH: String = "res://scenes/main/main.tscn"
const SLOT_COUNT: int = 3

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


func _ready() -> void:
	load_slot_buttons = [
		load_slot_1_button,
		load_slot_2_button,
		load_slot_3_button
	]

	new_game_button.pressed.connect(_on_new_game_pressed)
	load_button.pressed.connect(_on_load_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	load_back_button.pressed.connect(_on_load_back_pressed)

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
	status_label.text = "Дополнительное меню пока не готово."


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_load_back_pressed() -> void:
	_show_main_buttons()
	load_button.grab_focus()


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

	for slot_button: Button in load_slot_buttons:
		slot_button.visible = false

	load_back_button.visible = false
	status_label.text = ""


func _show_load_slots() -> void:
	new_game_button.visible = false
	load_button.visible = false
	menu_button.visible = false
	exit_button.visible = false

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
