extends "res://scripts/flags/player_flag_assignment_service.gd"

# Enemy-specific eligibility and commitment metadata layered over the shared
# flag assignment/path service. The objectives are persistent rally zones: a
# creature that later leaves the player-base area may receive a route back.
const FACTION_HELPER := preload("res://scripts/creatures/creature_faction.gd")
const ENEMY_CATALOG := preload("res://scripts/catalogs/enemy_species_catalog.gd")
const ENEMY_FLAG_COMMITMENT_REVISION_META := &"enemy_flag_committed_revision"


func _get_creature_species_id(creature: Node) -> StringName:
	if creature == null or not is_instance_valid(creature) or creature.is_queued_for_deletion():
		return StringName()

	if not FACTION_HELPER.is_enemy(creature):
		return StringName()

	var species_data := creature.get("species_data") as CreatureSpeciesData

	if species_data == null:
		return StringName()

	var species_id := StringName(species_data.species_id)
	var catalog_entry := ENEMY_CATALOG.get_entry(species_id)
	var expected_species_data := catalog_entry.get("species_data") as CreatureSpeciesData

	if expected_species_data == null:
		return StringName()

	if species_data.resource_path != expected_species_data.resource_path:
		return StringName()

	return species_id


func get_next_revision(_species_id: StringName, current_revision: int) -> int:
	return maxi(current_revision + 1, 1)


func _has_completed_current_flag(_creature: Node, _species_id: StringName) -> bool:
	# These are persistent enemy rally objectives rather than one-shot player orders.
	return false


func _has_current_flag_commitment(creature: Node, species_id: StringName) -> bool:
	return int(creature.get_meta(ENEMY_FLAG_COMMITMENT_REVISION_META, -1)) == _get_flag_revision(
		species_id
	)


func _mark_flag_committed(creature: Node, species_id: StringName) -> void:
	creature.set_meta(
		ENEMY_FLAG_COMMITMENT_REVISION_META,
		_get_flag_revision(species_id)
	)


func _clear_flag_commitment(creature: Node) -> void:
	if (
		creature != null
		and is_instance_valid(creature)
		and creature.has_meta(ENEMY_FLAG_COMMITMENT_REVISION_META)
	):
		creature.remove_meta(ENEMY_FLAG_COMMITMENT_REVISION_META)


func _clear_all_flag_commitments() -> void:
	for creature: Node in owner.get_tree().get_nodes_in_group("creatures"):
		_clear_flag_commitment(creature)


func _mark_flag_completed(creature: Node, _species_id: StringName) -> void:
	# Inside the objective area there is no route to keep. Do not store permanent
	# completion: after a survival/combat detour the creature may rally here again.
	_clear_flag_commitment(creature)
	target_allocator.call("clear_retry_choice", creature)
	_release_creature_target(creature, true)
