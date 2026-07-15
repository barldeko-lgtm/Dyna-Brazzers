extends Camera2D

# Free observer camera, constrained to the authored world.
@export var move_speed := 1000.0
@export var zoom_step := 0.1
@export var min_zoom := 0.7
@export var max_zoom := 7.0
@export var clamp_to_world := true
@export var use_camera_start_marker := true

var world_grid: Node = null
var start_position_checked: bool = false


func _ready() -> void:
	call_deferred("_initialize_camera")


# WASD pan.
func _process(delta: float) -> void:
	_ensure_world_grid()

	var direction: Vector2 = Vector2.ZERO

	if Input.is_key_pressed(KEY_D):
		direction.x += 1
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1

	if direction != Vector2.ZERO:
		global_position += direction.normalized() * move_speed * delta

	_clamp_camera_to_world()


func _initialize_camera() -> void:
	_ensure_world_grid()

	if use_camera_start_marker and not start_position_checked:
		var start_marker: Node = get_tree().get_first_node_in_group("camera_start")

		# SaveSystem restores a non-zero camera position after loading.
		# Only a fresh New Game session starts at the authored red marker.
		if start_marker is Node2D and global_position.is_equal_approx(Vector2.ZERO):
			global_position = start_marker.global_position

		start_position_checked = true

	_clamp_camera_to_world()


func _ensure_world_grid() -> void:
	if is_instance_valid(world_grid):
		return

	world_grid = get_tree().get_first_node_in_group("world_grid")


# Wheel zoom.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(zoom_step)


# Clamp zoom.
func change_zoom(amount: float) -> void:
	var new_zoom: float = zoom.x + amount
	new_zoom = clampf(new_zoom, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera_to_world()


func _clamp_camera_to_world() -> void:
	if not clamp_to_world:
		return

	_ensure_world_grid()

	if world_grid == null or not world_grid.has_method("get_world_bounds_rect"):
		return

	var world_bounds: Rect2 = world_grid.get_world_bounds_rect()

	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var safe_zoom_x: float = maxf(zoom.x, 0.001)
	var safe_zoom_y: float = maxf(zoom.y, 0.001)
	var half_visible: Vector2 = Vector2(
		viewport_size.x / safe_zoom_x,
		viewport_size.y / safe_zoom_y
	) * 0.5

	var minimum_center: Vector2 = world_bounds.position + half_visible
	var maximum_center: Vector2 = world_bounds.position + world_bounds.size - half_visible
	var target_position: Vector2 = global_position

	if minimum_center.x > maximum_center.x:
		target_position.x = world_bounds.get_center().x
	else:
		target_position.x = clampf(target_position.x, minimum_center.x, maximum_center.x)

	if minimum_center.y > maximum_center.y:
		target_position.y = world_bounds.get_center().y
	else:
		target_position.y = clampf(target_position.y, minimum_center.y, maximum_center.y)

	global_position = target_position
