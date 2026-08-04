extends Node

# Lightweight runtime counters for debugging simulation spikes.
# The counters are sampled twice per real second and displayed by creature_stats_ui.gd.
# Press F8 to toggle CSV recording.
#
# In the editor logs are written to:
#   <project folder>/logs/
#
# In an exported build logs are written to:
#   <folder with Dyna.exe>/logs/

const CSV_FOLDER_NAME := "logs"
const SAMPLE_INTERVAL_MSEC := 500
const PATH_SOURCE_NAMES := [
	"grazing",
	"predator",
	"egg_eater",
	"movement_repath",
	"movement_lookahead",
	"flag",
	"other"
]
const PATH_SOURCE_METRICS := [
	"calls",
	"expanded_tiles",
	"success",
	"failed",
	"capped"
]
const CSV_HEADER_COLUMNS := [
	"sample_time_sec",
	"game_time_sec",
	"sample_window_sec",
	"fps",
	"time_scale",
	"memory_static_mb",
	"node_count",
	"object_count",
	"creature_count",
	"grass_count",
	"grass_spread_per_sec",
	"grass_neighbor_checks_per_sec",
	"grass_spawned_per_sec",
	"grazing_searches_per_sec",
	"grazing_candidate_checks_per_sec",
	"grazing_footprint_queries_per_sec",
	"creature_physics_ticks_per_sec",
	"predator_prey_searches_per_sec",
	"predator_prey_candidates_per_sec",
	"path_calls_per_sec",
	"path_expanded_tiles_per_sec",
	"path_success_per_sec",
	"path_failed_per_sec",
	"path_capped_per_sec",
	"path_grazing_calls_per_sec",
	"path_grazing_expanded_tiles_per_sec",
	"path_grazing_success_per_sec",
	"path_grazing_failed_per_sec",
	"path_grazing_capped_per_sec",
	"path_predator_calls_per_sec",
	"path_predator_expanded_tiles_per_sec",
	"path_predator_success_per_sec",
	"path_predator_failed_per_sec",
	"path_predator_capped_per_sec",
	"path_egg_eater_calls_per_sec",
	"path_egg_eater_expanded_tiles_per_sec",
	"path_egg_eater_success_per_sec",
	"path_egg_eater_failed_per_sec",
	"path_egg_eater_capped_per_sec",
	"path_movement_repath_calls_per_sec",
	"path_movement_repath_expanded_tiles_per_sec",
	"path_movement_repath_success_per_sec",
	"path_movement_repath_failed_per_sec",
	"path_movement_repath_capped_per_sec",
	"path_movement_lookahead_calls_per_sec",
	"path_movement_lookahead_expanded_tiles_per_sec",
	"path_movement_lookahead_success_per_sec",
	"path_movement_lookahead_failed_per_sec",
	"path_movement_lookahead_capped_per_sec",
	"path_flag_calls_per_sec",
	"path_flag_expanded_tiles_per_sec",
	"path_flag_success_per_sec",
	"path_flag_failed_per_sec",
	"path_flag_capped_per_sec",
	"path_other_calls_per_sec",
	"path_other_expanded_tiles_per_sec",
	"path_other_success_per_sec",
	"path_other_failed_per_sec",
	"path_other_capped_per_sec",
	"grazing_candidate_unreachable_per_sec",
	"flag_creatures_scanned_per_sec",
	"flag_path_requests_per_sec",
	"flag_path_failures_per_sec",
	"static_route_simplify_attempts_per_sec",
	"static_route_simplify_success_per_sec",
	"static_route_simplify_fallback_per_sec",
	"static_route_simplify_candidate_checks_per_sec",
	"static_route_simplify_steps_saved_per_sec",
	"static_route_simplify_search_time_ms_per_sec",
	"static_route_simplify_search_max_ms",
	"proactive_route_lookahead_checks_per_sec",
	"proactive_route_lookahead_blocked_per_sec",
	"proactive_route_bypass_attempts_per_sec",
	"proactive_route_bypass_success_per_sec",
	"proactive_route_bypass_failed_per_sec",
	"proactive_route_bypass_search_time_ms_per_sec",
	"proactive_route_bypass_search_max_ms",
	"blocked_route_rejoin_attempts_per_sec",
	"blocked_route_rejoin_candidates_checked_per_sec",
	"blocked_route_rejoin_candidates_reachable_per_sec",
	"blocked_route_rejoin_success_per_sec",
	"blocked_route_rejoin_failed_per_sec",
	"blocked_route_rejoin_loops_removed_per_sec",
	"blocked_route_rejoin_steps_removed_per_sec",
	"blocked_route_rejoin_sharp_seam_candidates_per_sec",
	"blocked_route_rejoin_sharp_seam_avoided_per_sec",
	"blocked_route_rejoin_sharp_seam_fallback_per_sec",
	"blocked_route_rejoin_search_time_ms_per_sec",
	"blocked_route_rejoin_search_max_ms",
	"indirect_route_optimization_attempts_per_sec",
	"indirect_route_optimization_success_per_sec",
	"indirect_route_optimization_unchanged_per_sec",
	"enemy_rain_searches_per_sec",
	"enemy_rain_search_time_ms_per_sec",
	"enemy_rain_search_max_ms",
	"enemy_rain_grass_scanned_per_sec",
	"enemy_rain_mature_grass_per_sec",
	"enemy_rain_spread_ready_grass_per_sec",
	"enemy_rain_productive_grass_per_sec",
	"enemy_rain_unique_spawn_targets_per_sec",
	"enemy_rain_candidate_centers_per_sec",
	"enemy_rain_best_spread_max",
	"enemy_rain_actual_new_grass_per_sec",
	"enemy_rain_prediction_gap_per_sec",
	"enemy_rain_apply_calls_per_sec",
	"enemy_rain_apply_time_ms_per_sec",
	"enemy_rain_apply_max_ms",
	"enemy_rain_casts_per_sec",
	"f3_mode",
	"focused_path_steps"
]

var start_ticks_msec := 0
var sample_start_ticks_msec := 0
var last_sample_window_seconds := 0.0
var current_counters: Dictionary = {}
var last_rates: Dictionary = {}
var current_max_values: Dictionary = {}
var last_max_values: Dictionary = {}

var csv_recording_enabled := false
var csv_file: FileAccess = null
var csv_absolute_path := ""
var last_saved_csv_absolute_path := ""


func _ready() -> void:
	start_ticks_msec = Time.get_ticks_msec()
	sample_start_ticks_msec = start_ticks_msec
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		toggle_csv_recording()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()

	if sample_start_ticks_msec <= 0:
		sample_start_ticks_msec = now

	var elapsed_msec: int = now - sample_start_ticks_msec
	if elapsed_msec < SAMPLE_INTERVAL_MSEC:
		return

	var elapsed_seconds := float(elapsed_msec) / 1000.0
	last_sample_window_seconds = elapsed_seconds
	last_rates.clear()

	for key in current_counters.keys():
		last_rates[key] = float(current_counters[key]) / elapsed_seconds

	last_max_values = current_max_values.duplicate()

	if csv_recording_enabled:
		append_csv_sample()

	current_counters.clear()
	current_max_values.clear()
	sample_start_ticks_msec = now


func add_counter(counter_name: String, amount: int = 1) -> void:
	if amount == 0:
		return

	current_counters[counter_name] = int(current_counters.get(counter_name, 0)) + amount


func add_path_counter(source_name: StringName, metric_name: StringName, amount: int = 1) -> void:
	add_counter("path_%s_%s" % [String(source_name), String(metric_name)], amount)


func get_rate(counter_name: String) -> int:
	return int(round(get_rate_float(counter_name)))


func get_rate_float(counter_name: String) -> float:
	return float(last_rates.get(counter_name, 0.0))


func set_max_value(value_name: String, value: float) -> void:
	if not current_max_values.has(value_name):
		current_max_values[value_name] = value
		return

	current_max_values[value_name] = maxf(
		float(current_max_values.get(value_name, value)),
		value
	)


func get_last_max_value(value_name: String) -> float:
	return float(last_max_values.get(value_name, 0.0))


func get_elapsed_seconds() -> float:
	if start_ticks_msec <= 0:
		return 0.0

	return float(Time.get_ticks_msec() - start_ticks_msec) / 1000.0


func get_game_elapsed_seconds() -> float:
	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")

	if enemy_ai != null and enemy_ai.has_method("get_elapsed_simulation_seconds"):
		return maxf(float(enemy_ai.call("get_elapsed_simulation_seconds")), 0.0)

	return 0.0


func get_static_memory_mb() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)


func get_node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func get_object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func toggle_csv_recording() -> void:
	if csv_recording_enabled:
		stop_csv_recording()
		return

	start_csv_recording()


func start_csv_recording() -> bool:
	if csv_recording_enabled:
		return true

	var log_directory := get_log_directory_absolute()
	var dir_error := DirAccess.make_dir_recursive_absolute(log_directory)
	if dir_error != OK:
		push_warning("Failed to create performance log directory: %s" % log_directory)
		return false

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	csv_absolute_path = log_directory.path_join("perf_log_%s.csv" % timestamp)
	csv_file = FileAccess.open(csv_absolute_path, FileAccess.WRITE)

	if csv_file == null:
		push_warning("Failed to open performance log file: %s" % csv_absolute_path)
		csv_absolute_path = ""
		return false

	csv_file.store_line(",".join(CSV_HEADER_COLUMNS))
	csv_file.flush()
	csv_recording_enabled = true
	last_saved_csv_absolute_path = ""
	return true


func stop_csv_recording() -> void:
	if not csv_recording_enabled:
		return

	csv_recording_enabled = false
	last_saved_csv_absolute_path = csv_absolute_path

	if csv_file != null:
		csv_file.flush()
		csv_file = null


func is_csv_recording_enabled() -> bool:
	return csv_recording_enabled


func get_csv_status_text() -> String:
	if csv_recording_enabled:
		return "CSV: REC (F8) | logs/%s" % csv_absolute_path.get_file()

	if last_saved_csv_absolute_path != "":
		return "CSV: saved | logs/%s" % last_saved_csv_absolute_path.get_file()

	return "CSV: idle (F8)"


func get_last_saved_csv_absolute_path() -> String:
	return last_saved_csv_absolute_path


func get_log_directory_absolute() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join(CSV_FOLDER_NAME)

	var executable_path := OS.get_executable_path()
	if executable_path == "":
		return ProjectSettings.globalize_path("user://").path_join(CSV_FOLDER_NAME)

	return executable_path.get_base_dir().path_join(CSV_FOLDER_NAME)


func append_csv_sample() -> void:
	if csv_file == null:
		return

	csv_file.store_line(",".join(build_csv_sample_row()))
	csv_file.flush()


func build_csv_sample_row() -> Array[String]:

	var world_grid := get_tree().get_first_node_in_group("world_grid")
	var grass_count := 0
	var creature_count := 0

	if world_grid != null:
		grass_count = world_grid.grass_by_tile.size()
		creature_count = world_grid.creature_anchors.size()

	var f3_mode := "off"
	var focused_path_steps := 0
	var grid_debug := get_tree().get_first_node_in_group("grid_debug_overlay")

	if grid_debug != null and is_instance_valid(grid_debug):
		if grid_debug.has_method("get_debug_mode_name"):
			f3_mode = String(grid_debug.call("get_debug_mode_name"))
		if grid_debug.has_method("get_focused_path_steps"):
			focused_path_steps = int(grid_debug.call("get_focused_path_steps"))

	var row: Array[String] = []
	row.append(format_float(get_elapsed_seconds(), 2))
	row.append(format_float(get_game_elapsed_seconds(), 2))
	row.append(format_float(last_sample_window_seconds, 3))
	row.append(str(Engine.get_frames_per_second()))
	row.append(format_float(Engine.time_scale, 2))
	row.append(format_float(get_static_memory_mb(), 2))
	row.append(str(get_node_count()))
	row.append(str(get_object_count()))
	row.append(str(creature_count))
	row.append(str(grass_count))
	row.append(str(get_rate("grass_spread_events")))
	row.append(str(get_rate("grass_neighbor_checks")))
	row.append(str(get_rate("grass_spawned")))
	row.append(str(get_rate("grazing_searches")))
	row.append(str(get_rate("grazing_candidate_checks")))
	row.append(str(get_rate("grazing_footprint_queries")))
	row.append(str(get_rate("creature_physics_ticks")))
	row.append(str(get_rate("predator_prey_searches")))
	row.append(str(get_rate("predator_prey_candidates")))
	row.append(str(get_rate("path_calls")))
	row.append(str(get_rate("path_expanded_tiles")))
	row.append(str(get_rate("path_success")))
	row.append(str(get_rate("path_failed")))
	row.append(str(get_rate("path_capped")))

	for source_name: String in PATH_SOURCE_NAMES:
		for metric_name: String in PATH_SOURCE_METRICS:
			row.append(str(get_rate("path_%s_%s" % [source_name, metric_name])))

	row.append(str(get_rate("grazing_candidate_unreachable")))
	row.append(str(get_rate("flag_creatures_scanned")))
	row.append(str(get_rate("flag_path_requests")))
	row.append(str(get_rate("flag_path_failures")))
	row.append(str(get_rate("static_route_simplify_attempts")))
	row.append(str(get_rate("static_route_simplify_success")))
	row.append(str(get_rate("static_route_simplify_fallback")))
	row.append(str(get_rate("static_route_simplify_candidate_checks")))
	row.append(str(get_rate("static_route_simplify_steps_saved")))
	row.append(format_float(get_rate_float("static_route_simplify_search_usec") / 1000.0, 3))
	row.append(format_float(get_last_max_value("static_route_simplify_search_max_usec") / 1000.0, 3))
	row.append(str(get_rate("proactive_route_lookahead_checks")))
	row.append(str(get_rate("proactive_route_lookahead_blocked")))
	row.append(str(get_rate("proactive_route_bypass_attempts")))
	row.append(str(get_rate("proactive_route_bypass_success")))
	row.append(str(get_rate("proactive_route_bypass_failed")))
	row.append(format_float(get_rate_float("proactive_route_bypass_search_usec") / 1000.0, 3))
	row.append(format_float(get_last_max_value("proactive_route_bypass_search_max_usec") / 1000.0, 3))
	row.append(str(get_rate("blocked_route_rejoin_attempts")))
	row.append(str(get_rate("blocked_route_rejoin_candidates_checked")))
	row.append(str(get_rate("blocked_route_rejoin_candidates_reachable")))
	row.append(str(get_rate("blocked_route_rejoin_success")))
	row.append(str(get_rate("blocked_route_rejoin_failed")))
	row.append(str(get_rate("blocked_route_rejoin_loops_removed")))
	row.append(str(get_rate("blocked_route_rejoin_steps_removed")))
	row.append(str(get_rate("blocked_route_rejoin_sharp_seam_candidates")))
	row.append(str(get_rate("blocked_route_rejoin_sharp_seam_avoided")))
	row.append(str(get_rate("blocked_route_rejoin_sharp_seam_fallback")))
	row.append(format_float(get_rate_float("blocked_route_rejoin_search_usec") / 1000.0, 3))
	row.append(format_float(get_last_max_value("blocked_route_rejoin_search_max_usec") / 1000.0, 3))
	row.append(str(get_rate("indirect_route_optimization_attempts")))
	row.append(str(get_rate("indirect_route_optimization_success")))
	row.append(str(get_rate("indirect_route_optimization_unchanged")))
	row.append(str(get_rate("enemy_rain_searches")))
	row.append(format_float(get_rate_float("enemy_rain_search_usec") / 1000.0, 3))
	row.append(format_float(get_last_max_value("enemy_rain_search_max_usec") / 1000.0, 3))
	row.append(str(get_rate("enemy_rain_grass_scanned")))
	row.append(str(get_rate("enemy_rain_mature_grass")))
	row.append(str(get_rate("enemy_rain_spread_ready_grass")))
	row.append(str(get_rate("enemy_rain_productive_grass")))
	row.append(str(get_rate("enemy_rain_unique_spawn_targets")))
	row.append(str(get_rate("enemy_rain_candidate_centers")))
	row.append(str(roundi(get_last_max_value("enemy_rain_best_spread_max"))))
	row.append(str(get_rate("enemy_rain_actual_new_grass")))
	row.append(str(get_rate("enemy_rain_prediction_gap")))
	row.append(str(get_rate("enemy_rain_apply_calls")))
	row.append(format_float(get_rate_float("enemy_rain_apply_usec") / 1000.0, 3))
	row.append(format_float(get_last_max_value("enemy_rain_apply_max_usec") / 1000.0, 3))
	row.append(str(get_rate("enemy_rain_casts")))
	row.append(f3_mode)
	row.append(str(focused_path_steps))

	return row


func format_float(value: float, decimals: int = 2) -> String:
	return "%.*f" % [decimals, value]
