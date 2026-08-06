extends "res://scripts/save/save_system_with_flags.gd"

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

var ingame_transparent_option_arrow: ImageTexture = null

# Final save layer for current enemy session state. Core entities, factions and
# player flags remain owned by the existing save-system layers. The compact
# in-game Settings page is overridden here so it can share DisplaySettings
# without changing the stable base save/reconstruction layer.


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


func _collect_save_data() -> Dictionary:
	var save_data: Dictionary = super._collect_save_data()
	var enemy_energy := get_tree().get_first_node_in_group("enemy_energy")
	var enemy_production := get_tree().get_first_node_in_group("enemy_egg_production")
	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")
	var enemy_spells := get_tree().get_first_node_in_group("enemy_spell_controller")
	var game_end_controller := get_tree().get_first_node_in_group("game_end_controller")

	if enemy_energy != null and enemy_energy.has_method("get_energy"):
		save_data["enemy_energy"] = float(enemy_energy.call("get_energy"))

	if enemy_production != null and enemy_production.has_method("get_save_data"):
		save_data["enemy_production"] = enemy_production.call("get_save_data")

	if enemy_ai != null and enemy_ai.has_method("get_save_data"):
		save_data["enemy_ai"] = enemy_ai.call("get_save_data")

	if enemy_spells != null and enemy_spells.has_method("get_save_data"):
		save_data["enemy_spells"] = enemy_spells.call("get_save_data")

	if game_end_controller != null and game_end_controller.has_method("get_save_data"):
		save_data["game_end"] = game_end_controller.call("get_save_data")

	return save_data


func _apply_save_data(save_data: Dictionary) -> bool:
	var restored: bool = await super._apply_save_data(save_data)

	if not restored:
		return false

	var enemy_energy := get_tree().get_first_node_in_group("enemy_energy")
	var enemy_production := get_tree().get_first_node_in_group("enemy_egg_production")
	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")
	var enemy_spells := get_tree().get_first_node_in_group("enemy_spell_controller")
	var game_end_controller := get_tree().get_first_node_in_group("game_end_controller")

	if enemy_energy != null and enemy_energy.has_method("restore_energy"):
		var restored_energy := float(
			save_data.get("enemy_energy", enemy_energy.call("get_energy"))
		)
		enemy_energy.call("restore_energy", restored_energy)

	if (
		enemy_production != null
		and enemy_production.has_method("restore_save_data")
		and save_data.get("enemy_production", null) is Dictionary
	):
		enemy_production.call(
			"restore_save_data",
			save_data.get("enemy_production", {}) as Dictionary
		)

	if (
		enemy_ai != null
		and enemy_ai.has_method("restore_save_data")
		and save_data.get("enemy_ai", null) is Dictionary
	):
		enemy_ai.call(
			"restore_save_data",
			save_data.get("enemy_ai", {}) as Dictionary
		)

	if enemy_spells != null and enemy_spells.has_method("restore_save_data"):
		var enemy_spells_data_variant: Variant = save_data.get("enemy_spells", null)
		var enemy_spells_data: Dictionary = {}

		if enemy_spells_data_variant is Dictionary:
			enemy_spells_data = (enemy_spells_data_variant as Dictionary).duplicate(true)

		# An empty dictionary is intentional for old saves: the spell controller
		# rebuilds only the time-based reserve capacity. Actual reserve energy starts
		# at zero because it must come from real creature income.
		enemy_spells.call("restore_save_data", enemy_spells_data)


	if game_end_controller != null and game_end_controller.has_method("restore_save_data"):
		var game_end_data_variant: Variant = save_data.get("game_end", null)
		var game_end_data: Dictionary = {}

		if game_end_data_variant is Dictionary:
			game_end_data = (game_end_data_variant as Dictionary).duplicate(true)

		if not game_end_data.has("elapsed_simulation_seconds"):
			# Saves created before match-end tracking reuse the already persisted enemy-AI
			# simulation clock, avoiding a fresh two-minute grace period after loading.
			var enemy_ai_data_variant: Variant = save_data.get("enemy_ai", null)
			if enemy_ai_data_variant is Dictionary:
				game_end_data["elapsed_simulation_seconds"] = float(
					(enemy_ai_data_variant as Dictionary).get(
						"elapsed_simulation_seconds",
						0.0
					)
				)

		game_end_controller.call("restore_save_data", game_end_data)

	return true


# Stable public bridge used by the result overlay. The inherited menu transition
# already resets the active session and restores normal time before scene change.
func return_to_main_menu_from_result() -> void:
	_on_main_menu_pressed()
