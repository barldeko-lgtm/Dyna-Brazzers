extends Node2D

const TOGGLE_KEY := KEY_F3
const LIGHT_UPDATE_FRAME_INTERVAL := 6
const FULL_UPDATE_FRAME_INTERVAL := 3
const VISIBLE_TILE_MARGIN := 1
const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const BLOCKED_TERRAIN_FILL := Color(0.9, 0.2, 0.2, 0.16)
const BLOCKED_TERRAIN_OUTLINE := Color(0.95, 0.35, 0.35, 0.6)
const GRASS_STAGE_1_FILL := Color(0.55, 0.75, 0.2, 0.16)
const GRASS_STAGE_2_FILL := Color(0.15, 0.85, 0.2, 0.26)
const GRASS_OUTLINE := Color(0.2, 0.95, 0.35, 0.7)
const OCCUPIED_FILL := Color(1.0, 0.5, 0.1, 0.14)
const OCCUPIED_OUTLINE := Color(1.0, 0.65, 0.2, 0.65)
const SELECTED_FOOTPRINT_FILL := Color(1.0, 1.0, 1.0, 0.12)
const SELECTED_FOOTPRINT_OUTLINE := Color(1.0, 1.0, 1.0, 0.95)
const PENDING_FOOTPRINT_FILL := Color(0.6, 0.3, 1.0, 0.14)
const PENDING_FOOTPRINT_OUTLINE := Color(0.75, 0.45, 1.0, 0.95)
const TARGET_FILL := Color(1.0, 0.85, 0.2, 0.16)
const TARGET_OUTLINE := Color(1.0, 0.9, 0.3, 0.95)
const HUNT_TARGET_FILL := Color(1.0, 0.2, 0.2, 0.2)
const HUNT_TARGET_OUTLINE := Color(1.0, 0.35, 0.35, 0.95)
const FLAG_TARGET_FILL := Color(0.95, 0.35, 0.95, 0.18)
const FLAG_TARGET_OUTLINE := Color(1.0, 0.5, 1.0, 0.95)
const PATH_COLOR := Color(0.2, 0.7, 1.0, 0.95)
const PATH_POINT_COLOR := Color(0.35, 0.82, 1.0, 0.95)

enum DebugMode {
	OFF,
	LIGHT,
	FULL
}

var debug_mode := DebugMode.OFF
var frames_since_refresh := 0

@onready var info_panel: PanelContainer = $DebugCanvas/DebugInfoPanel
@onready var info_label: Label = $DebugCanvas/DebugInfoPanel/MarginContainer/DebugInfoLabel


func _ready() -> void:
	add_to_group("grid_debug_overlay")
	_refresh_visibility()


func _process(_delta: float) -> void:
	if debug_mode == DebugMode.OFF:
		return

	frames_since_refresh += 1

	if frames_since_refresh < _get_update_frame_interval():
		return

	frames_since_refresh = 0
	_refresh_debug_view()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo or event.keycode != TOGGLE_KEY:
		return

	var requested_mode := DebugMode.FULL if event.alt_pressed else DebugMode.LIGHT

	if debug_mode == requested_mode:
		_set_debug_mode(DebugMode.OFF)
	else:
		_set_debug_mode(requested_mode)

	get_viewport().set_input_as_handled()


func _draw() -> void:
	if debug_mode == DebugMode.OFF:
		return

	var world_grid := _find_world_grid()
	if world_grid == null:
		return

	if debug_mode == DebugMode.FULL:
		var visible_tiles := _get_visible_tile_bounds(world_grid)
		_draw_blocked_terrain(world_grid, visible_tiles)
		_draw_grass(world_grid, visible_tiles)
		_draw_occupied_tiles(world_grid, visible_tiles)

	_draw_selected_creature_debug(world_grid)


func _set_debug_mode(new_mode: int) -> void:
	debug_mode = new_mode
	frames_since_refresh = 0
	_refresh_visibility()

	if debug_mode == DebugMode.OFF:
		return

	_refresh_debug_view()


func _refresh_debug_view() -> void:
	if debug_mode == DebugMode.OFF:
		return

	info_label.text = _build_debug_text()
	queue_redraw()


func _refresh_visibility() -> void:
	var debug_visible := debug_mode != DebugMode.OFF
	visible = debug_visible

	if info_panel != null:
		info_panel.visible = debug_visible


func _get_update_frame_interval() -> int:
	if debug_mode == DebugMode.FULL:
		return FULL_UPDATE_FRAME_INTERVAL

	return LIGHT_UPDATE_FRAME_INTERVAL


func get_debug_mode_name() -> String:
	match debug_mode:
		DebugMode.LIGHT:
			return "light"
		DebugMode.FULL:
			return "full"
		_:
			return "off"


func get_focused_path_steps() -> int:
	return _get_creature_path_steps(_get_focus_creature())


func _find_world_grid() -> Node:
	return get_tree().get_first_node_in_group("world_grid")


func _get_focus_creature() -> Node:
	var ui_nodes := get_tree().get_nodes_in_group("creature_stats_ui")
	if ui_nodes.is_empty():
		return null

	var ui: Node = ui_nodes[0]
	var selected: Node = ui.get("selected_creature")
	if is_instance_valid(selected):
		return selected

	var hovered: Node = ui.get("hovered_creature")
	if is_instance_valid(hovered):
		return hovered

	return null


func _get_flag_debug_data(creature: Node) -> Dictionary:
	if creature != null and is_instance_valid(creature) and CREATURE_FACTION.is_enemy(creature):
		var enemy_flags := get_tree().get_first_node_in_group("enemy_flag_system")

		if enemy_flags == null or not enemy_flags.has_method("get_creature_flag_debug_data"):
			return {"status": "вражеские флаги недоступны", "flag_system": "enemy"}

		var enemy_data_variant: Variant = enemy_flags.call(
			"get_creature_flag_debug_data", creature
		)

		if enemy_data_variant is Dictionary:
			var enemy_data := enemy_data_variant as Dictionary
			enemy_data["flag_system"] = "enemy"
			return enemy_data

		return {"status": "нет данных", "flag_system": "enemy"}

	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags == null or not player_flags.has_method("get_creature_flag_debug_data"):
		return {"status": "система флагов недоступна", "flag_system": "player"}

	var data_variant: Variant = player_flags.call("get_creature_flag_debug_data", creature)

	if data_variant is Dictionary:
		var player_data := data_variant as Dictionary
		player_data["flag_system"] = "player"
		return player_data

	return {"status": "нет данных", "flag_system": "player"}


func _build_debug_text() -> String:
	var world_grid := _find_world_grid()
	var mode_title := "LIGHT" if debug_mode == DebugMode.LIGHT else "FULL"
	var shortcut_title := "F3" if debug_mode == DebugMode.LIGHT else "Alt+F3"

	if world_grid == null:
		return "Grid Debug [%s] — %s\nworld_grid: missing" % [shortcut_title, mode_title]

	var creature := _get_focus_creature()
	var lines: Array[String] = []
	lines.append("Grid Debug [%s] — %s" % [shortcut_title, mode_title])

	if debug_mode == DebugMode.FULL:
		var visible_tiles := _get_visible_tile_bounds(world_grid)
		lines.append(
			"grass: %d | occupied: %d | visible: %dx%d" % [
				world_grid.grass_by_tile.size(),
				world_grid.occupied_by_tile.size(),
				visible_tiles.size.x,
				visible_tiles.size.y
			]
		)

	if not is_instance_valid(creature):
		lines.append("focus: none")
		lines.append("select or hover a creature")
		return "\n".join(lines)

	lines.append(
		"focus: %s | %s" % [
			creature.get_creature_name(), _get_display_state_name(creature)
		]
	)

	var flag_debug := _get_flag_debug_data(creature)
	var flag_label := (
		"enemy flag" if String(flag_debug.get("flag_system", "player")) == "enemy" else "flag"
	)
	lines.append("%s: %s" % [flag_label, String(flag_debug.get("status", "нет данных"))])

	var flag_tile_variant: Variant = flag_debug.get("flag_tile", null)
	if flag_tile_variant is Vector2i:
		lines.append("flag center: %s" % _format_tile(flag_tile_variant))

	var flag_target_variant: Variant = flag_debug.get("target_tile", null)
	if flag_target_variant is Vector2i:
		lines.append("flag target: %s" % _format_tile(flag_target_variant))

	var target_retry := int(flag_debug.get("target_retry", 0))
	if target_retry > 0:
		lines.append("flag target retries: %d" % target_retry)

	lines.append("anchor: %s" % _format_tile(creature.anchor_tile))
	lines.append("pending: %s" % _format_tile(creature.pending_anchor_tile))
	lines.append("footprint: %dx%d" % [creature.footprint_size.x, creature.footprint_size.y])
	lines.append("target: %s" % _format_tile(creature.grazing_target_anchor))

	var hunt_target := _get_hunt_target(creature)
	if is_instance_valid(hunt_target):
		lines.append("hunt target: %s" % hunt_target.get_creature_name())

	lines.append(
		"path steps: %d | moving: %s" % [
			_get_creature_path_steps(creature), str(bool(creature.is_moving))
		]
	)
	return "\n".join(lines)


func _get_visible_tile_bounds(world_grid: Node) -> Rect2i:
	var full_bounds := Rect2i(
		world_grid.map_min,
		world_grid.map_max - world_grid.map_min + Vector2i.ONE
	)
	var camera := get_tree().get_first_node_in_group("game_camera") as Camera2D

	if camera == null:
		camera = get_viewport().get_camera_2d()

	if camera == null:
		return full_bounds

	var viewport_size := get_viewport_rect().size

	if camera.has_method("get_game_viewport_size"):
		viewport_size = camera.call("get_game_viewport_size") as Vector2
	var camera_zoom := camera.zoom
	var safe_zoom := Vector2(
		maxf(absf(camera_zoom.x), 0.001),
		maxf(absf(camera_zoom.y), 0.001)
	)
	var half_extent := Vector2(
		viewport_size.x / safe_zoom.x,
		viewport_size.y / safe_zoom.y
	) * 0.5
	var center := camera.get_screen_center_position()
	var min_variant: Variant = world_grid.world_to_map_tile(center - half_extent)
	var max_variant: Variant = world_grid.world_to_map_tile(center + half_extent)

	if not (min_variant is Vector2i) or not (max_variant is Vector2i):
		return full_bounds

	var min_tile: Vector2i = min_variant - Vector2i.ONE * VISIBLE_TILE_MARGIN
	var max_tile: Vector2i = max_variant + Vector2i.ONE * VISIBLE_TILE_MARGIN
	min_tile.x = clampi(min_tile.x, world_grid.map_min.x, world_grid.map_max.x)
	min_tile.y = clampi(min_tile.y, world_grid.map_min.y, world_grid.map_max.y)
	max_tile.x = clampi(max_tile.x, world_grid.map_min.x, world_grid.map_max.x)
	max_tile.y = clampi(max_tile.y, world_grid.map_min.y, world_grid.map_max.y)

	if max_tile.x < min_tile.x or max_tile.y < min_tile.y:
		return full_bounds

	return Rect2i(min_tile, max_tile - min_tile + Vector2i.ONE)


func _draw_blocked_terrain(world_grid: Node, tile_bounds: Rect2i) -> void:
	for y in range(tile_bounds.position.y, tile_bounds.end.y):
		for x in range(tile_bounds.position.x, tile_bounds.end.x):
			var tile := Vector2i(x, y)
			if world_grid.is_tile_blocked_terrain(tile):
				_draw_tile(tile, world_grid, BLOCKED_TERRAIN_FILL, BLOCKED_TERRAIN_OUTLINE)


func _draw_grass(world_grid: Node, tile_bounds: Rect2i) -> void:
	for y in range(tile_bounds.position.y, tile_bounds.end.y):
		for x in range(tile_bounds.position.x, tile_bounds.end.x):
			var tile := Vector2i(x, y)
			if not world_grid.grass_by_tile.has(tile):
				continue

			var grass: Node = world_grid.grass_by_tile[tile]
			var fill := GRASS_STAGE_1_FILL
			if is_instance_valid(grass) and grass.get("current_stage") == 1:
				fill = GRASS_STAGE_2_FILL

			_draw_tile(tile, world_grid, fill, GRASS_OUTLINE)


func _draw_occupied_tiles(world_grid: Node, tile_bounds: Rect2i) -> void:
	for y in range(tile_bounds.position.y, tile_bounds.end.y):
		for x in range(tile_bounds.position.x, tile_bounds.end.x):
			var tile := Vector2i(x, y)
			if world_grid.occupied_by_tile.has(tile):
				_draw_tile(tile, world_grid, OCCUPIED_FILL, OCCUPIED_OUTLINE)


func _draw_selected_creature_debug(world_grid: Node) -> void:
	var creature := _get_focus_creature()
	if not is_instance_valid(creature):
		return

	for tile in world_grid.get_footprint_tiles(creature.anchor_tile, creature.footprint_size):
		_draw_tile(tile, world_grid, SELECTED_FOOTPRINT_FILL, SELECTED_FOOTPRINT_OUTLINE)

	if bool(creature.is_moving):
		for tile in world_grid.get_footprint_tiles(
			creature.pending_anchor_tile, creature.footprint_size
		):
			_draw_tile(tile, world_grid, PENDING_FOOTPRINT_FILL, PENDING_FOOTPRINT_OUTLINE)

	if bool(creature.has_grazing_target):
		for tile in world_grid.get_footprint_tiles(
			creature.grazing_target_anchor, creature.footprint_size
		):
			_draw_tile(tile, world_grid, TARGET_FILL, TARGET_OUTLINE)

	var hunt_target := _get_hunt_target(creature)
	if is_instance_valid(hunt_target) and world_grid.creature_anchors.has(hunt_target):
		var hunt_anchor: Vector2i = world_grid.creature_anchors[hunt_target]
		for tile in world_grid.get_footprint_tiles(hunt_anchor, hunt_target.footprint_size):
			_draw_tile(tile, world_grid, HUNT_TARGET_FILL, HUNT_TARGET_OUTLINE)

	var flag_debug := _get_flag_debug_data(creature)
	var flag_target_variant: Variant = flag_debug.get("target_tile", null)

	if flag_target_variant is Vector2i:
		for tile in world_grid.get_footprint_tiles(
			flag_target_variant, creature.footprint_size
		):
			_draw_tile(tile, world_grid, FLAG_TARGET_FILL, FLAG_TARGET_OUTLINE)

	_draw_path(world_grid, creature)


func _draw_path(world_grid: Node, creature: Node) -> void:
	var points: PackedVector2Array = []
	points.append(
		world_grid.anchor_to_world_position(creature.anchor_tile, creature.footprint_size)
	)

	if bool(creature.is_moving):
		points.append(
			world_grid.anchor_to_world_position(
				creature.pending_anchor_tile, creature.footprint_size
			)
		)

	var path_variant: Variant = creature.get("current_path")
	if path_variant is Array:
		var path := path_variant as Array
		for anchor_variant: Variant in path:
			if anchor_variant is Vector2i:
				points.append(
					world_grid.anchor_to_world_position(
						anchor_variant, creature.footprint_size
					)
				)

	if points.size() >= 2:
		draw_polyline(points, PATH_COLOR, 4.0, true)

	for point in points:
		draw_circle(point, 7.0, PATH_POINT_COLOR)


func _get_creature_path_steps(creature: Node) -> int:
	if not is_instance_valid(creature):
		return 0

	var path_variant: Variant = creature.get("current_path")
	var path_steps := 0

	if path_variant is Array:
		path_steps = (path_variant as Array).size()

	return path_steps + (1 if bool(creature.get("is_moving")) else 0)


func _get_hunt_target(creature: Node) -> Node:
	if creature.has_method("get_hunt_target"):
		return creature.get_hunt_target()

	return null


func _draw_tile(tile: Vector2i, world_grid: Node, fill_color: Color, outline_color: Color) -> void:
	var rect := _get_tile_rect(tile, world_grid)
	draw_rect(rect, fill_color, true)
	draw_rect(rect, outline_color, false, 2.0)


func _get_tile_rect(tile: Vector2i, world_grid: Node) -> Rect2:
	var center: Vector2 = world_grid.map_to_world_center(tile)
	var size := Vector2(world_grid.tile_size)
	return Rect2(center - size * 0.5, size)


func _get_state_name(state_value: int) -> String:
	var state_name := "UNKNOWN"

	match state_value:
		0:
			state_name = "IDLE"
		1:
			state_name = "WALK"
		2:
			state_name = "SEEK_FOOD"
		3:
			state_name = "EATING"
		4:
			state_name = "LAYING_EGG"
		5:
			state_name = "COMBAT"
		6:
			state_name = "DEAD"

	return state_name


func _get_display_state_name(creature: Node) -> String:
	if creature.has_method("is_waiting_for_combat_engagement") and bool(creature.is_waiting_for_combat_engagement()):
		return "ENGAGED"

	if creature.has_method("is_hunting") and bool(creature.is_hunting()):
		return "HUNTING"

	return _get_state_name(int(creature.state))


func _format_tile(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]
