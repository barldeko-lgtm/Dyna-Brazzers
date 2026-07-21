extends "res://scripts/world/faction_base.gd"

# Enemy base has no production AI yet. The public wrapper is ready for the next
# step, where an enemy controller will decide when and which egg to create.
const FACTION_HELPER := preload("res://scripts/creatures/creature_faction.gd")


func _enter_tree() -> void:
	faction_id = FACTION_HELPER.ENEMY


func create_enemy_egg(species_data: CreatureSpeciesData) -> Node2D:
	return create_faction_egg(species_data)
