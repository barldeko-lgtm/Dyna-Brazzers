extends CharacterBody2D

# Ссылка на основной спрайт существа, который можно отражать по X.
@onready var sprite: Sprite2D = $BodySprite

# Таймер, который отвечает за длительность поедания травы.
@onready var eating_timer: Timer = $EatingTimer

# Зона, которая ловит наведение мыши на существо.
@onready var hover_area: Area2D = $HoverArea

# Простые состояния поведения существа на раннем этапе.
enum State {
	IDLE,
	WALK,
	SEEK_FOOD,
	EATING
}

# Скорость передвижения существа.
@export var speed := 100.0

# Минимальное время простоя.
@export var idle_time_min := 1.0

# Максимальное время простоя.
@export var idle_time_max := 3.0

# Минимальное время движения в одном направлении.
@export var walk_time_min := 2.0

# Максимальное время движения в одном направлении.
@export var walk_time_max := 5.0

# Технический идентификатор вида существа.
@export var species_id := "stegosaurus"

# Человекочитаемое название вида существа.
@export var species_name := "Стегозавр"

# Отображаемое имя существа для UI.
@export var creature_name := "Стегозавр"

# Максимальное здоровье существа.
@export var max_health := 100.0

# Текущее здоровье существа на старте.
@export var health := 100.0

# Скорость потери здоровья при полном голоде.
@export var starvation_health_decay_rate := 2.0

# Базовая атака существа для будущей боевой системы.
@export var attack := 10.0

# Базовая защита существа для будущей боевой системы.
@export var defense := 5.0

# Текущий возраст существа в условных годах.
@export var age := 0.0

# Возраст, при котором существо считается слишком старым и умирает.
@export var max_age := 100.0

# Максимальная сытость существа.
@export var max_hunger := 100.0

# Текущая сытость существа на старте.
@export var hunger := 100.0

# Скорость уменьшения сытости: 10 единиц в секунду.
@export var hunger_decay_rate := 10.0

# Порог, после которого существо начинает искать еду.
@export var hunger_search_threshold := 70.0

# Сколько сытости восстанавливается после одного приёма пищи.
@export var hunger_restore_amount := 30.0

# Время, которое существо тратит на поедание травы.
@export var eating_duration := 3.0

# Дистанция, на которой считается, что существо дошло до травы.
@export var eat_range := 24.0

# Текущее состояние существа.
var state: State = State.WALK

# Текущее направление движения.
var direction := Vector2.ZERO

# Таймер текущего состояния блуждания.
var state_timer := 0.0

# Текущая цель для еды.
var target_grass: Node2D


# Подготавливает существо, таймер еды и сразу запускает первое движение.
func _ready() -> void:
	randomize()
	eating_timer.one_shot = true

	if not eating_timer.timeout.is_connected(_on_eating_timer_timeout):
		eating_timer.timeout.connect(_on_eating_timer_timeout)

	if not hover_area.mouse_entered.is_connected(_on_hover_area_mouse_entered):
		hover_area.mouse_entered.connect(_on_hover_area_mouse_entered)

	if not hover_area.mouse_exited.is_connected(_on_hover_area_mouse_exited):
		hover_area.mouse_exited.connect(_on_hover_area_mouse_exited)

	health = clamp(health, 0.0, max_health)
	age = clamp(age, 0.0, max_age)
	hunger = clamp(hunger, 0.0, max_hunger)
	enter_walk()


# Обновляет голод, состояние существа и применяет движение через физику.
func _physics_process(delta: float) -> void:
	update_hunger(delta)
	update_health(delta)
	update_food_behavior()

	match state:
		State.IDLE:
			update_idle(delta)
		State.WALK:
			update_walk(delta)
		State.SEEK_FOOD:
			update_seek_food()
		State.EATING:
			update_eating()

	move_and_slide()


# Постепенно уменьшает сытость, пока существо не ест.
func update_hunger(delta: float) -> void:
	if state == State.EATING:
		return

	hunger = clamp(hunger - hunger_decay_rate * delta, 0.0, max_hunger)


# Уменьшает здоровье, если существо полностью голодно.
func update_health(delta: float) -> void:
	if hunger > 0.0:
		return

	health = clamp(health - starvation_health_decay_rate * delta, 0.0, max_health)


# Переключает существо в режим поиска еды, когда оно проголодалось.
func update_food_behavior() -> void:
	if state == State.EATING:
		return

	if hunger > hunger_search_threshold:
		if state == State.SEEK_FOOD and not is_instance_valid(target_grass):
			target_grass = null
		return

	if state == State.SEEK_FOOD and is_instance_valid(target_grass) and target_grass.has_method("can_be_eaten") and target_grass.can_be_eaten():
		return

	var nearest_grass := find_nearest_edible_grass()

	if nearest_grass != null:
		enter_seek_food(nearest_grass)


# Логика состояния покоя: существо стоит на месте до конца таймера.
func update_idle(delta: float) -> void:
	state_timer -= delta
	velocity = Vector2.ZERO

	if state_timer <= 0.0:
		enter_walk()


# Логика состояния движения: существо идёт в выбранную сторону.
func update_walk(delta: float) -> void:
	state_timer -= delta
	velocity = direction * speed
	update_sprite_flip()

	if state_timer <= 0.0:
		enter_idle()


# Логика поиска еды: существо идёт к ближайшей взрослой траве.
func update_seek_food() -> void:
	if not is_instance_valid(target_grass):
		target_grass = null
		enter_walk()
		return

	if not target_grass.has_method("can_be_eaten") or not target_grass.can_be_eaten():
		target_grass = null
		enter_walk()
		return

	var target_direction := global_position.direction_to(target_grass.global_position)
	direction = target_direction
	velocity = direction * speed
	update_sprite_flip()

	if global_position.distance_to(target_grass.global_position) <= eat_range:
		enter_eating()


# Логика поедания: существо стоит на месте и ждёт завершения таймера еды.
func update_eating() -> void:
	velocity = Vector2.ZERO


# Переводит существо в состояние покоя и задаёт новую длину паузы.
func enter_idle() -> void:
	state = State.IDLE
	state_timer = randf_range(idle_time_min, idle_time_max)
	velocity = Vector2.ZERO


# Переводит существо в состояние движения и выбирает новое направление.
func enter_walk() -> void:
	state = State.WALK
	target_grass = null
	choose_new_direction()
	state_timer = randf_range(walk_time_min, walk_time_max)
	velocity = direction * speed
	update_sprite_flip()


# Переводит существо в режим поиска указанной травы.
func enter_seek_food(grass: Node2D) -> void:
	state = State.SEEK_FOOD
	target_grass = grass
	velocity = Vector2.ZERO


# Переводит существо в режим поедания найденной травы.
func enter_eating() -> void:
	state = State.EATING
	velocity = Vector2.ZERO
	eating_timer.start(eating_duration)


# Выбирает случайное нормализованное направление движения.
func choose_new_direction() -> void:
	direction = Vector2.from_angle(randf() * TAU).normalized()


# Находит ближайшую взрослую траву, которую уже можно есть.
func find_nearest_edible_grass() -> Node2D:
	var grasses := get_tree().get_nodes_in_group("grass")
	var nearest_grass: Node2D = null
	var nearest_distance := INF

	for grass in grasses:
		if not (grass is Node2D):
			continue

		if not grass.has_method("can_be_eaten"):
			continue

		if not grass.can_be_eaten():
			continue

		var distance := global_position.distance_to(grass.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_grass = grass

	return nearest_grass


# Завершает поедание: уменьшает траву и восстанавливает часть сытости.
func _on_eating_timer_timeout() -> void:
	if is_instance_valid(target_grass) and target_grass.has_method("consume"):
		if target_grass.consume():
			hunger = clamp(hunger + hunger_restore_amount, 0.0, max_hunger)

	if hunger <= hunger_search_threshold:
		var nearest_grass := find_nearest_edible_grass()

		if nearest_grass != null:
			enter_seek_food(nearest_grass)
			return

	enter_walk()


# Разворачивает спрайт по X в зависимости от направления движения.
func update_sprite_flip() -> void:
	if direction.x > 0.01:
		sprite.flip_h = true
	elif direction.x < -0.01:
		sprite.flip_h = false


# Возвращает технический идентификатор вида.
func get_species_id() -> String:
	return species_id


# Возвращает название вида существа.
func get_species_name() -> String:
	return species_name


# Возвращает текущий возраст существа.
func get_age() -> float:
	return age


# Возвращает возраст смерти существа.
func get_max_age() -> float:
	return max_age


# Возвращает имя существа для UI.
func get_creature_name() -> String:
	return creature_name


# Возвращает текущее здоровье в процентах для UI.
func get_health_percent() -> float:
	if max_health <= 0.0:
		return 0.0

	return clamp((health / max_health) * 100.0, 0.0, 100.0)


# Возвращает текущую сытость в процентах для UI.
func get_hunger_percent() -> float:
	if max_hunger <= 0.0:
		return 0.0

	return clamp((hunger / max_hunger) * 100.0, 0.0, 100.0)


# Показывает UI со статами, когда мышка наведена на существо.
func _on_hover_area_mouse_entered() -> void:
	var stats_ui := get_tree().get_first_node_in_group("creature_stats_ui")

	if stats_ui != null and stats_ui.has_method("show_creature_stats"):
		stats_ui.show_creature_stats(self)


# Скрывает UI со статами, когда мышка уходит с существа.
func _on_hover_area_mouse_exited() -> void:
	var stats_ui := get_tree().get_first_node_in_group("creature_stats_ui")

	if stats_ui != null and stats_ui.has_method("hide_creature_stats"):
		stats_ui.hide_creature_stats()
