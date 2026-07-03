extends Node

# Lightweight runtime counters for debugging simulation spikes.
# The counters are sampled once per real second and displayed by creature_stats_ui.gd.
# Press F8 to toggle CSV recording.
#
# In the editor logs are written to:
#   <project folder>/logs/
#
# In an exported build logs are written to:
#   <folder with Dyna.exe>/logs/

const CSV_FOLDER_NAME := "logs"
const CSV_HEADER_COLUMNS := [
	"sample_time_sec",
	"fps",
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
	"grazing_candidate_unreachable_per_sec"
]

var start_ticks_msec := 0
var sample_start_ticks_msec := 0
var current_counters: Dictionary = {}
var last_rates: Dictionary = {}

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
	if elapsed_msec < 1000:
		return

	var elapsed_seconds := float(elapsed_msec) / 1000.0
	last_rates.clear()

	for key in current_counters.keys():
		last_rates[key] = float(current_counters[key]) / elapsed_seconds

	if csv_recording_enabled:
		append_csv_sample()

	current_counters.clear()
	sample_start_ticks_msec = now


func add_counter(counter_name: String, amount: int = 1) -> void:
	if amount == 0:
		return

	current_counters[counter_name] = int(current_counters.get(counter_name, 0)) + amount


func get_rate(counter_name: String) -> int:
	return int(round(float(last_rates.get(counter_name, 0.0))))


func get_elapsed_seconds() -> float:
	if start_ticks_msec <= 0:
		return 0.0

	return float(Time.get_ticks_msec() - start_ticks_msec) / 1000.0


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

	var world_grid := get_tree().get_first_node_in_group("world_grid")
	var grass_count := 0
	var creature_count := 0

	if world_grid != null:
		grass_count = world_grid.grass_by_tile.size()
		creature_count = world_grid.creature_anchors.size()

	var row: Array[String] = []
	row.append(format_float(get_elapsed_seconds(), 2))
	row.append(str(Engine.get_frames_per_second()))
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
	row.append(str(get_rate("grazing_candidate_unreachable")))

	csv_file.store_line(",".join(row))
	csv_file.flush()


func format_float(value: float, decimals: int = 2) -> String:
	return "%.*f" % [decimals, value]
