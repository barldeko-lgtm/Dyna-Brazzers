extends Node2D

# Ссылка на основной спрайт яйца.
@onready var body_sprite: Sprite2D = $BodySprite

# Таймер первой стадии яйца.
@onready var stage_1_timer: Timer = $Stage1Timer

# Таймер повторной проверки расширения яйца до 2x2.
@onready var expand_retry_timer: Timer = $ExpandRetryTimer

# Таймер вылупления после перехода во вторую стадию.
@onready var hatch_timer: Timer = $HatchTimer

# Стадии яйца: сначала вертикальное 1x2, потом блокирующее 2x2.
enum Stage {
	STAGE_1,
	STAGE_2
}

# Текстура первой стадии яйца.
@export var stage_1_texture: Texture2D

# Текстура второй стадии яйца.
@export var stage_2_texture: Texture2D

# Видовой идентификатор яйца.
@export var species_id := "stegosaurus"

# Сцена существа, которое должно вылупиться из яйца.
@export var hatch_creature_scene: PackedScene

# Длительность первой стадии яйца.
@export var stage_1_duration := 5.0

# Раз в сколько секунд яйцо повторно проверяет возможность расшириться до 2x2.
@export var expand_retry_interval := 1.0

# Длительность второй стадии до вылупления.
@export var stage_2_duration := 5.0

# Стартовое здоровье вылупившегося существа.
@export var hatch_health := 100.0

# Стартовая сытость вылупившегося существа.
@export var hatch_hunger := 50.0

# Текущая стадия яйца.
var current_stage: Stage = Stage.STAGE_1

# Ссылка на grid-manager мира.
var world_grid: Node = null

# Опорный тайл яйца.
var anchor_tile := Vector2i.ZERO

# Зарегистрировано ли яйцо как блокирующий объект во второй стадии.
var is_registered_as_blocker := false

# Вертикальный footprint первой стадии.
const STAGE_1_FOOTPRINT := Vector2i(1, 2)

# Блокирующий footprint второй стадии.
const STAGE_2_FOOTPRINT := Vector2i(2, 2)


# Инициализирует яйцо, подключает таймеры и синхронизирует его с миром.
func _ready() -> void:
	add_to_group("eggs")
	stage_1_timer.one_shot = true
	expand_retry_timer.one_shot = true
	hatch_timer.one_shot = true

	if not stage_1_timer.timeout.is_connected(_on_stage_1_timer_timeout):
		stage_1_timer.timeout.connect(_on_stage_1_timer_timeout)

	if not expand_retry_timer.timeout.is_connected(_on_expand_retry_timer_timeout):
		expand_retry_timer.timeout.connect(_on_expand_retry_timer_timeout)

	if not hatch_timer.timeout.is_connected(_on_hatch_timer_timeout):
		hatch_timer.timeout.connect(_on_hatch_timer_timeout)

	world_grid = find_world_grid()
	current_stage = Stage.STAGE_1
	apply_current_stage_visual()

	if world_grid != null:
		sync_anchor_with_world()

	stage_1_timer.start(stage_1_duration)


# Освобождает занятые тайлы, если яйцо было зарегистрировано как блокер.
func _exit_tree() -> void:
	if world_grid != null and is_registered_as_blocker:
		world_grid.unregister_blocker(self, STAGE_2_FOOTPRINT)
		is_registered_as_blocker = false


# Возвращает true, если яйцо уже живое и может быть съедено.
func can_be_eaten() -> bool:
	return current_stage == Stage.STAGE_2


# Съедает яйцо целиком без системы HP.
func consume() -> bool:
	if not can_be_eaten():
		return false

	queue_free()
	return true


# Обновляет визуал яйца под текущую стадию.
func apply_current_stage_visual() -> void:
	var target_texture: Texture2D = null
	var target_footprint := get_current_footprint()

	match current_stage:
		Stage.STAGE_1:
			target_texture = stage_1_texture
		Stage.STAGE_2:
			target_texture = stage_2_texture

	body_sprite.texture = target_texture
	body_sprite.scale = calculate_sprite_scale(target_texture, target_footprint)


# Считает масштаб спрайта так, чтобы он точно занимал нужный footprint без ручных хардкодов.
func calculate_sprite_scale(texture: Texture2D, footprint_size: Vector2i) -> Vector2:
	if texture == null:
		return Vector2.ONE

	var texture_size := texture.get_size()

	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ONE

	var tile_pixel_size := get_tile_pixel_size()
	var target_pixel_size := Vector2(
		float(footprint_size.x * tile_pixel_size.x),
		float(footprint_size.y * tile_pixel_size.y)
	)

	return Vector2(
		target_pixel_size.x / texture_size.x,
		target_pixel_size.y / texture_size.y
	)


# Возвращает размер тайла мира в пикселях; если мир ещё не найден, используем дефолт Dyna.
func get_tile_pixel_size() -> Vector2i:
	if world_grid != null:
		var grid_tile_size = world_grid.get("tile_size")

		if grid_tile_size is Vector2i:
			return grid_tile_size

	return Vector2i(128, 128)


# Синхронизирует опорный тайл яйца с текущей мировой позицией.
func sync_anchor_with_world() -> void:
	if world_grid == null:
		world_grid = find_world_grid()

	if world_grid == null:
		return

	anchor_tile = world_grid.world_to_anchor_tile(global_position, STAGE_1_FOOTPRINT)
	global_position = world_grid.anchor_to_world_position(anchor_tile, get_current_footprint())


# Возвращает текущий footprint яйца по его стадии.
func get_current_footprint() -> Vector2i:
	if current_stage == Stage.STAGE_2:
		return STAGE_2_FOOTPRINT

	return STAGE_1_FOOTPRINT


# После первой стадии пытается расширить яйцо до 2x2.
func _on_stage_1_timer_timeout() -> void:
	try_enter_stage_2()


# Повторно пытается расширить яйцо, если в прошлый раз не удалось.
func _on_expand_retry_timer_timeout() -> void:
	try_enter_stage_2()


# Пытается перевести яйцо во вторую стадию и сделать его блокирующим.
func try_enter_stage_2() -> void:
	if world_grid == null:
		return

	if world_grid.register_blocker(self, anchor_tile, STAGE_2_FOOTPRINT):
		is_registered_as_blocker = true
		current_stage = Stage.STAGE_2
		apply_current_stage_visual()
		hatch_timer.start(stage_2_duration)
		global_position = world_grid.anchor_to_world_position(anchor_tile, STAGE_2_FOOTPRINT)
		return

	expand_retry_timer.start(expand_retry_interval)


# По окончании второй стадии освобождает место и создаёт новое существо.
func _on_hatch_timer_timeout() -> void:
	if world_grid == null or hatch_creature_scene == null:
		queue_free()
		return

	if is_registered_as_blocker:
		world_grid.unregister_blocker(self, STAGE_2_FOOTPRINT)
		is_registered_as_blocker = false

	spawn_hatched_creature()
	queue_free()


# Создаёт существо из яйца в контейнере существ мира.
func spawn_hatched_creature() -> void:
	var creatures_container := find_named_container("Creatures")

	if creatures_container == null:
		creatures_container = get_parent() as Node2D

	if creatures_container == null:
		return

	var new_creature := hatch_creature_scene.instantiate() as Node2D

	if new_creature == null:
		return

	new_creature.set("health", hatch_health)
	new_creature.set("hunger", hatch_hunger)
	new_creature.set("age", 0.0)

	var spawn_world_position: Vector2 = world_grid.anchor_to_world_position(anchor_tile, STAGE_2_FOOTPRINT)
	new_creature.position = creatures_container.to_local(spawn_world_position)
	creatures_container.add_child(new_creature)


# Ищет grid-manager мира, поднимаясь вверх по дереву сцены.
func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_blocker") and current.has_method("world_to_anchor_tile"):
			return current

		current = current.get_parent()

	return null


# Ищет ближайший контейнер с указанным именем, поднимаясь вверх по дереву.
func find_named_container(target_name: String) -> Node2D:
	var current: Node = self

	while current != null:
		var candidate := current.get_node_or_null(target_name) as Node2D

		if candidate != null:
			return candidate

		current = current.get_parent()

	return null
