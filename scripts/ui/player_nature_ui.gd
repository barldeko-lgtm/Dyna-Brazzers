extends PanelContainer

const LIGHTNING_EFFECT_SCENE := preload("res://scenes/effects/lightning_strike_effect.tscn")
const RAIN_TARGET_PREVIEW_SCENE_PATH := "res://scenes/effects/rain_target_preview.tscn"
const SUN_TARGET_PREVIEW_SCENE_PATH := "res://scenes/effects/sun_target_preview.tscn"

# Player-facing nature powers HUD.
@export var max_energy := 9999.0
@export var starting_energy := 0.0
@export var energy_regen_per_second := 1.0
@export var lightning_damage := 50.0
@export var lightning_energy_cost := 50.0
@export var rain_energy_cost := 30.0
@export var rain_radius_tiles := 2
@export var sun_energy_cost := 100.0
@export var sun_radius_tiles := 3
@export var sun_spread_reset_radius_tiles := 4
@export var sun_remove_grass_count := 20

@onready var energy_value_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EnergyValueLabel")
@onready var lightning_button: Button = get_node_or_null("MarginContainer/VBoxContainer/LightningButton")
@onready var rain_button: Button = get_node_or_null("MarginContainer/VBoxContainer/RainButton")
@onready var sun_button: Button = get_node_or_null("MarginContainer/VBoxContainer/SunButton")

var current_energy := 0.0
var lightning_targeting_enabled := false
var rain_targeting_enabled := false
var sun_targeting_enabled := false
var rain_target_preview: Node2D = null
var sun_target_preview: Node2D = null


func _ready() -> void:
	add_to_group("player_nature_ui")
	set_process(true)
	current_energy = clamp(starting_energy, 0.0, max_energy)

	setup_lightning_button()
	setup_rain_button()
	setup_sun_button()
	_update_energy_ui()


func _process(delta: float) -> void:
	current_energy = clamp(current_energy + energy_regen_per_second * delta, 0.0, max_energy)
	_update_energy_ui()

	if rain_targeting_enabled:
		_update_rain_target_preview()

	if sun_targeting_enabled:
		_update_sun_target_preview()


func setup_lightning_button() -> void:
	if lightning_button == null:
		return

	lightning_button.toggle_mode = true
	lightning_button.text = _get_lightning_button_text()
	lightning_button.button_pressed = false

	if not lightning_button.toggled.is_connected(_on_lightning_button_toggled):
		lightning_button.toggled.connect(_on_lightning_button_toggled)


func setup_rain_button() -> void:
	if rain_button == null:
		return

	rain_button.toggle_mode = true
	rain_button.text = _get_rain_button_text()
	rain_button.button_pressed = false

	if not rain_button.toggled.is_connected(_on_rain_button_toggled):
		rain_button.toggled.connect(_on_rain_button_toggled)


func setup_sun_button() -> void:
	if sun_button == null:
		return

	sun_button.toggle_mode = true
	sun_button.text = _get_sun_button_text()
	sun_button.button_pressed = false

	if not sun_button.toggled.is_connected(_on_sun_button_toggled):
		sun_button.toggled.connect(_on_sun_button_toggled)


func _on_lightning_button_toggled(toggled_on: bool) -> void:
	if toggled_on and not can_spend_energy(lightning_energy_cost):
		if lightning_button != null:
			lightning_button.set_pressed_no_signal(false)
		lightning_targeting_enabled = false
		return

	if toggled_on:
		cancel_rain_targeting()
		cancel_sun_targeting()

	lightning_targeting_enabled = toggled_on
	_update_spell_buttons()


func _on_rain_button_toggled(toggled_on: bool) -> void:
	if toggled_on and not can_spend_energy(rain_energy_cost):
		if rain_button != null:
			rain_button.set_pressed_no_signal(false)
		rain_targeting_enabled = false
		return

	if toggled_on:
		cancel_lightning_targeting()
		cancel_sun_targeting()

	rain_targeting_enabled = toggled_on

	if rain_targeting_enabled:
		_ensure_rain_target_preview()
		_update_rain_target_preview()
	else:
		_hide_rain_target_preview()

	_update_spell_buttons()


func _on_sun_button_toggled(toggled_on: bool) -> void:
	if toggled_on and not can_spend_energy(sun_energy_cost):
		if sun_button != null:
			sun_button.set_pressed_no_signal(false)
		sun_targeting_enabled = false
		return

	if toggled_on:
		cancel_lightning_targeting()
		cancel_rain_targeting()

	sun_targeting_enabled = toggled_on

	if sun_targeting_enabled:
		_ensure_sun_target_preview()
		_update_sun_target_preview()
	else:
		_hide_sun_target_preview()

	_update_spell_buttons()


func is_lightning_targeting_enabled() -> bool:
	return lightning_targeting_enabled


func is_rain_targeting_enabled() -> bool:
	return rain_targeting_enabled


func is_sun_targeting_enabled() -> bool:
	return sun_targeting_enabled


func is_targeting_enabled() -> bool:
	return lightning_targeting_enabled or rain_targeting_enabled or sun_targeting_enabled


func try_apply_lightning_to_creature(creature: Node) -> bool:
	if not lightning_targeting_enabled:
		return false

	if creature == null or not is_instance_valid(creature):
		return false

	if not can_spend_energy(lightning_energy_cost):
		cancel_lightning_targeting()
		return false

	if creature.has_method("take_direct_damage"):
		if not spend_energy(lightning_energy_cost):
			cancel_lightning_targeting()
			return false

		_spawn_lightning_effect(creature)
		creature.take_direct_damage(lightning_damage)
		if not can_spend_energy(lightning_energy_cost):
			cancel_lightning_targeting()
		return true

	return false


func cancel_lightning_targeting() -> void:
	lightning_targeting_enabled = false

	if lightning_button != null and lightning_button.button_pressed:
		lightning_button.set_pressed_no_signal(false)

	_update_spell_buttons()


func cancel_rain_targeting() -> void:
	rain_targeting_enabled = false

	if rain_button != null and rain_button.button_pressed:
		rain_button.set_pressed_no_signal(false)

	_hide_rain_target_preview()
	_update_spell_buttons()


func cancel_sun_targeting() -> void:
	sun_targeting_enabled = false

	if sun_button != null and sun_button.button_pressed:
		sun_button.set_pressed_no_signal(false)

	_hide_sun_target_preview()
	_update_spell_buttons()


func cancel_all_targeting() -> void:
	cancel_lightning_targeting()
	cancel_rain_targeting()
	cancel_sun_targeting()


func can_spend_energy(amount: float) -> bool:
	return current_energy >= amount


func spend_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true

	if not can_spend_energy(amount):
		return false

	current_energy = clamp(current_energy - amount, 0.0, max_energy)
	_update_energy_ui()
	return true


func add_energy(amount: float) -> void:
	if amount <= 0.0:
		return

	current_energy = clamp(current_energy + amount, 0.0, max_energy)
	_update_energy_ui()


func get_energy() -> float:
	return current_energy


func get_max_energy() -> float:
	return max_energy


func _update_energy_ui() -> void:
	if energy_value_label != null:
		energy_value_label.text = "%d" % floori(current_energy)

	_update_spell_buttons()


func _update_spell_buttons() -> void:
	if lightning_button != null:
		lightning_button.text = _get_lightning_button_text()

		if lightning_targeting_enabled:
			lightning_button.disabled = false
		else:
			lightning_button.disabled = not can_spend_energy(lightning_energy_cost)

	if rain_button != null:
		rain_button.text = _get_rain_button_text()

		if rain_targeting_enabled:
			rain_button.disabled = false
		else:
			rain_button.disabled = not can_spend_energy(rain_energy_cost)

	if sun_button != null:
		sun_button.text = _get_sun_button_text()

		if sun_targeting_enabled:
			sun_button.disabled = false
		else:
			sun_button.disabled = not can_spend_energy(sun_energy_cost)


func _get_lightning_button_text() -> String:
	return "Молния (%d)" % floori(lightning_energy_cost)


func _get_rain_button_text() -> String:
	return "Дождь (%d)" % floori(rain_energy_cost)


func _get_sun_button_text() -> String:
	return "Солнце (%d)" % floori(sun_energy_cost)


func _try_apply_rain_at_mouse() -> bool:
	if not rain_targeting_enabled:
		return false

	var world_grid := _get_world_grid()

	if world_grid == null:
		return false

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())

	if not bool(world_grid.call("is_tile_inside_map", center_tile)):
		return false

	if not spend_energy(rain_energy_cost):
		cancel_rain_targeting()
		return false

	_apply_rain_at_tile(world_grid, center_tile)
	_play_rain_cast_effect(center_tile)
	if not can_spend_energy(rain_energy_cost):
		cancel_rain_targeting()
	return true


func _try_apply_sun_at_mouse() -> bool:
	if not sun_targeting_enabled:
		return false

	var world_grid := _get_world_grid()

	if world_grid == null:
		return false

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())

	if not bool(world_grid.call("is_tile_inside_map", center_tile)):
		return false

	if not spend_energy(sun_energy_cost):
		cancel_sun_targeting()
		return false

	_apply_sun_at_tile(world_grid, center_tile)
	if not can_spend_energy(sun_energy_cost):
		cancel_sun_targeting()
	return true


func _apply_rain_at_tile(world_grid: Node, center_tile: Vector2i) -> int:
	var checked_tiles := 0
	var affected_grass := 0

	for y in range(center_tile.y - rain_radius_tiles, center_tile.y + rain_radius_tiles + 1):
		for x in range(center_tile.x - rain_radius_tiles, center_tile.x + rain_radius_tiles + 1):
			checked_tiles += 1
			var tile := Vector2i(x, y)

			if not bool(world_grid.call("can_host_grass", tile)):
				continue

			var grass: Node = world_grid.call("get_grass_at_tile", tile)

			if not is_instance_valid(grass):
				continue

			if not grass.has_method("apply_rain"):
				continue

			if grass.apply_rain():
				affected_grass += 1

	PerformanceStats.add_counter("rain_tiles_checked", checked_tiles)
	PerformanceStats.add_counter("rain_grass_affected", affected_grass)
	return affected_grass


func _play_rain_cast_effect(center_tile: Vector2i) -> void:
	_ensure_rain_target_preview()

	if rain_target_preview != null and is_instance_valid(rain_target_preview):
		if rain_target_preview.has_method("play_cast_effect"):
			rain_target_preview.call("play_cast_effect", center_tile)


func _apply_sun_at_tile(world_grid: Node, center_tile: Vector2i) -> Dictionary:
	var checked_tiles := 0
	var reverted_grass := 0
	var grass_nodes: Array[Node] = []

	for y in range(center_tile.y - sun_radius_tiles, center_tile.y + sun_radius_tiles + 1):
		for x in range(center_tile.x - sun_radius_tiles, center_tile.x + sun_radius_tiles + 1):
			checked_tiles += 1
			var tile := Vector2i(x, y)

			if not bool(world_grid.call("can_host_grass", tile)):
				continue

			var grass: Node = world_grid.call("get_grass_at_tile", tile)

			if not is_instance_valid(grass):
				continue

			grass_nodes.append(grass)

			if grass.has_method("apply_sun") and grass.apply_sun():
				reverted_grass += 1

	var removable_grass: Array[Node] = []

	for grass in grass_nodes:
		if is_instance_valid(grass):
			removable_grass.append(grass)

	removable_grass.shuffle()

	var removed_grass := 0
	var target_remove_count: int = min(sun_remove_grass_count, removable_grass.size())

	for index in range(target_remove_count):
		var grass_to_remove := removable_grass[index]

		if not is_instance_valid(grass_to_remove):
			continue

		grass_to_remove.queue_free()
		removed_grass += 1

	var reset_spread_grass := _reset_spread_attempts_in_area(world_grid, center_tile, sun_spread_reset_radius_tiles)

	PerformanceStats.add_counter("sun_tiles_checked", checked_tiles)
	PerformanceStats.add_counter("sun_grass_reverted", reverted_grass)
	PerformanceStats.add_counter("sun_grass_removed", removed_grass)
	PerformanceStats.add_counter("sun_grass_spread_reset", reset_spread_grass)

	return {
		"checked_tiles": checked_tiles,
		"reverted_grass": reverted_grass,
		"removed_grass": removed_grass,
		"reset_spread_grass": reset_spread_grass
	}


func _reset_spread_attempts_in_area(world_grid: Node, center_tile: Vector2i, radius: int) -> int:
	var reset_count := 0

	for y in range(center_tile.y - radius, center_tile.y + radius + 1):
		for x in range(center_tile.x - radius, center_tile.x + radius + 1):
			var tile := Vector2i(x, y)

			if not bool(world_grid.call("can_host_grass", tile)):
				continue

			var grass: Node = world_grid.call("get_grass_at_tile", tile)

			if not is_instance_valid(grass):
				continue

			if grass.is_queued_for_deletion():
				continue

			if not grass.has_method("reset_spread_attempt"):
				continue

			if grass.reset_spread_attempt():
				reset_count += 1

	return reset_count


func _spawn_lightning_effect(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	if not (target is Node2D):
		return

	var effect_parent := target.get_parent()

	if effect_parent == null:
		effect_parent = get_tree().current_scene

	if effect_parent == null:
		return

	var effect := LIGHTNING_EFFECT_SCENE.instantiate() as Node2D

	if effect == null:
		return

	effect_parent.add_child(effect)
	effect.global_position = (target as Node2D).global_position


func _ensure_rain_target_preview() -> void:
	if rain_target_preview != null and is_instance_valid(rain_target_preview):
		return

	var world_grid := _get_world_grid()

	if world_grid == null:
		return

	var preview_scene := load(RAIN_TARGET_PREVIEW_SCENE_PATH) as PackedScene

	if preview_scene == null:
		return

	rain_target_preview = preview_scene.instantiate() as Node2D

	if rain_target_preview == null:
		return

	world_grid.add_child(rain_target_preview)

	if rain_target_preview.has_method("configure"):
		rain_target_preview.configure(world_grid, rain_radius_tiles)


func _ensure_sun_target_preview() -> void:
	if sun_target_preview != null and is_instance_valid(sun_target_preview):
		return

	var world_grid := _get_world_grid()

	if world_grid == null:
		return

	var preview_scene := load(SUN_TARGET_PREVIEW_SCENE_PATH) as PackedScene

	if preview_scene == null:
		return

	sun_target_preview = preview_scene.instantiate() as Node2D

	if sun_target_preview == null:
		return

	world_grid.add_child(sun_target_preview)

	if sun_target_preview.has_method("configure"):
		sun_target_preview.configure(world_grid, sun_radius_tiles)


func _update_rain_target_preview() -> void:
	if not rain_targeting_enabled:
		_hide_rain_target_preview()
		return

	var world_grid := _get_world_grid()

	if world_grid == null:
		_hide_rain_target_preview()
		return

	_ensure_rain_target_preview()

	if rain_target_preview == null or not is_instance_valid(rain_target_preview):
		return

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())
	var valid_target := bool(world_grid.call("is_tile_inside_map", center_tile))

	if rain_target_preview.has_method("set_center_tile"):
		rain_target_preview.set_center_tile(center_tile, valid_target)


func _update_sun_target_preview() -> void:
	if not sun_targeting_enabled:
		_hide_sun_target_preview()
		return

	var world_grid := _get_world_grid()

	if world_grid == null:
		_hide_sun_target_preview()
		return

	_ensure_sun_target_preview()

	if sun_target_preview == null or not is_instance_valid(sun_target_preview):
		return

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())
	var valid_target := bool(world_grid.call("is_tile_inside_map", center_tile))

	if sun_target_preview.has_method("set_center_tile"):
		sun_target_preview.set_center_tile(center_tile, valid_target)


func _hide_rain_target_preview() -> void:
	if rain_target_preview == null or not is_instance_valid(rain_target_preview):
		return

	if rain_target_preview.has_method("hide_preview"):
		rain_target_preview.hide_preview()
	else:
		rain_target_preview.visible = false


func _hide_sun_target_preview() -> void:
	if sun_target_preview == null or not is_instance_valid(sun_target_preview):
		return

	if sun_target_preview.has_method("hide_preview"):
		sun_target_preview.hide_preview()
	else:
		sun_target_preview.visible = false


func _get_world_grid() -> Node:
	return get_tree().get_first_node_in_group("world_grid")


func _get_world_mouse_position() -> Vector2:
	var camera := get_viewport().get_camera_2d()

	if camera != null:
		return camera.get_global_mouse_position()

	return get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	if not is_targeting_enabled():
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_all_targeting()
		get_viewport().set_input_as_handled()
		return

	if rain_targeting_enabled and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _try_apply_rain_at_mouse():
			get_viewport().set_input_as_handled()
		return

	if sun_targeting_enabled and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _try_apply_sun_at_mouse():
			get_viewport().set_input_as_handled()
