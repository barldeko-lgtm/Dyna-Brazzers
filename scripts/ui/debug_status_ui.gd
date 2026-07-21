extends Label

# Compact performance line + optional detailed debug status.
#
# Always visible:
# FPS | Time | Mem | Enemy Enka
#
# Press F4 to show/hide detailed debug text.
# F3 grid debug overlay remains separate in scripts/debug/grid_debug_overlay.gd.

const TOGGLE_KEY := KEY_F4

var details_visible := false
var simulation_elapsed_seconds := 0.0


func _ready() -> void:
	add_to_group("debug_status_ui")
	text = build_debug_status_text()


func _process(delta: float) -> void:
	simulation_elapsed_seconds += delta
	text = build_debug_status_text()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo:
		return

	if event.keycode != TOGGLE_KEY:
		return

	details_visible = not details_visible
	text = build_debug_status_text()
	get_viewport().set_input_as_handled()


func build_debug_status_text() -> String:
	var compact_line := build_compact_status_line()

	if not details_visible:
		return compact_line

	var world_grid := get_tree().get_first_node_in_group("world_grid")
	var mouse_screen := get_viewport().get_mouse_position()
	var mouse_world := get_mouse_world_position(mouse_screen)
	var mouse_tile_text := "?"
	var grass_count := 0
	var creature_count := 0

	if world_grid != null:
		grass_count = world_grid.grass_by_tile.size()
		creature_count = world_grid.creature_anchors.size()
		mouse_tile_text = format_tile(world_grid.world_to_map_tile(mouse_world))

	var lines: Array[String] = []
	lines.append(compact_line)
	lines.append("Debug: F4")
	lines.append("Mouse: W%s | Tile: %s" % [format_vector2(mouse_world), mouse_tile_text])
	lines.append("World: creatures %d | grass %d | nodes %d | objects %d" % [creature_count, grass_count, PerformanceStats.get_node_count(), PerformanceStats.get_object_count()])
	lines.append("Grass/s: spread %d | checks %d | spawned %d" % [PerformanceStats.get_rate("grass_spread_events"), PerformanceStats.get_rate("grass_neighbor_checks"), PerformanceStats.get_rate("grass_spawned")])
	lines.append("Graze/s: searches %d | candidate tiles %d | footprint checks %d" % [PerformanceStats.get_rate("grazing_searches"), PerformanceStats.get_rate("grazing_candidate_checks"), PerformanceStats.get_rate("grazing_footprint_queries")])
	lines.append("Creature/s: physics %d | predator searches %d | candidates %d" % [PerformanceStats.get_rate("creature_physics_ticks"), PerformanceStats.get_rate("predator_prey_searches"), PerformanceStats.get_rate("predator_prey_candidates")])
	lines.append("Path/s: calls %d | expanded %d | success %d | failed %d" % [PerformanceStats.get_rate("path_calls"), PerformanceStats.get_rate("path_expanded_tiles"), PerformanceStats.get_rate("path_success"), PerformanceStats.get_rate("path_failed")])
	lines.append("Flags/s: updates %d | scanned %d | paths %d | failed %d" % [PerformanceStats.get_rate("flag_updates"), PerformanceStats.get_rate("flag_creatures_scanned"), PerformanceStats.get_rate("flag_path_requests"), PerformanceStats.get_rate("flag_path_failures")])
	lines.append(PerformanceStats.get_csv_status_text())
	return "\n".join(lines)


func build_compact_status_line() -> String:
	var elapsed_text := format_elapsed_time(simulation_elapsed_seconds)
	var memory_mb := PerformanceStats.get_static_memory_mb()
	var enemy_energy_value := 0.0
	var enemy_energy := get_tree().get_first_node_in_group("enemy_energy")

	if enemy_energy != null and enemy_energy.has_method("get_energy"):
		enemy_energy_value = float(enemy_energy.call("get_energy"))

	return "FPS: %d | Time: %s | Mem: %.1f MB | Enemy Enka: %d" % [
		Engine.get_frames_per_second(),
		elapsed_text,
		memory_mb,
		roundi(enemy_energy_value)
	]


func get_mouse_world_position(mouse_screen: Vector2) -> Vector2:
	var camera := find_camera_2d()

	if camera == null:
		return mouse_screen

	var viewport_size := get_viewport().get_visible_rect().size
	return camera.get_screen_center_position() + (mouse_screen - viewport_size * 0.5) / camera.zoom


func find_camera_2d() -> Camera2D:
	var current := get_parent()

	while current != null:
		var camera := current.get_node_or_null("Camera2D") as Camera2D

		if camera != null:
			return camera

		current = current.get_parent()

	return get_viewport().get_camera_2d()


func format_vector2(value: Vector2) -> String:
	return "(%d, %d)" % [int(round(value.x)), int(round(value.y))]


func format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]


func format_elapsed_time(total_seconds: float) -> String:
	var seconds := int(total_seconds)
	var hours := int(seconds / 3600)
	var minutes := int((seconds % 3600) / 60)
	var remaining_seconds := seconds % 60

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]

	return "%02d:%02d" % [minutes, remaining_seconds]
