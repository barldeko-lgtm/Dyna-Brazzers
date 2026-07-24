extends "res://scripts/save/save_system_with_flags.gd"

# Final save layer for current enemy session state. Core entities, factions and
# player flags remain owned by the existing save-system layers.


func _collect_save_data() -> Dictionary:
	var save_data: Dictionary = super._collect_save_data()
	var enemy_energy := get_tree().get_first_node_in_group("enemy_energy")
	var enemy_production := get_tree().get_first_node_in_group("enemy_egg_production")
	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")

	if enemy_energy != null and enemy_energy.has_method("get_energy"):
		save_data["enemy_energy"] = float(enemy_energy.call("get_energy"))

	if enemy_production != null and enemy_production.has_method("get_save_data"):
		save_data["enemy_production"] = enemy_production.call("get_save_data")

	if enemy_ai != null and enemy_ai.has_method("get_save_data"):
		save_data["enemy_ai"] = enemy_ai.call("get_save_data")

	return save_data


func _apply_save_data(save_data: Dictionary) -> bool:
	var restored: bool = await super._apply_save_data(save_data)

	if not restored:
		return false

	var enemy_energy := get_tree().get_first_node_in_group("enemy_energy")
	var enemy_production := get_tree().get_first_node_in_group("enemy_egg_production")
	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")

	if enemy_energy != null and enemy_energy.has_method("restore_energy"):
		var restored_energy := float(
			save_data.get("enemy_energy", enemy_energy.call("get_energy"))
		)
		enemy_energy.call("restore_energy", restored_energy)

	if (
		enemy_production != null
		and enemy_production.has_method("restore_save_data")
		and save_data.get("enemy_production", null) is Dictionary
	):
		enemy_production.call(
			"restore_save_data",
			save_data.get("enemy_production", {}) as Dictionary
		)

	if (
		enemy_ai != null
		and enemy_ai.has_method("restore_save_data")
		and save_data.get("enemy_ai", null) is Dictionary
	):
		enemy_ai.call(
			"restore_save_data",
			save_data.get("enemy_ai", {}) as Dictionary
		)

	return true
