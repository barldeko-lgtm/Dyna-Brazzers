extends "res://scripts/save/save_system.gd"

const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const FLAG_COMPLETION_REVISION_META := &"player_flag_completed_revision"

# Small save-system extension for player species flags, entity factions and
# in-game audio settings. Core entity reconstruction stays in save_system.gd.


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
	_add_creature_factions_to_save_records(save_data.get("creatures", []) as Array)
	_add_egg_factions_to_save_records(save_data.get("eggs", []) as Array)

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

	_restore_entity_factions(save_data)

	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("restore_save_data"):
		player_flags.call("restore_save_data", save_data.get("player_flags", {}) as Dictionary)

	return true


func _add_creature_factions_to_save_records(saved_records: Array) -> void:
	var record_index := 0

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		if not is_instance_valid(creature) or creature.is_queued_for_deletion():
			continue

		if int(creature.get("state")) == 6:
			continue

		var species_data := creature.get("species_data") as Resource

		if species_data == null or species_data.resource_path.is_empty():
			continue

		if record_index >= saved_records.size():
			break

		var record_variant: Variant = saved_records[record_index]

		if record_variant is Dictionary:
			var record := record_variant as Dictionary
			record["faction_id"] = String(CREATURE_FACTION.get_id(creature))
			record["flag_completed_revision"] = int(
				creature.get_meta(FLAG_COMPLETION_REVISION_META, -1)
			)
			saved_records[record_index] = record

		record_index += 1


func _add_egg_factions_to_save_records(saved_records: Array) -> void:
	var record_index := 0

	for egg: Node in get_tree().get_nodes_in_group("eggs"):
		if not is_instance_valid(egg) or egg.is_queued_for_deletion():
			continue

		if record_index >= saved_records.size():
			break

		var record_variant: Variant = saved_records[record_index]

		if record_variant is Dictionary:
			var record := record_variant as Dictionary
			record["faction_id"] = String(CREATURE_FACTION.get_id(egg))
			saved_records[record_index] = record

		record_index += 1


func _restore_entity_factions(save_data: Dictionary) -> void:
	_restore_creature_factions(save_data.get("creatures", []) as Array)
	_restore_egg_factions(save_data.get("eggs", []) as Array)


func _restore_creature_factions(saved_records: Array) -> void:
	var factions_by_key := _build_faction_queue_by_key(saved_records, true)
	var completions_by_key := _build_flag_completion_queue_by_key(saved_records)

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		if not is_instance_valid(creature) or creature.is_queued_for_deletion():
			continue

		var key := _get_creature_node_key(creature)
		CREATURE_FACTION.set_id(creature, _take_faction_for_key(factions_by_key, key))
		var completed_revision := _take_flag_completion_for_key(completions_by_key, key)

		if completed_revision >= 0:
			creature.set_meta(FLAG_COMPLETION_REVISION_META, completed_revision)
		elif creature.has_meta(FLAG_COMPLETION_REVISION_META):
			creature.remove_meta(FLAG_COMPLETION_REVISION_META)


func _build_flag_completion_queue_by_key(saved_records: Array) -> Dictionary:
	var completions_by_key: Dictionary = {}

	for record_variant: Variant in saved_records:
		if not (record_variant is Dictionary):
			continue

		var record := record_variant as Dictionary
		var key := _get_creature_record_key(record)
		var queue: Array = completions_by_key.get(key, []) as Array
		queue.append(int(record.get("flag_completed_revision", -1)))
		completions_by_key[key] = queue

	return completions_by_key


func _take_flag_completion_for_key(completions_by_key: Dictionary, key: String) -> int:
	var queue: Array = completions_by_key.get(key, []) as Array

	if queue.is_empty():
		return -1

	var completed_revision := int(queue.pop_front())
	completions_by_key[key] = queue
	return completed_revision


func _restore_egg_factions(saved_records: Array) -> void:
	var factions_by_key := _build_faction_queue_by_key(saved_records, false)

	for egg: Node in get_tree().get_nodes_in_group("eggs"):
		if not is_instance_valid(egg) or egg.is_queued_for_deletion():
			continue

		var key := _get_egg_node_key(egg)
		CREATURE_FACTION.set_id(egg, _take_faction_for_key(factions_by_key, key))


func _build_faction_queue_by_key(saved_records: Array, creatures: bool) -> Dictionary:
	var factions_by_key: Dictionary = {}

	for record_variant: Variant in saved_records:
		if not (record_variant is Dictionary):
			continue

		var record := record_variant as Dictionary
		var key := _get_creature_record_key(record) if creatures else _get_egg_record_key(record)
		var queue: Array = factions_by_key.get(key, []) as Array
		queue.append(StringName(String(record.get("faction_id", CREATURE_FACTION.PLAYER))))
		factions_by_key[key] = queue

	return factions_by_key


func _take_faction_for_key(factions_by_key: Dictionary, key: String) -> StringName:
	var queue: Array = factions_by_key.get(key, []) as Array

	if queue.is_empty():
		return CREATURE_FACTION.PLAYER

	var faction_id := CREATURE_FACTION.normalize(queue.pop_front())
	factions_by_key[key] = queue
	return faction_id


func _get_creature_record_key(record: Dictionary) -> String:
	return "%s|%d|%d" % [
		String(record.get("species_path", "")),
		int(record.get("anchor_x", 0)),
		int(record.get("anchor_y", 0))
	]


func _get_creature_node_key(creature: Node) -> String:
	var species_data := creature.get("species_data") as Resource
	var species_path := species_data.resource_path if species_data != null else ""
	var anchor_variant: Variant = creature.get("anchor_tile")
	var anchor := Vector2i.ZERO

	if anchor_variant is Vector2i:
		anchor = anchor_variant as Vector2i

	return "%s|%d|%d" % [species_path, anchor.x, anchor.y]


func _get_egg_record_key(record: Dictionary) -> String:
	var species_key := String(record.get("hatch_species_path", ""))

	if species_key.is_empty():
		species_key = String(record.get("species_id", ""))

	return "%s|%d|%d" % [
		species_key,
		int(record.get("anchor_x", 0)),
		int(record.get("anchor_y", 0))
	]


func _get_egg_node_key(egg: Node) -> String:
	var hatch_species := egg.get("hatch_species_data") as Resource
	var species_key := hatch_species.resource_path if hatch_species != null else ""

	if species_key.is_empty():
		species_key = String(egg.get("species_id"))

	var anchor_variant: Variant = egg.get("anchor_tile")
	var anchor := Vector2i.ZERO

	if anchor_variant is Vector2i:
		anchor = anchor_variant as Vector2i

	return "%s|%d|%d" % [species_key, anchor.x, anchor.y]


func _cancel_active_nature_targeting() -> void:
	super._cancel_active_nature_targeting()

	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("cancel_targeting"):
		player_flags.call("cancel_targeting")
