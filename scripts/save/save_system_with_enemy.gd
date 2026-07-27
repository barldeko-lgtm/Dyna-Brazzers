extends "res://scripts/save/save_system_with_flags.gd"

# Final save layer for current enemy session state. Core entities, factions and
# player flags remain owned by the existing save-system layers.


func _collect_save_data() -> Dictionary:
	var save_data: Dictionary = super._collect_save_data()
	var enemy_energy := get_tree().get_first_node_in_group("enemy_energy")
	var enemy_production := get_tree().get_first_node_in_group("enemy_egg_production")
	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")
	var enemy_spells := get_tree().get_first_node_in_group("enemy_spell_controller")
	var game_end_controller := get_tree().get_first_node_in_group("game_end_controller")

	if enemy_energy != null and enemy_energy.has_method("get_energy"):
		save_data["enemy_energy"] = float(enemy_energy.call("get_energy"))

	if enemy_production != null and enemy_production.has_method("get_save_data"):
		save_data["enemy_production"] = enemy_production.call("get_save_data")

	if enemy_ai != null and enemy_ai.has_method("get_save_data"):
		save_data["enemy_ai"] = enemy_ai.call("get_save_data")

	if enemy_spells != null and enemy_spells.has_method("get_save_data"):
		save_data["enemy_spells"] = enemy_spells.call("get_save_data")

	if game_end_controller != null and game_end_controller.has_method("get_save_data"):
		save_data["game_end"] = game_end_controller.call("get_save_data")

	return save_data


func _apply_save_data(save_data: Dictionary) -> bool:
	var restored: bool = await super._apply_save_data(save_data)

	if not restored:
		return false

	var enemy_energy := get_tree().get_first_node_in_group("enemy_energy")
	var enemy_production := get_tree().get_first_node_in_group("enemy_egg_production")
	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")
	var enemy_spells := get_tree().get_first_node_in_group("enemy_spell_controller")
	var game_end_controller := get_tree().get_first_node_in_group("game_end_controller")

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

	if enemy_spells != null and enemy_spells.has_method("restore_save_data"):
		var enemy_spells_data_variant: Variant = save_data.get("enemy_spells", null)
		var enemy_spells_data: Dictionary = {}

		if enemy_spells_data_variant is Dictionary:
			enemy_spells_data = (enemy_spells_data_variant as Dictionary).duplicate(true)

		# An empty dictionary is intentional for old saves: the spell controller
		# rebuilds the reserve from the already restored enemy-AI clock.
		enemy_spells.call("restore_save_data", enemy_spells_data)


	if game_end_controller != null and game_end_controller.has_method("restore_save_data"):
		var game_end_data_variant: Variant = save_data.get("game_end", null)
		var game_end_data: Dictionary = {}

		if game_end_data_variant is Dictionary:
			game_end_data = (game_end_data_variant as Dictionary).duplicate(true)

		if not game_end_data.has("elapsed_simulation_seconds"):
			# Saves created before match-end tracking reuse the already persisted enemy-AI
			# simulation clock, avoiding a fresh two-minute grace period after loading.
			var enemy_ai_data_variant: Variant = save_data.get("enemy_ai", null)
			if enemy_ai_data_variant is Dictionary:
				game_end_data["elapsed_simulation_seconds"] = float(
					(enemy_ai_data_variant as Dictionary).get(
						"elapsed_simulation_seconds",
						0.0
					)
				)

		game_end_controller.call("restore_save_data", game_end_data)

	return true


# Stable public bridge used by the result overlay. The inherited menu transition
# already resets the active session and restores normal time before scene change.
func return_to_main_menu_from_result() -> void:
	_on_main_menu_pressed()
