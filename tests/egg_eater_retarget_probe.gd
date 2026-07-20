extends Node

const CreatureEggEaterLogic = preload("res://scripts/creatures/behaviors/creature_egg_eater_logic.gd")
const CreatureSpeciesData = preload("res://scripts/creatures/creature_species_data.gd")

class FakeCreature extends Node:
	enum State {
		IDLE,
		WALK,
		SEEK_FOOD,
		EATING,
		LAYING_EGG,
		COMBAT,
		DEAD
	}

	var species_data: CreatureSpeciesData
	var world_grid: Node
	var hunger := 70.0
	var state: State = State.WALK
	var is_moving := true
	var anchor_tile := Vector2i.ZERO
	var footprint_size := Vector2i(2, 2)
	var current_path: Array[Vector2i] = []

	func is_egg_eater() -> bool:
		return true

	func are_footprints_side_adjacent(
		_a_anchor: Vector2i,
		_a_size: Vector2i,
		_b_anchor: Vector2i,
		_b_size: Vector2i
	) -> bool:
		return false


class FakeEgg extends Node:
	var anchor_tile := Vector2i.ZERO
	var species_id := "stegosaurus"

	func can_be_eaten() -> bool:
		return true


func _ready() -> void:
	call_deferred("_run_probe")


func _run_probe() -> void:
	var egg_eater := FakeCreature.new()
	egg_eater.species_data = CreatureSpeciesData.new()
	egg_eater.species_data.diet_type = CreatureSpeciesData.DietType.EGG_EATER
	egg_eater.species_data.species_id = "egg_eater"
	egg_eater.species_data.hunger_search_threshold = 70.0
	egg_eater.species_data.predator_target_radius = 10
	egg_eater.world_grid = Node.new()
	egg_eater.add_child(egg_eater.world_grid)
	add_child(egg_eater)

	var far_egg := FakeEgg.new()
	far_egg.anchor_tile = Vector2i(6, 0)
	far_egg.add_to_group("eggs")
	add_child(far_egg)

	var logic := CreatureEggEaterLogic.new(egg_eater)
	logic.target_egg = far_egg
	logic.search_cooldown_remaining = 0.0

	var nearby_egg := FakeEgg.new()
	nearby_egg.anchor_tile = Vector2i(4, 0)
	nearby_egg.add_to_group("eggs")
	add_child(nearby_egg)

	logic.update_egg_eater_behavior()

	if logic.target_egg != nearby_egg:
		push_error("Egg eater must retarget after 0.5 seconds when a new egg is at least two steps closer.")
		get_tree().quit(1)
		return

	print("PASS: egg eater retargets to an egg two steps closer.")
	get_tree().quit(0)
