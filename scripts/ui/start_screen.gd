extends Control

const GAME_SCENE_PATH: String = "res://scenes/main/main.tscn"

@onready var new_game_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/NewGameButton
@onready var load_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/LoadButton
@onready var menu_button: Button = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/MenuButton
@onready var status_label: Label = $CenterContainer/MenuPanel/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	new_game_button.grab_focus()
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_button.pressed.connect(_on_load_pressed)
	menu_button.pressed.connect(_on_menu_pressed)


func _on_new_game_pressed() -> void:
	var error: Error = get_tree().change_scene_to_file(GAME_SCENE_PATH)

	if error != OK:
		status_label.text = "Не удалось запустить новую игру."


func _on_load_pressed() -> void:
	status_label.text = "Загрузка появится вместе с системой сохранений."


func _on_menu_pressed() -> void:
	status_label.text = "Дополнительное меню пока не готово."
