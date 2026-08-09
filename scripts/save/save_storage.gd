extends RefCounted

const SAVE_VERSION := 1
const SLOT_COUNT := 3
const DEFAULT_LEVEL_ID := 1
const AUTOSAVE_FILE_PATH := "user://dyna_autosave.json"


func get_slot_path(slot_index: int) -> String:
	return "user://dyna_save_slot_%d.json" % slot_index

func get_autosave_path() -> String:
	return AUTOSAVE_FILE_PATH

func get_autosave_temp_path() -> String:
	return "%s.tmp" % get_autosave_path()

func get_autosave_backup_path() -> String:
	return "%s.bak" % get_autosave_path()

func get_slot_temp_path(slot_index: int) -> String:
	return "%s.tmp" % get_slot_path(slot_index)

func get_slot_backup_path(slot_index: int) -> String:
	return "%s.bak" % get_slot_path(slot_index)

func has_save(slot_index: int) -> bool:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return false

	recover_slot_backup(slot_index)
	return is_valid_save_data(read_save_dictionary_at_path(get_slot_path(slot_index)))

func has_autosave() -> bool:
	recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	return is_valid_save_data(read_save_dictionary_at_path(get_autosave_path()))

func get_most_recent_save_candidate() -> Dictionary:
	var candidates: Array[Dictionary] = []
	recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	var autosave_data := read_save_dictionary_at_path(get_autosave_path())

	if is_valid_save_data(autosave_data):
		candidates.append({
			"kind": "autosave",
			"saved_at": int(autosave_data.get("saved_at", 0)),
			"valid": true
		})

	for slot_index: int in range(1, SLOT_COUNT + 1):
		var slot_data := read_save_dictionary(slot_index)

		if not is_valid_save_data(slot_data):
			continue

		candidates.append({
			"kind": "slot",
			"slot_index": slot_index,
			"saved_at": int(slot_data.get("saved_at", 0)),
			"valid": true
		})

	return select_most_recent_save_candidate(candidates)

func select_most_recent_save_candidate(candidates: Array) -> Dictionary:
	var selected: Dictionary = {}
	var selected_timestamp := -1

	for candidate_variant: Variant in candidates:
		if not candidate_variant is Dictionary:
			continue

		var candidate := candidate_variant as Dictionary

		if not bool(candidate.get("valid", false)):
			continue

		var kind := String(candidate.get("kind", ""))

		if kind == "slot":
			var slot_index := int(candidate.get("slot_index", 0))

			if slot_index < 1 or slot_index > SLOT_COUNT:
				continue
		elif kind != "autosave":
			continue

		var timestamp := maxi(int(candidate.get("saved_at", 0)), 0)
		var wins_timestamp := timestamp > selected_timestamp
		var wins_autosave_tie := (
			timestamp == selected_timestamp
			and kind == "autosave"
			and String(selected.get("kind", "")) != "autosave"
		)

		if selected.is_empty() or wins_timestamp or wins_autosave_tie:
			selected = candidate.duplicate(true)
			selected_timestamp = timestamp

	return selected

func has_continue_save() -> bool:
	return not get_most_recent_save_candidate().is_empty()

func recover_slot_backup(slot_index: int) -> void:
	recover_save_backup(get_slot_path(slot_index), get_slot_backup_path(slot_index))

func recover_save_backup(save_path: String, backup_path: String) -> void:

	if FileAccess.file_exists(save_path) or not FileAccess.file_exists(backup_path):
		return

	var saves_directory := DirAccess.open("user://")

	if saves_directory != null:
		saves_directory.rename(backup_path.get_file(), save_path.get_file())

func read_save_dictionary(slot_index: int) -> Dictionary:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return {}

	recover_slot_backup(slot_index)
	return read_save_dictionary_at_path(get_slot_path(slot_index))

func read_save_dictionary_at_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var save_file: FileAccess = FileAccess.open(path, FileAccess.READ)

	if save_file == null:
		return {}

	var raw_text: String = save_file.get_as_text()
	save_file.close()

	var parsed: Variant = JSON.parse_string(raw_text)

	if parsed is Dictionary:
		return parsed as Dictionary

	return {}

func is_valid_save_data(save_data: Dictionary) -> bool:
	if save_data.is_empty() or int(save_data.get("version", 0)) != SAVE_VERSION:
		return false

	var creatures: Variant = save_data.get("creatures", null)
	var grass: Variant = save_data.get("grass", null)
	var eggs: Variant = save_data.get("eggs", null)
	var camera: Variant = save_data.get("camera", null)
	var player_energy: Variant = save_data.get("player_energy", null)
	var time_scale: Variant = save_data.get("time_scale", null)
	var level_id: Variant = save_data.get("level_id", DEFAULT_LEVEL_ID)

	return (
		creatures is Array
		and grass is Array
		and eggs is Array
		and camera is Dictionary
		and (player_energy is int or player_energy is float)
		and (time_scale is int or time_scale is float)
		and (level_id is int or level_id is float)
		and int(level_id) >= 1
		and _are_valid_creature_records(creatures as Array)
		and _are_valid_grass_records(grass as Array)
		and _are_valid_egg_records(eggs as Array)
	)

func _are_valid_creature_records(records: Array) -> bool:
	for record_variant: Variant in records:
		if not (record_variant is Dictionary):
			return false
		var record := record_variant as Dictionary
		if String(record.get("species_path", "")).is_empty():
			return false
		if not _has_numeric_coordinates(record, &"anchor_x", &"anchor_y"):
			return false
	return true

func _are_valid_grass_records(records: Array) -> bool:
	for record_variant: Variant in records:
		if not (record_variant is Dictionary):
			return false
		var record := record_variant as Dictionary
		if not _has_numeric_coordinates(record, &"tile_x", &"tile_y"):
			return false
	return true

func _are_valid_egg_records(records: Array) -> bool:
	for record_variant: Variant in records:
		if not (record_variant is Dictionary):
			return false
		var record := record_variant as Dictionary
		if not _has_numeric_coordinates(record, &"anchor_x", &"anchor_y"):
			return false
	return true

func _has_numeric_coordinates(record: Dictionary, x_key: StringName, y_key: StringName) -> bool:
	var x_value: Variant = record.get(x_key, null)
	var y_value: Variant = record.get(y_key, null)
	return (
		(x_value is int or x_value is float)
		and (y_value is int or y_value is float)
	)

func write_save_data(
	save_data: Dictionary,
	save_path: String,
	temp_path: String,
	backup_path: String,
	save_label: String
) -> bool:
	if not is_valid_save_data(save_data):
		push_error("SaveSystem: refused to write incomplete %s data." % save_label)
		return false

	var saves_directory := DirAccess.open("user://")

	if saves_directory == null:
		push_error("SaveSystem: failed to open the save directory.")
		return false

	if FileAccess.file_exists(temp_path):
		saves_directory.remove(temp_path.get_file())

	var temp_file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)

	if temp_file == null:
		push_error("SaveSystem: failed to open temporary %s for writing." % save_label)
		return false

	temp_file.store_string(JSON.stringify(save_data, "	"))
	temp_file.flush()
	var write_error := temp_file.get_error()
	temp_file.close()

	if write_error != OK or not is_valid_save_data(read_save_dictionary_at_path(temp_path)):
		saves_directory.remove(temp_path.get_file())
		push_error("SaveSystem: temporary %s could not be verified." % save_label)
		return false

	if FileAccess.file_exists(backup_path) and saves_directory.remove(backup_path.get_file()) != OK:
		saves_directory.remove(temp_path.get_file())
		push_error("SaveSystem: failed to clear the previous backup for %s." % save_label)
		return false

	if FileAccess.file_exists(save_path) and saves_directory.rename(save_path.get_file(), backup_path.get_file()) != OK:
		saves_directory.remove(temp_path.get_file())
		push_error("SaveSystem: failed to protect the previous %s." % save_label)
		return false

	if saves_directory.rename(temp_path.get_file(), save_path.get_file()) != OK:
		if FileAccess.file_exists(backup_path):
			saves_directory.rename(backup_path.get_file(), save_path.get_file())
		push_error("SaveSystem: failed to replace %s." % save_label)
		return false

	if FileAccess.file_exists(backup_path):
		saves_directory.remove(backup_path.get_file())

	return true
