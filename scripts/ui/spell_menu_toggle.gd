extends Button

# Small helper for the player UI spell section.
# Opens a fixed-size spell submenu without moving the energy block.
@export var spell_button_paths: Array[NodePath] = []
@export var back_button_path: NodePath

var spell_buttons: Array[Control] = []
var back_button: Button = null


func _ready() -> void:
	toggle_mode = true
	button_pressed = false
	tooltip_text = "Заклинания"

	for spell_button_path in spell_button_paths:
		var node := get_node_or_null(spell_button_path)
		if node is Control:
			spell_buttons.append(node)

	var back_node := get_node_or_null(back_button_path)
	if back_node is Button:
		back_button = back_node
		back_button.focus_mode = Control.FOCUS_NONE
		if not back_button.pressed.is_connected(_on_back_button_pressed):
			back_button.pressed.connect(_on_back_button_pressed)

	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)

	_apply_open_state(false)


func _on_toggled(toggled_on: bool) -> void:
	_apply_open_state(toggled_on)


func _on_back_button_pressed() -> void:
	button_pressed = false
	set_pressed_no_signal(false)
	_apply_open_state(false)


func _apply_open_state(is_open: bool) -> void:
	visible = not is_open

	for spell_button in spell_buttons:
		if is_instance_valid(spell_button):
			spell_button.visible = is_open

	if back_button != null and is_instance_valid(back_button):
		back_button.visible = is_open
