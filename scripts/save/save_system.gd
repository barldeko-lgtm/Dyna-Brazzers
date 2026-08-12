extends Node

const SAVE_STORAGE_SCRIPT := preload("res://scripts/save/save_storage.gd")
const GAME_SCENE_PATH: String = "res://scenes/main/main.tscn"
const START_SCREEN_SCENE_PATH: String = "res://scenes/ui/start_screen.tscn"
const SAVE_VERSION: int = SAVE_STORAGE_SCRIPT.SAVE_VERSION
const SLOT_COUNT: int = SAVE_STORAGE_SCRIPT.SLOT_COUNT
const AUTOSAVE_INTERVAL_SECONDS := 300.0
const DEFAULT_LEVEL_ID: int = SAVE_STORAGE_SCRIPT.DEFAULT_LEVEL_ID
const LEVEL_SCENE_PATHS: Dictionary = {
	1: GAME_SCENE_PATH,
	2: GAME_SCENE_PATH,
	3: GAME_SCENE_PATH,
}

const IN_GAME_SYSTEM_MENU_SCRIPT := preload("res://scripts/ui/in_game_system_menu.gd")
const WORLD_SAVE_CODEC_SCRIPT := preload("res://scripts/save/world_save_codec.gd")
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const FLAG_COMPLETION_REVISION_META := &"player_flag_completed_revision"

var system_menu: Node = null
var save_storage: RefCounted = null
var world_save_codec: Node = null
var current_level_id: int = DEFAULT_LEVEL_ID
var autosave_elapsed := 0.0
var autosave_in_progress := false
var load_in_progress := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	save_storage = SAVE_STORAGE_SCRIPT.new()
	world_save_codec = WORLD_SAVE_CODEC_SCRIPT.new()
	world_save_codec.name = "WorldSaveCodec"
	world_save_codec.call("setup", self)
	add_child(world_save_codec)
	system_menu = IN_GAME_SYSTEM_MENU_SCRIPT.new()
	system_menu.name = "InGameSystemMenu"
	system_menu.call("setup", self)
	add_child(system_menu)
	set_process(true)


func _process(delta: float) -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		_update_autosave(delta, current_scene)


func _update_autosave(delta: float, current_scene: Node) -> void:
	if not _can_advance_autosave(current_scene):
		return

	if not advance_autosave_timer(delta):
		return

	autosave_in_progress = true
	var save_succeeded := save_autosave()
	autosave_in_progress = false

	if not save_succeeded:
		push_error("SaveSystem: automatic save failed.")


func _can_advance_autosave(current_scene: Node) -> bool:
	var active_level_scene_path := get_level_scene_path(current_level_id)

	if (
		current_scene == null
		or active_level_scene_path.is_empty()
		or current_scene.scene_file_path != active_level_scene_path
	):
		return false

	if is_system_menu_open() or autosave_in_progress or load_in_progress or Engine.time_scale <= 0.0:
		return false

	var game_end_controller := get_tree().get_first_node_in_group("game_end_controller")

	if game_end_controller != null and int(game_end_controller.get("match_result")) != 0:
		return false

	return true


func advance_autosave_timer(simulation_delta: float) -> bool:
	autosave_elapsed += maxf(simulation_delta, 0.0)

	if autosave_elapsed < AUTOSAVE_INTERVAL_SECONDS:
		return false

	autosave_elapsed = 0.0
	return true


# Session and in-game menu facade.

func _reset_active_game_session() -> void:
	Engine.time_scale = 1.0
	current_level_id = DEFAULT_LEVEL_ID
	autosave_elapsed = 0.0
	autosave_in_progress = false
	load_in_progress = false
	if system_menu != null and is_instance_valid(system_menu):
		system_menu.call("reset_session")


func is_system_menu_open() -> bool:
	return system_menu != null and is_instance_valid(system_menu) and bool(system_menu.call("is_open"))


func get_slot_path(slot_index: int) -> String:
	return String(save_storage.call("get_slot_path", slot_index))


func get_autosave_path() -> String:
	return String(save_storage.call("get_autosave_path"))


func get_autosave_temp_path() -> String:
	return String(save_storage.call("get_autosave_temp_path"))


func get_autosave_backup_path() -> String:
	return String(save_storage.call("get_autosave_backup_path"))


func get_slot_temp_path(slot_index: int) -> String:
	return String(save_storage.call("get_slot_temp_path", slot_index))


func get_slot_backup_path(slot_index: int) -> String:
	return String(save_storage.call("get_slot_backup_path", slot_index))


func has_save(slot_index: int) -> bool:
	return bool(save_storage.call("has_save", slot_index))


func has_autosave() -> bool:
	return bool(save_storage.call("has_autosave"))


func get_most_recent_save_candidate() -> Dictionary:
	return save_storage.call("get_most_recent_save_candidate") as Dictionary


func select_most_recent_save_candidate(candidates: Array) -> Dictionary:
	return save_storage.call("select_most_recent_save_candidate", candidates) as Dictionary


func has_continue_save() -> bool:
	return bool(save_storage.call("has_continue_save"))


func load_most_recent_save(preloaded_scene: PackedScene = null) -> bool:
	var selected := get_most_recent_save_candidate()

	if selected.is_empty():
		return false

	if String(selected.get("kind", "")) == "autosave":
		return await load_autosave(preloaded_scene)

	return await load_game(int(selected.get("slot_index", 0)), preloaded_scene)


func get_most_recent_save_level_id() -> int:
	var selected := get_most_recent_save_candidate()
	if selected.is_empty():
		return 0
	if String(selected.get("kind", "")) == "autosave":
		return get_autosave_level_id()
	return get_save_slot_level_id(int(selected.get("slot_index", 0)))


func get_save_slot_level_id(slot_index: int) -> int:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return 0
	var save_data := _read_save_dictionary(slot_index)
	if not _is_valid_save_data(save_data):
		return 0
	return get_saved_level_id(save_data)


func get_autosave_level_id() -> int:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	var save_data := _read_save_dictionary_at_path(get_autosave_path())
	if not _is_valid_save_data(save_data):
		return 0
	return get_saved_level_id(save_data)


func get_slot_button_text(slot_index: int) -> String:
	return _get_slot_button_text(slot_index)


func get_autosave_button_text() -> String:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())

	if not FileAccess.file_exists(get_autosave_path()):
		return "%s - %s" % [tr("SAVE_AUTOSAVE_SHORT"), tr("SAVE_EMPTY")]

	var metadata := _read_save_dictionary_at_path(get_autosave_path())

	if not _is_valid_save_data(metadata):
		return "%s - %s" % [tr("SAVE_AUTOSAVE_SHORT"), tr("SAVE_CORRUPTED")]

	return format_autosave_metadata(metadata)


func _get_slot_button_text(slot_index: int) -> String:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return tr("SAVE_SLOT_UNAVAILABLE")

	_recover_slot_backup(slot_index)
	var slot_path := get_slot_path(slot_index)

	if not FileAccess.file_exists(slot_path):
		return tr("SAVE_SLOT_EMPTY") % slot_index

	var metadata := _read_save_dictionary_at_path(slot_path)

	if not _is_valid_save_data(metadata):
		return tr("SAVE_SLOT_CORRUPTED") % slot_index

	return format_slot_metadata(slot_index, metadata)


func format_slot_metadata(_slot_index: int, metadata: Dictionary) -> String:
	return _format_save_metadata("", metadata)


func format_autosave_metadata(metadata: Dictionary) -> String:
	return _format_save_metadata(tr("SAVE_AUTOSAVE_SHORT"), metadata)


func _format_save_metadata(label: String, metadata: Dictionary) -> String:
	var level_id: int = get_saved_level_id(metadata)
	var map_label := tr("SAVE_MAP_LABEL") % level_id
	var label_prefix := "%s - " % label if not label.is_empty() else ""
	var saved_at: int = int(metadata.get("saved_at", 0))

	if saved_at <= 0:
		return tr("SAVE_WITHOUT_TIME") % [label_prefix, map_label]

	var offset_variant: Variant = metadata.get("saved_at_utc_offset_minutes", null)
	var offset_minutes: int

	if offset_variant is int or offset_variant is float:
		offset_minutes = int(offset_variant)
	else:
		var time_zone: Dictionary = Time.get_time_zone_from_system()
		offset_minutes = int(time_zone.get("bias", 0))

	var local_saved_at: int = saved_at + offset_minutes * 60
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(local_saved_at)
	var month: int = int(date.get("month", 0))
	var day: int = int(date.get("day", 0))
	var hour: int = int(date.get("hour", 0))
	var minute: int = int(date.get("minute", 0))

	return "%s%s - %02d.%02d %02d:%02d" % [
		label_prefix,
		map_label,
		day,
		month,
		hour,
		minute
	]


func save_game(slot_index: int) -> bool:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return false

	_recover_slot_backup(slot_index)
	return _write_current_save(
		get_slot_path(slot_index),
		get_slot_temp_path(slot_index),
		get_slot_backup_path(slot_index),
		"slot %d" % slot_index
	)


func save_autosave() -> bool:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	return _write_current_save(
		get_autosave_path(),
		get_autosave_temp_path(),
		get_autosave_backup_path(),
		"autosave"
	)


func _write_current_save(save_path: String, temp_path: String, backup_path: String, save_label: String) -> bool:
	return bool(save_storage.call("write_save_data", _collect_save_data(), save_path, temp_path, backup_path, save_label))


func _recover_slot_backup(slot_index: int) -> void:
	save_storage.call("recover_slot_backup", slot_index)


func _recover_save_backup(save_path: String, backup_path: String) -> void:
	save_storage.call("recover_save_backup", save_path, backup_path)


func _read_save_dictionary(slot_index: int) -> Dictionary:
	return save_storage.call("read_save_dictionary", slot_index) as Dictionary


func _read_save_dictionary_at_path(path: String) -> Dictionary:
	return save_storage.call("read_save_dictionary_at_path", path) as Dictionary


func _is_valid_save_data(save_data: Dictionary) -> bool:
	return bool(save_storage.call("is_valid_save_data", save_data))


func get_level_scene_path(level_id: int) -> String:
	return String(LEVEL_SCENE_PATHS.get(level_id, ""))


func get_saved_level_id(save_data: Dictionary) -> int:
	var level_id: Variant = save_data.get("level_id", DEFAULT_LEVEL_ID)

	if not (level_id is int or level_id is float):
		return DEFAULT_LEVEL_ID

	return maxi(int(level_id), 1)


func start_new_game(level_id: int, preloaded_scene: PackedScene = null) -> Error:
	var level_scene_path: String = get_level_scene_path(level_id)

	if level_scene_path.is_empty():
		return ERR_DOES_NOT_EXIST

	var previous_level_id: int = current_level_id
	current_level_id = level_id
	autosave_elapsed = 0.0
	Engine.time_scale = 1.0
	var scene_error: Error = _change_scene_to_level(level_scene_path, preloaded_scene)

	if scene_error != OK:
		current_level_id = previous_level_id

	return scene_error


func load_game(slot_index: int, preloaded_scene: PackedScene = null) -> bool:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		return false

	var save_data := _read_save_dictionary(slot_index)

	if not _is_valid_save_data(save_data):
		push_error("SaveSystem: slot %d is missing or invalid." % slot_index)
		return false

	return await _load_save_data(save_data, preloaded_scene)


func load_autosave(preloaded_scene: PackedScene = null) -> bool:
	_recover_save_backup(get_autosave_path(), get_autosave_backup_path())
	var save_data := _read_save_dictionary_at_path(get_autosave_path())

	if not _is_valid_save_data(save_data):
		push_error("SaveSystem: autosave is missing or invalid.")
		return false

	return await _load_save_data(save_data, preloaded_scene)


func _load_save_data(save_data: Dictionary, preloaded_scene: PackedScene = null) -> bool:
	load_in_progress = true
	autosave_elapsed = 0.0
	var saved_level_id: int = get_saved_level_id(save_data)
	var level_scene_path: String = get_level_scene_path(saved_level_id)

	if level_scene_path.is_empty():
		load_in_progress = false
		push_error("SaveSystem: level %d is unavailable." % saved_level_id)
		return false

	var current_scene: Node = get_tree().current_scene

	if (
		current_scene == null
		or current_scene.scene_file_path != level_scene_path
		or current_level_id != saved_level_id
	):
		var previous_level_id: int = current_level_id
		current_level_id = saved_level_id
		var scene_error: Error = _change_scene_to_level(level_scene_path, preloaded_scene)

		if scene_error != OK:
			current_level_id = previous_level_id
			load_in_progress = false
			return false

		await get_tree().process_frame
		await get_tree().process_frame

	else:
		current_level_id = saved_level_id

	var load_succeeded: bool = await _apply_save_data(save_data)

	if load_succeeded:
		_reset_loaded_time_speed()

	load_in_progress = false
	return load_succeeded


func _change_scene_to_level(
	level_scene_path: String,
	preloaded_scene: PackedScene = null
) -> Error:
	if (
		preloaded_scene != null
		and preloaded_scene.resource_path == level_scene_path
	):
		return get_tree().change_scene_to_packed(preloaded_scene)
	return get_tree().change_scene_to_file(level_scene_path)


func _reset_loaded_time_speed() -> void:
	Engine.time_scale = 1.0
	if system_menu != null and is_instance_valid(system_menu):
		system_menu.set("menu_previous_time_scale", 1.0)
	var player_ui := get_tree().get_first_node_in_group("player_ui")

	if player_ui != null and player_ui.has_method("reset_time_speed_after_load"):
		player_ui.call("reset_time_speed_after_load")


# ---------------------------------------------------------------------------
# Collect current simulation.
# ---------------------------------------------------------------------------

func _collect_save_data() -> Dictionary:
	var saved_time_scale := Engine.time_scale
	if is_system_menu_open() and system_menu != null:
		saved_time_scale = float(system_menu.call("get_previous_time_scale"))
	var time_zone := Time.get_time_zone_from_system()
	var world_data := world_save_codec.call("collect_world_data") as Dictionary
	var save_data := {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"saved_at_utc_offset_minutes": int(time_zone.get("bias", 0)),
		"level_id": current_level_id,
		"time_scale": saved_time_scale,
		"camera": world_data.get("camera", {}),
		"player_energy": world_data.get("player_energy", 0.0),
		"creatures": world_data.get("creatures", []),
		"grass": world_data.get("grass", []),
		"eggs": world_data.get("eggs", []),
		"cleared_dry_ground_tiles": world_data.get("cleared_dry_ground_tiles", []),
		"dry_ground_rain_hits": world_data.get("dry_ground_rain_hits", []),
	}
	_collect_player_flag_save_fields(save_data)
	_collect_enemy_save_fields(save_data)
	return save_data


func _enrich_creature_save_record(record: Dictionary, creature: Node) -> void:
	record["faction_id"] = String(CREATURE_FACTION.get_id(creature))
	record["flag_completed_revision"] = int(
		creature.get_meta(FLAG_COMPLETION_REVISION_META, -1)
	)


func _enrich_egg_save_record(record: Dictionary, egg: Node) -> void:
	record["faction_id"] = String(CREATURE_FACTION.get_id(egg))

func _prepare_creature_restore_record(record: Dictionary, creature: Node) -> void:
	CREATURE_FACTION.set_id(
		creature,
		StringName(String(record.get("faction_id", CREATURE_FACTION.PLAYER)))
	)
	var completed_revision := int(record.get("flag_completed_revision", -1))
	if completed_revision >= 0:
		creature.set_meta(FLAG_COMPLETION_REVISION_META, completed_revision)
	elif creature.has_meta(FLAG_COMPLETION_REVISION_META):
		creature.remove_meta(FLAG_COMPLETION_REVISION_META)


func _prepare_egg_restore_record(record: Dictionary, egg: Node) -> void:
	CREATURE_FACTION.set_id(
		egg,
		StringName(String(record.get("faction_id", CREATURE_FACTION.PLAYER)))
	)


func _apply_save_data(save_data: Dictionary) -> bool:
	var restored := bool(await world_save_codec.call("apply_save_data", save_data))
	if not restored:
		return false
	_restore_player_flag_save_fields(save_data)
	_restore_enemy_save_fields(save_data)
	return true

func _collect_player_flag_save_fields(save_data: Dictionary) -> void:
	var player_flags := get_node_or_null("/root/PlayerFlags")
	if player_flags != null and player_flags.has_method("get_save_data"):
		save_data["player_flags"] = player_flags.call("get_save_data")
	else:
		save_data["player_flags"] = {}


func _restore_player_flag_save_fields(save_data: Dictionary) -> void:
	var player_flags := get_node_or_null("/root/PlayerFlags")
	if player_flags != null and player_flags.has_method("restore_save_data"):
		player_flags.call("restore_save_data", save_data.get("player_flags", {}) as Dictionary)


func _collect_enemy_save_fields(save_data: Dictionary) -> void:
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


func _restore_enemy_save_fields(save_data: Dictionary) -> void:
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


# Stable public bridge used by the result overlay. The inherited menu transition
# already resets the active session and restores normal time before scene change.


func return_to_main_menu() -> Error:
	_reset_active_game_session()
	return get_tree().change_scene_to_file(START_SCREEN_SCENE_PATH)


func return_to_main_menu_from_result() -> void:
	return_to_main_menu()
