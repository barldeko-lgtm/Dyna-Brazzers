extends Node2D

const TOGGLE_KEY := KEY_F3
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

var debug_enabled := false

@onready var info_panel: PanelContainer = $DebugCanvas/DebugInfoPanel
@onready var info_label: Label = $DebugCanvas/DebugInfoPanel/MarginContainer/DebugInfoLabel


func _ready() -> void:
	_refresh_visibility()


func _process(_delta: float) -> void:
	if not debug_enabled:
		return

	info_label.text = _build_debug_text()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo:
		return

	if event.keycode != TOGGLE_KEY:
		return

	debug_enabled = not debug_enabled
	_refresh_visibility()
	queue_redraw()
	get_viewport().set_input_as_handled()


func _draw() -> void:
	if not debug_enabled:
		return

	var world_grid := _find_world_grid()
	if world_grid == null:
		return

	_draw_blocked_terrain(world_grid)
	_draw_grass(world_grid)
	_draw_occupied_tiles(world_grid)
	_draw_selected_creature_debug(world_grid)


func _refresh_visibility() -> void:
	visible = debug_enabled
	if info_panel != null:
		info_panel.visible = debug_enabled


func _find_world_grid() -> Node:
	var nodes := get_tree().get_nodes_in_group("world_grid")
	if nodes.is_empty():
		return null

	return nodes[0]


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
	if world_grid == null:
		return "Grid Debug [F3]\nworld_grid: missing"

	var creature := _get_focus_creature()
	var lines: Array[String] = []
	lines.append("Grid Debug [F3]")
	lines.append(
		"grass: %d | occupied: %d" % [
			world_grid.grass_by_tile.size(), world_grid.occupied_by_tile.size()
		]
	)
	lines.append("blocked terrain: %d" % _count_blocked_tiles(world_grid))

	if not is_instance_valid(creature):
		lines.append("focus: none")
		lines.append("select or hover a creature")
		return "\n".join(lines)

	var path_length := 0
	if creature.get("current_path") != null:
		path_length = creature.current_path.size()

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
		"path steps: %d | moving: %s" % [path_length, str(bool(creature.is_moving))]
	)
	return "\n".join(lines)


func _draw_blocked_terrain(world_grid: Node) -> void:
	for y in range(world_grid.map_min.y, world_grid.map_max.y + 1):
		for x in range(world_grid.map_min.x, world_grid.map_max.x + 1):
			var tile := Vector2i(x, y)
			if not world_grid.is_tile_blocked_terrain(tile):
				continue

			_draw_tile(tile, world_grid, BLOCKED_TERRAIN_FILL, BLOCKED_TERRAIN_OUTLINE)


func _draw_grass(world_grid: Node) -> void:
	for tile in world_grid.grass_by_tile.keys():
		var grass: Node = world_grid.grass_by_tile[tile]
		var fill := GRASS_STAGE_1_FILL
		if is_instance_valid(grass) and grass.get("current_stage") == 1:
			fill = GRASS_STAGE_2_FILL

		_draw_tile(tile, world_grid, fill, GRASS_OUTLINE)


func _draw_occupied_tiles(world_grid: Node) -> void:
	for tile in world_grid.occupied_by_tile.keys():
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

	for anchor in creature.current_path:
		points.append(world_grid.anchor_to_world_position(anchor, creature.footprint_size))

	if points.size() >= 2:
		draw_polyline(points, PATH_COLOR, 4.0, true)

	for point in points:
		draw_circle(point, 7.0, PATH_POINT_COLOR)


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


func _count_blocked_tiles(world_grid: Node) -> int:
	var count := 0
	for y in range(world_grid.map_min.y, world_grid.map_max.y + 1):
		for x in range(world_grid.map_min.x, world_grid.map_max.x + 1):
			if world_grid.is_tile_blocked_terrain(Vector2i(x, y)):
				count += 1
	return count


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
