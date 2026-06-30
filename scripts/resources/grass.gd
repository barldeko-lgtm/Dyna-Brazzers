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

# Стартовая стадия травы при запуске сцены.
@export var start_stage: Stage = Stage.STAGE_1

# Текущая рабочая стадия травы.
var current_stage: Stage = Stage.STAGE_1

# Ссылка на grid-manager мира.
var world_grid: Node = null

# Тайл, на котором стоит этот куст травы.
var tile_position := Vector2i.ZERO

# Исходный визуальный сдвиг куста относительно математического центра тайла.
var render_offset := Vector2.ZERO

# Сдвиги для размножения по 4 сторонам.
const CARDINAL_TILE_OFFSETS := [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.UP,
	Vector2i.DOWN
]


# Инициализирует траву, подключает таймеры и регистрирует куст на сетке.
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
	world_grid = find_world_grid()

	if world_grid != null:
		sync_tile_position_with_world()


# Удаляет куст из реестра мира при освобождении узла.
func _exit_tree() -> void:
	if world_grid != null:
		world_grid.unregister_grass(self, tile_position)


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

	spread_to_cardinal_tiles()
	spread_timer.start(spread_delay)


# Пытается создать новую траву сверху, снизу, слева и справа от текущего тайла.
func spread_to_cardinal_tiles() -> void:
	for offset in CARDINAL_TILE_OFFSETS:
		try_spawn_grass(tile_position + offset)


# Создаёт новую траву на указанном тайле, если он свободен.
func try_spawn_grass(target_tile: Vector2i) -> void:
	if world_grid == null:
		return

	if not world_grid.is_tile_walkable(target_tile):
		return

	if world_grid.has_grass_at_tile(target_tile):
		return

	var grass_scene := load(scene_file_path) as PackedScene

	if grass_scene == null:
		return

	var new_grass := grass_scene.instantiate() as Node2D

	if new_grass == null:
		return

	get_parent().add_child(new_grass)
	new_grass.global_position = world_grid.grass_tile_to_world_position(target_tile)

	if new_grass.has_method("sync_tile_position_with_world"):
		new_grass.sync_tile_position_with_world()


# Ищет grid-manager мира, поднимаясь вверх по дереву сцены.
func sync_tile_position_with_world() -> void:
	if world_grid == null:
		world_grid = find_world_grid()

	if world_grid == null:
		return

	world_grid.unregister_grass(self, tile_position)
	var initial_position := global_position
	tile_position = world_grid.world_to_map_tile(initial_position)
	render_offset = initial_position - world_grid.map_to_world_center(tile_position)
	world_grid.register_grass(self, tile_position)
	global_position = world_grid.grass_tile_to_world_position(tile_position)


# Ищет grid-manager мира, поднимаясь вверх по дереву сцены.
func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_grass") and current.has_method("world_to_map_tile"):
			return current

		current = current.get_parent()

	return null
