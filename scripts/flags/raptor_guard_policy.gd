extends RefCounted

const CREATURE_FACTION := preload("res://scripts/creatures/creature_faction.gd")
const RAPTOR_ID: StringName = &"raptor"
const LEASH_RADIUS_TILES := 8


static func is_guard_raptor(creature: Node) -> bool:
	if creature == null or not is_instance_valid(creature):
		return false

	var species_data := creature.get("species_data") as CreatureSpeciesData
	return (
		species_data != null
		and StringName(species_data.species_id) == RAPTOR_ID
		and species_data.is_defensive_predator()
	)


static func is_anchor_within_leash(flag_tile: Vector2i, anchor: Vector2i) -> bool:
	return max(abs(anchor.x - flag_tile.x), abs(anchor.y - flag_tile.y)) <= LEASH_RADIUS_TILES


static func is_wander_anchor_allowed(creature: Node, candidate_anchor: Vector2i) -> bool:
	if not is_guard_raptor(creature):
		return true

	var flag_system := _get_flag_system(creature)

	if flag_system == null or not flag_system.has_method("has_flag"):
		return true

	if not bool(flag_system.call("has_flag", RAPTOR_ID)):
		return true

	if not flag_system.has_method("get_flag_tile"):
		return true

	var flag_tile_variant: Variant = flag_system.call("get_flag_tile", RAPTOR_ID)

	if not (flag_tile_variant is Vector2i):
		return true

	return is_anchor_within_leash(flag_tile_variant, candidate_anchor)


static func should_recall(
	creature: Node,
	flag_tile: Vector2i,
	anchor: Vector2i
) -> bool:
	if not is_guard_raptor(creature):
		return false

	if creature.has_method("is_hunting") and bool(creature.call("is_hunting")):
		return false

	return not is_anchor_within_leash(flag_tile, anchor)


static func _get_flag_system(creature: Node) -> Node:
	var tree := creature.get_tree()

	if tree == null:
		return null

	if CREATURE_FACTION.is_enemy(creature):
		return tree.get_first_node_in_group("enemy_flag_system")

	if CREATURE_FACTION.is_player(creature):
		return tree.get_first_node_in_group("player_flag_system")

	return null
