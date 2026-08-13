extends Node2D
class_name Egg

signal hatched(creature: Node2D)

const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const HATCH_SOUND := preload("res://assets/audio/sfx/egg_hatch.mp3")
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

# Shared incubation timing for every egg, regardless of species or faction.
const STAGE_1_DURATION := 5.0
const EXPAND_RETRY_INTERVAL := 1.0
const STAGE_2_DURATION := 10.0

var current_stage: Stage = Stage.STAGE_1

var world_grid: Node = null

var anchor_tile := Vector2i.ZERO

var is_registered_as_blocker := false

var awaiting_base_landing := false

var consumption_claimant: Node = null

var hatch_sound_started := false

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

	if awaiting_base_landing:
		body_sprite.visible = false
		return

	stage_1_timer.start(STAGE_1_DURATION)


func _exit_tree() -> void:
	if world_grid != null and is_registered_as_blocker:
		world_grid.unregister_blocker(self, STAGE_2_FOOTPRINT)
		is_registered_as_blocker = false


func _process(_delta: float) -> void:
	_try_start_hatch_sound()


func prepare_base_launch_wait() -> void:
	# Called before add_child(). _ready() can therefore avoid starting the
	# normal stage-one timer even if the launch effect is created immediately
	# after the egg enters the tree.
	awaiting_base_landing = true


func has_landed() -> bool:
	return not awaiting_base_landing


func complete_base_landing() -> void:
	if not awaiting_base_landing:
		return

	awaiting_base_landing = false

	# If a visual-effect setup failed before _ready(), the normal _ready() path
	# will see the cleared flag and start incubation itself.
	if not is_node_ready():
		return

	if body_sprite != null:
		body_sprite.visible = true
	apply_current_stage_visual()
	stage_1_timer.start(STAGE_1_DURATION)


func can_be_eaten() -> bool:
	return has_landed() and current_stage == Stage.STAGE_2


func can_be_tracked_by_egg_eater() -> bool:
	return has_landed() and not is_queued_for_deletion()


func can_be_claimed_for_consumption(eater: Node) -> bool:
	if not can_be_eaten() or eater == null or not is_instance_valid(eater):
		return false

	if consumption_claimant != null and not is_instance_valid(consumption_claimant):
		consumption_claimant = null
		hatch_timer.paused = false

	return consumption_claimant == null or consumption_claimant == eater


func try_claim_for_consumption(eater: Node) -> bool:
	if not can_be_claimed_for_consumption(eater):
		return false

	consumption_claimant = eater
	hatch_timer.paused = true
	return true


func is_consumption_claimed_by(eater: Node) -> bool:
	return (
		eater != null
		and is_instance_valid(eater)
		and consumption_claimant == eater
	)


func cancel_consumption_claim(eater: Node) -> void:
	if not is_consumption_claimed_by(eater):
		return

	consumption_claimant = null
	hatch_timer.paused = false


func finish_consumption(eater: Node) -> bool:
	if not is_consumption_claimed_by(eater) or not can_be_eaten():
		return false

	consumption_claimant = null
	hatch_timer.paused = false
	queue_free()
	return true


func destroy_by_earthquake() -> bool:
	if not has_landed() or is_queued_for_deletion():
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


func get_world_visual_rect() -> Rect2:
	if body_sprite == null:
		return Rect2(global_position - Vector2(48.0, 48.0), Vector2(96.0, 96.0))

	var local_rect := body_sprite.get_rect()
	var corners: Array[Vector2] = [
		body_sprite.to_global(local_rect.position),
		body_sprite.to_global(Vector2(local_rect.end.x, local_rect.position.y)),
		body_sprite.to_global(local_rect.end),
		body_sprite.to_global(Vector2(local_rect.position.x, local_rect.end.y)),
	]
	var minimum := corners[0]
	var maximum := corners[0]
	for corner: Vector2 in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


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
		_start_hatch_timer(STAGE_2_DURATION)
		global_position = world_grid.anchor_to_world_position(anchor_tile, STAGE_2_FOOTPRINT)
		return

	expand_retry_timer.start(EXPAND_RETRY_INTERVAL)


# Hatch flow.
func _on_hatch_timer_timeout() -> void:
	if world_grid == null or hatch_creature_scene == null:
		queue_free()
		return

	if spawn_hatched_creature():
		queue_free()
		return

	# Keep the stage-2 egg and try again later if the world is completely full.
	if not is_queued_for_deletion():
		_start_hatch_timer(EXPAND_RETRY_INTERVAL)


func _start_hatch_timer(duration: float) -> void:
	hatch_sound_started = false
	hatch_timer.start(duration)


func _try_start_hatch_sound() -> void:
	if (
		hatch_sound_started
		or current_stage != Stage.STAGE_2
		or awaiting_base_landing
		or hatch_timer == null
		or hatch_timer.is_stopped()
		or hatch_timer.paused
		or Engine.time_scale <= 0.0
	):
		return

	var half_sound_duration := HATCH_SOUND.get_length() * 0.5
	var simulation_lead_time := half_sound_duration * Engine.time_scale
	if hatch_timer.time_left > simulation_lead_time:
		return

	hatch_sound_started = true
	AudioManager.play_world_sfx(HATCH_SOUND, global_position)


func spawn_hatched_creature() -> bool:
	var creatures_container := find_named_container("Creatures")

	if creatures_container == null:
		creatures_container = get_parent() as Node2D

	if creatures_container == null:
		return false

	var new_creature := hatch_creature_scene.instantiate() as Node2D

	if new_creature == null:
		return false

	var spawn_species := hatch_species_data

	if spawn_species == null:
		spawn_species = new_creature.get("species_data") as CreatureSpeciesData

	if spawn_species == null:
		new_creature.free()
		return false

	new_creature.set("species_data", spawn_species)

	# Every creature born from an egg starts fully healthy and fully fed.
	var spawn_health: float = spawn_species.max_health
	var spawn_hunger: float = spawn_species.max_hunger
	new_creature.set("health", spawn_health)
	new_creature.set("hunger", spawn_hunger)
	new_creature.set("age", 0.0)

	var spawn_footprint := STAGE_2_FOOTPRINT
	var raw_footprint: Variant = new_creature.get("footprint_size")

	if raw_footprint is Vector2i:
		spawn_footprint = raw_footprint

	# The egg's own blocker is ignored during the preflight check. The blocker is
	# released only after a valid creature footprint has been found.
	var spawn_anchor: Vector2i = world_grid.find_nearest_valid_anchor(
		anchor_tile,
		spawn_footprint,
		self,
		12
	)

	if not world_grid.can_place_footprint(spawn_anchor, spawn_footprint, self):
		new_creature.free()
		return false

	var blocker_was_registered := is_registered_as_blocker

	if blocker_was_registered:
		world_grid.unregister_blocker(self, STAGE_2_FOOTPRINT)
		is_registered_as_blocker = false

	var spawn_world_position: Vector2 = world_grid.anchor_to_world_position(
		spawn_anchor,
		spawn_footprint
	)
	new_creature.position = creatures_container.to_local(spawn_world_position)
	CREATURE_FACTION.set_id(new_creature, CREATURE_FACTION.get_id(self))
	creatures_container.add_child(new_creature)

	var creature_registered := false

	if world_grid.has_method("is_creature_registered"):
		creature_registered = bool(world_grid.call("is_creature_registered", new_creature))

	if creature_registered:
		hatched.emit(new_creature)
		return true

	if is_instance_valid(new_creature):
		new_creature.queue_free()

	if blocker_was_registered:
		is_registered_as_blocker = world_grid.register_blocker(
			self,
			anchor_tile,
			STAGE_2_FOOTPRINT
		)

		if not is_registered_as_blocker:
			push_error("Egg: failed to restore its blocker after a hatch registration failure.")
			queue_free()

	return false


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
