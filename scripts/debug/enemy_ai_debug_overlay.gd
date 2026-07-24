extends Node2D

# Separate F5-only enemy-AI diagnostics. F4 remains the general performance and
# world debug panel, while this overlay shows only the latest strategic snapshot.
const TOGGLE_KEY := KEY_F5
const REFRESH_INTERVAL := 0.2

@onready var debug_panel: PanelContainer = $DebugCanvas/DebugInfoPanel
@onready var debug_label: Label = $DebugCanvas/DebugInfoPanel/MarginContainer/DebugInfoLabel

var refresh_timer := 0.0


func _ready() -> void:
	add_to_group("enemy_ai_debug_ui")
	debug_panel.visible = false
	refresh_debug_text()


func _process(delta: float) -> void:
	if not debug_panel.visible:
		return

	refresh_timer -= delta

	if refresh_timer > 0.0:
		return

	refresh_timer = REFRESH_INTERVAL
	refresh_debug_text()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	if not event.pressed or event.echo:
		return

	if event.keycode != TOGGLE_KEY:
		return

	debug_panel.visible = not debug_panel.visible
	refresh_timer = 0.0
	refresh_debug_text()
	get_viewport().set_input_as_handled()


func refresh_debug_text() -> void:
	if debug_label == null:
		return

	var enemy_ai := get_tree().get_first_node_in_group("enemy_ai")

	if enemy_ai == null or not enemy_ai.has_method("get_population_snapshot"):
		debug_label.text = "Enemy AI — F5\nКонтроллер ИИ не найден."
		return

	var snapshot_variant: Variant = enemy_ai.call("get_population_snapshot")
	var snapshot: Dictionary = snapshot_variant if snapshot_variant is Dictionary else {}
	var turn_index := int(snapshot.get("turn_index", 0))
	var action_text := "ожидание первого хода"
	var time_until_next_turn := 0.0
	var enemy_energy_value := float(snapshot.get("enemy_energy_after_action", 0.0))
	var elapsed_simulation_seconds := float(snapshot.get("elapsed_simulation_seconds", 0.0))
	var herbivore_cap := int(snapshot.get("herbivore_cap", 10))
	var production_phase := str(snapshot.get("production_phase", "waiting"))

	if enemy_ai.has_method("get_last_action_text"):
		action_text = str(enemy_ai.call("get_last_action_text"))

	if enemy_ai.has_method("get_time_until_next_turn"):
		time_until_next_turn = maxf(float(enemy_ai.call("get_time_until_next_turn")), 0.0)

	if enemy_ai.has_method("get_enemy_energy_value"):
		enemy_energy_value = maxf(float(enemy_ai.call("get_enemy_energy_value")), 0.0)

	if enemy_ai.has_method("get_elapsed_simulation_seconds"):
		elapsed_simulation_seconds = maxf(
			float(enemy_ai.call("get_elapsed_simulation_seconds")),
			0.0
		)

	if enemy_ai.has_method("get_current_herbivore_cap"):
		herbivore_cap = maxi(int(enemy_ai.call("get_current_herbivore_cap")), 0)

	var lines: Array[String] = []
	lines.append("Enemy AI — F5")
	lines.append("Ход: %d | следующий через %.1f сек" % [turn_index, time_until_next_turn])
	lines.append("Время ИИ: %s | энка: %d" % [
		_format_elapsed_time(elapsed_simulation_seconds),
		roundi(enemy_energy_value)
	])
	lines.append("Режим: %s" % _format_production_phase(production_phase))
	lines.append("Травоядные: %d / %d | хищники: %d" % [
		int(snapshot.get("planned_herbivore_count", 0)),
		herbivore_cap,
		int(snapshot.get("planned_predator_count", 0))
	])
	lines.append("Действие: %s" % action_text)
	lines.append(
		"Популяция для решений: %d = взрослые %d + яйца %d" % [
			int(snapshot.get("planned_population_count", 0)),
			int(snapshot.get("adult_count", 0)),
			int(snapshot.get("egg_count", 0))
		]
	)
	lines.append("")
	lines.append("Яйца уже входят в расчёт популяции.")
	debug_label.text = "\n".join(lines)


func _format_production_phase(phase: String) -> String:
	match phase:
		"herbivores":
			return "добор травоядных (стег/триц = 3:1)"
		"predators":
			return "хищники (2 раптора → тирекс → птеро → чередование)"
	return "ожидание"


func _format_elapsed_time(total_seconds: float) -> String:
	var seconds := maxi(int(total_seconds), 0)
	var hours := int(seconds / 3600)
	var minutes := int((seconds % 3600) / 60)
	var remaining_seconds := seconds % 60

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]

	return "%02d:%02d" % [minutes, remaining_seconds]
