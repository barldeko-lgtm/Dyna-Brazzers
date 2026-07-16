extends "res://scripts/save/save_system.gd"

# Small save-system extension for player species flags. The existing creature,
# grass, egg, energy, camera and menu logic remains owned by save_system.gd.


func _collect_save_data() -> Dictionary:
	var save_data: Dictionary = super._collect_save_data()
	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("get_save_data"):
		save_data["player_flags"] = player_flags.call("get_save_data")
	else:
		save_data["player_flags"] = {}

	return save_data


func _apply_save_data(save_data: Dictionary) -> bool:
	var restored: bool = await super._apply_save_data(save_data)

	if not restored:
		return false

	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("restore_save_data"):
		player_flags.call("restore_save_data", save_data.get("player_flags", {}) as Dictionary)

	return true


func _cancel_active_nature_targeting() -> void:
	super._cancel_active_nature_targeting()

	var player_flags := get_node_or_null("/root/PlayerFlags")

	if player_flags != null and player_flags.has_method("cancel_targeting"):
		player_flags.call("cancel_targeting")
