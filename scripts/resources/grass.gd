extends Node2D

# Grass growth and spread.
@onready var body_sprite: Sprite2D = $BodySprite

@onready var growth_timer: Timer = $GrowthTimer

@onready var spread_timer: Timer = $SpreadTimer

# Growth stages.
enum Stage {
	STAGE_1,
	STAGE_2
}

# Timing and visuals.
@export var stage_1_texture: Texture2D

@export var stage_2_texture: Texture2D

@export var growth_time := 8.0

@export var spread_delay := 10.0

@export var start_stage: Stage = Stage.STAGE_1

var current_stage: Stage = Stage.STAGE_1

var world_grid: Node = null

var tile_position := Vector2i.ZERO

var render_offset := Vector2.ZERO

const CARDINAL_TILE_OFFSETS := [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.UP,
	Vector2i.DOWN
]


# Setup.
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
		if not sync_tile_position_with_world():
			call_deferred("queue_free")


func _exit_tree() -> void:
	if world_grid != null:
		world_grid.unregister_grass(self, tile_position)


# Consumption.
func can_be_eaten() -> bool:
	return current_stage == Stage.STAGE_2


func consume() -> bool:
	if not can_be_eaten():
		return false

	set_stage(Stage.STAGE_1)
	return true


func set_stage(new_stage: Stage) -> void:
	current_stage = new_stage
	apply_current_stage_visual()
	update_timers()


# Visuals.
func apply_current_stage_visual() -> void:
	match current_stage:
		Stage.STAGE_1:
			body_sprite.texture = stage_1_texture
		Stage.STAGE_2:
			body_sprite.texture = stage_2_texture


# Stage timers.
func update_timers() -> void:
	if current_stage == Stage.STAGE_1:
		growth_timer.start(growth_time)
		spread_timer.stop()
	else:
		growth_timer.stop()
		spread_timer.start(spread_delay)


func _on_growth_timer_timeout() -> void:
	set_stage(Stage.STAGE_2)


func _on_spread_timer_timeout() -> void:
	if current_stage != Stage.STAGE_2:
		return

	spread_to_cardinal_tiles()
	spread_timer.start(spread_delay)


# Spread.
func spread_to_cardinal_tiles() -> void:
	for offset in CARDINAL_TILE_OFFSETS:
		try_spawn_grass(tile_position + offset)


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


# Grid sync.
func sync_tile_position_with_world() -> bool:
	if world_grid == null:
		world_grid = find_world_grid()

	if world_grid == null:
		return false

	world_grid.unregister_grass(self, tile_position)
	var initial_position := global_position
	tile_position = world_grid.world_to_map_tile(initial_position)

	if world_grid.has_method("can_host_grass") and not world_grid.can_host_grass(tile_position):
		return false

	render_offset = Vector2.ZERO
	world_grid.register_grass(self, tile_position)
	global_position = world_grid.grass_tile_to_world_position(tile_position)
	return true


# Lookup helper.
func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_grass") and current.has_method("world_to_map_tile"):
			return current

		current = current.get_parent()

	return null
