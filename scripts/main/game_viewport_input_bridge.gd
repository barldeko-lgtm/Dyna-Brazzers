extends Node

# Bridges unhandled game-area input back to root-owned systems.
func _unhandled_input(event: InputEvent) -> void:
	var camera := get_tree().get_first_node_in_group("game_camera") as Camera2D

	if (
		camera != null
		and camera.has_method("handle_game_viewport_input")
		and bool(camera.call("handle_game_viewport_input", event))
	):
		get_viewport().set_input_as_handled()
		return

	var nature_ui := get_tree().get_first_node_in_group("player_nature_ui")

	if (
		nature_ui != null
		and nature_ui.has_method("handle_game_viewport_input")
		and bool(nature_ui.call("handle_game_viewport_input", event))
	):
		get_viewport().set_input_as_handled()
		return

	var flag_system := get_tree().get_first_node_in_group("player_flag_system")

	if (
		flag_system != null
		and flag_system.has_method("handle_game_viewport_input")
		and bool(flag_system.call("handle_game_viewport_input", event))
	):
		get_viewport().set_input_as_handled()
