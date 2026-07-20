extends Node

# Stable facade for player species flags. UI targeting and route assignment live
# in dedicated helpers; this node owns scene attachment, placed flag data,
# public save/debug entry points, and world-visual synchronization.

const GAME_SCENE_PATH := "res://scenes/main/main.tscn"
const FLAG_VISUAL_SCRIPT := preload("res://scripts/flags/player_flag_visual.gd")
const FLAG_UI_CONTROLLER := preload("res://scripts/flags/player_flag_ui_controller.gd")

const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)
const BEHAVIOUR_UPDATE_INTERVAL := 0.5
const UI_ATTACH_RETRY_FRAMES := 16

var flags: Dictionary = {}

var attached_scene_id := 0
var attached_to_game := false
var world_grid: Node = null
var flag_visual: Node2D = null

var nature_ui: Node = null
var nature_content: Control = null
var main_menu_grid: GridContainer = null
var flag_menu_button: Button = null
var ui_controller: RefCounted = null
var behaviour_update_timer := 0.0


func _ready() -> void:
	add_to_group("player_flag_system")
	ui_controller = FLAG_UI_CONTROLLER.new(self)
	set_process(true)
	set_physics_process(true)


func _process(_delta: float) -> void:
	_refresh_scene_attachment()

	if not attached_to_game:
		return

	if world_grid == null or not is_instance_valid(world_grid):
		world_grid = get_tree().get_first_node_in_group("world_grid")
		_ensure_flag_visual()

	if ui_controller != null:
		ui_controller.call("update_targeting_preview")


func _physics_process(delta: float) -> void:
	if not attached_to_game or world_grid == null or not is_instance_valid(world_grid):
		return

	behaviour_update_timer -= delta

	if behaviour_update_timer > 0.0:
		return

	behaviour_update_timer = BEHAVIOUR_UPDATE_INTERVAL
	_update_creature_flag_behaviour()


func _unhandled_input(event: InputEvent) -> void:
	if ui_controller == null:
		return

	if bool(ui_controller.call("handle_unhandled_input", event)):
		get_viewport().set_input_as_handled()


func _refresh_scene_attachment() -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	var current_scene_id := int(current_scene.get_instance_id())

	if current_scene_id == attached_scene_id:
		return

	attached_scene_id = current_scene_id
	_detach_runtime_references()

	if current_scene.scene_file_path == GAME_SCENE_PATH:
		call_deferred("_attach_to_game_scene", current_scene)
	else:
		clear_all_flags()


func _attach_to_game_scene(scene: Node) -> void:
	for _attempt in range(UI_ATTACH_RETRY_FRAMES):
		if scene == null or not is_instance_valid(scene) or get_tree().current_scene != scene:
			return

		world_grid = get_tree().get_first_node_in_group("world_grid")
		nature_ui = get_tree().get_first_node_in_group("player_nature_ui")
		nature_content = null
		main_menu_grid = null
		flag_menu_button = null

		if (
			nature_ui != null
			and nature_ui.has_method("get_menu_content_root")
			and nature_ui.has_method("get_main_menu_grid")
			and nature_ui.has_method("get_menu_button")
		):
			nature_content = nature_ui.call("get_menu_content_root") as Control
			main_menu_grid = nature_ui.call("get_main_menu_grid") as GridContainer
			flag_menu_button = nature_ui.call("get_menu_button", &"flags") as Button

		if _has_required_runtime_nodes():
			attached_to_game = true
			_ensure_flag_visual()
			ui_controller.call(
				"attach",
				nature_ui,
				nature_content,
				main_menu_grid,
				flag_menu_button,
				_get_flag_menu_entries()
			)
			_sync_flag_visual()
			return

		await get_tree().process_frame

	push_warning("PlayerFlags: nature-menu API or world grid was not found.")


func _has_required_runtime_nodes() -> bool:
	return (
		world_grid != null
		and nature_ui != null
		and nature_content != null
		and main_menu_grid != null
		and flag_menu_button != null
	)


func _detach_runtime_references() -> void:
	if ui_controller != null:
		ui_controller.call("detach")

	attached_to_game = false
	world_grid = null
	flag_visual = null
	nature_ui = null
	nature_content = null
	main_menu_grid = null
	flag_menu_button = null
	behaviour_update_timer = 0.0
	_reset_behaviour_runtime()


func _ensure_flag_visual() -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		return

	if flag_visual != null and is_instance_valid(flag_visual):
		return

	var existing_visual := world_grid.get_node_or_null("PlayerFlagVisual") as Node2D

	if existing_visual != null:
		flag_visual = existing_visual
	else:
		flag_visual = FLAG_VISUAL_SCRIPT.new() as Node2D
		flag_visual.name = "PlayerFlagVisual"
		world_grid.add_child(flag_visual)

	if flag_visual != null and flag_visual.has_method("configure"):
		flag_visual.call("configure", world_grid)

	_sync_flag_visual()


func ensure_flag_visual() -> void:
	_ensure_flag_visual()


func get_flag_visual() -> Node2D:
	return flag_visual


func get_world_grid() -> Node:
	return world_grid


func get_flag_mouse_world_position() -> Vector2:
	var camera := get_viewport().get_camera_2d()

	if camera != null:
		return camera.get_global_mouse_position()

	return get_viewport().get_mouse_position()


func is_valid_flag_tile(tile: Vector2i) -> bool:
	if world_grid == null or not is_instance_valid(world_grid):
		return false

	if not bool(world_grid.call("is_tile_inside_map", tile)):
		return false

	return bool(world_grid.call("is_tile_walkable", tile))


func get_species_flag_at_tile(tile: Vector2i) -> StringName:
	for species_id_variant: Variant in flags.keys():
		var species_id := StringName(species_id_variant)

		if flags.get(species_id, INVALID_ANCHOR) == tile:
			return species_id

	return StringName()


func get_flag_count() -> int:
	return flags.size()


func get_flag_tile(species_id: StringName) -> Vector2i:
	var tile_variant: Variant = flags.get(species_id, INVALID_ANCHOR)
	return tile_variant if tile_variant is Vector2i else INVALID_ANCHOR


func _get_flag_menu_entries() -> Array[Dictionary]:
	return []


func _is_supported_species(species_id: StringName) -> bool:
	return species_id != StringName()


func set_flag(species_id: StringName, tile: Vector2i) -> void:
	if not _is_supported_species(species_id):
		return

	flags[species_id] = tile
	_reset_behaviour_runtime()
	_sync_flag_visual()


func remove_flag(species_id: StringName) -> void:
	flags.erase(species_id)
	_reset_behaviour_runtime()
	_sync_flag_visual()


func clear_all_flags() -> void:
	_reset_behaviour_runtime()
	flags.clear()
	_sync_flag_visual()


func has_flag(species_id: StringName) -> bool:
	return flags.has(species_id)


func get_save_data() -> Dictionary:
	var saved_flags: Array[Dictionary] = []

	for species_id_variant: Variant in flags.keys():
		var tile_variant: Variant = flags.get(species_id_variant)

		if not (tile_variant is Vector2i):
			continue

		var tile: Vector2i = tile_variant
		saved_flags.append({
			"species_id": String(species_id_variant),
			"tile_x": tile.x,
			"tile_y": tile.y
		})

	return {"flags": saved_flags}


func restore_save_data(save_data: Dictionary) -> void:
	_reset_behaviour_runtime()
	flags.clear()
	var saved_flags_variant: Variant = save_data.get("flags", [])

	if saved_flags_variant is Array:
		for record_variant: Variant in saved_flags_variant:
			if not (record_variant is Dictionary):
				continue

			var record := record_variant as Dictionary
			var species_id := StringName(String(record.get("species_id", "")))

			if not _is_supported_species(species_id):
				continue

			flags[species_id] = Vector2i(
				int(record.get("tile_x", 0)),
				int(record.get("tile_y", 0))
			)

	_sync_flag_visual()


func cancel_targeting() -> void:
	if ui_controller != null:
		ui_controller.call("cancel_targeting")


func is_targeting() -> bool:
	return ui_controller != null and bool(ui_controller.call("is_targeting"))


func _sync_flag_visual() -> void:
	if flag_visual != null and is_instance_valid(flag_visual) and flag_visual.has_method("set_flags"):
		flag_visual.call("set_flags", flags)

	if ui_controller != null:
		ui_controller.call("refresh_status")


func _update_creature_flag_behaviour() -> void:
	return


func _reset_behaviour_runtime() -> void:
	return


func get_creature_flag_debug_data(_creature: Node) -> Dictionary:
	return {"status": "нет активного флага", "committed": false, "target_retry": 0}
