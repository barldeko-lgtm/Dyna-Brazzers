extends Node2D

# Egg lifecycle and hatch spawn.
@onready var body_sprite: Sprite2D = $BodySprite

@onready var stage_1_timer: Timer = $Stage1Timer

@onready var expand_retry_timer: Timer = $ExpandRetryTimer

@onready var hatch_timer: Timer = $HatchTimer

# Egg stages.
enum Stage {
	STAGE_1,
	STAGE_2
}

# Stage visuals and hatch tuning.
@export var stage_1_texture: Texture2D

@export var stage_2_texture: Texture2D

@export var species_id := "stegosaurus"

@export var hatch_species_data: CreatureSpeciesData

@export var hatch_creature_scene: PackedScene

@export var stage_1_duration := 5.0

@export var expand_retry_interval := 1.0

@export var stage_2_duration := 5.0

@export var hatch_health := 100.0

@export var hatch_hunger := 50.0

var current_stage: Stage = Stage.STAGE_1

var world_grid: Node = null

var anchor_tile := Vector2i.ZERO

var is_registered_as_blocker := false

const STAGE_1_FOOTPRINT := Vector2i(1, 2)

const STAGE_2_FOOTPRINT := Vector2i(2, 2)


# Setup.
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
		if not sync_anchor_with_world():
			call_deferred("queue_free")
			return

	stage_1_timer.start(stage_1_duration)


func _exit_tree() -> void:
	if world_grid != null and is_registered_as_blocker:
		world_grid.unregister_blocker(self, STAGE_2_FOOTPRINT)
		is_registered_as_blocker = false


func can_be_eaten() -> bool:
	return current_stage == Stage.STAGE_2


func consume() -> bool:
	if not can_be_eaten():
		return false

	queue_free()
	return true


# Visuals and footprint scale.
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


func get_tile_pixel_size() -> Vector2i:
	if world_grid != null:
		var grid_tile_size = world_grid.get("tile_size")

		if grid_tile_size is Vector2i:
			return grid_tile_size

	return Vector2i(128, 128)


func sync_anchor_with_world() -> bool:
	if world_grid == null:
		world_grid = find_world_grid()

	if world_grid == null:
		return false

	anchor_tile = world_grid.world_to_anchor_tile(global_position, STAGE_1_FOOTPRINT)

	if not can_place_stage_1_anchor(anchor_tile):
		return false

	global_position = world_grid.anchor_to_world_position(anchor_tile, get_current_footprint())
	return true


func can_place_stage_1_anchor(candidate_anchor: Vector2i) -> bool:
	if world_grid == null:
		return false

	if not world_grid.has_method("get_footprint_tiles") or not world_grid.has_method("is_tile_walkable"):
		return false

	for tile in world_grid.get_footprint_tiles(candidate_anchor, STAGE_1_FOOTPRINT):
		if not world_grid.is_tile_walkable(tile):
			return false

	return true


func get_current_footprint() -> Vector2i:
	if current_stage == Stage.STAGE_2:
		return STAGE_2_FOOTPRINT

	return STAGE_1_FOOTPRINT


func _on_stage_1_timer_timeout() -> void:
	try_enter_stage_2()


func _on_expand_retry_timer_timeout() -> void:
	try_enter_stage_2()


# Stage transition.
func try_enter_stage_2() -> void:
	if world_grid == null:
		return

	# Stage 1 is one tile wide and stage 2 is two tiles wide. Try expanding
	# to the right first; if that side is blocked, keep the original stage-1
	# cells and expand to the left instead.
	var candidate_anchors: Array[Vector2i] = [
		anchor_tile,
		anchor_tile + Vector2i.LEFT
	]

	for candidate_anchor in candidate_anchors:
		if not world_grid.register_blocker(self, candidate_anchor, STAGE_2_FOOTPRINT):
			continue

		anchor_tile = candidate_anchor
		is_registered_as_blocker = true
		current_stage = Stage.STAGE_2
		apply_current_stage_visual()
		hatch_timer.start(stage_2_duration)
		global_position = world_grid.anchor_to_world_position(anchor_tile, STAGE_2_FOOTPRINT)
		return

	expand_retry_timer.start(expand_retry_interval)


# Hatch flow.
func _on_hatch_timer_timeout() -> void:
	if world_grid == null or hatch_creature_scene == null:
		queue_free()
		return

	if is_registered_as_blocker:
		world_grid.unregister_blocker(self, STAGE_2_FOOTPRINT)
		is_registered_as_blocker = false

	spawn_hatched_creature()
	queue_free()


func spawn_hatched_creature() -> void:
	var creatures_container := find_named_container("Creatures")

	if creatures_container == null:
		creatures_container = get_parent() as Node2D

	if creatures_container == null:
		return

	var new_creature := hatch_creature_scene.instantiate() as Node2D

	if new_creature == null:
		return

	var spawn_health: float = hatch_health
	var spawn_hunger: float = hatch_hunger

	if hatch_species_data != null:
		new_creature.set("species_data", hatch_species_data)
		spawn_health = hatch_species_data.max_health
		spawn_hunger = hatch_species_data.max_hunger

	# Every creature born from an egg starts fully healthy and fully fed.
	# The exported fallback values remain available for an incomplete future egg
	# that has no species data assigned yet.
	new_creature.set("health", spawn_health)
	new_creature.set("hunger", spawn_hunger)
	new_creature.set("age", 0.0)

	var spawn_world_position: Vector2 = world_grid.anchor_to_world_position(anchor_tile, STAGE_2_FOOTPRINT)
	new_creature.position = creatures_container.to_local(spawn_world_position)
	creatures_container.add_child(new_creature)


# Lookup helpers.
func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_blocker") and current.has_method("world_to_anchor_tile"):
			return current

		current = current.get_parent()

	return null


func find_named_container(target_name: String) -> Node2D:
	var current: Node = self

	while current != null:
		var candidate := current.get_node_or_null(target_name) as Node2D

		if candidate != null:
			return candidate

		current = current.get_parent()

	return null
