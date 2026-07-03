extends CharacterBody2D

const Duel = preload("res://scripts/combat/duel.gd")
const CreatureGrazingLogic = preload("res://scripts/creatures/behaviors/creature_grazing_logic.gd")
const CreatureVisualController = preload("res://scripts/creatures/behaviors/creature_visual_controller.gd")
const CreatureReproductionLogic = preload("res://scripts/creatures/behaviors/creature_reproduction_logic.gd")
const CreaturePredatorLogic = preload("res://scripts/creatures/behaviors/creature_predator_logic.gd")

# Core creature FSM.
@onready var sprite: Sprite2D = $BodySprite
@onready var walk_right_sprite: AnimatedSprite2D = $WalkRightSprite

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
	COMBAT,
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

# Hard cap on how many tiles a single pathfinding attempt may expand before
# giving up. Keeps one blocked/unreachable target from costing more than a
# bounded amount of work, no matter how large the map or population gets.
@export var max_path_search_tiles := 300

# How many ranked grazing candidates to keep when searching for food. If the
# best one turns out unreachable, the creature tries the next one instead of
# re-scanning the whole map or getting stuck retrying the same dead target.
@export var max_grazing_candidates := 5

# Minimum time between path rebuild attempts toward prey after a failed
# attempt, so a predator chasing an unreachable target doesn't retry every
# physics frame.
@export var predator_path_retry_interval := 1.0

# Static species config. All species stats and visuals live in this resource.
@export var species_data: CreatureSpeciesData

var eating_anchor_tile := Vector2i.ZERO

# Runtime stats/state that can change per creature instance.
var health := -1.0

var age := 0.0

# Global aging tick. Per-species lifespan is stored in species_data.max_age.
@export var age_tick_interval := 30.0

var hunger := -1.0

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

# Ranked runner-up grazing candidates left over from the last search, tried
# in order if the current target becomes unreachable.
var grazing_candidate_queue: Array[Vector2i] = []

# Countdown before a predator is allowed to rebuild its path to prey again
# after a failed attempt.
var predator_path_retry_cooldown_remaining := 0.0

var pending_anchor_tile := Vector2i.ZERO

var movement_target_position := Vector2.ZERO

var is_moving := false

var reproduction_cooldown_remaining := 0.0

var pending_egg_anchor := Vector2i.ZERO
var current_duel: Duel = null
var grazing_logic: RefCounted
var visual_controller: RefCounted
var reproduction_logic: RefCounted
var predator_logic: RefCounted



# Initialize mutable runtime stats from species_data once.
func apply_species_data() -> void:
	if species_data == null:
		push_error("Creature has no species_data assigned.")
		return

	if health < 0.0:
		health = species_data.starting_health

	if hunger < 0.0:
		hunger = species_data.starting_hunger



func change_state(new_state: State) -> void:
	if state == new_state:
		update_sprite_visual()
		return

	state = new_state
	update_sprite_visual()


func _ready() -> void:
	randomize()
	add_to_group("creatures")
	visual_controller = CreatureVisualController.new(self)
	reproduction_logic = CreatureReproductionLogic.new(self)
	predator_logic = CreaturePredatorLogic.new(self)
	eating_timer.one_shot = true
	egg_laying_timer.one_shot = true

	apply_species_data()

	if species_data == null:
		set_physics_process(false)
		return

	if not species_data.is_predator:
		grazing_logic = CreatureGrazingLogic.new(self)

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

	health = clamp(health, 0.0, species_data.max_health)
	age = 0.0
	age_tick_elapsed = 0.0
	hunger = clamp(hunger, 0.0, species_data.max_hunger)
	world_grid = find_world_grid()

	if world_grid != null:
		var initial_position := global_position
		anchor_tile = world_grid.world_to_anchor_tile(initial_position, footprint_size)
		anchor_tile = world_grid.find_nearest_valid_anchor(anchor_tile, footprint_size, self)
		render_offset = Vector2.ZERO
		world_grid.register_creature(self, anchor_tile, footprint_size)
		global_position = world_grid.anchor_to_world_position(anchor_tile, footprint_size)
		sprite.position = Vector2.ZERO

	configure_walk_animation()
	enter_walk()


func _exit_tree() -> void:
	if world_grid != null:
		world_grid.unregister_creature(self, footprint_size)


func configure_walk_animation() -> void:
	if visual_controller == null:
		return

	visual_controller.configure_walk_animation()


func can_use_walk_right_animation() -> bool:
	if visual_controller == null:
		return false

	return visual_controller.can_use_walk_right_animation()


func set_walk_right_animation_active(active: bool, flip_h: bool = false) -> void:
	if visual_controller == null:
		return

	visual_controller.set_walk_right_animation_active(active, flip_h)


func _physics_process(delta: float) -> void:
	PerformanceStats.add_counter("creature_physics_ticks")

	if state == State.DEAD:
		return

	ensure_combat_state_consistency()

	if state == State.DEAD:
		return

	update_age(delta)

	if check_age_death():
		return

	update_hunger(delta)
	update_health(delta)
	update_reproduction_cooldown(delta)
	update_predator_path_retry_cooldown(delta)

	if check_health_death():
		return

	update_predator_behavior()
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
		State.COMBAT:
			update_combat()
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

	if age < species_data.max_age:
		return false

	enter_dead()
	return true


func update_hunger(delta: float) -> void:
	if state == State.EATING or state == State.LAYING_EGG or state == State.COMBAT:
		return

	hunger = clamp(hunger - species_data.hunger_decay_rate * delta, 0.0, species_data.max_hunger)


func update_health(delta: float) -> void:
	if state == State.COMBAT:
		return

	if hunger <= 0.0:
		health = clamp(health - species_data.starvation_health_decay_rate * delta, 0.0, species_data.max_health)
		return

	if hunger > species_data.satiety_heal_threshold and health < species_data.max_health:
		health = clamp(health + species_data.well_fed_health_regen_rate * delta, 0.0, species_data.max_health)


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


func update_predator_path_retry_cooldown(delta: float) -> void:
	if predator_path_retry_cooldown_remaining <= 0.0:
		return

	predator_path_retry_cooldown_remaining = max(predator_path_retry_cooldown_remaining - delta, 0.0)


func update_predator_behavior() -> void:
	predator_logic.update_predator_behavior()


func update_food_behavior() -> void:
	if grazing_logic == null:
		return

	grazing_logic.update_food_behavior()


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
	if grazing_logic == null:
		enter_walk()
		return

	grazing_logic.update_seek_food(delta)


func update_eating() -> void:
	return


func update_laying_egg() -> void:
	return


func update_combat() -> void:
	return


func ensure_combat_state_consistency() -> void:
	if state != State.COMBAT:
		return

	if current_duel != null and is_instance_valid(current_duel):
		return

	current_duel = null

	if hunger <= species_data.hunger_search_threshold:
		enter_hungry_behavior()
		return

	enter_walk()


# State transitions.
func enter_idle() -> void:
	state_timer = randf_range(idle_time_min, idle_time_max)
	clear_path()
	change_state(State.IDLE)


func enter_walk() -> void:
	state_timer = randf_range(walk_time_min, walk_time_max)
	has_grazing_target = false
	clear_path()
	change_state(State.WALK)


func enter_seek_food() -> void:
	if species_data != null and species_data.is_predator:
		enter_walk()
		return

	if grazing_logic == null:
		return

	grazing_logic.enter_seek_food()


func enter_hungry_behavior() -> void:
	if species_data != null and species_data.is_predator:
		enter_walk()
		return

	enter_seek_food()


func enter_eating() -> void:
	eating_anchor_tile = anchor_tile
	clear_path()
	change_state(State.EATING)
	eating_timer.start(species_data.eating_duration)


func enter_laying_egg(egg_anchor: Vector2i) -> void:
	pending_egg_anchor = egg_anchor
	clear_path()
	change_state(State.LAYING_EGG)
	egg_laying_timer.start(species_data.egg_laying_duration)


func enter_dead() -> void:
	if state == State.DEAD:
		return

	change_state(State.DEAD)

	if current_duel != null:
		current_duel.handle_fighter_death(self)

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
	if grazing_logic == null:
		return false

	return grazing_logic.can_start_eating_here()


func get_navigation_anchor() -> Vector2i:
	if is_moving:
		return pending_anchor_tile

	return anchor_tile


# Grazing target selection.
func try_acquire_grazing_target() -> void:
	if grazing_logic == null:
		return

	grazing_logic.try_acquire_grazing_target()


func apply_grazing_target(target_data: Dictionary) -> void:
	if grazing_logic == null:
		return

	grazing_logic.apply_grazing_target(target_data)


func build_path_to_grazing_target() -> void:
	if grazing_logic == null:
		return

	grazing_logic.build_path_to_grazing_target()


func recheck_grazing_target() -> void:
	if grazing_logic == null:
		return

	grazing_logic.recheck_grazing_target()


func is_current_grazing_target_still_valid() -> bool:
	if grazing_logic == null:
		return false

	return grazing_logic.is_current_grazing_target_still_valid()


func get_current_grazing_target_adult_count() -> int:
	if grazing_logic == null:
		return 0

	return grazing_logic.get_current_grazing_target_adult_count()


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
	is_moving = true
	update_sprite_visual()


func advance_movement(delta: float) -> void:
	global_position = global_position.move_toward(movement_target_position, species_data.speed * delta)

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
		hunger = clamp(hunger + species_data.hunger_restore_amount * float(consumed_grass_count), 0.0, species_data.max_hunger)

	if hunger <= species_data.hunger_search_threshold:
		enter_hungry_behavior()
		return

	enter_walk()


func _on_egg_laying_timer_timeout() -> void:
	reproduction_logic.on_egg_laying_timer_timeout()


func find_nearest_prey() -> Node:
	return predator_logic.find_nearest_prey()


func is_valid_prey(candidate: Node) -> bool:
	return predator_logic.is_valid_prey(candidate)


func is_prey_in_duel_range(prey: Node) -> bool:
	return predator_logic.is_prey_in_duel_range(prey)


func are_footprints_side_adjacent(a_anchor: Vector2i, a_size: Vector2i, b_anchor: Vector2i, b_size: Vector2i) -> bool:
	return predator_logic.are_footprints_side_adjacent(a_anchor, a_size, b_anchor, b_size)


func build_path_to_prey(prey: Node) -> void:
	predator_logic.build_path_to_prey(prey)


func update_reproduction_behavior() -> void:
	reproduction_logic.update_reproduction_behavior()


func get_egg_spawn_anchor() -> Vector2i:
	return reproduction_logic.get_egg_spawn_anchor()


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
	return reproduction_logic.spawn_egg_at_pending_anchor()


func find_named_container(target_name: String) -> Node2D:
	return reproduction_logic.find_named_container(target_name)


func update_sprite_visual() -> void:
	if visual_controller == null:
		return

	visual_controller.update_sprite_visual()


func can_continue_duel(duel: Duel) -> bool:
	return state != State.DEAD and current_duel == duel


func can_be_hunted() -> bool:
	return state != State.DEAD and current_duel == null


func can_fight() -> bool:
	return state == State.IDLE or state == State.WALK or state == State.SEEK_FOOD


func is_in_duel() -> bool:
	return current_duel != null


func attach_duel(duel: Duel) -> void:
	current_duel = duel
	has_grazing_target = false
	clear_path()
	eating_timer.stop()
	egg_laying_timer.stop()
	change_state(State.COMBAT)

	if duel != null:
		face_duel_opponent(duel)


func detach_duel(duel: Duel) -> void:
	if current_duel != duel:
		return

	current_duel = null

	if state == State.DEAD:
		return

	if hunger <= species_data.hunger_search_threshold:
		enter_hungry_behavior()
		return

	enter_walk()


func start_duel_with(opponent: Node) -> Duel:
	return predator_logic.start_duel_with(opponent)


func take_duel_damage(amount: float, _attacker: Node = null) -> void:
	take_direct_damage(amount)


func take_direct_damage(amount: float) -> void:
	health = clamp(health - amount, 0.0, species_data.max_health)

	if health <= 0.0:
		enter_dead()


func face_duel_opponent(duel: Duel) -> void:
	if duel == null:
		return

	var opponent: Node = duel.fighter_a if duel.fighter_b == self else duel.fighter_b
	face_target(opponent)


func face_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	var to_target: Vector2 = target.global_position - global_position
	if to_target.length_squared() <= 0.0001:
		return

	direction = to_target.normalized()
	velocity = Vector2.ZERO
	update_sprite_visual()


func _on_duel_finished(duel: Duel, winner: Node, _loser: Node) -> void:
	if duel != current_duel and current_duel != null:
		return

	if winner != self or not species_data.is_predator:
		return

	hunger = clamp(hunger + species_data.hunger_restore_amount, 0.0, species_data.max_hunger)


func find_world_grid() -> Node:
	var current: Node = self

	while current != null:
		if current.has_method("register_creature") and current.has_method("world_to_anchor_tile"):
			return current

		current = current.get_parent()

	return null


# UI helpers.
func get_species_id() -> String:
	return species_data.species_id


func get_species_name() -> String:
	return species_data.species_name


func get_age() -> float:
	return age


func get_max_age() -> float:
	return species_data.max_age


func get_creature_name() -> String:
	return species_data.creature_name


func get_is_predator() -> bool:
	return species_data != null and species_data.is_predator


func get_attack() -> float:
	if species_data == null:
		return 0.0

	return species_data.attack


func get_defense() -> float:
	if species_data == null:
		return 0.0

	return species_data.defense


func get_max_health() -> float:
	if species_data == null:
		return 0.0

	return species_data.max_health


func get_max_hunger() -> float:
	if species_data == null:
		return 0.0

	return species_data.max_hunger


func get_health_percent() -> float:
	if species_data.max_health <= 0.0:
		return 0.0

	return clamp((health / species_data.max_health) * 100.0, 0.0, 100.0)


func get_hunger_percent() -> float:
	if species_data.max_hunger <= 0.0:
		return 0.0

	return clamp((hunger / species_data.max_hunger) * 100.0, 0.0, 100.0)


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

	if stats_ui != null and stats_ui.has_method("try_apply_lightning_to_creature"):
		if stats_ui.try_apply_lightning_to_creature(self):
			get_viewport().set_input_as_handled()
			return

	if stats_ui != null and stats_ui.has_method("toggle_creature_selection"):
		stats_ui.toggle_creature_selection(self)
		get_viewport().set_input_as_handled()
