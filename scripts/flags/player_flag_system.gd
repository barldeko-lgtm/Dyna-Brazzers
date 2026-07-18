extends Node

# Species-specific indirect orders. Flags softly attract otherwise-idle
# creatures into their own centered 11x11 area; survival, feeding,
# reproduction and combat stay above the flag in the behaviour priority order.

const GAME_SCENE_PATH := "res://scenes/main/main.tscn"
const FLAG_VISUAL_SCRIPT := preload("res://scripts/flags/player_flag_visual.gd")

const STEGOSAURUS_ID := &"stegosaurus"
const TRICERATOPS_ID := &"triceratops"
const TYRANNOSAURUS_ID := &"tyrannosaurus"
const RAPTOR_ID := &"raptor"
const PTERODACTYL_ID := &"pterodactyl"
const EGG_EATER_ID := &"egg_eater"
const SUPPORTED_SPECIES_IDS: Array[StringName] = [
	STEGOSAURUS_ID,
	TRICERATOPS_ID,
	TYRANNOSAURUS_ID,
	RAPTOR_ID,
	PTERODACTYL_ID,
	EGG_EATER_ID,
]
const FLAG_AREA_SIZE := Vector2i(11, 11)
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)

const CREATURE_STATE_IDLE := 0
const CREATURE_STATE_WALK := 1
const CREATURE_STATE_SEEK_FOOD := 2
const BEHAVIOUR_UPDATE_INTERVAL := 0.5
const FAILED_PATH_RETRY_SECONDS := 2.0
const PATH_SEARCH_TILE_CAP := 1800
const UI_ATTACH_RETRY_FRAMES := 16

const PLAYER_SIDE_ROOT := "UI/PlayerSidePanel/MarginContainer/VBoxContainer/"
const NATURE_PANEL_RELATIVE := "PlayerNaturePanel"
const NATURE_CONTENT_RELATIVE := NATURE_PANEL_RELATIVE + "/MarginContainer/VBoxContainer"
const MAIN_MENU_RELATIVE := NATURE_CONTENT_RELATIVE + "/MainMenuGrid"

const NATURE_PANEL_PATH := NodePath(PLAYER_SIDE_ROOT + NATURE_PANEL_RELATIVE)
const NATURE_CONTENT_PATH := NodePath(PLAYER_SIDE_ROOT + NATURE_CONTENT_RELATIVE)
const MAIN_MENU_GRID_PATH := NodePath(PLAYER_SIDE_ROOT + MAIN_MENU_RELATIVE)
const FLAG_MENU_BUTTON_PATH := NodePath(PLAYER_SIDE_ROOT + MAIN_MENU_RELATIVE + "/MainPlaceholder4")

var flags: Dictionary = {}
var assigned_targets: Dictionary = {}
var failed_path_retry_until: Dictionary = {}

var attached_scene_id := 0
var attached_to_game := false
var world_grid: Node = null
var flag_visual: Node2D = null

var nature_ui: Node = null
var nature_content: Control = null
var main_menu_grid: GridContainer = null
var flag_menu_button: Button = null
var flag_menu_grid: GridContainer = null
var status_label: Label = null

var targeting_species_id := StringName()
var removal_targeting_enabled := false
var behaviour_update_timer := 0.0


func _ready() -> void:
	add_to_group("player_flag_system")
	set_process(true)
	set_physics_process(true)


func _process(_delta: float) -> void:
	_refresh_scene_attachment()

	if not attached_to_game:
		return

	if world_grid == null or not is_instance_valid(world_grid):
		world_grid = get_tree().get_first_node_in_group("world_grid")
		_ensure_flag_visual()

	_update_targeting_preview()


func _physics_process(delta: float) -> void:
	if not attached_to_game or world_grid == null or not is_instance_valid(world_grid):
		return

	behaviour_update_timer -= delta

	if behaviour_update_timer > 0.0:
		return

	behaviour_update_timer = BEHAVIOUR_UPDATE_INTERVAL
	_update_creature_flag_behaviour()


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
		nature_ui = scene.get_node_or_null(NATURE_PANEL_PATH)
		nature_content = scene.get_node_or_null(NATURE_CONTENT_PATH) as Control
		main_menu_grid = scene.get_node_or_null(MAIN_MENU_GRID_PATH) as GridContainer
		flag_menu_button = scene.get_node_or_null(FLAG_MENU_BUTTON_PATH) as Button

		if _has_required_runtime_nodes():
			attached_to_game = true
			_ensure_flag_visual()
			_build_flag_menu()
			flag_menu_button.tooltip_text = "Флаги видов"

			if not flag_menu_button.pressed.is_connected(_on_flag_menu_button_pressed):
				flag_menu_button.pressed.connect(_on_flag_menu_button_pressed)

			_sync_flag_visual()
			return

		await get_tree().process_frame

	push_warning("PlayerFlags: player UI or world grid was not found.")


func _has_required_runtime_nodes() -> bool:
	return (
		world_grid != null
		and nature_ui != null
		and nature_content != null
		and main_menu_grid != null
		and flag_menu_button != null
	)


func _detach_runtime_references() -> void:
	cancel_targeting()
	attached_to_game = false
	world_grid = null
	flag_visual = null
	nature_ui = null
	nature_content = null
	main_menu_grid = null
	flag_menu_button = null
	flag_menu_grid = null
	status_label = null
	assigned_targets.clear()
	failed_path_retry_until.clear()
	behaviour_update_timer = 0.0


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


func _build_flag_menu() -> void:
	if flag_menu_grid != null and is_instance_valid(flag_menu_grid):
		return

	if nature_content == null or flag_menu_button == null:
		return

	flag_menu_grid = GridContainer.new()
	flag_menu_grid.name = "SpeciesFlagMenu"
	flag_menu_grid.position = Vector2(0.0, 66.0)
	flag_menu_grid.size = Vector2(260.0, 218.0)
	flag_menu_grid.columns = 3
	flag_menu_grid.add_theme_constant_override("h_separation", 6)
	flag_menu_grid.add_theme_constant_override("v_separation", 6)
	flag_menu_grid.visible = false
	nature_content.add_child(flag_menu_grid)

	for species_id in SUPPORTED_SPECIES_IDS:
		var species_button := _duplicate_menu_button()
		species_button.name = "%sFlagButton" % String(species_id).capitalize()
		species_button.custom_minimum_size = Vector2(80.0, 52.0)
		species_button.text = _get_species_button_text(species_id)
		species_button.tooltip_text = _get_species_flag_tooltip(species_id)
		species_button.add_theme_font_size_override("font_size", 11)
		species_button.pressed.connect(_on_species_flag_pressed.bind(species_id))
		flag_menu_grid.add_child(species_button)

	var remove_button := _duplicate_menu_button()
	remove_button.name = "RemoveSpeciesFlagButton"
	remove_button.custom_minimum_size = Vector2(80.0, 52.0)
	remove_button.text = "Удалить\nфлаг"
	remove_button.tooltip_text = "Выбрать флаг на карте для удаления"
	remove_button.add_theme_font_size_override("font_size", 12)
	remove_button.pressed.connect(_on_remove_flag_pressed)
	flag_menu_grid.add_child(remove_button)

	var back_button := _duplicate_menu_button()
	back_button.name = "FlagMenuBackButton"
	back_button.custom_minimum_size = Vector2(80.0, 52.0)
	back_button.text = "← Назад"
	back_button.tooltip_text = "Вернуться в основное меню"
	back_button.add_theme_font_size_override("font_size", 14)
	back_button.pressed.connect(_on_back_button_pressed)
	flag_menu_grid.add_child(back_button)

	status_label = Label.new()
	status_label.name = "FlagStatusLabel"
	status_label.custom_minimum_size = Vector2(80.0, 52.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 11)
	flag_menu_grid.add_child(status_label)
	_update_status_for_current_flag()


func _duplicate_menu_button() -> Button:
	var duplicated_button := flag_menu_button.duplicate() as Button

	if duplicated_button == null:
		duplicated_button = Button.new()

	duplicated_button.toggle_mode = false
	duplicated_button.button_pressed = false
	duplicated_button.focus_mode = Control.FOCUS_NONE
	duplicated_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return duplicated_button


func _on_flag_menu_button_pressed() -> void:
	if nature_ui != null and nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")

	if main_menu_grid != null:
		main_menu_grid.visible = false

	if flag_menu_grid != null:
		flag_menu_grid.visible = true

	_update_status_for_current_flag()


func _on_species_flag_pressed(species_id: StringName) -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		_set_status("Мир не найден")
		return

	if nature_ui != null and nature_ui.has_method("cancel_all_targeting"):
		nature_ui.call("cancel_all_targeting")

	removal_targeting_enabled = false
	targeting_species_id = species_id
	_set_status("ЛКМ по карте\nПКМ — отмена")
	_update_targeting_preview()


func _on_remove_flag_pressed() -> void:
	cancel_targeting()
	removal_targeting_enabled = true
	_set_status("ЛКМ по флагу\nПКМ — отмена")


func _on_back_button_pressed() -> void:
	cancel_targeting()

	if flag_menu_grid != null:
		flag_menu_grid.visible = false

	if main_menu_grid != null:
		main_menu_grid.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_targeting() or not (event is InputEventMouseButton):
		return

	_handle_targeting_mouse(event as InputEventMouseButton)


func _handle_targeting_mouse(mouse_event: InputEventMouseButton) -> void:
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_targeting()
		_set_status("Установка отменена")
		get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if world_grid == null or not is_instance_valid(world_grid):
		return

	var mouse_world_position := _get_world_mouse_position()
	var target_tile: Vector2i = world_grid.call("world_to_map_tile", mouse_world_position)

	if removal_targeting_enabled:
		var species_id := _get_species_flag_at_tile(target_tile)

		if species_id == StringName():
			_set_status("Нужен центр\nфлага")
			return

		remove_flag(species_id)
		cancel_targeting()
		_set_status("Флаг удалён")
		get_viewport().set_input_as_handled()
		return

	if not _is_valid_flag_tile(target_tile):
		_set_status("Нужен свободный\nтайл земли")
		return

	set_flag(targeting_species_id, target_tile)
	cancel_targeting()
	_set_status("Флаг поставлен")
	get_viewport().set_input_as_handled()


func cancel_targeting() -> void:
	targeting_species_id = StringName()
	removal_targeting_enabled = false

	if flag_visual == null or not is_instance_valid(flag_visual):
		return

	if flag_visual.has_method("hide_preview"):
		flag_visual.call("hide_preview")


func is_targeting() -> bool:
	return targeting_species_id != StringName() or removal_targeting_enabled


func _update_targeting_preview() -> void:
	if not is_targeting():
		return

	if world_grid == null or not is_instance_valid(world_grid):
		return

	if removal_targeting_enabled:
		if flag_visual != null and is_instance_valid(flag_visual):
			flag_visual.call("hide_preview")
		return

	_ensure_flag_visual()

	if flag_visual == null or not is_instance_valid(flag_visual):
		return

	var target_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())
	var is_valid := _is_valid_flag_tile(target_tile)

	if flag_visual.has_method("set_preview"):
		flag_visual.call("set_preview", target_tile, is_valid)


func _get_world_mouse_position() -> Vector2:
	var camera := get_viewport().get_camera_2d()

	if camera != null:
		return camera.get_global_mouse_position()

	return get_viewport().get_mouse_position()


func _is_valid_flag_tile(tile: Vector2i) -> bool:
	if world_grid == null or not is_instance_valid(world_grid):
		return false

	if not bool(world_grid.call("is_tile_inside_map", tile)):
		return false

	return bool(world_grid.call("is_tile_walkable", tile))


func _get_species_flag_at_tile(tile: Vector2i) -> StringName:
	for species_id in SUPPORTED_SPECIES_IDS:
		if flags.get(species_id, INVALID_ANCHOR) == tile:
			return species_id

	return StringName()


func _get_species_button_text(species_id: StringName) -> String:
	match species_id:
		STEGOSAURUS_ID:
			return "Стего\nпастбище"
		TRICERATOPS_ID:
			return "Трицер\nпастбище"
		TYRANNOSAURUS_ID:
			return "Ти-рекс\nохота"
		RAPTOR_ID:
			return "Раптор\nзащита"
		PTERODACTYL_ID:
			return "Птеро\nпатруль"
		EGG_EATER_ID:
			return "Яйцеед\nпоиск"
		_:
			return "Флаг\nвида"


func _get_species_flag_tooltip(species_id: StringName) -> String:
	match species_id:
		STEGOSAURUS_ID:
			return "Поставить или перенести пастбищный флаг стегозавров"
		TRICERATOPS_ID:
			return "Поставить или перенести пастбищный флаг трицератопсов"
		TYRANNOSAURUS_ID:
			return "Поставить или перенести флаг охоты ти-рексов"
		RAPTOR_ID:
			return "Поставить или перенести защитный флаг рапторов"
		PTERODACTYL_ID:
			return "Поставить или перенести патрульный флаг птеродактилей"
		EGG_EATER_ID:
			return "Поставить или перенести флаг поиска яйцеедов"
		_:
			return "Поставить или перенести флаг вида"


func set_flag(species_id: StringName, tile: Vector2i) -> void:
	if not SUPPORTED_SPECIES_IDS.has(species_id):
		return

	_cancel_assigned_flag_routes()
	flags[species_id] = tile
	assigned_targets.clear()
	failed_path_retry_until.clear()
	_sync_flag_visual()


func remove_flag(species_id: StringName) -> void:
	_cancel_assigned_flag_routes()
	flags.erase(species_id)
	assigned_targets.clear()
	failed_path_retry_until.clear()
	_sync_flag_visual()


func clear_all_flags() -> void:
	_cancel_assigned_flag_routes()
	flags.clear()
	assigned_targets.clear()
	failed_path_retry_until.clear()
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
		saved_flags.append(
			{"species_id": String(species_id_variant), "tile_x": tile.x, "tile_y": tile.y}
		)

	return {"flags": saved_flags}


func restore_save_data(save_data: Dictionary) -> void:
	_cancel_assigned_flag_routes()
	flags.clear()
	assigned_targets.clear()
	failed_path_retry_until.clear()

	var saved_flags_variant: Variant = save_data.get("flags", [])

	if saved_flags_variant is Array:
		for record_variant: Variant in saved_flags_variant:
			if not (record_variant is Dictionary):
				continue

			var record := record_variant as Dictionary
			var species_id := StringName(String(record.get("species_id", "")))

			if species_id == StringName() or not SUPPORTED_SPECIES_IDS.has(species_id):
				continue

			flags[species_id] = Vector2i(int(record.get("tile_x", 0)), int(record.get("tile_y", 0)))

	_sync_flag_visual()


func _sync_flag_visual() -> void:
	if flag_visual == null or not is_instance_valid(flag_visual):
		return

	if flag_visual.has_method("set_flags"):
		flag_visual.call("set_flags", flags)


func _update_status_for_current_flag() -> void:
	if flags.is_empty():
		_set_status("Флагов нет")
		return

	_set_status("Флагов: %d" % flags.size())


func _set_status(message: String) -> void:
	if status_label != null and is_instance_valid(status_label):
		status_label.text = message


func _update_creature_flag_behaviour() -> void:
	_cleanup_creature_runtime_data()

	if flags.is_empty():
		return

	PerformanceStats.add_counter("flag_updates")
	var scanned_creatures := 0

	for creature: Node in get_tree().get_nodes_in_group("creatures"):
		scanned_creatures += 1
		var species_id := _get_creature_species_id(creature)

		if species_id == StringName() or not has_flag(species_id):
			_release_creature_target(creature)
			continue

		# Hunger immediately cancels the flag-owned route. If the creature is in
		# the middle of one grid step, let that step finish but switch its state to
		# SEEK_FOOD now so it cannot start another flag/wander step afterwards.
		if _hunger_overrides_flag(creature):
			_drop_flag_route_for_hunger(creature)
			continue

		if not _can_follow_flag(creature):
			_release_creature_target(creature)
			continue

		var footprint_variant: Variant = creature.get("footprint_size")
		var anchor_variant: Variant = creature.get("anchor_tile")

		if not (footprint_variant is Vector2i) or not (anchor_variant is Vector2i):
			continue

		var footprint: Vector2i = footprint_variant
		var anchor: Vector2i = anchor_variant
		var navigation_anchor := anchor

		if creature.has_method("get_navigation_anchor"):
			var navigation_variant: Variant = creature.call("get_navigation_anchor")

			if navigation_variant is Vector2i:
				navigation_anchor = navigation_variant

		if _is_footprint_inside_flag_area(species_id, navigation_anchor, footprint):
			_release_creature_target(creature, true)
			continue

		var retry_until := int(failed_path_retry_until.get(creature, 0))

		if Time.get_ticks_msec() < retry_until:
			continue

		var previous_target_variant: Variant = assigned_targets.get(creature, INVALID_ANCHOR)
		var already_assigned := previous_target_variant is Vector2i
		var target_anchor := _get_or_assign_target(creature, species_id, footprint)

		if target_anchor == INVALID_ANCHOR:
			_set_failed_path_retry(creature)
			continue

		# An existing assignment with a current movement step or queued path is
		# already being followed. A newly assigned creature is handled below even
		# while it is moving: its flag route becomes the continuation after the
		# current step, which lets the whole herd react instead of only whichever
		# creature happens to be standing still during this update.
		if (
			already_assigned
			and previous_target_variant == target_anchor
			and _has_flag_route_in_progress(creature)
		):
			continue

		var max_path_tiles := PATH_SEARCH_TILE_CAP
		var creature_cap_variant: Variant = creature.get("max_path_search_tiles")

		if creature_cap_variant is int:
			max_path_tiles = max(PATH_SEARCH_TILE_CAP, int(creature_cap_variant))

		PerformanceStats.add_counter("flag_path_requests")
		var path_variant: Variant = world_grid.call(
			"find_path", navigation_anchor, target_anchor, footprint, creature, max_path_tiles
		)

		if not (path_variant is Array) or (path_variant as Array).is_empty():
			PerformanceStats.add_counter("flag_path_failures")
			_release_creature_target(creature, true)
			_set_failed_path_retry(creature)
			continue

		_apply_flag_path(creature, path_variant as Array)

	PerformanceStats.add_counter("flag_creatures_scanned", scanned_creatures)


func _get_creature_species_id(creature: Node) -> StringName:
	if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
		return StringName()

	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null:
		return StringName()

	var species_id := StringName(species_data.species_id)
	return species_id if SUPPORTED_SPECIES_IDS.has(species_id) else StringName()


func _species_prefers_pasture(species_id: StringName) -> bool:
	return species_id == STEGOSAURUS_ID or species_id == TRICERATOPS_ID


func _is_creature_hungry(creature: Node) -> bool:
	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null:
		return false

	return float(creature.get("hunger")) <= species_data.hunger_search_threshold


func _hunger_overrides_flag(creature: Node) -> bool:
	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null or species_data.is_egg_eater():
		return false

	return _is_creature_hungry(creature)


func _can_follow_flag(creature: Node) -> bool:
	if _get_creature_species_id(creature) == StringName() or _hunger_overrides_flag(creature):
		return false

	var state := int(creature.get("state"))
	return state == CREATURE_STATE_IDLE or state == CREATURE_STATE_WALK


func _has_flag_route_in_progress(creature: Node) -> bool:
	if bool(creature.get("is_moving")):
		return true

	var current_path_variant: Variant = creature.get("current_path")
	return current_path_variant is Array and not (current_path_variant as Array).is_empty()


func _apply_flag_path(creature: Node, path: Array) -> void:
	# Never interrupt the creature halfway between grid anchors. While it is
	# moving, replace only the queued continuation; the active step completes
	# normally and the flag route starts immediately afterwards.
	if bool(creature.get("is_moving")):
		creature.set("current_path", path)
		creature.set("state_timer", 30.0)
		return

	if creature.has_method("enter_walk"):
		creature.call("enter_walk")

	creature.set("state_timer", 30.0)
	creature.set("current_path", path)

	if creature.has_method("start_next_path_step_if_needed"):
		creature.call("start_next_path_step_if_needed")


func _drop_flag_route_for_hunger(creature: Node) -> void:
	var had_flag_assignment := assigned_targets.has(creature)
	assigned_targets.erase(creature)
	failed_path_retry_until.erase(creature)

	if not had_flag_assignment:
		return

	_clear_queued_path(creature)
	creature.set("has_grazing_target", false)
	creature.set("food_recheck_timer", 0.0)

	var grazing_queue_variant: Variant = creature.get("grazing_candidate_queue")

	if grazing_queue_variant is Array:
		(grazing_queue_variant as Array).clear()

	if bool(creature.get("is_moving")):
		if creature.has_method("change_state"):
			creature.call("change_state", CREATURE_STATE_SEEK_FOOD)
		else:
			creature.set("state", CREATURE_STATE_SEEK_FOOD)
		return

	if creature.has_method("enter_hungry_behavior"):
		creature.call("enter_hungry_behavior")


func _clear_queued_path(creature: Node) -> void:
	var current_path_variant: Variant = creature.get("current_path")

	if current_path_variant is Array:
		var current_path := current_path_variant as Array
		current_path.clear()
		creature.set("current_path", current_path)


func _get_or_assign_target(
	creature: Node, species_id: StringName, footprint: Vector2i
) -> Vector2i:
	var existing_variant: Variant = assigned_targets.get(creature, INVALID_ANCHOR)

	if existing_variant is Vector2i:
		var existing: Vector2i = existing_variant

		if existing != INVALID_ANCHOR and _is_valid_assigned_target(
			creature, species_id, existing, footprint
		):
			return existing

	var new_target := INVALID_ANCHOR

	if _species_prefers_pasture(species_id):
		new_target = _find_grass_target(creature, species_id, footprint)

	if new_target == INVALID_ANCHOR:
		new_target = _find_free_target(creature, species_id, footprint)

	if new_target != INVALID_ANCHOR:
		assigned_targets[creature] = new_target

	return new_target


func _find_grass_target(
	creature: Node, species_id: StringName, footprint: Vector2i
) -> Vector2i:
	var flag_tile_variant: Variant = flags.get(species_id, INVALID_ANCHOR)

	if not (flag_tile_variant is Vector2i):
		return INVALID_ANCHOR

	var flag_tile: Vector2i = flag_tile_variant
	var ranked_variant: Variant = world_grid.call(
		"find_best_grazing_targets", flag_tile, footprint, 1, 5, creature, 24.0, 0.5, 16
	)

	if not (ranked_variant is Array):
		return INVALID_ANCHOR

	var candidates: Array[Vector2i] = []

	for result_variant: Variant in ranked_variant:
		if not (result_variant is Dictionary):
			continue

		var candidate_variant: Variant = (result_variant as Dictionary).get(
			"anchor", INVALID_ANCHOR
		)

		if not (candidate_variant is Vector2i):
			continue

		var candidate: Vector2i = candidate_variant

		if not _anchor_fits_flag_area(species_id, candidate, footprint):
			continue

		if not bool(world_grid.call("can_place_footprint", candidate, footprint, creature)):
			continue

		if _is_target_reserved_by_other(creature, candidate, footprint):
			continue

		candidates.append(candidate)

	return _choose_spread_candidate(creature, species_id, candidates)


func _find_free_target(
	creature: Node, species_id: StringName, footprint: Vector2i
) -> Vector2i:
	var bounds := _get_flag_area_bounds(species_id)

	if bounds.is_empty():
		return INVALID_ANCHOR

	var area_min: Vector2i = bounds.get("min", Vector2i.ZERO)
	var area_end: Vector2i = bounds.get("end", Vector2i.ZERO)
	var candidates: Array[Vector2i] = []

	for y in range(area_min.y, area_end.y - footprint.y + 1):
		for x in range(area_min.x, area_end.x - footprint.x + 1):
			var candidate := Vector2i(x, y)

			if not bool(world_grid.call("can_place_footprint", candidate, footprint, creature)):
				continue

			if _is_target_reserved_by_other(creature, candidate, footprint):
				continue

			candidates.append(candidate)

	return _choose_spread_candidate(creature, species_id, candidates)


func _choose_spread_candidate(
	creature: Node, species_id: StringName, candidates: Array[Vector2i]
) -> Vector2i:
	if candidates.is_empty():
		return INVALID_ANCHOR

	var seed_value := int(creature.get_instance_id())
	var flag_tile: Vector2i = flags.get(species_id, Vector2i.ZERO)
	var start_index := posmod(seed_value + flag_tile.x * 31 + flag_tile.y * 17, candidates.size())
	return candidates[start_index]


func _is_valid_assigned_target(
	creature: Node, species_id: StringName, target: Vector2i, footprint: Vector2i
) -> bool:
	if not _anchor_fits_flag_area(species_id, target, footprint):
		return false

	if not bool(world_grid.call("can_place_footprint", target, footprint, creature)):
		return false

	return not _is_target_reserved_by_other(creature, target, footprint)


func _is_target_reserved_by_other(creature: Node, target: Vector2i, footprint: Vector2i) -> bool:
	var target_tiles: Array = world_grid.call("get_footprint_tiles", target, footprint)

	for other_creature_variant: Variant in assigned_targets.keys():
		var other_creature := other_creature_variant as Node

		if (
			other_creature == creature
			or other_creature == null
			or not is_instance_valid(other_creature)
		):
			continue

		var other_target_variant: Variant = assigned_targets.get(other_creature, INVALID_ANCHOR)
		var other_footprint_variant: Variant = other_creature.get("footprint_size")

		if not (other_target_variant is Vector2i) or not (other_footprint_variant is Vector2i):
			continue

		var other_tiles: Array = world_grid.call(
			"get_footprint_tiles", other_target_variant, other_footprint_variant
		)

		for tile_variant: Variant in target_tiles:
			if other_tiles.has(tile_variant):
				return true

	return false


func _is_footprint_inside_flag_area(
	species_id: StringName, anchor: Vector2i, footprint: Vector2i
) -> bool:
	var bounds := _get_flag_area_bounds(species_id)

	if bounds.is_empty():
		return false

	var area_min: Vector2i = bounds.get("min", Vector2i.ZERO)
	var area_end: Vector2i = bounds.get("end", Vector2i.ZERO)
	var footprint_center := Vector2(anchor) + Vector2(footprint) * 0.5
	return (
		footprint_center.x >= float(area_min.x)
		and footprint_center.x < float(area_end.x)
		and footprint_center.y >= float(area_min.y)
		and footprint_center.y < float(area_end.y)
	)


func _anchor_fits_flag_area(species_id: StringName, anchor: Vector2i, footprint: Vector2i) -> bool:
	var bounds := _get_flag_area_bounds(species_id)

	if bounds.is_empty():
		return false

	var area_min: Vector2i = bounds.get("min", Vector2i.ZERO)
	var area_end: Vector2i = bounds.get("end", Vector2i.ZERO)
	return (
		anchor.x >= area_min.x
		and anchor.y >= area_min.y
		and anchor.x + footprint.x <= area_end.x
		and anchor.y + footprint.y <= area_end.y
	)


func _get_flag_area_bounds(species_id: StringName) -> Dictionary:
	var tile_variant: Variant = flags.get(species_id, INVALID_ANCHOR)

	if not (tile_variant is Vector2i):
		return {}

	var flag_tile: Vector2i = tile_variant
	var area_min := flag_tile - Vector2i(FLAG_AREA_SIZE.x / 2, FLAG_AREA_SIZE.y / 2)
	return {"min": area_min, "end": area_min + FLAG_AREA_SIZE}


func _cancel_assigned_flag_routes() -> void:
	for creature_variant: Variant in assigned_targets.keys():
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature):
			continue

		_cancel_flag_route_continuation(creature)


func _release_creature_target(creature: Node, clear_flag_route := false) -> void:
	var had_flag_assignment := assigned_targets.has(creature)
	assigned_targets.erase(creature)
	failed_path_retry_until.erase(creature)

	if clear_flag_route and had_flag_assignment:
		_cancel_flag_route_continuation(creature)


func _cancel_flag_route_continuation(creature: Node) -> void:
	if creature == null or not is_instance_valid(creature):
		return

	var state := int(creature.get("state"))

	if state != CREATURE_STATE_IDLE and state != CREATURE_STATE_WALK:
		return

	_clear_queued_path(creature)

	if bool(creature.get("is_moving")):
		# Finish only the active grid step, then fall back to idle instead of
		# immediately starting another obsolete flag/wander route.
		creature.set("state_timer", 0.0)
		return

	if creature.has_method("enter_walk"):
		creature.call("enter_walk")


func _set_failed_path_retry(creature: Node) -> void:
	failed_path_retry_until[creature] = (
		Time.get_ticks_msec() + int(FAILED_PATH_RETRY_SECONDS * 1000.0)
	)


func _cleanup_creature_runtime_data() -> void:
	for creature_variant: Variant in assigned_targets.keys():
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			assigned_targets.erase(creature_variant)

	for creature_variant: Variant in failed_path_retry_until.keys():
		var creature := creature_variant as Node

		if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
			failed_path_retry_until.erase(creature_variant)
