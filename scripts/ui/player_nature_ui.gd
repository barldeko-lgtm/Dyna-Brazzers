extends PanelContainer

# Player-facing nature powers HUD.
@export var max_energy := 500.0
@export var starting_energy := 0.0
@export var energy_regen_per_second := 1.0
@export var lightning_damage := 50.0

@onready var energy_bar: ProgressBar = $MarginContainer/VBoxContainer/EnergyBar
@onready var energy_value_label: Label = $MarginContainer/VBoxContainer/EnergyBar/EnergyValueLabel
@onready var lightning_button: Button = $MarginContainer/VBoxContainer/LightningButton

var current_energy := 0.0
var lightning_targeting_enabled := false


func _ready() -> void:
	add_to_group("player_nature_ui")
	current_energy = clamp(starting_energy, 0.0, max_energy)

	energy_bar.min_value = 0.0
	energy_bar.max_value = max_energy
	energy_bar.show_percentage = false

	setup_lightning_button()
	_update_energy_ui()


func _process(delta: float) -> void:
	if current_energy >= max_energy:
		return

	current_energy = clamp(current_energy + energy_regen_per_second * delta, 0.0, max_energy)
	_update_energy_ui()


func setup_lightning_button() -> void:
	lightning_button.toggle_mode = true
	lightning_button.text = "Молния"
	lightning_button.button_pressed = false

	if not lightning_button.toggled.is_connected(_on_lightning_button_toggled):
		lightning_button.toggled.connect(_on_lightning_button_toggled)


func _on_lightning_button_toggled(toggled_on: bool) -> void:
	lightning_targeting_enabled = toggled_on


func is_lightning_targeting_enabled() -> bool:
	return lightning_targeting_enabled


func is_targeting_enabled() -> bool:
	return lightning_targeting_enabled


func try_apply_lightning_to_creature(creature: Node) -> bool:
	if not lightning_targeting_enabled:
		return false

	if creature == null or not is_instance_valid(creature):
		return false

	if creature.has_method("take_direct_damage"):
		creature.take_direct_damage(lightning_damage)
		cancel_lightning_targeting()
		return true

	return false


func cancel_lightning_targeting() -> void:
	lightning_targeting_enabled = false

	if lightning_button.button_pressed:
		lightning_button.set_pressed_no_signal(false)


func can_spend_energy(amount: float) -> bool:
	return current_energy >= amount


func spend_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true

	if not can_spend_energy(amount):
		return false

	current_energy = clamp(current_energy - amount, 0.0, max_energy)
	_update_energy_ui()
	return true


func add_energy(amount: float) -> void:
	if amount <= 0.0:
		return

	current_energy = clamp(current_energy + amount, 0.0, max_energy)
	_update_energy_ui()


func get_energy() -> float:
	return current_energy


func get_max_energy() -> float:
	return max_energy


func _update_energy_ui() -> void:
	if energy_bar == null or energy_value_label == null:
		return

	energy_bar.value = current_energy
	energy_value_label.text = "%d / %d" % [floori(current_energy), floori(max_energy)]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	if not lightning_targeting_enabled:
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_lightning_targeting()
		get_viewport().set_input_as_handled()
