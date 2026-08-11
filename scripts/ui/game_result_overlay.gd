extends CanvasLayer
class_name GameResultOverlay

signal main_menu_requested

const VICTORY_TITLE_COLOR := Color(0.42, 1.0, 0.48, 1.0)
const DEFEAT_TITLE_COLOR := Color(1.0, 0.35, 0.30, 1.0)
const VICTORY_SOUND := preload("res://assets/audio/sfx/result_victory.mp3")
const DEFEAT_SOUND := preload("res://assets/audio/sfx/result_defeat.mp3")

@onready var title_label: Label = $Dimmer/CenterContainer/ResultPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $Dimmer/CenterContainer/ResultPanel/MarginContainer/VBoxContainer/MessageLabel
@onready var time_label: Label = $Dimmer/CenterContainer/ResultPanel/MarginContainer/VBoxContainer/TimeLabel
@onready var main_menu_button: Button = $Dimmer/CenterContainer/ResultPanel/MarginContainer/VBoxContainer/MainMenuButton


func _ready() -> void:
	visible = false
	main_menu_button.text = tr("RESULT_MAIN_MENU")
	var button_callable := Callable(self, "_on_main_menu_button_pressed")

	if not main_menu_button.pressed.is_connected(button_callable):
		main_menu_button.pressed.connect(button_callable)


func show_result(
	title_text: String,
	message_text: String,
	formatted_duration: String,
	is_victory: bool
) -> void:
	title_label.text = tr(title_text)
	message_label.text = tr(message_text)
	time_label.text = tr("RESULT_TIME") % formatted_duration
	title_label.add_theme_color_override(
		"font_color",
		VICTORY_TITLE_COLOR if is_victory else DEFEAT_TITLE_COLOR
	)
	visible = true
	AudioManager.play_sfx(VICTORY_SOUND if is_victory else DEFEAT_SOUND)
	main_menu_button.grab_focus()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
