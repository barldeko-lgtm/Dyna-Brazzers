extends RefCounted

const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const EGG_STAGE_1_FOOTPRINT := Vector2i(1, 2)
const INVALID_ANCHOR := Vector2i(2147483647, 2147483647)

var creature: Node


func _init(owner_creature: Node) -> void:
	creature = owner_creature


func update_reproduction_behavior() -> void:
	if creature.world_grid == null:
		return

	if creature.state == creature.State.DEAD or creature.state == creature.State.EATING or creature.state == creature.State.LAYING_EGG or creature.state == creature.State.COMBAT:
		return

	if creature.is_moving:
		return

	if creature.reproduction_cooldown_remaining > 0.0:
		return

	if creature.health <= creature.species_data.reproduction_min_health:
		return

	if creature.hunger <= creature.species_data.reproduction_min_hunger:
		return

	if creature.age <= creature.species_data.reproduction_min_age:
		return

	var egg_anchor := get_egg_spawn_anchor()

	if egg_anchor == INVALID_ANCHOR:
		return

	creature.enter_laying_egg(egg_anchor)


func on_egg_laying_timer_timeout() -> void:
	if creature.world_grid == null:
		creature.enter_walk()
		return

	if spawn_egg_at_pending_anchor():
		creature.hunger = clamp(creature.hunger - creature.species_data.reproduction_hunger_cost, 0.0, creature.species_data.max_hunger)
		creature.reproduction_cooldown_remaining = creature.species_data.reproduction_cooldown

	if creature.hunger <= creature.species_data.hunger_search_threshold:
		if creature.has_method("enter_hungry_behavior"):
			creature.enter_hungry_behavior()
		else:
			creature.enter_seek_food()
		return

	creature.enter_walk()


func get_egg_spawn_anchor() -> Vector2i:
	if creature.world_grid == null:
		return INVALID_ANCHOR

	return creature.world_grid.world_to_anchor_tile(creature.global_position, EGG_STAGE_1_FOOTPRINT)


func spawn_egg_at_pending_anchor() -> bool:
	if creature.species_data.egg_scene == null:
		return false

	var eggs_container := find_named_container("Eggs")

	if eggs_container == null:
		eggs_container = creature.get_parent() as Node2D

	if eggs_container == null:
		return false

	var new_egg := creature.species_data.egg_scene.instantiate() as Node2D

	if new_egg == null:
		return false

	new_egg.set("species_id", creature.species_data.species_id)
	new_egg.set("hatch_species_data", creature.species_data)
	CREATURE_FACTION.set_id(new_egg, CREATURE_FACTION.get_id(creature))

	if creature.species_data.egg_stage_1_texture != null:
		new_egg.set("stage_1_texture", creature.species_data.egg_stage_1_texture)

	if creature.species_data.egg_stage_2_texture != null:
		new_egg.set("stage_2_texture", creature.species_data.egg_stage_2_texture)

	new_egg.set("stage_1_duration", creature.species_data.egg_stage_1_duration)
	new_egg.set("expand_retry_interval", creature.species_data.egg_expand_retry_interval)
	new_egg.set("stage_2_duration", creature.species_data.egg_stage_2_duration)
	new_egg.set("hatch_health", creature.species_data.hatchling_health)
	new_egg.set("hatch_hunger", creature.species_data.hatchling_hunger)
	new_egg.set("hatch_creature_scene", load(creature.scene_file_path) as PackedScene)

	var egg_world_position: Vector2 = creature.world_grid.anchor_to_world_position(creature.pending_egg_anchor, EGG_STAGE_1_FOOTPRINT)
	new_egg.position = eggs_container.to_local(egg_world_position)
	eggs_container.add_child(new_egg)

	return true


func find_named_container(target_name: String) -> Node2D:
	var current: Node = creature

	while current != null:
		var candidate := current.get_node_or_null(target_name) as Node2D

		if candidate != null:
			return candidate

		current = current.get_parent()

	return null
