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
		debug_label.text = "Контроллер ИИ не найден."
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
	var adult_herbivore_count := int(snapshot.get("adult_herbivore_count", 0))
	var average_herbivore_satiety := float(
		snapshot.get("average_adult_herbivore_satiety_percent", -1.0)
	)
	var satiety_threshold := float(
		snapshot.get("minimum_average_herbivore_satiety_percent", 40.0)
	)
	var herbivore_spawning_blocked := bool(
		snapshot.get("herbivore_spawning_blocked_by_hunger", false)
	)

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
	lines.append("Ход: %d | следующий через %.1f сек" % [turn_index, time_until_next_turn])
	lines.append("Время ИИ: %s | энка: %d" % [
		_format_elapsed_time(elapsed_simulation_seconds),
		roundi(enemy_energy_value)
	])
	lines.append("Режим: %s" % _format_production_phase(production_phase))
	if adult_herbivore_count <= 0 or average_herbivore_satiety < 0.0:
		lines.append("Сытость травоядных врага: нет данных | добор: разрешён")
	else:
		lines.append("Сытость травоядных врага (%d взрослых): %.1f%% / %.0f%% | добор: %s" % [
			adult_herbivore_count,
			average_herbivore_satiety,
			satiety_threshold,
			"СТОП" if herbivore_spawning_blocked else "разрешён"
		])
	lines.append("Травоядные: %d / %d | хищники: %d" % [
		int(snapshot.get("planned_herbivore_count", 0)),
		herbivore_cap,
		int(snapshot.get("planned_predator_count", 0))
	])
	lines.append("Яйцеед AI: %d | 10 мин: %s | ядро 2R+T+P: %s" % [
		int(snapshot.get("planned_egg_eater_count", 0)),
		"да" if bool(snapshot.get("egg_eater_production_unlocked", false)) else "нет",
		"да" if bool(snapshot.get("living_predator_core_ready", false)) else "нет"
	])
	lines.append("Действие: %s" % action_text)
	lines.append(
		"Популяция для решений: %d = взрослые %d + яйца %d" % [
			int(snapshot.get("planned_population_count", 0)),
			int(snapshot.get("adult_count", 0)),
			int(snapshot.get("egg_count", 0))
		]
	)
	_append_rain_debug_lines(lines)
	debug_label.text = "\n".join(lines)


func _append_rain_debug_lines(lines: Array[String]) -> void:
	var spell_controller := get_tree().get_first_node_in_group("enemy_spell_controller")

	if spell_controller == null or not spell_controller.has_method("get_rain_debug_data"):
		lines.append("Дождь: контроллер спеллов не найден")
		return

	var debug_variant: Variant = spell_controller.call("get_rain_debug_data")
	var rain_data: Dictionary = debug_variant if debug_variant is Dictionary else {}
	lines.append("Дождь: %s" % str(rain_data.get("action_text", "ожидание")))
	lines.append("Поиск: %.3f мс | максимум %.3f мс | запусков %d" % [
		float(rain_data.get("search_duration_msec", 0.0)),
		float(rain_data.get("max_search_duration_msec", 0.0)),
		int(rain_data.get("total_search_count", 0))
	])
	lines.append("Трава: %d просмотрено | зрелой %d" % [
		int(rain_data.get("grass_entries_scanned", 0)),
		int(rain_data.get("mature_grass_count", 0))
	])
	lines.append("Готовой к размножению %d | полезной %d" % [
		int(rain_data.get("spread_ready_grass_count", 0)),
		int(rain_data.get("productive_grass_count", 0))
	])
	lines.append("Новых клеток %d | центров 5x5: %d" % [
		int(rain_data.get("unique_spawn_target_count", 0)),
		int(rain_data.get("candidate_center_count", 0))
	])
	lines.append("DryGround у травы: всего %d | в цели 0/3 %d, 1/3 %d, 2/3 %d" % [
		int(rain_data.get("adjacent_dry_ground_count", 0)),
		int(rain_data.get("best_dry_ground_zero_hit_count", 0)),
		int(rain_data.get("best_dry_ground_one_hit_count", 0)),
		int(rain_data.get("best_dry_ground_two_hit_count", 0))
	])
	lines.append("Дино для спроса: %d | в цели %d/%d/%d тайлов: %d/%d/%d | спрос %.2f" % [
		int(rain_data.get("eligible_herbivore_count", 0)),
		int(rain_data.get("herbivore_near_distance_tiles", 3)),
		int(rain_data.get("herbivore_medium_distance_tiles", 6)),
		int(rain_data.get("herbivore_far_distance_tiles", 10)),
		int(rain_data.get("best_near_herbivore_count", 0)),
		int(rain_data.get("best_medium_herbivore_count", 0)),
		int(rain_data.get("best_far_herbivore_count", 0)),
		float(rain_data.get("best_herbivore_demand", 0.0))
	])
	lines.append("Оценка: %.1f = база %d × спрос %.2f × близость %.3f (%d т.) | трава %d×%d + Dry %d | веса Dry %d/%d/%d" % [
		float(rain_data.get("best_total_score", 0.0)),
		int(rain_data.get("best_base_score", 0)),
		float(rain_data.get("best_demand_multiplier", 0.5)),
		float(rain_data.get("best_base_proximity_multiplier", 1.0)),
		int(rain_data.get("best_base_distance_tiles", 20)),
		int(rain_data.get("best_predicted_new_grass", 0)),
		int(rain_data.get("new_grass_score", 10)),
		int(rain_data.get("best_dry_ground_score", 0)),
		int(rain_data.get("dry_ground_zero_hit_score", 5)),
		int(rain_data.get("dry_ground_one_hit_score", 7)),
		int(rain_data.get("dry_ground_two_hit_score", 9))
	])
	lines.append("Результат: прогноз +%d | реально +%d | разница %d" % [
		int(rain_data.get("best_predicted_new_grass", 0)),
		int(rain_data.get("actual_new_grass", 0)),
		int(rain_data.get("prediction_gap", 0))
	])
	lines.append("Зона поиска: ±%d тайлов от базы | рамка дождя: %.1f сек" % [
		int(rain_data.get("search_radius_tiles", 0)),
		float(rain_data.get("rain_frame_duration_seconds", 0.0))
	])
	lines.append("Применение: %.3f мс | максимум %.3f мс | запусков %d" % [
		float(rain_data.get("apply_duration_msec", 0.0)),
		float(rain_data.get("max_apply_duration_msec", 0.0)),
		int(rain_data.get("total_apply_count", 0))
	])


func _format_production_phase(phase: String) -> String:
	match phase:
		"herbivores":
			return "добор травоядных (стег/триц = 3:1)"
		"predators":
			return "атака (2 раптора → тирекс → птеро → яйцеед после 10 мин → чередование)"
		"wait_food_pressure":
			return "пропуск хода: голод ниже потолка"
	return "ожидание"


func _format_elapsed_time(total_seconds: float) -> String:
	var seconds := maxi(int(total_seconds), 0)
	var hours := int(seconds / 3600)
	var minutes := int((seconds % 3600) / 60)
	var remaining_seconds := seconds % 60

	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, remaining_seconds]

	return "%02d:%02d" % [minutes, remaining_seconds]
