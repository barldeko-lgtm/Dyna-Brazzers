extends CharacterBody2D

# Core creature FSM.
@onready var sprite: Sprite2D = $BodySprite

@onready var eating_timer: Timer = $EatingTimer

@onready var egg_laying_timer: Timer = $EggLayingTimer

@onready var hover_area: Area2D = $HoverArea

# High-level behaviour states.
enum State {
	IDLE,
	WALK,
	SEEK_FOOD,
	EATING,
	LAYING_EGG,
	DEAD
}

# Wander and grazing tuning.
@export var idle_time_min := 1.0

@export var idle_time_max := 3.0

@export var walk_time_min := 2.0

@export var walk_time_max := 5.0

@export var footprint_size := Vector2i(2, 2)

@export var food_recheck_interval := 2.0

@export var nearby_grazing_recheck_radius := 6

@export var min_grass_to_eat := 2

@export var grazing_grass_weight := 10.0

@export var grazing_distance_penalty := 2.5

@export var retarget_distance_advantage := 2

# Static species config.
@export var species_data: CreatureSpeciesData

var eating_anchor_tile := Vector2i.ZERO

var species_id := "stegosaurus"

var species_name := "Стегозавр"

var creature_name := "Стегозавр"

var down_texture: Texture2D
var up_texture: Texture2D
var right_texture: Texture2D
var up_right_texture: Texture2D
var down_right_texture: Texture2D

# Runtime stats copied from species_data.
var speed := 140.0
var max_health := 100.0
var health := -1.0
var starvation_health_decay_rate := 2.0
var well_fed_health_regen_rate := 1.0
var satiety_heal_threshold := 70.0
var attack := 10.0
var defense := 5.0

var age := 0.0

# Aging tuning.
@export var max_age := 10.0

@export var age_tick_interval := 30.0

var max_hunger := 100.0
var hunger := -1.0
var hunger_decay_rate := 10.0
var hunger_search_threshold := 70.0
var hunger_restore_amount := 10.0
var eating_duration := 3.0

var egg_scene: PackedScene
var egg_stage_1_texture: Texture2D
var egg_stage_2_texture: Texture2D
var egg_laying_duration := 5.0
var egg_stage_1_duration := 5.0
var egg_expand_retry_interval := 1.0
var egg_stage_2_duration := 5.0
var reproduction_min_health := 30.0
var reproduction_min_hunger := 70.0
var reproduction_min_age := 3.0
var reproduction_cooldown := 20.0
var reproduction_hunger_cost := 20.0
var hatchling_health := 100.0
var hatchling_hunger := 50.0

# Runtime state.
var state: State = State.WALK

var age_tick_elapsed := 0.0

var world_grid: Node = null

var anchor_tile := Vector2i.ZERO

var render_offset := Vector2.ZERO

var direction := Vector2.ZERO

var state_timer := 0.0

var food_recheck_timer := 0.0

var current_path: Array[Vector2i] = []

var grazing_target_anchor := Vector2i.ZERO

var has_grazing_target := false

var pending_anchor_tile := Vector2i.ZERO

var movement_target_position := Vector2.ZERO

var is_moving := false

var reproduction_cooldown_remaining := 0.0

var pending_egg_anchor := Vector2i.ZERO

const EGG_STAGE_1_FOOTPRINT := Vector2i(1, 2)


# Pull static config into runtime fields.
func apply_species_data() -> void:
	if species_data == null:
		return

	species_id = species_data.species_id
	species_name = species_data.species_name
	creature_name = species_data.creature_name
	down_texture = species_data.down_texture
	up_texture = species_data.up_texture
	right_texture = species_data.right_texture
	up_right_texture = species_data.up_right_texture
	down_right_texture = species_data.down_right_texture
	speed = species_data.speed
	max_health = species_data.max_health
	starvation_health_decay_rate = species_data.starvation_health_decay_rate
	well_fed_health_regen_rate = species_data.well_fed_health_regen_rate
	satiety_heal_threshold = species_data.satiety_heal_threshold
	attack = species_data.attack
	defense = species_data.defense
	max_hunger = species_data.max_hunger
	hunger_decay_rate = species_data.hunger_decay_rate
	hunger_search_threshold = species_data.hunger_search_threshold
	hunger_restore_amount = species_data.hunger_restore_amount
	eating_duration = species_data.eating_duration
	egg_scene = species_data.egg_scene
	egg_stage_1_texture = species_data.egg_stage_1_texture
	egg_stage_2_texture = species_data.egg_stage_2_texture
	egg_laying_duration = species_data.egg_laying_duration
	egg_stage_1_duration = species_data.egg_stage_1_duration
	egg_expand_retry_interval = species_data.egg_expand_retry_interval
	egg_stage_2_duration = species_data.egg_stage_2_duration
	reproduction_min_health = species_data.reproduction_min_health
	reproduction_min_hunger = species_data.reproduction_min_hunger
	reproduction_min_age = species_data.reproduction_min_age
	reproduction_cooldown = species_data.reproduction_cooldown
	reproduction_hunger_cost = species_data.reproduction_hunger_cost
	hatchling_health = species_data.hatchling_health
	hatchling_hunger = species_data.hatchling_hunger

	if health < 0.0:
		health = species_data.starting_health

	if hunger < 0.0:
		hunger = species_data.starting_hunger


func _ready() -> void:
	randomize()
	eating_timer.one_shot = true
	egg_laying_timer.one_shot = true

	apply_species_data()

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


func _exit_tree() -> void:
	if world_grid != null:
		world_grid.unregister_creature(self, footprint_size)


# Main simulation tick.
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

# Survival ticks.
func update_age(delta: float) -> void:
	if age_tick_interval <= 0.0:
		return

	age_tick_elapsed += delta

	while age_tick_elapsed >= age_tick_interval:
		age_tick_elapsed -= age_tick_interval
		age += 1.0


func check_age_death() -> bool:
	if state == State.DEAD:
		return true

	if age < max_age:
		return false

	enter_dead()
	return true


func update_hunger(delta: float) -> void:
	if state == State.EATING or state == State.LAYING_EGG:
		return

	hunger = clamp(hunger - hunger_decay_rate * delta, 0.0, max_hunger)


func update_health(delta: float) -> void:
	if hunger <= 0.0:
		health = clamp(health - starvation_health_decay_rate * delta, 0.0, max_health)
		return

	if hunger > satiety_heal_threshold and health < max_health:
		health = clamp(health + well_fed_health_regen_rate * delta, 0.0, max_health)


func check_health_death() -> bool:
	if state == State.DEAD:
		return true

	if health > 0.0:
		return false

	enter_dead()
	return true


func update_reproduction_cooldown(delta: float) -> void:
	if reproduction_cooldown_remaining <= 0.0:
		return

	reproduction_cooldown_remaining = max(reproduction_cooldown_remaining - delta, 0.0)


# Food state machine.
func update_food_behavior() -> void:
	if world_grid == null:
		return

	if state == State.EATING or state == State.LAYING_EGG:
		return

	if is_moving:
		return

	if hunger > hunger_search_threshold:
		return

	if state != State.SEEK_FOOD:
		enter_seek_food()


func update_idle(delta: float) -> void:
	state_timer -= delta

	if state_timer <= 0.0:
		enter_walk()


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


func update_eating() -> void:
	return


func update_laying_egg() -> void:
	return


# State transitions.
func enter_idle() -> void:
	state = State.IDLE
	state_timer = randf_range(idle_time_min, idle_time_max)
	clear_path()


func enter_walk() -> void:
	state = State.WALK
	state_timer = randf_range(walk_time_min, walk_time_max)
	has_grazing_target = false
	clear_path()


func enter_seek_food() -> void:
	state = State.SEEK_FOOD
	food_recheck_timer = food_recheck_interval
	has_grazing_target = false
	clear_path()
	try_acquire_grazing_target()


func enter_eating() -> void:
	state = State.EATING
	eating_anchor_tile = anchor_tile
	clear_path()
	eating_timer.start(eating_duration)


func enter_laying_egg(egg_anchor: Vector2i) -> void:
	state = State.LAYING_EGG
	pending_egg_anchor = egg_anchor
	clear_path()
	egg_laying_timer.start(egg_laying_duration)


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


func choose_random_wander_step() -> void:
	if world_grid == null:
		return

	var neighbors: Array[Vector2i] = world_grid.get_neighbors(anchor_tile, footprint_size, self)

	if neighbors.is_empty():
		return

	var random_index := randi_range(0, neighbors.size() - 1)
	current_path = [neighbors[random_index]]


func can_start_eating_here() -> bool:
	if world_grid == null:
		return false

	return world_grid.count_adult_grass_under_footprint(anchor_tile, footprint_size) >= min_grass_to_eat


func get_navigation_anchor() -> Vector2i:
	if is_moving:
		return pending_anchor_tile

	return anchor_tile


# Grazing target selection.
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


func apply_grazing_target(target_data: Dictionary) -> void:
	has_grazing_target = true
	grazing_target_anchor = target_data.get("anchor", anchor_tile)
	build_path_to_grazing_target()


func build_path_to_grazing_target() -> void:
	if world_grid == null or not has_grazing_target:
		return

	var navigation_anchor := get_navigation_anchor()
	current_path = world_grid.find_path(navigation_anchor, grazing_target_anchor, footprint_size, self)


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


func is_current_grazing_target_still_valid() -> bool:
	if not has_grazing_target or world_grid == null:
		return false

	if not world_grid.can_place_footprint(grazing_target_anchor, footprint_size, self):
		return false

	return get_current_grazing_target_adult_count() >= min_grass_to_eat


func get_current_grazing_target_adult_count() -> int:
	if world_grid == null or not has_grazing_target:
		return 0

	return world_grid.count_adult_grass_under_footprint(grazing_target_anchor, footprint_size)


# Grid movement.
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


func advance_movement(delta: float) -> void:
	global_position = global_position.move_toward(movement_target_position, speed * delta)

	if global_position.distance_to(movement_target_position) > 0.1:
		return

	global_position = movement_target_position
	is_moving = false

	if world_grid != null and not world_grid.move_creature(self, pending_anchor_tile, footprint_size):
		global_position = world_grid.anchor_to_world_position(anchor_tile, footprint_size)
		clear_path()
		has_grazing_target = false
		return

	anchor_tile = pending_anchor_tile

	if state == State.SEEK_FOOD and can_start_eating_here() and (not has_grazing_target or anchor_tile == grazing_target_anchor):
		enter_eating()


func clear_path() -> void:
	current_path.clear()
	is_moving = false
	pending_anchor_tile = anchor_tile
	movement_target_position = global_position


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


# Reproduction flow.
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


func get_egg_spawn_anchor() -> Vector2i:
	if world_grid == null:
		return Vector2i(2147483647, 2147483647)

	return world_grid.world_to_anchor_tile(global_position, EGG_STAGE_1_FOOTPRINT)


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


# Egg spawn.
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


func find_named_container(target_name: String) -> Node2D:
	var current: Node = self

	while current != null:
		var candidate := current.get_node_or_null(target_name) as Node2D

		if candidate != null:
			return candidate

		current = current.get_parent()

	return null


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


func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_creature") and current.has_method("world_to_anchor_tile"):
			return current

		current = current.get_parent()

	return null


# UI helpers.
func get_species_id() -> String:
	return species_id


func get_species_name() -> String:
	return species_name


func get_age() -> float:
	return age


func get_max_age() -> float:
	return max_age


func get_creature_name() -> String:
	return creature_name


func get_health_percent() -> float:
	if max_health <= 0.0:
		return 0.0

	return clamp((health / max_health) * 100.0, 0.0, 100.0)


func get_hunger_percent() -> float:
	if max_hunger <= 0.0:
		return 0.0

	return clamp((hunger / max_hunger) * 100.0, 0.0, 100.0)


# Hover and selection hooks.
func _on_hover_area_mouse_entered() -> void:
	var stats_ui := get_tree().get_first_node_in_group("creature_stats_ui")

	if stats_ui != null and stats_ui.has_method("show_creature_stats"):
		stats_ui.show_creature_stats(self)


func _on_hover_area_mouse_exited() -> void:
	var stats_ui := get_tree().get_first_node_in_group("creature_stats_ui")

	if stats_ui != null and stats_ui.has_method("hide_creature_stats"):
		stats_ui.hide_creature_stats()


func _on_hover_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton):
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	var stats_ui := get_tree().get_first_node_in_group("creature_stats_ui")

	if stats_ui != null and stats_ui.has_method("toggle_creature_selection"):
		stats_ui.toggle_creature_selection(self)
		get_viewport().set_input_as_handled()
