extends Camera2D

@export var move_speed := 500.0
@export var zoom_step := 0.1
@export var min_zoom := 0.5
@export var max_zoom := 5.0

func _process(delta):
	var direction = Vector2.ZERO

	if Input.is_key_pressed(KEY_D):
		direction.x += 1
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1

	if direction != Vector2.ZERO:
		position += direction.normalized() * move_speed * delta


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(zoom_step)


func change_zoom(amount: float):
	var new_zoom = zoom.x + amount
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
