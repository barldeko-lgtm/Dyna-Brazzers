extends PanelContainer

signal rain_applied(center_tile: Vector2i)

const RAIN_TARGET_PREVIEW_SCENE_PATH := "res://scenes/effects/rain_target_preview.tscn"
const SUN_TARGET_PREVIEW_SCENE_PATH := "res://scenes/effects/sun_target_preview.tscn"
const EARTHQUAKE_TARGET_PREVIEW_SCENE_PATH := "res://scenes/effects/earthquake_target_preview.tscn"

const MENU_EGGS := &"eggs"
const MENU_SPELLS := &"spells"
const MENU_FLAGS := &"flags"
const MENU_SYSTEM := &"system"
const SPELL_RAIN := &"rain"

# Player-facing nature powers HUD and stable access point for its nested menus.
@export var lightning_energy_cost := 1000.0
@export var rain_energy_cost := 50.0
@export var sun_energy_cost := 500.0
@export var earthquake_energy_cost := 1700.0

@onready var energy_value_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EnergyValueLabel")
@onready var energy_icon: TextureRect = get_node_or_null("MarginContainer/VBoxContainer/EnergyIcon") as TextureRect
@onready var time_controls_panel: PanelContainer = get_node_or_null("MarginContainer/VBoxContainer/TimeControlsPanel") as PanelContainer
@onready var lightning_button: Button = get_node_or_null("MarginContainer/VBoxContainer/LightningButton")
@onready var rain_button: Button = get_node_or_null("MarginContainer/VBoxContainer/RainButton")
@onready var sun_button: Button = get_node_or_null("MarginContainer/VBoxContainer/SunButton")
@onready var earthquake_button: Button = get_node_or_null("MarginContainer/VBoxContainer/EarthquakeButton")
@onready var menu_content_root: Control = get_node_or_null("MarginContainer/VBoxContainer") as Control
@onready var main_menu_grid: GridContainer = get_node_or_null("MarginContainer/VBoxContainer/MainMenuGrid") as GridContainer
@onready var egg_menu_button: Button = get_node_or_null("MarginContainer/VBoxContainer/MainMenuGrid/EggMenuButton") as Button
@onready var spell_menu_button: Button = get_node_or_null("MarginContainer/VBoxContainer/MainMenuGrid/SpellMenuButton") as Button
@onready var flag_menu_button: Button = get_node_or_null("MarginContainer/VBoxContainer/MainMenuGrid/FlagMenuButton") as Button
@onready var system_menu_button: Button = get_node_or_null("MarginContainer/VBoxContainer/MainMenuGrid/SystemMenuButton") as Button
@onready var time_speed_buttons: Array[Button] = [
	get_node_or_null("MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed1Button"),
	get_node_or_null("MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed2Button"),
	get_node_or_null("MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed3Button"),
	get_node_or_null("MarginContainer/VBoxContainer/TimeControlsPanel/MarginContainer/HBoxContainer/TimeSpeed5Button"),
]

var player_energy: Node = null
var lightning_targeting_enabled := false
var rain_targeting_enabled := false
var sun_targeting_enabled := false
var earthquake_targeting_enabled := false
var rain_target_preview: Node2D = null
var rain_preview_tile_override_enabled := false
var rain_preview_tile_override := Vector2i.ZERO
var sun_target_preview: Node2D = null
var earthquake_target_preview: Node2D = null


func _ready() -> void:
	add_to_group("player_nature_ui")
	set_process(true)
	_bind_player_energy()

	setup_lightning_button()
	setup_rain_button()
	setup_sun_button()
	setup_earthquake_button()
	_refresh_localized_text()
	LocalizationManager.locale_changed.connect(_on_locale_changed)
	_update_energy_ui()


func _process(_delta: float) -> void:
	_bind_player_energy()

	if rain_targeting_enabled:
		_update_rain_target_preview()

	if sun_targeting_enabled:
		_update_sun_target_preview()

	if earthquake_targeting_enabled:
		_update_earthquake_target_preview()


func get_menu_content_root() -> Control:
	return menu_content_root


func get_main_menu_grid() -> GridContainer:
	return main_menu_grid


func get_menu_button(menu_id: StringName) -> Button:
	match menu_id:
		MENU_EGGS:
			return egg_menu_button
		MENU_SPELLS:
			return spell_menu_button
		MENU_FLAGS:
			return flag_menu_button
		MENU_SYSTEM:
			return system_menu_button

	return null


func get_spell_button(spell_id: StringName) -> Button:
	match spell_id:
		SPELL_RAIN:
			return rain_button
	return null


func return_spell_menu_to_main() -> void:
	if spell_menu_button != null and spell_menu_button.has_method("return_to_main_menu"):
		spell_menu_button.call("return_to_main_menu")


func set_rain_preview_tile_override(tile: Vector2i) -> void:
	rain_preview_tile_override = tile
	rain_preview_tile_override_enabled = true
	_update_rain_target_preview()


func get_time_speed_buttons() -> Array[Button]:
	return time_speed_buttons


func get_tutorial_energy_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if energy_icon != null:
		controls.append(energy_icon)
	if energy_value_label != null:
		controls.append(energy_value_label)
	return controls


func get_tutorial_time_controls() -> Control:
	return time_controls_panel


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


func setup_earthquake_button() -> void:
	if earthquake_button == null:
		return

	earthquake_button.toggle_mode = true
	earthquake_button.text = _get_earthquake_button_text()
	earthquake_button.button_pressed = false

	if not earthquake_button.toggled.is_connected(_on_earthquake_button_toggled):
		earthquake_button.toggled.connect(_on_earthquake_button_toggled)


func _on_lightning_button_toggled(toggled_on: bool) -> void:
	if toggled_on and not can_spend_energy(lightning_energy_cost):
		if lightning_button != null:
			lightning_button.set_pressed_no_signal(false)
		lightning_targeting_enabled = false
		return

	if toggled_on:
		cancel_rain_targeting()
		cancel_sun_targeting()
		cancel_earthquake_targeting()

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
		cancel_earthquake_targeting()

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
		cancel_earthquake_targeting()

	sun_targeting_enabled = toggled_on

	if sun_targeting_enabled:
		_ensure_sun_target_preview()
		_update_sun_target_preview()
	else:
		_hide_sun_target_preview()

	_update_spell_buttons()


func _on_earthquake_button_toggled(toggled_on: bool) -> void:
	if toggled_on and not can_spend_energy(earthquake_energy_cost):
		if earthquake_button != null:
			earthquake_button.set_pressed_no_signal(false)
		earthquake_targeting_enabled = false
		return

	if toggled_on:
		cancel_lightning_targeting()
		cancel_rain_targeting()
		cancel_sun_targeting()

	earthquake_targeting_enabled = toggled_on

	if earthquake_targeting_enabled:
		_ensure_earthquake_target_preview()
		_update_earthquake_target_preview()
	else:
		_hide_earthquake_target_preview()

	_update_spell_buttons()


func is_lightning_targeting_enabled() -> bool:
	return lightning_targeting_enabled


func is_rain_targeting_enabled() -> bool:
	return rain_targeting_enabled


func is_sun_targeting_enabled() -> bool:
	return sun_targeting_enabled


func is_earthquake_targeting_enabled() -> bool:
	return earthquake_targeting_enabled


func is_targeting_enabled() -> bool:
	return lightning_targeting_enabled or rain_targeting_enabled or sun_targeting_enabled or earthquake_targeting_enabled


func try_apply_lightning_to_creature(creature: Node) -> bool:
	if not lightning_targeting_enabled:
		return false

	if creature == null or not is_instance_valid(creature):
		return false

	var nature_effects := _get_nature_effects_system()

	if (
		nature_effects == null
		or not nature_effects.has_method("can_apply_lightning")
		or not nature_effects.has_method("apply_lightning")
	):
		return false

	if not bool(nature_effects.call("can_apply_lightning", creature)):
		return false

	if not can_spend_energy(lightning_energy_cost):
		cancel_lightning_targeting()
		return false

	if not spend_energy(lightning_energy_cost):
		cancel_lightning_targeting()
		return false

	if not bool(nature_effects.call("apply_lightning", creature)):
		add_energy(lightning_energy_cost)
		return false

	if not can_spend_energy(lightning_energy_cost):
		cancel_lightning_targeting()
	return true


func cancel_lightning_targeting() -> void:
	lightning_targeting_enabled = false

	if lightning_button != null and lightning_button.button_pressed:
		lightning_button.set_pressed_no_signal(false)

	_update_spell_buttons()


func cancel_rain_targeting() -> void:
	rain_targeting_enabled = false
	rain_preview_tile_override_enabled = false

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


func cancel_earthquake_targeting() -> void:
	earthquake_targeting_enabled = false

	if earthquake_button != null and earthquake_button.button_pressed:
		earthquake_button.set_pressed_no_signal(false)

	_hide_earthquake_target_preview()
	_update_spell_buttons()


func cancel_all_targeting() -> void:
	cancel_lightning_targeting()
	cancel_rain_targeting()
	cancel_sun_targeting()
	cancel_earthquake_targeting()


func can_spend_energy(amount: float) -> bool:
	return player_energy != null and bool(player_energy.call("can_spend", amount))


func spend_energy(amount: float) -> bool:
	return player_energy != null and bool(player_energy.call("spend", amount))


func add_energy(amount: float) -> void:
	if player_energy != null:
		player_energy.call("add_energy", amount)


func get_energy() -> float:
	if player_energy == null:
		return 0.0

	return float(player_energy.call("get_energy"))


func get_max_energy() -> float:
	if player_energy == null:
		return 0.0

	return float(player_energy.call("get_max_energy"))


func _update_energy_ui() -> void:
	if energy_value_label != null:
		energy_value_label.text = "%d" % floori(get_energy())

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

	if earthquake_button != null:
		earthquake_button.text = _get_earthquake_button_text()
		if earthquake_targeting_enabled:
			earthquake_button.disabled = false
		else:
			earthquake_button.disabled = not can_spend_energy(earthquake_energy_cost)


func _get_lightning_button_text() -> String:
	return "%s (%d)" % [tr("SPELL_LIGHTNING"), floori(lightning_energy_cost)]


func _get_rain_button_text() -> String:
	return "%s (%d)" % [tr("SPELL_RAIN"), floori(rain_energy_cost)]


func _get_sun_button_text() -> String:
	return "%s (%d)" % [tr("SPELL_SUN"), floori(sun_energy_cost)]


func _get_earthquake_button_text() -> String:
	return "%s (%d)" % [tr("SPELL_EARTHQUAKE"), floori(earthquake_energy_cost)]


func _on_locale_changed(_locale: String) -> void:
	_refresh_localized_text()


func _refresh_localized_text() -> void:
	var tooltip_keys := {
		"MarginContainer/VBoxContainer/MainMenuGrid/EggMenuButton": "NATURE_EGG",
		"MarginContainer/VBoxContainer/MainMenuGrid/BaseMenuButton": "NATURE_BASE",
		"MarginContainer/VBoxContainer/MainMenuGrid/SpellMenuButton": "NATURE_SPELLS",
		"MarginContainer/VBoxContainer/MainMenuGrid/EnemyMenuButton": "NATURE_ENEMY",
		"MarginContainer/VBoxContainer/MainMenuGrid/FlagMenuButton": "NATURE_FLAG",
		"MarginContainer/VBoxContainer/MainMenuGrid/SystemMenuButton": "NATURE_MENU",
		"MarginContainer/VBoxContainer/LightningButton": "SPELL_LIGHTNING",
		"MarginContainer/VBoxContainer/RainButton": "SPELL_RAIN",
		"MarginContainer/VBoxContainer/SunButton": "SPELL_SUN",
		"MarginContainer/VBoxContainer/EarthquakeButton": "SPELL_EARTHQUAKE",
		"MarginContainer/VBoxContainer/SpellBackButton": "MENU_BACK",
	}
	for node_path: String in tooltip_keys:
		var button := get_node_or_null(node_path) as Button
		if button != null:
			button.tooltip_text = tr(String(tooltip_keys[node_path]))
	var button_text_keys := {
		"MarginContainer/VBoxContainer/MainMenuGrid/BaseMenuButton": "NATURE_BASE_BUTTON",
		"MarginContainer/VBoxContainer/MainMenuGrid/EnemyMenuButton": "NATURE_ENEMY_BUTTON",
		"MarginContainer/VBoxContainer/MainMenuGrid/SystemMenuButton": "NATURE_MENU_BUTTON",
	}
	for node_path: String in button_text_keys:
		var button := get_node_or_null(node_path) as Button
		if button != null:
			button.text = tr(String(button_text_keys[node_path]))
	_update_spell_buttons()


func _try_apply_rain_at_mouse() -> bool:
	return _try_apply_rain_at_world_position(_get_world_mouse_position())


func _try_apply_rain_at_world_position(world_position: Vector2) -> bool:
	if not rain_targeting_enabled:
		return false

	var world_grid := _get_world_grid()
	var nature_effects := _get_nature_effects_system()

	if world_grid == null or nature_effects == null:
		return false

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", world_position)

	if not nature_effects.has_method("can_apply_rain") or not bool(
		nature_effects.call("can_apply_rain", center_tile)
	):
		return false

	if not spend_energy(rain_energy_cost):
		cancel_rain_targeting()
		return false

	if not bool(nature_effects.call("apply_rain", center_tile)):
		add_energy(rain_energy_cost)
		return false

	rain_applied.emit(center_tile)

	if not can_spend_energy(rain_energy_cost):
		cancel_rain_targeting()
	return true


func _try_apply_sun_at_mouse() -> bool:
	if not sun_targeting_enabled:
		return false

	var world_grid := _get_world_grid()
	var nature_effects := _get_nature_effects_system()

	if world_grid == null or nature_effects == null:
		return false

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())

	if not nature_effects.has_method("can_apply_sun") or not bool(
		nature_effects.call("can_apply_sun", center_tile)
	):
		return false

	if not spend_energy(sun_energy_cost):
		cancel_sun_targeting()
		return false

	if not bool(nature_effects.call("apply_sun", center_tile)):
		add_energy(sun_energy_cost)
		return false

	if not can_spend_energy(sun_energy_cost):
		cancel_sun_targeting()
	return true


func _try_apply_earthquake_at_mouse() -> bool:
	if not earthquake_targeting_enabled:
		return false

	var world_grid := _get_world_grid()
	var nature_effects := _get_nature_effects_system()

	if world_grid == null or nature_effects == null:
		return false

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())

	if not nature_effects.has_method("can_apply_earthquake") or not bool(
		nature_effects.call("can_apply_earthquake", center_tile)
	):
		return false

	if not spend_energy(earthquake_energy_cost):
		cancel_earthquake_targeting()
		return false

	if not bool(nature_effects.call("apply_earthquake", center_tile)):
		add_energy(earthquake_energy_cost)
		return false

	if not can_spend_energy(earthquake_energy_cost):
		cancel_earthquake_targeting()
	return true


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
		rain_target_preview.configure(world_grid, _get_rain_preview_radius())


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
		sun_target_preview.configure(world_grid, _get_sun_preview_radius())


func _ensure_earthquake_target_preview() -> void:
	if earthquake_target_preview != null and is_instance_valid(earthquake_target_preview):
		return

	var world_grid := _get_world_grid()

	if world_grid == null:
		return

	var preview_scene := load(EARTHQUAKE_TARGET_PREVIEW_SCENE_PATH) as PackedScene

	if preview_scene == null:
		return

	earthquake_target_preview = preview_scene.instantiate() as Node2D

	if earthquake_target_preview == null:
		return

	world_grid.add_child(earthquake_target_preview)

	if earthquake_target_preview.has_method("configure"):
		earthquake_target_preview.configure(world_grid, _get_earthquake_preview_radius())


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

	var center_tile := rain_preview_tile_override
	if not rain_preview_tile_override_enabled:
		center_tile = world_grid.call("world_to_map_tile", _get_world_mouse_position())
	var nature_effects := _get_nature_effects_system()
	var valid_target := nature_effects != null and nature_effects.has_method("can_apply_rain") and bool(
		nature_effects.call("can_apply_rain", center_tile)
	)

	if rain_target_preview.has_method("set_center_tile"):
		rain_target_preview.set_center_tile(center_tile, valid_target)


func _update_sun_target_preview() -> void:
	if not sun_targeting_enabled:
		_hide_sun_target_preview()
		return

	var world_grid := _get_world_grid()
	var nature_effects := _get_nature_effects_system()

	if world_grid == null or nature_effects == null:
		_hide_sun_target_preview()
		return

	_ensure_sun_target_preview()

	if sun_target_preview == null or not is_instance_valid(sun_target_preview):
		return

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())
	var valid_target: bool = nature_effects.has_method("can_apply_sun") and bool(
		nature_effects.call("can_apply_sun", center_tile)
	)

	if sun_target_preview.has_method("set_center_tile"):
		sun_target_preview.set_center_tile(center_tile, valid_target)


func _update_earthquake_target_preview() -> void:
	if not earthquake_targeting_enabled:
		_hide_earthquake_target_preview()
		return

	var world_grid := _get_world_grid()
	var nature_effects := _get_nature_effects_system()

	if world_grid == null or nature_effects == null:
		_hide_earthquake_target_preview()
		return

	_ensure_earthquake_target_preview()

	if earthquake_target_preview == null or not is_instance_valid(earthquake_target_preview):
		return

	var center_tile: Vector2i = world_grid.call("world_to_map_tile", _get_world_mouse_position())
	var valid_target := nature_effects.has_method("can_apply_earthquake") and bool(
		nature_effects.call("can_apply_earthquake", center_tile)
	)

	if earthquake_target_preview.has_method("set_center_tile"):
		earthquake_target_preview.set_center_tile(center_tile, valid_target)


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


func _hide_earthquake_target_preview() -> void:
	if earthquake_target_preview == null or not is_instance_valid(earthquake_target_preview):
		return

	if earthquake_target_preview.has_method("hide_preview"):
		earthquake_target_preview.hide_preview()
	else:
		earthquake_target_preview.visible = false


func _bind_player_energy() -> void:
	var resolved_energy := _get_player_energy()

	if resolved_energy == player_energy:
		return

	player_energy = resolved_energy

	if player_energy == null:
		return

	var changed_callable := Callable(self, "_on_energy_changed")

	if player_energy.has_signal("energy_changed") and not player_energy.is_connected(
		"energy_changed", changed_callable
	):
		player_energy.connect("energy_changed", changed_callable)

	_update_energy_ui()


func _on_energy_changed(_current_energy: float, _max_energy: float) -> void:
	_update_energy_ui()


func _get_player_energy() -> Node:
	return get_tree().get_first_node_in_group("player_energy")


func _get_nature_effects_system() -> Node:
	return get_tree().get_first_node_in_group("nature_effects_system")


func _get_rain_preview_radius() -> int:
	var nature_effects := _get_nature_effects_system()

	if nature_effects != null and nature_effects.has_method("get_rain_radius_tiles"):
		return int(nature_effects.call("get_rain_radius_tiles"))

	return 0


func _get_sun_preview_radius() -> int:
	var nature_effects := _get_nature_effects_system()

	if nature_effects != null and nature_effects.has_method("get_sun_radius_tiles"):
		return int(nature_effects.call("get_sun_radius_tiles"))

	return 0


func _get_earthquake_preview_radius() -> int:
	var nature_effects := _get_nature_effects_system()

	if nature_effects != null and nature_effects.has_method("get_earthquake_radius_tiles"):
		return int(nature_effects.call("get_earthquake_radius_tiles"))

	return 0


func _get_world_grid() -> Node:
	return get_tree().get_first_node_in_group("world_grid")


func _get_world_mouse_position() -> Vector2:
	var camera := get_tree().get_first_node_in_group("game_camera") as Camera2D
	if camera == null:
		camera = get_viewport().get_camera_2d()

	if camera != null:
		if camera.has_method("get_game_mouse_world_position"):
			return camera.call("get_game_mouse_world_position") as Vector2

		return camera.get_global_mouse_position()

	return get_viewport().get_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	if handle_game_viewport_input(event):
		get_viewport().set_input_as_handled()


func handle_game_viewport_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false

	if not is_targeting_enabled():
		return false

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_all_targeting()
		return true

	if rain_targeting_enabled and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return _try_apply_rain_at_mouse()

	if sun_targeting_enabled and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return _try_apply_sun_at_mouse()

	if earthquake_targeting_enabled and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return _try_apply_earthquake_at_mouse()

	return false


func handle_game_subviewport_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion and rain_targeting_enabled:
		var motion_camera := get_tree().get_first_node_in_group("game_camera") as Camera2D
		var motion_world_grid := _get_world_grid()
		if motion_camera != null and motion_camera.has_method("game_screen_to_world") and motion_world_grid != null:
			var motion_world_position: Vector2 = motion_camera.call("game_screen_to_world", event.position)
			rain_preview_tile_override = motion_world_grid.call("world_to_map_tile", motion_world_position)
			rain_preview_tile_override_enabled = true
			_update_rain_target_preview()
		return false
	if not (event is InputEventMouseButton):
		return false
	if not is_targeting_enabled():
		return false
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_all_targeting()
		return true
	if rain_targeting_enabled and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var camera := get_tree().get_first_node_in_group("game_camera") as Camera2D
		if camera == null or not camera.has_method("game_screen_to_world"):
			return false
		var world_position: Vector2 = camera.call("game_screen_to_world", event.position)
		return _try_apply_rain_at_world_position(world_position)
	return handle_game_viewport_input(event)
