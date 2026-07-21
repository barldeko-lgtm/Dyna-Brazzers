extends "res://scripts/world/faction_base.gd"

# Player-facing wrapper kept for the existing egg-purchase UI.
const FACTION_HELPER := preload("res://scripts/creatures/creature_faction.gd")


func _enter_tree() -> void:
	faction_id = FACTION_HELPER.PLAYER
	placement_search_radius = 8


func create_player_egg(species_data: CreatureSpeciesData) -> Node2D:
	return create_faction_egg(species_data)


func find_player_egg_spawn_anchor() -> Vector2i:
	return find_egg_spawn_anchor()


func can_place_player_egg_anchor(candidate_anchor: Vector2i) -> bool:
	return can_place_egg_anchor(candidate_anchor)
