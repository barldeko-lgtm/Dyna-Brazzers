extends Node

const EGG_PATH := "res://scripts/resources/egg.gd"
const SPECIES_PATH := "res://scripts/creatures/creature_species_data.gd"
const SAVE_SYSTEM_PATH := "res://scripts/save/save_system.gd"


func _ready() -> void:
	call_deferred("_run_probe")


func _run_probe() -> void:
	var egg_source := FileAccess.get_file_as_string(EGG_PATH)
	var species_source := FileAccess.get_file_as_string(SPECIES_PATH)
	var save_source := FileAccess.get_file_as_string(SAVE_SYSTEM_PATH)

	if egg_source.contains('"stage_1_duration"') or egg_source.contains('"expand_retry_interval"') or egg_source.contains('"stage_2_duration"'):
		_fail("Egg still exposes legacy incubation properties.")
		return

	if species_source.contains('"egg_stage_1_duration"') or species_source.contains('"egg_expand_retry_interval"') or species_source.contains('"egg_stage_2_duration"'):
		_fail("CreatureSpeciesData still exposes legacy incubation properties.")
		return

	if save_source.contains('"stage_1_duration"') or save_source.contains('"expand_retry_interval"') or save_source.contains('"stage_2_duration"'):
		_fail("SaveSystem still reads or writes legacy egg timing properties.")
		return

	print("PASS: save restoration uses shared Egg timing without legacy property bridges.")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
