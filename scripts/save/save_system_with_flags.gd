extends "res://scripts/save/save_system.gd"

# Small save-system extension for player species flags and in-game audio settings.
# Creature, grass, egg, energy, camera and base menu logic stays in save_system.gd.


func _create_menu_root(content_root: Control) -> void:
	super._create_menu_root(content_root)

	if menu_root != null:
		menu_root.position = Vector2(0.0, 49.0)
		menu_root.size = Vector2(260.0, 235.0)

	if menu_vbox != null:
		menu_vbox.add_theme_constant_override("separation", 3)


func _show_action_menu() -> void:
	current_slot_mode = ""
	_clear_menu_vbox()
	_add_title_label("Меню")
	_add_menu_button("Сохранить", _on_save_mode_pressed, 27.0)
	_add_menu_button("Загрузить", _on_load_mode_pressed, 27.0)
	_add_menu_button("Настройки", _on_audio_settings_pressed, 27.0)
	_add_menu_button("Главное меню", _on_main_menu_pressed, 27.0)
	_add_menu_button("Закрыть игру", _on_quit_game_pressed, 27.0)
	_add_menu_button("Назад", _on_close_menu_pressed, 27.0)

	if not status_message.is_empty():
		_add_status_label(status_message)


func _on_audio_settings_pressed() -> void:
	status_message = ""
	_show_audio_settings_menu()


func _show_audio_settings_menu() -> void:
	_clear_menu_vbox()
	_add_title_label("Настройки")
	_add_audio_volume_control(
		"Музыка",
		AudioManager.get_music_volume(),
		"music"
	)
	_add_audio_volume_control(
		"Звуки",
		AudioManager.get_sound_volume(),
		"sounds"
	)
	_add_menu_button("Назад", _on_audio_settings_back_pressed, 34.0)


func _on_audio_settings_back_pressed() -> void:
	_show_action_menu()


func _add_audio_volume_control(
	label_prefix: String,
	initial_value: float,
	setting_name: String
) -> void:
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(260.0, 22.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 15)
	_update_audio_value_label(value_label, label_prefix, initial_value * 100.0)
	menu_vbox.add_child(value_label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(260.0, 27.0)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial_value * 100.0
	slider.focus_mode = Control.FOCUS_ALL
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(
		_on_audio_volume_changed.bind(value_label, label_prefix, setting_name)
	)
	menu_vbox.add_child(slider)


func _on_audio_volume_changed(
	value: float,
	value_label: Label,
	label_prefix: String,
	setting_name: String
) -> void:
	var normalized_value: float = clampf(value / 100.0, 0.0, 1.0)

	if setting_name == "music":
		AudioManager.set_music_volume(normalized_value)
	else:
		AudioManager.set_sound_volume(normalized_value)

	_update_audio_value_label(value_label, label_prefix, value)


func _update_audio_value_label(
	value_label: Label,
	label_prefix: String,
	value: float
) -> void:
	if value_label != null:
		value_label.text = "%s: %d%%" % [label_prefix, roundi(value)]


func _refresh_menu_tooltip() -> void:
	if menu_button == null:
		return

	menu_button.tooltip_text = "Меню: сохранение, загрузка и настройки"


func _collect_save_data() -> Dictionary:
	var save_data: Dictionary = super._collect_save_data()
	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("get_save_data"):
		save_data["player_flags"] = player_flags.call("get_save_data")
	else:
		save_data["player_flags"] = {}

	return save_data


func _apply_save_data(save_data: Dictionary) -> bool:
	var restored: bool = await super._apply_save_data(save_data)

	if not restored:
		return false

	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("restore_save_data"):
		player_flags.call("restore_save_data", save_data.get("player_flags", {}) as Dictionary)

	return true


func _cancel_active_nature_targeting() -> void:
	super._cancel_active_nature_targeting()

	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("cancel_targeting"):
		player_flags.call("cancel_targeting")
