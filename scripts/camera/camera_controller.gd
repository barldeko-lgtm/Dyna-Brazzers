extends Camera2D

# Скорость перемещения камеры по карте.
@export var move_speed := 500.0

# Шаг изменения зума за одно прокручивание колеса мыши.
@export var zoom_step := 0.1

# Минимально допустимое приближение камеры.
@export var min_zoom := 0.7

# Максимально допустимое отдаление камеры.
@export var max_zoom := 7.0


# Обрабатывает движение камеры по WASD каждый кадр.
func _process(delta: float) -> void:
	var direction := Vector2.ZERO

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


# Обрабатывает прокрутку колеса мыши для изменения зума.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(zoom_step)


# Меняет текущий зум камеры в пределах заданных ограничений.
func change_zoom(amount: float) -> void:
	var new_zoom := zoom.x + amount
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
