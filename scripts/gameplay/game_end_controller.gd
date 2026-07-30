extends Node
class_name GameEndController

const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const START_SCREEN_SCENE_PATH := "res://scenes/ui/start_screen.tscn"

@export var result_overlay_path: NodePath
@export var elimination_grace_seconds := 120.0
@export var population_check_interval := 0.5

enum MatchResult {
	ACTIVE,
	VICTORY,
	DEFEAT
}

var elapsed_simulation_seconds := 0.0
var population_check_elapsed := 0.0
var match_result := MatchResult.ACTIVE
var result_overlay: Node = null


func _ready() -> void:
	add_to_group("game_end_controller")
	result_overlay = get_node_or_null(result_overlay_path)

	if result_overlay == null:
		push_error("GameEndController: game-result overlay was not found.")
		return

	var menu_callable := Callable(self, "_on_main_menu_requested")
	if result_overlay.has_signal("main_menu_requested") and not result_overlay.is_connected(
		"main_menu_requested",
		menu_callable
	):
		result_overlay.connect("main_menu_requested", menu_callable)


func _process(delta: float) -> void:
	if match_result != MatchResult.ACTIVE:
		return

	var simulation_delta := maxf(delta, 0.0)
	elapsed_simulation_seconds += simulation_delta

	if elapsed_simulation_seconds < get_elimination_grace_seconds():
		return

	population_check_elapsed += simulation_delta

	if population_check_elapsed < get_population_check_interval():
		return

	population_check_elapsed = 0.0
	_check_elimination_conditions()


func _check_elimination_conditions() -> void:
	var enemy_population := _count_faction_population(CREATURE_FACTION.ENEMY)

	if int(enemy_population.get("creatures", 0)) + int(enemy_population.get("eggs", 0)) <= 0:
		_finish_match(MatchResult.VICTORY)
		return

	var player_population := _count_faction_population(CREATURE_FACTION.PLAYER)

	if int(player_population.get("creatures", 0)) + int(player_population.get("eggs", 0)) <= 0:
		_finish_match(MatchResult.DEFEAT)


func _count_faction_population(faction_id: StringName) -> Dictionary:
	var creature_count := 0
	var egg_count := 0

	for creature_variant: Variant in get_tree().get_nodes_in_group("creatures"):
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature):
			continue

		if creature.is_queued_for_deletion():
			continue

		if CREATURE_FACTION.get_id(creature) != faction_id:
			continue

		if int(creature.get("state")) == Creature.State.DEAD:
			continue

		creature_count += 1

	for egg_variant: Variant in get_tree().get_nodes_in_group("eggs"):
		var egg := egg_variant as Node

		if egg == null or not is_instance_valid(egg):
			continue

		if egg.is_queued_for_deletion():
			continue

		if CREATURE_FACTION.get_id(egg) != faction_id:
			continue

		egg_count += 1

	return {
		"creatures": creature_count,
		"eggs": egg_count
	}


func _finish_match(result: int) -> void:
	if match_result != MatchResult.ACTIVE:
		return

	match_result = result
	population_check_elapsed = 0.0
	set_process(false)
	_present_match_result()


func _present_match_result() -> void:
	_cancel_active_nature_targeting()
	Engine.time_scale = 0.0

	if result_overlay == null or not is_instance_valid(result_overlay):
		result_overlay = get_node_or_null(result_overlay_path)

	if result_overlay == null or not result_overlay.has_method("show_result"):
		push_error("GameEndController: cannot show the match result.")
		return

	var is_victory := match_result == MatchResult.VICTORY
	var title := "RESULT_VICTORY" if is_victory else "RESULT_DEFEAT"
	var message := (
		"RESULT_VICTORY_MESSAGE"
		if is_victory
		else "RESULT_DEFEAT_MESSAGE"
	)

	result_overlay.call(
		"show_result",
		title,
		message,
		_format_match_duration(elapsed_simulation_seconds),
		is_victory
	)


func _cancel_active_nature_targeting() -> void:
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")

	if nature_ui != null and nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")


func _on_main_menu_requested() -> void:
	var save_system := get_node_or_null("/root/SaveSystem")

	if save_system != null and save_system.has_method("return_to_main_menu_from_result"):
		save_system.call("return_to_main_menu_from_result")
		return

	# Defensive fallback for a missing autoload bridge.
	Engine.time_scale = 1.0
	var scene_error := get_tree().change_scene_to_file(START_SCREEN_SCENE_PATH)

	if scene_error != OK:
		Engine.time_scale = 0.0
		push_error("GameEndController: failed to open the main menu.")


func get_elimination_grace_seconds() -> float:
	return maxf(elimination_grace_seconds, 0.0)


func get_population_check_interval() -> float:
	return maxf(population_check_interval, 0.05)


func get_save_data() -> Dictionary:
	return {
		"elapsed_simulation_seconds": maxf(elapsed_simulation_seconds, 0.0),
		"match_result": int(match_result)
	}


func restore_save_data(saved_data: Dictionary) -> void:
	elapsed_simulation_seconds = maxf(
		float(saved_data.get("elapsed_simulation_seconds", 0.0)),
		0.0
	)
	population_check_elapsed = 0.0
	match_result = clampi(
		int(saved_data.get("match_result", MatchResult.ACTIVE)),
		MatchResult.ACTIVE,
		MatchResult.DEFEAT
	)

	if match_result == MatchResult.ACTIVE:
		set_process(true)
		return

	set_process(false)
	call_deferred("_present_match_result")


func _format_match_duration(duration_seconds: float) -> String:
	var total_seconds := maxi(int(floor(maxf(duration_seconds, 0.0))), 0)
	var minutes := int(total_seconds / 60)
	var seconds := total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
