extends Node2D

# Ссылка на спрайт травы для смены визуальной стадии.
@onready var body_sprite: Sprite2D = $BodySprite

# Ссылка на таймер роста травы.
@onready var growth_timer: Timer = $GrowthTimer

# Ссылка на таймер размножения травы.
@onready var spread_timer: Timer = $SpreadTimer

# Две простые стадии травы: маленькая и выросшая.
enum Stage {
	STAGE_1,
	STAGE_2
}

# Текстура маленькой травы.
@export var stage_1_texture: Texture2D

# Текстура выросшей травы.
@export var stage_2_texture: Texture2D

# Время, за которое трава дорастает из 1 стадии во 2.
@export var growth_time := 8.0

# Время ожидания перед размножением, пока трава стоит во 2 стадии.
@export var spread_delay := 10.0

# Расстояние размножения в пикселях. По умолчанию равно одному тайлу.
@export var spread_distance := 128.0

# Текущая стадия травы при старте сцены.
@export var start_stage: Stage = Stage.STAGE_1

# Текущая рабочая стадия травы.
var current_stage: Stage = Stage.STAGE_1


# Инициализирует траву, подключает таймеры и ставит нужную стартовую стадию.
func _ready() -> void:
	add_to_group("grass")
	growth_timer.one_shot = true
	spread_timer.one_shot = true

	if not growth_timer.timeout.is_connected(_on_growth_timer_timeout):
		growth_timer.timeout.connect(_on_growth_timer_timeout)

	if not spread_timer.timeout.is_connected(_on_spread_timer_timeout):
		spread_timer.timeout.connect(_on_spread_timer_timeout)

	current_stage = start_stage
	apply_current_stage_visual()
	update_timers()


# Возвращает true, если траву уже можно есть.
func can_be_eaten() -> bool:
	return current_stage == Stage.STAGE_2


# Съедает траву: откатывает её в первую стадию и запускает новый рост.
func consume() -> bool:
	if not can_be_eaten():
		return false

	set_stage(Stage.STAGE_1)
	return true


# Принудительно задаёт стадию травы и сразу обновляет визуал и таймеры.
func set_stage(new_stage: Stage) -> void:
	current_stage = new_stage
	apply_current_stage_visual()
	update_timers()


# Обновляет спрайт травы в зависимости от текущей стадии.
func apply_current_stage_visual() -> void:
	match current_stage:
		Stage.STAGE_1:
			body_sprite.texture = stage_1_texture
		Stage.STAGE_2:
			body_sprite.texture = stage_2_texture


# Обновляет таймеры роста и размножения в зависимости от текущей стадии.
func update_timers() -> void:
	if current_stage == Stage.STAGE_1:
		growth_timer.start(growth_time)
		spread_timer.stop()
	else:
		growth_timer.stop()
		spread_timer.start(spread_delay)


# Переводит траву во вторую стадию, когда заканчивается рост.
func _on_growth_timer_timeout() -> void:
	set_stage(Stage.STAGE_2)


# Запускает размножение травы по четырём сторонам, если её никто не съел.
func _on_spread_timer_timeout() -> void:
	if current_stage != Stage.STAGE_2:
		return

	spread_to_cardinal_directions()
	spread_timer.start(spread_delay)


# Пытается создать новую траву сверху, снизу, слева и справа от текущей.
func spread_to_cardinal_directions() -> void:
	var offsets := [
		Vector2.RIGHT * spread_distance,
		Vector2.LEFT * spread_distance,
		Vector2.UP * spread_distance,
		Vector2.DOWN * spread_distance
	]

	for offset in offsets:
		try_spawn_grass(global_position + offset)


# Создаёт новую траву в указанной точке, если там ещё нет другой травы.
func try_spawn_grass(target_global_position: Vector2) -> void:
	var grass_parent := get_parent()

	if grass_parent == null:
		return

	if has_grass_at_position(grass_parent, target_global_position):
		return

	var grass_scene := load(scene_file_path) as PackedScene

	if grass_scene == null:
		return

	var new_grass := grass_scene.instantiate() as Node2D

	if new_grass == null:
		return

	grass_parent.add_child(new_grass)
	new_grass.global_position = target_global_position


# Проверяет, есть ли уже трава в нужной точке, чтобы не плодить дубликаты.
func has_grass_at_position(grass_parent: Node, target_global_position: Vector2) -> bool:
	for child in grass_parent.get_children():
		if child == self:
			continue

		if not (child is Node2D):
			continue

		if child.scene_file_path != scene_file_path:
			continue

		if child.global_position.distance_to(target_global_position) < 1.0:
			return true

	return false
