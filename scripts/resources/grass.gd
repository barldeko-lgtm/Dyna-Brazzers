extends Node2D

const CREATURE_GRAZING_LOGIC = preload(
	"res://scripts/creatures/behaviors/creature_grazing_logic.gd"
)

# Grass growth and spread.
@onready var body_sprite: Sprite2D = $BodySprite

@onready var growth_timer: Timer = $GrowthTimer

@onready var spread_timer: Timer = $SpreadTimer

# Growth stages.
enum Stage {
	STAGE_1,
	STAGE_2,
	STAGE_3,
	STAGE_4
}

# Timing and visuals.
@export var stage_1_texture: Texture2D

@export var stage_2_texture: Texture2D

@export var stage_3_texture: Texture2D

@export var stage_4_texture: Texture2D

@export var growth_time := 8.0

@export var spread_delay := 45.0

@export var start_stage: Stage = Stage.STAGE_1

var current_stage: Stage = Stage.STAGE_1

# Mature grass should try to spread only once.
# Some nature powers can reset this to let an area recover again.
var has_tried_to_spread := false

var world_grid: Node = null

var tile_position := Vector2i.ZERO

var render_offset := Vector2.ZERO

var last_consumed_food_value := 0

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
	if world_grid != null and is_instance_valid(world_grid):
		var was_registered: bool = world_grid.get_grass_at_tile(tile_position) == self
		world_grid.unregister_grass(self, tile_position)

		if was_registered:
			_notify_grazing_cache_changed(tile_position)


# Consumption.
func can_be_eaten() -> bool:
	return current_stage >= Stage.STAGE_2


func get_food_value() -> int:
	match current_stage:
		Stage.STAGE_2:
			return 5
		Stage.STAGE_3:
			return 7
		Stage.STAGE_4:
			return 9
		_:
			return 0


func get_last_consumed_food_value() -> int:
	return last_consumed_food_value


func consume() -> bool:
	if not can_be_eaten():
		return false

	last_consumed_food_value = get_food_value()
	set_stage(Stage.STAGE_1)
	return true


func set_stage(new_stage: Stage) -> void:
	var stage_changed: bool = current_stage != new_stage
	current_stage = new_stage
	apply_current_stage_visual()
	update_timers()

	if stage_changed:
		_notify_grazing_cache_changed(tile_position)


# Rain.
func apply_rain() -> bool:
	if current_stage != Stage.STAGE_4:
		PerformanceStats.add_counter("rain_grass_grown")
		set_stage(get_next_stage())
		return true

	PerformanceStats.add_counter("rain_grass_spread_requests")
	return _try_spread_once()


# Sun.
func apply_sun() -> bool:
	if current_stage == Stage.STAGE_1:
		return false

	PerformanceStats.add_counter("sun_grass_reverted")
	set_stage(get_sun_reduced_stage())
	return true


func reset_spread_attempt() -> bool:
	var changed := has_tried_to_spread
	has_tried_to_spread = false

	if current_stage == Stage.STAGE_4:
		update_timers()
		return true

	return changed


# Visuals.
func apply_current_stage_visual() -> void:
	match current_stage:
		Stage.STAGE_1:
			body_sprite.texture = stage_1_texture
		Stage.STAGE_2:
			body_sprite.texture = stage_2_texture
		Stage.STAGE_3:
			body_sprite.texture = stage_3_texture
		Stage.STAGE_4:
			body_sprite.texture = stage_4_texture


func get_next_stage() -> Stage:
	match current_stage:
		Stage.STAGE_1:
			return Stage.STAGE_2
		Stage.STAGE_2:
			return Stage.STAGE_3
		Stage.STAGE_3:
			return Stage.STAGE_4
		_:
			return Stage.STAGE_4


func get_sun_reduced_stage() -> Stage:
	match current_stage:
		Stage.STAGE_4:
			return Stage.STAGE_2
		Stage.STAGE_3:
			return Stage.STAGE_1
		Stage.STAGE_2:
			return Stage.STAGE_1
		_:
			return Stage.STAGE_1


# Stage timers.
func update_timers() -> void:
	if current_stage != Stage.STAGE_4:
		growth_timer.start(growth_time)
		spread_timer.stop()
	else:
		growth_timer.stop()

		if has_tried_to_spread:
			spread_timer.stop()
		else:
			spread_timer.start(spread_delay)


func _on_growth_timer_timeout() -> void:
	PerformanceStats.add_counter("grass_growth_done")
	set_stage(get_next_stage())


func _on_spread_timer_timeout() -> void:
	PerformanceStats.add_counter("grass_spread_timer_ticks")
	_try_spread_once()


func _try_spread_once() -> bool:
	if current_stage != Stage.STAGE_4:
		return false

	if has_tried_to_spread:
		spread_timer.stop()
		return false

	has_tried_to_spread = true
	PerformanceStats.add_counter("grass_spread_events")
	spread_to_cardinal_tiles()
	spread_timer.stop()
	return true


# Spread.
func spread_to_cardinal_tiles() -> void:
	PerformanceStats.add_counter("grass_neighbor_checks", CARDINAL_TILE_OFFSETS.size())

	for offset in CARDINAL_TILE_OFFSETS:
		try_spawn_grass(tile_position + offset)


func try_spawn_grass(target_tile: Vector2i) -> void:
	PerformanceStats.add_counter("grass_spawn_checks")

	if world_grid == null:
		return

	if world_grid.has_method("can_host_grass"):
		if not world_grid.can_host_grass(target_tile):
			return
	elif not world_grid.is_tile_walkable(target_tile):
		return

	if world_grid.has_grass_at_tile(target_tile):
		return

	var grass_scene := load(scene_file_path) as PackedScene

	if grass_scene == null:
		return

	var new_grass := grass_scene.instantiate() as Node2D

	if new_grass == null:
		return

	var grass_parent := get_parent() as Node2D

	if grass_parent == null:
		return

	# Set the future local position before add_child().
	# _ready() runs during add_child(), so the grass must already point at the
	# target ground tile instead of briefly appearing at world tile (0, 0).
	var target_world_position: Vector2 = world_grid.grass_tile_to_world_position(target_tile)
	new_grass.position = grass_parent.to_local(target_world_position)
	grass_parent.add_child(new_grass)
	PerformanceStats.add_counter("grass_spawned")


# Grid sync.
func sync_tile_position_with_world() -> bool:
	if world_grid == null:
		world_grid = find_world_grid()

	if world_grid == null:
		return false

	var previous_tile: Vector2i = tile_position
	var was_registered: bool = world_grid.get_grass_at_tile(previous_tile) == self
	world_grid.unregister_grass(self, previous_tile)

	if was_registered:
		_notify_grazing_cache_changed(previous_tile)

	var initial_position := global_position
	tile_position = world_grid.world_to_map_tile(initial_position)

	if world_grid.has_method("can_host_grass") and not world_grid.can_host_grass(tile_position):
		return false

	render_offset = Vector2.ZERO
	world_grid.register_grass(self, tile_position)
	_notify_grazing_cache_changed(tile_position)
	global_position = world_grid.grass_tile_to_world_position(tile_position)
	return true


func _notify_grazing_cache_changed(changed_tile: Vector2i) -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		return

	CREATURE_GRAZING_LOGIC.notify_grass_changed(world_grid, changed_tile)


# Lookup helper.
func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_grass") and current.has_method("world_to_map_tile"):
			return current

		current = current.get_parent()

	return null
