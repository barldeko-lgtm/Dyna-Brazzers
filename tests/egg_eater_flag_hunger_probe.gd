extends Node

const FlagAssignmentService = preload("res://scripts/flags/player_flag_assignment_service.gd")
const CreatureSpeciesData = preload("res://scripts/creatures/creature_species_data.gd")

class FakeCreature extends Node:
	var species_data: CreatureSpeciesData
	var hunger := 0.0


func _ready() -> void:
	call_deferred("_run_probe")


func _run_probe() -> void:
	var egg_eater := FakeCreature.new()
	egg_eater.species_data = CreatureSpeciesData.new()
	egg_eater.species_data.diet_type = CreatureSpeciesData.DietType.EGG_EATER
	egg_eater.species_data.hunger_search_threshold = 70.0
	egg_eater.hunger = 70.0
	add_child(egg_eater)

	var service := FlagAssignmentService.new(self)
	var hunger_overrides_flag := bool(service.call("_hunger_overrides_flag", egg_eater))

	if not hunger_overrides_flag:
		push_error("A hungry egg eater must pause its species-flag route for egg hunting.")
		get_tree().quit(1)
		return

	print("PASS: hunger overrides the flag route for an egg eater.")
	get_tree().quit(0)
