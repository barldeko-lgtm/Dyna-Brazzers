extends Button

# Small helper for the player UI spell section.
# Keeps the nature power buttons hidden until the spell menu button is opened.
@export var spell_button_paths: Array[NodePath] = []
@export var resize_control_path: NodePath
@export var collapsed_height := 96.0
@export var expanded_height := 148.0

var spell_buttons: Array[Control] = []
var resize_control: Control = null


func _ready() -> void:
	toggle_mode = true
	button_pressed = false
	tooltip_text = "Заклинания"

	for spell_button_path in spell_button_paths:
		var node := get_node_or_null(spell_button_path)
		if node is Control:
			spell_buttons.append(node)

	var resize_node := get_node_or_null(resize_control_path)
	if resize_node is Control:
		resize_control = resize_node

	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)

	_apply_open_state(false)


func _on_toggled(toggled_on: bool) -> void:
	_apply_open_state(toggled_on)


func _apply_open_state(is_open: bool) -> void:
	for spell_button in spell_buttons:
		if is_instance_valid(spell_button):
			spell_button.visible = is_open

	if resize_control != null and is_instance_valid(resize_control):
		var size := resize_control.custom_minimum_size
		size.y = expanded_height if is_open else collapsed_height
		resize_control.custom_minimum_size = size

	text = "✦" if not is_open else "✦"
