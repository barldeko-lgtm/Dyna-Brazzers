extends CanvasLayer

const TOTAL_STEPS := 10
const INTRO_PANEL_SIZE := Vector2(1000.0, 686.0)
const INTERFACE_PANEL_SIZE := Vector2(900.0, 620.0)
const INSTRUCTION_PANEL_SIZE := Vector2(700.0, 480.0)
const WAIT_PANEL_SIZE := Vector2(700.0, 300.0)
const RAIN_TARGET_PANEL_SIZE := Vector2(760.0, 270.0)
const FLAG_PLACEMENT_PANEL_SIZE := Vector2(760.0, 320.0)
const COMPLETION_PANEL_SIZE := Vector2(850.0, 580.0)
const INTERFACE_PANEL_SHIFT_LEFT := 150.0
const INSTRUCTION_PANEL_SHIFT_LEFT := 180.0
const WAIT_PANEL_SHIFT_LEFT := 180.0
const WAIT_PANEL_SHIFT_UP := 150.0
const RAIN_TARGET_PANEL_SHIFT_LEFT := 150.0
const RAIN_TARGET_PANEL_SHIFT_UP := 249.0
const FLAG_PLACEMENT_PANEL_SHIFT_LEFT := 150.0
const FLAG_PLACEMENT_PANEL_SHIFT_UP := 224.0
const RAIN_TARGET_RADIUS_TILES := 2
const HIGHLIGHT_PADDING := 5.0

@onready var spotlight: Control = $Spotlight
@onready var panel_center: CenterContainer = $PanelCenter
@onready var panel: Control = $PanelCenter/Panel
@onready var header_label: Label = $PanelCenter/Panel/HeaderLabel
@onready var body_label: Label = $PanelCenter/Panel/BodyLabel
@onready var skip_button: Button = $PanelCenter/Panel/SkipButton
@onready var next_button: Button = $PanelCenter/Panel/NextButton
@onready var input_blockers: Array[Control] = [
	$InputBlockers/Top,
	$InputBlockers/Bottom,
	$InputBlockers/Left,
	$InputBlockers/Right,
]

var owns_active_tutorial := false
var current_step := 1
var egg_menu_button: Button = null
var tracked_egg: Node2D = null
var rain_target_center_tile := Vector2i.ZERO
var rain_target_area_screen_rect := Rect2()
var rain_target_tile_screen_rect := Rect2()
var rain_completed := false
var stegosaurus_flag_selected := false
var flag_placement_active := false
var showing_completion := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	visible = false
	skip_button.pressed.connect(_on_skip_pressed)
	next_button.pressed.connect(_on_next_pressed)
	LocalizationManager.locale_changed.connect(_on_locale_changed)
	_start_if_requested()


func _process(_delta: float) -> void:
	if current_step == 5 and tracked_egg != null and is_instance_valid(tracked_egg):
		_refresh_wait_step_highlights()


func _exit_tree() -> void:
	if not owns_active_tutorial or not TutorialManager.is_tutorial_active():
		return

	TutorialManager.finish_tutorial()
	Engine.time_scale = 1.0


func _start_if_requested() -> void:
	if not TutorialManager.begin_requested_tutorial():
		return

	owns_active_tutorial = true
	visible = true
	Engine.time_scale = 0.0
	_show_step(1)


func _show_step(step_number: int) -> void:
	current_step = clampi(step_number, 1, TOTAL_STEPS)
	showing_completion = false
	flag_placement_active = false
	skip_button.visible = true
	next_button.visible = true
	_set_fully_blocked()
	spotlight.call("set_hole_rects", [])

	match current_step:
		1:
			_apply_intro_layout()
			next_button.disabled = false
		2:
			_apply_interface_layout()
			next_button.disabled = false
			call_deferred("_refresh_interface_highlights")
		3:
			_apply_instruction_layout()
			next_button.disabled = true
			call_deferred("_configure_egg_menu_step")
		4:
			_apply_instruction_layout()
			next_button.disabled = true
			call_deferred("_configure_stegosaurus_step")
		5:
			_apply_wait_layout()
			next_button.disabled = true
			Engine.time_scale = 1.0
			call_deferred("_configure_wait_step")
		6:
			_apply_instruction_layout()
			next_button.disabled = true
			Engine.time_scale = 0.0
			call_deferred("_configure_spells_step")
		7:
			_apply_instruction_layout()
			next_button.disabled = true
			Engine.time_scale = 0.0
			call_deferred("_configure_rain_step")
		8:
			_apply_rain_target_layout()
			next_button.disabled = true
			Engine.time_scale = 0.0
			call_deferred("_configure_rain_target_step")
		9:
			_apply_instruction_layout()
			next_button.disabled = true
			Engine.time_scale = 0.0
			call_deferred("_configure_flags_step")
		10:
			_apply_flag_placement_layout()
			next_button.disabled = true
			Engine.time_scale = 0.0
			call_deferred("_configure_stegosaurus_flag_step")
		_:
			_apply_instruction_layout()
			next_button.disabled = true

	_refresh_localized_text()


func _apply_intro_layout() -> void:
	panel.custom_minimum_size = INTRO_PANEL_SIZE
	panel_center.offset_left = 0.0
	panel_center.offset_right = 0.0
	panel_center.offset_top = 0.0
	panel_center.offset_bottom = 0.0
	_set_control_rect(header_label, Vector2(105.0, 66.0), Vector2(790.0, 46.0))
	_set_control_rect(body_label, Vector2(112.0, 130.0), Vector2(776.0, 440.0))
	body_label.add_theme_font_size_override("font_size", 20)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_control_rect(next_button, Vector2(305.0, 587.0), Vector2(170.0, 54.0))
	_set_control_rect(skip_button, Vector2(525.0, 587.0), Vector2(170.0, 54.0))


func _apply_interface_layout() -> void:
	panel.custom_minimum_size = INTERFACE_PANEL_SIZE
	panel_center.offset_left = -INTERFACE_PANEL_SHIFT_LEFT
	panel_center.offset_right = -INTERFACE_PANEL_SHIFT_LEFT
	panel_center.offset_top = 0.0
	panel_center.offset_bottom = 0.0
	_set_control_rect(header_label, Vector2(90.0, 52.0), Vector2(720.0, 42.0))
	_set_control_rect(body_label, Vector2(96.0, 108.0), Vector2(708.0, 390.0))
	body_label.add_theme_font_size_override("font_size", 20)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_set_control_rect(next_button, Vector2(250.0, 530.0), Vector2(170.0, 52.0))
	_set_control_rect(skip_button, Vector2(480.0, 530.0), Vector2(170.0, 52.0))


func _apply_instruction_layout() -> void:
	panel.custom_minimum_size = INSTRUCTION_PANEL_SIZE
	panel_center.offset_left = -INSTRUCTION_PANEL_SHIFT_LEFT
	panel_center.offset_right = -INSTRUCTION_PANEL_SHIFT_LEFT
	panel_center.offset_top = 0.0
	panel_center.offset_bottom = 0.0
	_set_control_rect(header_label, Vector2(70.0, 48.0), Vector2(560.0, 42.0))
	_set_control_rect(body_label, Vector2(78.0, 108.0), Vector2(544.0, 230.0))
	body_label.add_theme_font_size_override("font_size", 20)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_control_rect(next_button, Vector2(155.0, 385.0), Vector2(170.0, 52.0))
	_set_control_rect(skip_button, Vector2(375.0, 385.0), Vector2(170.0, 52.0))


func _apply_wait_layout() -> void:
	panel.custom_minimum_size = WAIT_PANEL_SIZE
	panel_center.offset_left = -WAIT_PANEL_SHIFT_LEFT
	panel_center.offset_right = -WAIT_PANEL_SHIFT_LEFT
	panel_center.offset_top = -WAIT_PANEL_SHIFT_UP
	panel_center.offset_bottom = -WAIT_PANEL_SHIFT_UP
	_set_control_rect(header_label, Vector2(70.0, 28.0), Vector2(560.0, 38.0))
	_set_control_rect(body_label, Vector2(78.0, 72.0), Vector2(544.0, 120.0))
	body_label.add_theme_font_size_override("font_size", 20)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_control_rect(next_button, Vector2(155.0, 215.0), Vector2(170.0, 48.0))
	_set_control_rect(skip_button, Vector2(375.0, 215.0), Vector2(170.0, 48.0))


func _apply_rain_target_layout() -> void:
	panel.custom_minimum_size = RAIN_TARGET_PANEL_SIZE
	panel_center.offset_left = -RAIN_TARGET_PANEL_SHIFT_LEFT
	panel_center.offset_right = -RAIN_TARGET_PANEL_SHIFT_LEFT
	panel_center.offset_top = -RAIN_TARGET_PANEL_SHIFT_UP
	panel_center.offset_bottom = -RAIN_TARGET_PANEL_SHIFT_UP
	_set_control_rect(header_label, Vector2(60.0, 14.0), Vector2(640.0, 32.0))
	_set_control_rect(body_label, Vector2(50.0, 48.0), Vector2(660.0, 144.0))
	body_label.add_theme_font_size_override("font_size", 20)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_control_rect(next_button, Vector2(185.0, 210.0), Vector2(170.0, 44.0))
	_set_control_rect(skip_button, Vector2(405.0, 210.0), Vector2(170.0, 44.0))


func _apply_flag_placement_layout() -> void:
	panel.custom_minimum_size = FLAG_PLACEMENT_PANEL_SIZE
	panel_center.offset_left = -FLAG_PLACEMENT_PANEL_SHIFT_LEFT
	panel_center.offset_right = -FLAG_PLACEMENT_PANEL_SHIFT_LEFT
	panel_center.offset_top = -FLAG_PLACEMENT_PANEL_SHIFT_UP
	panel_center.offset_bottom = -FLAG_PLACEMENT_PANEL_SHIFT_UP
	_set_control_rect(header_label, Vector2(60.0, 14.0), Vector2(640.0, 32.0))
	_set_control_rect(body_label, Vector2(50.0, 48.0), Vector2(660.0, 198.0))
	body_label.add_theme_font_size_override("font_size", 20)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_control_rect(next_button, Vector2(185.0, 260.0), Vector2(170.0, 44.0))
	_set_control_rect(skip_button, Vector2(405.0, 260.0), Vector2(170.0, 44.0))


func _apply_completion_layout() -> void:
	panel.custom_minimum_size = COMPLETION_PANEL_SIZE
	panel_center.offset_left = 0.0
	panel_center.offset_right = 0.0
	panel_center.offset_top = 0.0
	panel_center.offset_bottom = 0.0
	_set_control_rect(header_label, Vector2(90.0, 58.0), Vector2(670.0, 48.0))
	_set_control_rect(body_label, Vector2(95.0, 128.0), Vector2(660.0, 260.0))
	body_label.add_theme_font_size_override("font_size", 20)
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_control_rect(next_button, Vector2(340.0, 430.0), Vector2(170.0, 52.0))
	skip_button.visible = false


func _set_control_rect(control: Control, position: Vector2, control_size: Vector2) -> void:
	control.position = position
	control.size = control_size


func _refresh_interface_highlights() -> void:
	if current_step != 2 or spotlight == null:
		return

	var highlight_rects: Array[Rect2] = []
	var player_ui := get_tree().get_first_node_in_group("player_ui")
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")

	if player_ui != null:
		_append_control_highlight(
			highlight_rects,
			player_ui.call("get_tutorial_minimap_control") as Control
		)
		_append_control_highlight(
			highlight_rects,
			player_ui.call("get_tutorial_creature_counts_control") as Control
		)

	if nature_ui != null:
		var energy_controls_variant: Variant = nature_ui.call("get_tutorial_energy_controls")
		if energy_controls_variant is Array:
			var energy_rect := _get_controls_global_rect(energy_controls_variant as Array)
			if energy_rect.size.x > 0.0 and energy_rect.size.y > 0.0:
				highlight_rects.append(_global_rect_to_spotlight(energy_rect).grow(HIGHLIGHT_PADDING))

		_append_control_highlight(
			highlight_rects,
			nature_ui.call("get_tutorial_time_controls") as Control
		)

	if highlight_rects.size() != 4:
		push_warning(
			"Tutorial step 2 resolved %d of 4 interface highlights." % highlight_rects.size()
		)

	spotlight.call("set_hole_rects", highlight_rects)


func _configure_egg_menu_step() -> void:
	if current_step != 3:
		return

	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	egg_menu_button = nature_ui.call("get_menu_button", &"eggs") as Button if nature_ui != null else null

	if egg_menu_button == null or not is_instance_valid(egg_menu_button):
		push_warning("Tutorial step 3 could not resolve the egg-menu button; manual advance enabled.")
		next_button.disabled = false
		return

	if not egg_menu_button.pressed.is_connected(_on_egg_menu_pressed):
		egg_menu_button.pressed.connect(_on_egg_menu_pressed)
	_set_interactive_highlight(egg_menu_button)


func _configure_stegosaurus_step() -> void:
	if current_step != 4:
		return

	var egg_creation_ui := get_tree().get_first_node_in_group("player_egg_creation_ui")
	var stegosaurus_button := (
		egg_creation_ui.call("get_species_button", &"stegosaurus") as Button
		if egg_creation_ui != null
		else null
	)

	if stegosaurus_button == null or not is_instance_valid(stegosaurus_button):
		push_warning("Tutorial step 4 could not resolve the stegosaurus egg button.")
		return

	var egg_created_callback := Callable(self, "_on_tutorial_egg_created")
	if not egg_creation_ui.is_connected("egg_created", egg_created_callback):
		egg_creation_ui.connect("egg_created", egg_created_callback)
	_set_interactive_highlight(stegosaurus_button)


func _on_tutorial_egg_created(species_id: StringName, egg: Node2D) -> void:
	if current_step != 4 or species_id != &"stegosaurus" or egg == null:
		return

	tracked_egg = egg
	var hatch_callback := Callable(self, "_on_tracked_egg_hatched")
	if not tracked_egg.is_connected("hatched", hatch_callback):
		tracked_egg.connect("hatched", hatch_callback, CONNECT_ONE_SHOT)
	var exit_callback := Callable(self, "_on_tracked_egg_tree_exiting")
	if not tracked_egg.tree_exiting.is_connected(exit_callback):
		tracked_egg.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)

	var egg_creation_ui := get_tree().get_first_node_in_group("player_egg_creation_ui")
	if egg_creation_ui != null and egg_creation_ui.has_method("return_to_main_menu"):
		egg_creation_ui.call("return_to_main_menu")
	_show_step(5)


func _configure_wait_step() -> void:
	if current_step != 5:
		return
	_refresh_wait_step_highlights()


func _refresh_wait_step_highlights() -> void:
	if current_step != 5 or tracked_egg == null or not is_instance_valid(tracked_egg):
		return

	var highlight_rects: Array[Rect2] = []
	var egg_rect := _get_tracked_egg_screen_rect()
	if egg_rect.size.x > 0.0 and egg_rect.size.y > 0.0:
		_position_wait_panel_clear_of_egg(egg_rect)
		highlight_rects.append(egg_rect.grow(HIGHLIGHT_PADDING))

	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	var speed_controls := (
		nature_ui.call("get_tutorial_time_controls") as Control
		if nature_ui != null
		else null
	)
	if speed_controls != null and speed_controls.is_visible_in_tree():
		var speed_rect := _global_rect_to_spotlight(speed_controls.get_global_rect()).grow(HIGHLIGHT_PADDING)
		highlight_rects.append(speed_rect)
		spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_input_blockers_around(speed_rect)

	spotlight.call("set_hole_rects", highlight_rects)


func _position_wait_panel_clear_of_egg(egg_rect: Rect2) -> void:
	var panel_rect := panel.get_global_rect()
	var required_clearance := panel_rect.end.y - (egg_rect.position.y - 10.0)
	if required_clearance <= 0.0:
		return
	var available_upward_space := maxf(panel_rect.position.y - 6.0, 0.0)
	var shift_up := minf(required_clearance, available_upward_space)
	panel_center.offset_top -= shift_up
	panel_center.offset_bottom -= shift_up


func _get_tracked_egg_screen_rect() -> Rect2:
	if tracked_egg == null or not tracked_egg.has_method("get_world_visual_rect"):
		return Rect2()
	var main_game := get_tree().get_first_node_in_group("main_game")
	if main_game == null or not main_game.has_method("world_rect_to_root_viewport_rect"):
		return Rect2()
	var world_rect := tracked_egg.call("get_world_visual_rect") as Rect2
	var root_rect := main_game.call("world_rect_to_root_viewport_rect", world_rect) as Rect2
	return _global_rect_to_spotlight(root_rect)


func _on_tracked_egg_hatched(_creature: Node2D) -> void:
	if not owns_active_tutorial or current_step != 5:
		return
	tracked_egg = null
	_show_step(6)


func _on_tracked_egg_tree_exiting() -> void:
	if owns_active_tutorial and current_step == 5:
		call_deferred("_recover_from_lost_tutorial_egg")


func _recover_from_lost_tutorial_egg() -> void:
	if current_step != 5:
		return
	tracked_egg = null
	Engine.time_scale = 0.0
	_show_step(3)


func _configure_spells_step() -> void:
	if current_step != 6:
		return
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	var spells_button := nature_ui.call("get_menu_button", &"spells") as Button if nature_ui != null else null
	if spells_button == null or not spells_button.is_visible_in_tree():
		push_warning("Tutorial step 6 could not resolve the spells button.")
		return
	if not spells_button.pressed.is_connected(_on_spells_menu_pressed):
		spells_button.pressed.connect(_on_spells_menu_pressed)
	_set_interactive_highlight(spells_button)


func _on_spells_menu_pressed() -> void:
	if current_step == 6:
		_show_step(7)


func _configure_rain_step() -> void:
	if current_step != 7:
		return
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	var rain_button := nature_ui.call("get_spell_button", &"rain") as Button if nature_ui != null else null
	if rain_button == null or not rain_button.is_visible_in_tree():
		push_warning("Tutorial step 7 could not resolve the rain button.")
		return
	if not rain_button.toggled.is_connected(_on_rain_button_toggled):
		rain_button.toggled.connect(_on_rain_button_toggled)
	_set_interactive_highlight(rain_button)


func _on_rain_button_toggled(toggled_on: bool) -> void:
	if current_step == 7 and toggled_on:
		call_deferred("_open_rain_target_step_if_ready")


func _open_rain_target_step_if_ready() -> void:
	if current_step != 7:
		return
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	if nature_ui != null and bool(nature_ui.call("is_rain_targeting_enabled")):
		_show_step(8)


func _configure_rain_target_step() -> void:
	if current_step != 8:
		return
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	if nature_ui == null or not bool(nature_ui.call("is_rain_targeting_enabled")):
		push_warning("Tutorial step 8 started without active rain targeting.")
		_finish_tutorial()
		return

	if not nature_ui.is_connected("rain_applied", _on_tutorial_rain_applied):
		nature_ui.connect("rain_applied", _on_tutorial_rain_applied)
	nature_ui.call("return_spell_menu_to_main")

	var world_grid := get_tree().get_first_node_in_group("world_grid")
	var main_scene := get_tree().current_scene
	if world_grid == null or main_scene == null or not main_scene.has_method("world_rect_to_root_viewport_rect"):
		push_warning("Tutorial step 8 could not resolve the world-grid projection API.")
		nature_ui.call("cancel_rain_targeting")
		_finish_tutorial()
		return

	var target_data := _find_centered_grass_rain_target(world_grid, main_scene)
	if target_data.is_empty():
		push_warning("Tutorial step 8 found no visible grass-centered 5x5 rain target.")
		nature_ui.call("cancel_rain_targeting")
		_finish_tutorial()
		return

	rain_target_center_tile = target_data["tile"]
	rain_target_area_screen_rect = target_data["area_rect"]
	rain_target_tile_screen_rect = target_data["tile_rect"]
	rain_completed = false
	nature_ui.call("set_rain_preview_tile_override", rain_target_center_tile)
	_set_world_target_highlight(rain_target_area_screen_rect, rain_target_tile_screen_rect)


func _find_centered_grass_rain_target(world_grid: Node, main_scene: Node) -> Dictionary:
	var grass_tiles_variant: Variant = world_grid.call("get_registered_grass_tiles")
	if not (grass_tiles_variant is Array):
		return {}
	var game_rect: Rect2 = main_scene.call("get_game_viewport_root_rect")
	var panel_rect := panel.get_global_rect().grow(8.0)
	var nature_effects := get_tree().get_first_node_in_group("nature_effects_system")
	var best_data: Dictionary = {}
	var best_distance := INF

	for tile_variant: Variant in grass_tiles_variant:
		var tile: Vector2i = tile_variant
		if not bool(world_grid.call("is_tile_region_inside_map", tile, RAIN_TARGET_RADIUS_TILES)):
			continue
		if nature_effects == null or not bool(nature_effects.call("can_apply_rain", tile)):
			continue
		var area_world_rect: Rect2 = world_grid.call(
			"get_tile_region_world_rect", tile, RAIN_TARGET_RADIUS_TILES
		)
		var tile_world_rect: Rect2 = world_grid.call("get_tile_region_world_rect", tile, 0)
		var area_rect: Rect2 = main_scene.call("world_rect_to_root_viewport_rect", area_world_rect)
		var tile_rect: Rect2 = main_scene.call("world_rect_to_root_viewport_rect", tile_world_rect)
		if not game_rect.encloses(area_rect) or area_rect.intersects(panel_rect):
			continue
		var distance := area_rect.get_center().distance_squared_to(game_rect.get_center())
		if distance >= best_distance:
			continue
		best_distance = distance
		best_data = {
			"tile": tile,
			"area_rect": area_rect,
			"tile_rect": tile_rect,
		}

	return best_data


func _set_world_target_highlight(area_global_rect: Rect2, target_global_rect: Rect2) -> void:
	var area_rect := _global_rect_to_spotlight(area_global_rect)
	var target_rect := _global_rect_to_spotlight(target_global_rect)
	spotlight.call("set_hole_rects", [area_rect, target_rect])
	spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_input_blockers_around(area_rect)


func _on_tutorial_rain_applied(center_tile: Vector2i) -> void:
	if current_step != 8:
		return
	var offset := center_tile - rain_target_center_tile
	if absi(offset.x) > RAIN_TARGET_RADIUS_TILES or absi(offset.y) > RAIN_TARGET_RADIUS_TILES:
		return
	rain_completed = true
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	if nature_ui != null:
		nature_ui.call("cancel_rain_targeting")
	_show_step(9)


func _configure_flags_step() -> void:
	if current_step != 9:
		return
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	var flags_button := nature_ui.call("get_menu_button", &"flags") as Button if nature_ui != null else null
	if flags_button == null or not flags_button.is_visible_in_tree():
		push_warning("Tutorial step 9 could not resolve the flags button.")
		return
	if not flags_button.pressed.is_connected(_on_flags_menu_pressed):
		flags_button.pressed.connect(_on_flags_menu_pressed)
	_set_interactive_highlight(flags_button)


func _on_flags_menu_pressed() -> void:
	if current_step == 9:
		call_deferred("_open_stegosaurus_flag_step")


func _open_stegosaurus_flag_step() -> void:
	if current_step == 9:
		_show_step(10)


func _configure_stegosaurus_flag_step() -> void:
	if current_step != 10:
		return
	var flag_system := get_tree().get_first_node_in_group("player_flag_system")
	var stegosaurus_button := flag_system.call("get_species_flag_button", &"stegosaurus") as Button if flag_system != null else null
	if stegosaurus_button == null or not stegosaurus_button.is_visible_in_tree():
		push_warning("Tutorial step 10 could not resolve the Stegosaurus flag button.")
		return
	if not flag_system.is_connected("flag_targeting_started", _on_flag_targeting_started):
		flag_system.connect("flag_targeting_started", _on_flag_targeting_started)
	if not flag_system.is_connected("flag_placed", _on_tutorial_flag_placed):
		flag_system.connect("flag_placed", _on_tutorial_flag_placed)
	stegosaurus_flag_selected = false
	flag_placement_active = false
	_set_interactive_highlight(stegosaurus_button)


func _on_flag_targeting_started(species_id: StringName) -> void:
	if current_step != 10 or species_id != &"stegosaurus":
		return
	stegosaurus_flag_selected = true
	flag_placement_active = true
	_refresh_localized_text()
	_set_world_flag_placement_input()


func _set_world_flag_placement_input() -> void:
	var main_scene := get_tree().current_scene
	if main_scene == null or not main_scene.has_method("get_game_viewport_root_rect"):
		push_warning("Tutorial step 10 could not resolve the game viewport for flag placement.")
		return
	var game_global_rect: Rect2 = main_scene.call("get_game_viewport_root_rect")
	var game_rect := _global_rect_to_spotlight(game_global_rect)
	spotlight.call("set_hole_rects", [game_rect])
	spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_input_blockers_around(game_rect)


func _on_tutorial_flag_placed(species_id: StringName, _tile: Vector2i) -> void:
	if current_step != 10 or not flag_placement_active or species_id != &"stegosaurus":
		return
	_show_completion()


func _show_completion() -> void:
	showing_completion = true
	flag_placement_active = false
	Engine.time_scale = 0.0
	_set_fully_blocked()
	spotlight.call("set_hole_rects", [])
	_apply_completion_layout()
	next_button.visible = true
	next_button.disabled = false
	_refresh_localized_text()


func _set_visual_highlight(control: Control) -> void:
	if control == null or not control.is_visible_in_tree():
		return
	var target_rect := _global_rect_to_spotlight(control.get_global_rect()).grow(HIGHLIGHT_PADDING)
	spotlight.call("set_hole_rects", [target_rect])


func _set_interactive_highlight(control: Control) -> void:
	if control == null or not control.is_visible_in_tree():
		return

	var target_rect := _global_rect_to_spotlight(control.get_global_rect()).grow(HIGHLIGHT_PADDING)
	spotlight.call("set_hole_rects", [target_rect])
	spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_input_blockers_around(target_rect)


func _set_fully_blocked() -> void:
	spotlight.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_center.mouse_filter = Control.MOUSE_FILTER_PASS
	for blocker: Control in input_blockers:
		blocker.visible = false


func _set_input_blockers_around(target_rect: Rect2) -> void:
	var bounds := Rect2(Vector2.ZERO, spotlight.size)
	var hole := target_rect.intersection(bounds)
	if hole.size.x <= 0.0 or hole.size.y <= 0.0:
		_set_fully_blocked()
		return

	_set_blocker_rect(input_blockers[0], Rect2(0.0, 0.0, bounds.size.x, hole.position.y))
	_set_blocker_rect(
		input_blockers[1],
		Rect2(0.0, hole.end.y, bounds.size.x, bounds.size.y - hole.end.y)
	)
	_set_blocker_rect(
		input_blockers[2],
		Rect2(0.0, hole.position.y, hole.position.x, hole.size.y)
	)
	_set_blocker_rect(
		input_blockers[3],
		Rect2(hole.end.x, hole.position.y, bounds.size.x - hole.end.x, hole.size.y)
	)


func _set_blocker_rect(blocker: Control, blocker_rect: Rect2) -> void:
	blocker.position = blocker_rect.position
	blocker.size = blocker_rect.size.max(Vector2.ZERO)
	blocker.visible = blocker.size.x > 0.0 and blocker.size.y > 0.0


func _append_control_highlight(rects: Array[Rect2], control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return
	var local_rect := _global_rect_to_spotlight(control.get_global_rect())
	rects.append(local_rect.grow(HIGHLIGHT_PADDING))


func _get_controls_global_rect(controls: Array) -> Rect2:
	var combined_rect := Rect2()
	var has_rect := false

	for control_variant: Variant in controls:
		var control := control_variant as Control
		if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		if not has_rect:
			combined_rect = control.get_global_rect()
			has_rect = true
		else:
			combined_rect = combined_rect.merge(control.get_global_rect())

	return combined_rect if has_rect else Rect2()


func _global_rect_to_spotlight(global_rect: Rect2) -> Rect2:
	var spotlight_global_origin := spotlight.get_global_rect().position
	return Rect2(global_rect.position - spotlight_global_origin, global_rect.size)


func _on_skip_pressed() -> void:
	if not owns_active_tutorial:
		return
	_finish_tutorial()


func _finish_tutorial() -> void:
	owns_active_tutorial = false
	tracked_egg = null
	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")
	if nature_ui != null:
		nature_ui.call("cancel_all_targeting")
		nature_ui.call("return_spell_menu_to_main")
	var flag_system := get_tree().get_first_node_in_group("player_flag_system")
	if flag_system != null:
		flag_system.call("cancel_targeting")
	TutorialManager.finish_tutorial()
	visible = false
	Engine.time_scale = 1.0


func _on_next_pressed() -> void:
	if showing_completion:
		_finish_tutorial()
		return
	match current_step:
		1:
			_show_step(2)
		2:
			_show_step(3)
		3:
			if not next_button.disabled:
				_show_step(4)


func _on_egg_menu_pressed() -> void:
	if current_step == 3:
		_show_step(4)


func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_text()


func _refresh_localized_text() -> void:
	if showing_completion:
		header_label.text = tr("TUTORIAL_COMPLETE_TITLE")
		body_label.text = tr("TUTORIAL_COMPLETE_BODY").replace("\\n", "\n")
		next_button.text = tr("TUTORIAL_NEXT")
		return
	header_label.text = tr("TUTORIAL_STEP_PROGRESS") % [current_step, TOTAL_STEPS]
	var body_key := "TUTORIAL_INTRO_BODY"
	match current_step:
		2:
			body_key = "TUTORIAL_INTERFACE_BODY"
		3:
			body_key = "TUTORIAL_EGG_MENU_BODY"
		4:
			body_key = "TUTORIAL_STEGOSAURUS_BODY"
		5:
			body_key = "TUTORIAL_EGG_HATCH_BODY"
		6:
			body_key = "TUTORIAL_SPELLS_BODY"
		7:
			body_key = "TUTORIAL_RAIN_BODY"
		8:
			body_key = "TUTORIAL_RAIN_TARGET_BODY"
		9:
			body_key = "TUTORIAL_FLAGS_BODY"
		10:
			body_key = (
				"TUTORIAL_FLAG_PLACEMENT_BODY"
				if flag_placement_active
				else "TUTORIAL_STEGOSAURUS_FLAG_BODY"
			)
	body_label.text = tr(body_key).replace("\\n", "\n")
	skip_button.text = tr("TUTORIAL_SKIP")
	next_button.text = tr("TUTORIAL_NEXT")
