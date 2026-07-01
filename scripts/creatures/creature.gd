extends CharacterBody2D

# Ссылка на основной спрайт существа, который можно отражать по X.
@onready var sprite: Sprite2D = $BodySprite

# Таймер, который отвечает за длительность поедания травы.
@onready var eating_timer: Timer = $EatingTimer

# Таймер, который отвечает за длительность состояния откладки яйца.
@onready var egg_laying_timer: Timer = $EggLayingTimer

# Зона, которая ловит наведение мыши на существо.
@onready var hover_area: Area2D = $HoverArea

# Простые состояния поведения существа на текущем этапе.
enum State {
	IDLE,
	WALK,
	SEEK_FOOD,
	EATING,
	LAYING_EGG,
	DEAD
}

# Спрайт существа, когда оно смотрит вниз.
@export var down_texture: Texture2D

# Спрайт существа, когда оно смотрит вверх.
@export var up_texture: Texture2D

# Спрайт существа, когда оно смотрит вправо.
@export var right_texture: Texture2D

# Спрайт существа, когда оно смотрит вверх-вправо.
@export var up_right_texture: Texture2D

# Спрайт существа, когда оно смотрит вниз-вправо.
@export var down_right_texture: Texture2D

# Скорость перемещения существа в пикселях в секунду.
@export var speed := 140.0

# Минимальное время простоя.
@export var idle_time_min := 1.0

# Максимальное время простоя.
@export var idle_time_max := 3.0

# Минимальное время блуждания.
@export var walk_time_min := 2.0

# Максимальное время блуждания.
@export var walk_time_max := 5.0

# Размер существа в тайлах: по договорённости сейчас 2x2.
@export var footprint_size := Vector2i(2, 2)

# Раз в сколько секунд голодное существо перепроверяет ближайшие пастбища.
@export var food_recheck_interval := 2.0

# Радиус локального пересмотра цели пастьбы в тайлах.
@export var nearby_grazing_recheck_radius := 6

# Минимум взрослых кустов под существом, чтобы оно начинало есть.
@export var min_grass_to_eat := 2

# Вес числа взрослых кустов в формуле выбора пастбища.
@export var grazing_grass_weight := 10.0

# Штраф за каждый шаг расстояния в формуле выбора пастбища.
@export var grazing_distance_penalty := 2.5

# Насколько новый маршрут должен быть короче при почти равной выгоде, чтобы менять цель.
@export var retarget_distance_advantage := 2

# Опорный тайл, на котором существо зафиксировалось в момент начала еды.
var eating_anchor_tile := Vector2i.ZERO

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

# Скорость пассивного восстановления здоровья, пока существо сыто.
@export var well_fed_health_regen_rate := 1.0

# Порог сытости, выше которого включается пассивная регенерация здоровья.
@export var satiety_heal_threshold := 70.0

# Базовая атака существа для будущей боевой системы.
@export var attack := 10.0

# Базовая защита существа для будущей боевой системы.
@export var defense := 5.0

# Текущий возраст существа в условных годах.
@export var age := 0.0

# Возраст, при котором существо считается слишком старым и умирает.
@export var max_age := 10.0

# Раз в сколько секунд существо становится старше на 1 год.
@export var age_tick_interval := 30.0

# Максимальная сытость существа.
@export var max_hunger := 100.0

# Текущая сытость существа на старте.
@export var hunger := 100.0

# Скорость уменьшения сытости: 10 единиц в секунду.
@export var hunger_decay_rate := 10.0

# Порог, после которого существо начинает искать еду.
@export var hunger_search_threshold := 70.0

# Сколько сытости восстанавливается за один взрослый куст травы под телом.
@export var hunger_restore_amount := 10.0

# Время, которое существо тратит на поедание травы.
@export var eating_duration := 3.0

# Сцена яйца для текущего вида существа.
@export var egg_scene: PackedScene

# Текстура первой стадии яйца этого вида.
@export var egg_stage_1_texture: Texture2D

# Текстура второй стадии яйца этого вида.
@export var egg_stage_2_texture: Texture2D

# Сколько секунд длится состояние откладки яйца у существа.
@export var egg_laying_duration := 5.0

# Сколько секунд длится первая стадия яйца.
@export var egg_stage_1_duration := 5.0

# Раз в сколько секунд яйцо повторно проверяет возможность расшириться до 2x2.
@export var egg_expand_retry_interval := 1.0

# Сколько секунд длится вторая стадия яйца до вылупления.
@export var egg_stage_2_duration := 5.0

# Порог здоровья, выше которого существо может размножаться.
@export var reproduction_min_health := 30.0

# Порог сытости, выше которого существо может размножаться.
@export var reproduction_min_hunger := 70.0

# Минимальный возраст для откладки яйца.
@export var reproduction_min_age := 3.0

# Кулдаун между откладками яиц.
@export var reproduction_cooldown := 20.0

# Сколько сытости тратится на откладку яйца.
@export var reproduction_hunger_cost := 20.0

# Стартовое здоровье вылупившегося существа.
@export var hatchling_health := 100.0

# Стартовая сытость вылупившегося существа.
@export var hatchling_hunger := 50.0

# Текущее состояние существа.
var state: State = State.WALK

# Сколько времени прошло до следующего увеличения возраста.
var age_tick_elapsed := 0.0

# Ссылка на grid-manager мира.
var world_grid: Node = null

# Тайл-опора существа: верхний левый тайл его footprint.
var anchor_tile := Vector2i.ZERO

# Временный визуальный сдвиг спрайта. Сейчас держим в нуле для честной проверки центра 2x2.
var render_offset := Vector2.ZERO

# Направление последнего движения для отражения спрайта.
var direction := Vector2.ZERO

# Таймер текущего состояния блуждания.
var state_timer := 0.0

# Таймер периодической переоценки пастбища.
var food_recheck_timer := 0.0

# Текущий маршрут как список опорных тайлов.
var current_path: Array[Vector2i] = []

# Текущий целевой тайл для пастьбы.
var grazing_target_anchor := Vector2i.ZERO

# Есть ли сейчас валидная целевая точка пастьбы.
var has_grazing_target := false

# Следующий тайл шага, к которому существо сейчас визуально движется.
var pending_anchor_tile := Vector2i.ZERO

# Мировая точка, в которую сейчас едет центр существа.
var movement_target_position := Vector2.ZERO

# Идёт ли сейчас визуальное перемещение между тайлами.
var is_moving := false

# Сколько осталось до следующей разрешённой откладки яйца.
var reproduction_cooldown_remaining := 0.0

# Куда существо собирается положить яйцо после завершения анимации откладки.
var pending_egg_anchor := Vector2i.ZERO

# Footprint яйца в первой стадии: вертикальный 1x2.
const EGG_STAGE_1_FOOTPRINT := Vector2i(1, 2)


# Подготавливает существо, регистрирует его на сетке и сразу запускает первое поведение.
func _ready() -> void:
	randomize()
	eating_timer.one_shot = true
	egg_laying_timer.one_shot = true

	if not eating_timer.timeout.is_connected(_on_eating_timer_timeout):
		eating_timer.timeout.connect(_on_eating_timer_timeout)

	if not egg_laying_timer.timeout.is_connected(_on_egg_laying_timer_timeout):
		egg_laying_timer.timeout.connect(_on_egg_laying_timer_timeout)

	if not hover_area.mouse_entered.is_connected(_on_hover_area_mouse_entered):
		hover_area.mouse_entered.connect(_on_hover_area_mouse_entered)

	if not hover_area.mouse_exited.is_connected(_on_hover_area_mouse_exited):
		hover_area.mouse_exited.connect(_on_hover_area_mouse_exited)

	if not hover_area.input_event.is_connected(_on_hover_area_input_event):
		hover_area.input_event.connect(_on_hover_area_input_event)

	health = clamp(health, 0.0, max_health)
	age = 0.0
	age_tick_elapsed = 0.0
	hunger = clamp(hunger, 0.0, max_hunger)
	world_grid = find_world_grid()

	if world_grid != null:
		var initial_position := global_position
		anchor_tile = world_grid.world_to_anchor_tile(initial_position, footprint_size)
		anchor_tile = world_grid.find_nearest_valid_anchor(anchor_tile, footprint_size, self)
		render_offset = Vector2.ZERO
		world_grid.register_creature(self, anchor_tile, footprint_size)
		global_position = world_grid.anchor_to_world_position(anchor_tile, footprint_size)
		sprite.position = Vector2.ZERO

	update_sprite_visual()
	enter_walk()


# Освобождает занятые тайлы при удалении существа со сцены.
func _exit_tree() -> void:
	if world_grid != null:
		world_grid.unregister_creature(self, footprint_size)


# Обновляет голод, состояние и движение существа по сетке.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	update_age(delta)

	if check_age_death():
		return

	update_hunger(delta)
	update_health(delta)
	update_reproduction_cooldown(delta)

	if check_health_death():
		return

	update_reproduction_behavior()
	update_food_behavior()

	if is_moving:
		advance_movement(delta)

	match state:
		State.IDLE:
			update_idle(delta)
		State.WALK:
			update_walk(delta)
		State.SEEK_FOOD:
			update_seek_food(delta)
		State.EATING:
			update_eating()
		State.LAYING_EGG:
			update_laying_egg()
		State.DEAD:
			return

# Раз в 30 секунд добавляет существу 1 год возраста.
func update_age(delta: float) -> void:
	if age_tick_interval <= 0.0:
		return

	age_tick_elapsed += delta

	while age_tick_elapsed >= age_tick_interval:
		age_tick_elapsed -= age_tick_interval
		age += 1.0


# Проверяет, не умерло ли существо от старости.
func check_age_death() -> bool:
	if state == State.DEAD:
		return true

	if age < max_age:
		return false

	enter_dead()
	return true


# Постепенно уменьшает сытость, пока существо не ест.
func update_hunger(delta: float) -> void:
	if state == State.EATING or state == State.LAYING_EGG:
		return

	hunger = clamp(hunger - hunger_decay_rate * delta, 0.0, max_hunger)


# Обновляет здоровье: при полном голоде снимает HP, а при высокой сытости медленно восстанавливает.
func update_health(delta: float) -> void:
	if hunger <= 0.0:
		health = clamp(health - starvation_health_decay_rate * delta, 0.0, max_health)
		return

	if hunger > satiety_heal_threshold and health < max_health:
		health = clamp(health + well_fed_health_regen_rate * delta, 0.0, max_health)


# Проверяет, не умерло ли существо от потери здоровья.
func check_health_death() -> bool:
	if state == State.DEAD:
		return true

	if health > 0.0:
		return false

	enter_dead()
	return true


# Уменьшает кулдаун размножения, если он сейчас активен.
func update_reproduction_cooldown(delta: float) -> void:
	if reproduction_cooldown_remaining <= 0.0:
		return

	reproduction_cooldown_remaining = max(reproduction_cooldown_remaining - delta, 0.0)


# Решает, пора ли существу искать пастбище.
func update_food_behavior() -> void:
	if world_grid == null:
		return

	if state == State.EATING or state == State.LAYING_EGG:
		return

	# Не переключаемся на поиск еды посреди шага: сначала доходим до центра текущего тайла.
	if is_moving:
		return

	if hunger > hunger_search_threshold:
		return

	if state != State.SEEK_FOOD:
		enter_seek_food()


# Логика состояния покоя: существо стоит на месте до конца таймера.
func update_idle(delta: float) -> void:
	state_timer -= delta

	if state_timer <= 0.0:
		enter_walk()


# Логика блуждания: существо случайно шагает по соседним тайлам.
func update_walk(delta: float) -> void:
	state_timer -= delta

	if is_moving:
		return

	if state_timer <= 0.0:
		enter_idle()
		return

	if current_path.is_empty():
		choose_random_wander_step()

	start_next_path_step_if_needed()


# Логика поиска еды: существо идёт к лучшей точке пастьбы и иногда переоценивает цель.
func update_seek_food(delta: float) -> void:
	food_recheck_timer -= delta

	if food_recheck_timer <= 0.0:
		recheck_grazing_target()
		food_recheck_timer = food_recheck_interval

	if not is_moving and can_start_eating_here() and (not has_grazing_target or anchor_tile == grazing_target_anchor):
		enter_eating()
		return

	if not has_grazing_target:
		if not is_moving and current_path.is_empty():
			choose_random_wander_step()

		start_next_path_step_if_needed()
		return

	start_next_path_step_if_needed()

	if not is_moving and current_path.is_empty() and has_grazing_target:
		if anchor_tile == grazing_target_anchor:
			if can_start_eating_here():
				enter_eating()
			else:
				has_grazing_target = false
				try_acquire_grazing_target()
		else:
			build_path_to_grazing_target()


# Во время еды существо стоит на месте и ждёт таймер.
func update_eating() -> void:
	return


# Во время откладки яйца существо просто стоит на месте и ждёт таймер.
func update_laying_egg() -> void:
	return


# Переводит существо в состояние покоя и задаёт новую длину паузы.
func enter_idle() -> void:
	state = State.IDLE
	state_timer = randf_range(idle_time_min, idle_time_max)
	clear_path()


# Переводит существо в состояние блуждания.
func enter_walk() -> void:
	state = State.WALK
	state_timer = randf_range(walk_time_min, walk_time_max)
	has_grazing_target = false
	clear_path()


# Переводит существо в режим поиска пастбища.
func enter_seek_food() -> void:
	state = State.SEEK_FOOD
	food_recheck_timer = food_recheck_interval
	has_grazing_target = false
	clear_path()
	try_acquire_grazing_target()


# Переводит существо в режим поедания травы.
func enter_eating() -> void:
	state = State.EATING
	eating_anchor_tile = anchor_tile
	clear_path()
	eating_timer.start(eating_duration)


# Переводит существо в состояние откладки яйца.
func enter_laying_egg(egg_anchor: Vector2i) -> void:
	state = State.LAYING_EGG
	pending_egg_anchor = egg_anchor
	clear_path()
	egg_laying_timer.start(egg_laying_duration)


# Переводит существо в состояние смерти и удаляет его из мира.
func enter_dead() -> void:
	if state == State.DEAD:
		return

	state = State.DEAD
	has_grazing_target = false
	clear_path()
	eating_timer.stop()
	egg_laying_timer.stop()
	hover_area.input_pickable = false
	call_deferred("queue_free")


# Выбирает один случайный валидный соседний тайл для шага.
func choose_random_wander_step() -> void:
	if world_grid == null:
		return

	var neighbors: Array[Vector2i] = world_grid.get_neighbors(anchor_tile, footprint_size, self)

	if neighbors.is_empty():
		return

	var random_index := randi_range(0, neighbors.size() - 1)
	current_path = [neighbors[random_index]]


# Проверяет, можно ли начать есть на текущей позиции.
func can_start_eating_here() -> bool:
	if world_grid == null:
		return false

	return world_grid.count_adult_grass_under_footprint(anchor_tile, footprint_size) >= min_grass_to_eat


# Возвращает опорный тайл, от которого нужно считать навигацию прямо сейчас.
func get_navigation_anchor() -> Vector2i:
	if is_moving:
		return pending_anchor_tile

	return anchor_tile


# Пытается найти лучшую цель пастьбы: сначала рядом, потом по всей карте.
func try_acquire_grazing_target() -> void:
	if world_grid == null:
		return

	var navigation_anchor := get_navigation_anchor()
	var local_target: Dictionary = world_grid.find_best_grazing_target(
		navigation_anchor,
		footprint_size,
		min_grass_to_eat,
		nearby_grazing_recheck_radius,
		self,
		grazing_grass_weight,
		grazing_distance_penalty
	)

	if not local_target.is_empty():
		apply_grazing_target(local_target)
		return

	var global_target: Dictionary = world_grid.find_best_grazing_target(
		navigation_anchor,
		footprint_size,
		min_grass_to_eat,
		-1,
		self,
		grazing_grass_weight,
		grazing_distance_penalty
	)

	if not global_target.is_empty():
		apply_grazing_target(global_target)
		return

	has_grazing_target = false
	grazing_target_anchor = anchor_tile
	clear_path()


# Назначает новую точку пастьбы и перестраивает маршрут к ней.
func apply_grazing_target(target_data: Dictionary) -> void:
	has_grazing_target = true
	grazing_target_anchor = target_data.get("anchor", anchor_tile)
	build_path_to_grazing_target()


# Перестраивает путь к текущей точке пастьбы.
func build_path_to_grazing_target() -> void:
	if world_grid == null or not has_grazing_target:
		return

	var navigation_anchor := get_navigation_anchor()
	current_path = world_grid.find_path(navigation_anchor, grazing_target_anchor, footprint_size, self)


# Раз в несколько секунд переоценивает ближайшие пастбища, чтобы не тупить на старой цели.
func recheck_grazing_target() -> void:
	if world_grid == null:
		return

	var navigation_anchor := get_navigation_anchor()
	var nearby_target: Dictionary = world_grid.find_best_grazing_target(
		navigation_anchor,
		footprint_size,
		min_grass_to_eat,
		nearby_grazing_recheck_radius,
		self,
		grazing_grass_weight,
		grazing_distance_penalty
	)

	if nearby_target.is_empty():
		if has_grazing_target and is_current_grazing_target_still_valid():
			return

		# Если рядом еды нет и текущая цель потеряна, обязательно делаем fallback на общий поиск по карте.
		try_acquire_grazing_target()
		return

	if not has_grazing_target:
		apply_grazing_target(nearby_target)
		return

	var new_score := float(nearby_target.get("score", -INF))
	var current_adult_count := get_current_grazing_target_adult_count()
	var current_distance: int = world_grid.estimate_path_steps(navigation_anchor, grazing_target_anchor)
	var current_score := float(current_adult_count) * grazing_grass_weight - float(current_distance) * grazing_distance_penalty
	var new_distance := int(nearby_target.get("distance", 0))

	if new_score > current_score:
		apply_grazing_target(nearby_target)
		return

	if is_equal_approx(new_score, current_score) and new_distance < current_distance - retarget_distance_advantage:
		apply_grazing_target(nearby_target)
		return

	if not is_current_grazing_target_still_valid():
		apply_grazing_target(nearby_target)


# Проверяет, не испортилась ли текущая точка пастьбы.
func is_current_grazing_target_still_valid() -> bool:
	if not has_grazing_target or world_grid == null:
		return false

	if not world_grid.can_place_footprint(grazing_target_anchor, footprint_size, self):
		return false

	return get_current_grazing_target_adult_count() >= min_grass_to_eat


# Возвращает число взрослых кустов на текущей цели пастьбы.
func get_current_grazing_target_adult_count() -> int:
	if world_grid == null or not has_grazing_target:
		return 0

	return world_grid.count_adult_grass_under_footprint(grazing_target_anchor, footprint_size)


# Начинает движение к следующему тайлу из текущего пути.
func start_next_path_step_if_needed() -> void:
	if is_moving:
		return

	if current_path.is_empty():
		return

	pending_anchor_tile = current_path[0]
	current_path.remove_at(0)
	movement_target_position = world_grid.anchor_to_world_position(pending_anchor_tile, footprint_size)
	direction = global_position.direction_to(movement_target_position)
	update_sprite_visual()
	is_moving = true


# Плавно двигает существо к следующему опорному тайлу.
func advance_movement(delta: float) -> void:
	global_position = global_position.move_toward(movement_target_position, speed * delta)

	if global_position.distance_to(movement_target_position) > 0.1:
		return

	global_position = movement_target_position
	is_moving = false

	if world_grid != null and not world_grid.move_creature(self, pending_anchor_tile, footprint_size):
		# Если целевой footprint успели занять, откатываем визуал к старому логическому anchor.
		# Иначе существо может стоять в одном 2x2, а есть/занимать тайлы в другом.
		global_position = world_grid.anchor_to_world_position(anchor_tile, footprint_size)
		clear_path()
		has_grazing_target = false
		return

	anchor_tile = pending_anchor_tile

	if state == State.SEEK_FOOD and can_start_eating_here() and (not has_grazing_target or anchor_tile == grazing_target_anchor):
		enter_eating()


# Очищает текущий маршрут и останавливает визуальный переход между тайлами.
func clear_path() -> void:
	current_path.clear()
	is_moving = false
	pending_anchor_tile = anchor_tile
	movement_target_position = global_position


# Завершает поедание: съедает всю взрослую траву под телом и восстанавливает сытость.
func _on_eating_timer_timeout() -> void:
	if world_grid == null:
		enter_walk()
		return

	var consumed_grass_count: int = world_grid.consume_adult_grass_under_footprint(eating_anchor_tile, footprint_size)

	if consumed_grass_count > 0:
		hunger = clamp(hunger + hunger_restore_amount * float(consumed_grass_count), 0.0, max_hunger)

	if hunger <= hunger_search_threshold:
		enter_seek_food()
		return

	enter_walk()


# Завершает состояние откладки: создаёт яйцо и тратит ресурсы существа.
func _on_egg_laying_timer_timeout() -> void:
	if world_grid == null:
		enter_walk()
		return

	if spawn_egg_at_pending_anchor():
		hunger = clamp(hunger - reproduction_hunger_cost, 0.0, max_hunger)
		reproduction_cooldown_remaining = reproduction_cooldown

	if hunger <= hunger_search_threshold:
		enter_seek_food()
		return

	enter_walk()


# Проверяет, можно ли сейчас начать размножение, и при успехе запускает откладку яйца.
func update_reproduction_behavior() -> void:
	if world_grid == null:
		return

	if state == State.DEAD or state == State.EATING or state == State.LAYING_EGG:
		return

	if is_moving:
		return

	if reproduction_cooldown_remaining > 0.0:
		return

	if health <= reproduction_min_health:
		return

	if hunger <= reproduction_min_hunger:
		return

	if age <= reproduction_min_age:
		return

	var egg_anchor := get_egg_spawn_anchor()

	if egg_anchor == Vector2i(2147483647, 2147483647):
		return

	enter_laying_egg(egg_anchor)


# Вычисляет anchor первой стадии яйца из текущей позиции существа, чтобы яйцо появлялось в том же месте.
func get_egg_spawn_anchor() -> Vector2i:
	if world_grid == null:
		return Vector2i(2147483647, 2147483647)

	return world_grid.world_to_anchor_tile(global_position, EGG_STAGE_1_FOOTPRINT)


# Возвращает основное направление взгляда существа в координатах тайлов.
func get_facing_tile_direction() -> Vector2i:
	if absf(direction.x) >= absf(direction.y):
		if direction.x < -0.01:
			return Vector2i.LEFT
		if direction.x > 0.01:
			return Vector2i.RIGHT
	else:
		if direction.y < -0.01:
			return Vector2i.UP
		if direction.y > 0.01:
			return Vector2i.DOWN

	return Vector2i.DOWN


# Создаёт яйцо на уже выбранном тайле откладки.
func spawn_egg_at_pending_anchor() -> bool:
	if egg_scene == null:
		return false

	var eggs_container := find_named_container("Eggs")

	if eggs_container == null:
		eggs_container = get_parent() as Node2D

	if eggs_container == null:
		return false

	var new_egg := egg_scene.instantiate() as Node2D

	if new_egg == null:
		return false

	new_egg.set("species_id", species_id)
	new_egg.set("stage_1_texture", egg_stage_1_texture)
	new_egg.set("stage_2_texture", egg_stage_2_texture)
	new_egg.set("stage_1_duration", egg_stage_1_duration)
	new_egg.set("expand_retry_interval", egg_expand_retry_interval)
	new_egg.set("stage_2_duration", egg_stage_2_duration)
	new_egg.set("hatch_health", hatchling_health)
	new_egg.set("hatch_hunger", hatchling_hunger)
	new_egg.set("hatch_creature_scene", load(scene_file_path) as PackedScene)

	var egg_world_position: Vector2 = world_grid.anchor_to_world_position(pending_egg_anchor, EGG_STAGE_1_FOOTPRINT)
	new_egg.position = eggs_container.to_local(egg_world_position)
	eggs_container.add_child(new_egg)

	return true


# Ищет ближайший контейнер с указанным именем, поднимаясь вверх по дереву.
func find_named_container(target_name: String) -> Node2D:
	var current: Node = self

	while current != null:
		var candidate := current.get_node_or_null(target_name) as Node2D

		if candidate != null:
			return candidate

		current = current.get_parent()

	return null


# Выбирает нужный directional-спрайт и при необходимости флипает его влево.
func update_sprite_visual() -> void:
	if sprite == null:
		return

	var abs_x := absf(direction.x)
	var abs_y := absf(direction.y)
	var faces_left := direction.x < -0.01
	var faces_right := direction.x > 0.01
	var faces_up := direction.y < -0.01
	var faces_down := direction.y > 0.01

	sprite.flip_h = false

	if abs_x <= 0.01 and abs_y <= 0.01:
		if down_texture != null:
			sprite.texture = down_texture
		return

	if abs_x <= abs_y * 0.5:
		if faces_up and up_texture != null:
			sprite.texture = up_texture
			return
		if faces_down and down_texture != null:
			sprite.texture = down_texture
			return

	if abs_y <= abs_x * 0.5:
		if right_texture != null:
			sprite.texture = right_texture
			sprite.flip_h = faces_left
			return

	if faces_up and up_right_texture != null:
		sprite.texture = up_right_texture
		sprite.flip_h = faces_left
		return

	if faces_down and down_right_texture != null:
		sprite.texture = down_right_texture
		sprite.flip_h = faces_left
		return

	if right_texture != null:
		sprite.texture = right_texture
		sprite.flip_h = faces_left


# Ищет grid-manager мира, поднимаясь вверх по дереву сцены.
func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_creature") and current.has_method("world_to_anchor_tile"):
			return current

		current = current.get_parent()

	return null


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


# Закрепляет или снимает выбор существа по клику мыши.
func _on_hover_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton):
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	var stats_ui := get_tree().get_first_node_in_group("creature_stats_ui")

	if stats_ui != null and stats_ui.has_method("toggle_creature_selection"):
		stats_ui.toggle_creature_selection(self)
		get_viewport().set_input_as_handled()
