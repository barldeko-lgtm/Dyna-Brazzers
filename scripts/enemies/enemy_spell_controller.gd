extends Node2D
class_name EnemySpellController

# Single strategic facade for enemy spells. It owns the EnemyAI turn connection,
# spell priority, shared combat reserve, save compatibility and public diagnostics.
# Spell-specific targeting and execution live in dedicated child modules.
const LIGHTNING_SPELL_SCRIPT := preload("res://scripts/enemies/spells/enemy_lightning_spell.gd")
const EARTHQUAKE_SPELL_SCRIPT := preload("res://scripts/enemies/spells/enemy_earthquake_spell.gd")
const RAIN_SPELL_SCRIPT := preload("res://scripts/enemies/spells/enemy_rain_spell.gd")

const INITIALIZATION_RETRY_FRAMES := 12
const COMBAT_RESERVE_SAVE_VERSION := 2

# Spell tuning remains on the facade so existing runtime configuration and the
# documented single ownership point stay compatible after the code split.
@export var rain_energy_cost := 50.0
@export var minimum_rain_target_score := 1
@export var new_grass_score := 10
@export var dry_ground_zero_hit_score := 5
@export var dry_ground_one_hit_score := 7
@export var dry_ground_two_hit_score := 9
@export var rain_expansion_phase_start_seconds := 600.0
@export var expansion_dry_ground_zero_hit_score := 8
@export var expansion_dry_ground_one_hit_score := 11
@export var expansion_dry_ground_two_hit_score := 15
@export var rain_initial_priority_phase_duration_seconds := 180.0
@export var rain_initial_priority_multiplier := 10.0
@export var empty_area_score_multiplier := 0.5
@export var herbivore_demand_multiplier_step := 0.3
@export var maximum_herbivore_score_multiplier := 2.5
@export var herbivore_near_distance_tiles := 3
@export var herbivore_medium_distance_tiles := 6
@export var herbivore_far_distance_tiles := 10
@export_range(0.0, 1.0, 0.05) var herbivore_medium_demand_weight := 0.5
@export_range(0.0, 1.0, 0.05) var herbivore_far_demand_weight := 0.25
@export var rain_search_radius_tiles := 20
@export var base_proximity_reference_distance_tiles := 20
@export var base_proximity_multiplier_step := 0.007
@export var expansion_base_proximity_multiplier_step := 0.014
@export var rain_area_frame_duration_seconds := 4.0
@export var search_area_frame_color := Color(1.0, 0.48, 0.12, 0.82)
@export var rain_area_frame_color := Color(0.20, 0.78, 1.0, 0.95)
@export var search_area_frame_line_width := 8.0
@export var rain_area_frame_line_width := 10.0

# Match time grows only the reserve capacity. Actual reserve energy is diverted
# from real enemy-creature income by EnemyEnergy and never appears from time alone.
@export var combat_reserve_unlock_minutes := 10
@export var combat_reserve_late_rate_after_minutes := 20
@export var combat_reserve_capacity_gain_per_minute := 100.0
@export var combat_reserve_capacity_late_gain_per_minute := 200.0
@export var combat_reserve_maximum := 3000.0
# Combat spells may empty stored reserve energy completely. This floor applies
# only to the capacity after a successful offensive cast.
@export var combat_reserve_minimum_after_cast := 500.0

@export_group("Enemy Lightning")
@export var lightning_energy_cost := 1000.0
@export var lightning_damage_threshold := 50.0
@export var lightning_double_strike_delay_seconds := 2.0
@export var tyrannosaurus_base_radius_tiles := 30.0
@export var tyrannosaurus_raptor_guard_radius_tiles := 20.0
@export var egg_eater_base_radius_tiles := 20.0

@export_group("Enemy Earthquake")
@export var earthquake_energy_cost := 1700.0
@export var minimum_earthquake_player_eggs := 2

var world_grid: Node = null
var nature_effects: Node = null
var enemy_ai: Node = null
var enemy_energy: Node = null
var enemy_base: Node2D = null

var combat_reserve := 0.0
var combat_reserve_capacity := 0.0
var next_combat_reserve_capacity_tick_minute := 0
var last_combat_reserve_income_deposit := 0.0

var lightning_spell: Node = null
var earthquake_spell: Node = null
var rain_spell: Node2D = null


func _ready() -> void:
	add_to_group("enemy_spell_controller")
	_reset_combat_reserve_for_new_session()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_create_spell_modules()
	call_deferred("_initialize_runtime")


func _process(_delta: float) -> void:
	_update_combat_reserve_capacity_from_match_time()


func _exit_tree() -> void:
	_disconnect_enemy_ai()


func _create_spell_modules() -> void:
	lightning_spell = LIGHTNING_SPELL_SCRIPT.new() as Node
	if lightning_spell == null:
		push_error("EnemySpellController: lightning module could not be created.")
	else:
		lightning_spell.name = "EnemyLightningSpell"
		add_child(lightning_spell)
		lightning_spell.call("setup", self)

	earthquake_spell = EARTHQUAKE_SPELL_SCRIPT.new() as Node
	if earthquake_spell == null:
		push_error("EnemySpellController: earthquake module could not be created.")
	else:
		earthquake_spell.name = "EnemyEarthquakeSpell"
		add_child(earthquake_spell)
		earthquake_spell.call("setup", self)

	rain_spell = RAIN_SPELL_SCRIPT.new() as Node2D
	if rain_spell == null:
		push_error("EnemySpellController: rain module could not be created.")
	else:
		rain_spell.name = "EnemyRainSpell"
		add_child(rain_spell)
		rain_spell.call("setup", self)


func _initialize_runtime() -> void:
	for _attempt in range(INITIALIZATION_RETRY_FRAMES):
		refresh_runtime_references()

		if _connect_enemy_ai():
			_update_combat_reserve_capacity_from_match_time()
			if rain_spell != null and rain_spell.has_method("refresh_search_area_bounds"):
				rain_spell.call("refresh_search_area_bounds")
			return

		await get_tree().process_frame

	push_warning("EnemySpellController: enemy AI turn signal was not found.")


func _connect_enemy_ai() -> bool:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		return false
	if not enemy_ai.has_signal("turn_completed"):
		return false

	var turn_callable := Callable(self, "_on_enemy_turn_completed")

	if not enemy_ai.is_connected("turn_completed", turn_callable):
		enemy_ai.connect("turn_completed", turn_callable)

	return true


func _disconnect_enemy_ai() -> void:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		return

	var turn_callable := Callable(self, "_on_enemy_turn_completed")

	if enemy_ai.has_signal("turn_completed") and enemy_ai.is_connected(
		"turn_completed", turn_callable
	):
		enemy_ai.disconnect("turn_completed", turn_callable)


func _on_enemy_turn_completed(snapshot: Dictionary) -> void:
	if (
		lightning_spell != null
		and lightning_spell.has_method("is_sequence_active")
		and bool(lightning_spell.call("is_sequence_active"))
	):
		return

	# One strategic spell action per completed turn. Child modules never subscribe
	# to EnemyAI themselves; this facade preserves the existing strict priority.
	if (
		lightning_spell != null
		and lightning_spell.has_method("try_cast_at_egg_eater")
		and bool(lightning_spell.call("try_cast_at_egg_eater"))
	):
		return

	var adult_herbivore_count := int(snapshot.get("adult_herbivore_count", 0))
	var average_satiety := float(
		snapshot.get("average_adult_herbivore_satiety_percent", -1.0)
	)
	var satiety_threshold := clampf(
		float(snapshot.get("minimum_average_herbivore_satiety_percent", 40.0)),
		0.0,
		100.0
	)
	var herd_needs_rain := (
		adult_herbivore_count > 0
		and average_satiety >= 0.0
		and average_satiety < satiety_threshold
	)

	if (
		herd_needs_rain
		and rain_spell != null
		and rain_spell.has_method("try_cast_for_hungry_herd")
		and bool(rain_spell.call("try_cast_for_hungry_herd"))
	):
		return

	if (
		earthquake_spell != null
		and earthquake_spell.has_method("try_cast")
		and bool(earthquake_spell.call("try_cast"))
	):
		return

	if lightning_spell != null and lightning_spell.has_method("try_cast_at_tyrannosaurus"):
		lightning_spell.call("try_cast_at_tyrannosaurus")


func refresh_runtime_references() -> void:
	if world_grid == null or not is_instance_valid(world_grid):
		var parent_grid := get_parent() as Node

		if parent_grid != null and parent_grid.has_method("is_tile_inside_map"):
			world_grid = parent_grid
		else:
			world_grid = get_tree().get_first_node_in_group("world_grid")

	if nature_effects == null or not is_instance_valid(nature_effects):
		nature_effects = get_tree().get_first_node_in_group("nature_effects_system")

	if enemy_ai == null or not is_instance_valid(enemy_ai):
		enemy_ai = get_tree().get_first_node_in_group("enemy_ai")

	if enemy_energy == null or not is_instance_valid(enemy_energy):
		enemy_energy = get_tree().get_first_node_in_group("enemy_energy")

	if enemy_base == null or not is_instance_valid(enemy_base):
		if world_grid != null and is_instance_valid(world_grid):
			enemy_base = world_grid.get_node_or_null("EnemyBase") as Node2D


func get_enemy_elapsed_simulation_seconds() -> float:
	return _get_enemy_elapsed_simulation_seconds()


func spend_combat_reserve_for_rain(amount: float) -> bool:
	var safe_cost := maxf(amount, 0.0)
	if safe_cost <= 0.0:
		return true
	if not can_spend_combat_reserve(safe_cost):
		return false
	combat_reserve = maxf(combat_reserve - safe_cost, 0.0)
	return true


func refund_combat_reserve_for_rain(amount: float) -> void:
	var safe_amount := maxf(amount, 0.0)
	if safe_amount <= 0.0:
		return
	combat_reserve = minf(
		combat_reserve + safe_amount,
		_get_combat_reserve_capacity()
	)


func _reset_combat_reserve_for_new_session() -> void:
	combat_reserve = 0.0
	combat_reserve_capacity = 0.0
	next_combat_reserve_capacity_tick_minute = _get_first_combat_reserve_capacity_tick_minute()
	last_combat_reserve_income_deposit = 0.0


func _update_combat_reserve_capacity_from_match_time() -> void:
	if enemy_ai == null or not is_instance_valid(enemy_ai):
		refresh_runtime_references()

	_advance_combat_reserve_capacity_to_elapsed(_get_enemy_elapsed_simulation_seconds())


func _advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds: float) -> void:
	var first_tick_minute := _get_first_combat_reserve_capacity_tick_minute()

	if next_combat_reserve_capacity_tick_minute < first_tick_minute:
		next_combat_reserve_capacity_tick_minute = first_tick_minute

	var elapsed_full_minutes := maxi(
		int(floor(maxf(elapsed_simulation_seconds, 0.0) / 60.0)),
		0
	)
	var safe_maximum := _get_combat_reserve_maximum()

	while next_combat_reserve_capacity_tick_minute <= elapsed_full_minutes:
		var gain := _get_combat_reserve_capacity_gain_for_tick(
			next_combat_reserve_capacity_tick_minute
		)
		combat_reserve_capacity = minf(
			combat_reserve_capacity + gain,
			safe_maximum
		)
		next_combat_reserve_capacity_tick_minute += 1

	combat_reserve = minf(combat_reserve, combat_reserve_capacity)


func _get_enemy_elapsed_simulation_seconds() -> float:
	if (
		enemy_ai != null
		and is_instance_valid(enemy_ai)
		and enemy_ai.has_method("get_elapsed_simulation_seconds")
	):
		return maxf(
			float(enemy_ai.call("get_elapsed_simulation_seconds")),
			0.0
		)

	return 0.0


func _get_first_combat_reserve_capacity_tick_minute() -> int:
	return maxi(combat_reserve_unlock_minutes, 0)


func _get_combat_reserve_capacity_gain_for_tick(tick_minute: int) -> float:
	var late_rate_after := maxi(
		combat_reserve_late_rate_after_minutes,
		maxi(combat_reserve_unlock_minutes, 0)
	)

	if tick_minute > late_rate_after:
		return maxf(combat_reserve_capacity_late_gain_per_minute, 0.0)

	return maxf(combat_reserve_capacity_gain_per_minute, 0.0)


func _get_combat_reserve_maximum() -> float:
	return maxf(combat_reserve_maximum, 0.0)


func _get_combat_reserve_capacity() -> float:
	return clampf(
		combat_reserve_capacity,
		0.0,
		_get_combat_reserve_maximum()
	)


func _get_combat_reserve_minimum_after_cast() -> float:
	return clampf(
		combat_reserve_minimum_after_cast,
		0.0,
		_get_combat_reserve_maximum()
	)


func get_save_data() -> Dictionary:
	_update_combat_reserve_capacity_from_match_time()
	return {
		"combat_reserve_save_version": COMBAT_RESERVE_SAVE_VERSION,
		"combat_reserve": get_combat_reserve(),
		"combat_reserve_capacity": get_combat_reserve_capacity(),
		"next_combat_reserve_capacity_tick_minute": next_combat_reserve_capacity_tick_minute
	}


func restore_save_data(saved_data: Dictionary) -> void:
	refresh_runtime_references()
	var elapsed_simulation_seconds := _get_enemy_elapsed_simulation_seconds()
	var saved_version := int(saved_data.get("combat_reserve_save_version", 0))

	_reset_combat_reserve_for_new_session()

	if saved_version >= COMBAT_RESERVE_SAVE_VERSION:
		combat_reserve_capacity = clampf(
			float(saved_data.get("combat_reserve_capacity", 0.0)),
			0.0,
			_get_combat_reserve_maximum()
		)
		var default_next_tick := maxi(
			int(floor(elapsed_simulation_seconds / 60.0)) + 1,
			_get_first_combat_reserve_capacity_tick_minute()
		)
		next_combat_reserve_capacity_tick_minute = maxi(
			int(saved_data.get(
				"next_combat_reserve_capacity_tick_minute",
				default_next_tick
			)),
			_get_first_combat_reserve_capacity_tick_minute()
		)
		_advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds)
		combat_reserve = clampf(
			float(saved_data.get("combat_reserve", 0.0)),
			0.0,
			_get_combat_reserve_capacity()
		)
	else:
		# The previous reserve prototype created energy from elapsed time. Its saved
		# amount is intentionally discarded; only the capacity is rebuilt.
		_advance_combat_reserve_capacity_to_elapsed(elapsed_simulation_seconds)
		combat_reserve = 0.0


func deposit_combat_reserve_income(amount: float) -> float:
	_update_combat_reserve_capacity_from_match_time()
	last_combat_reserve_income_deposit = 0.0
	var safe_amount := maxf(amount, 0.0)
	var available_space := maxf(
		_get_combat_reserve_capacity() - combat_reserve,
		0.0
	)

	if safe_amount <= 0.0 or available_space <= 0.0:
		return 0.0

	last_combat_reserve_income_deposit = minf(safe_amount, available_space)
	combat_reserve += last_combat_reserve_income_deposit
	PerformanceStats.add_counter(
		"enemy_combat_reserve_income",
		roundi(last_combat_reserve_income_deposit)
	)
	return last_combat_reserve_income_deposit


func get_combat_reserve() -> float:
	return clampf(combat_reserve, 0.0, _get_combat_reserve_capacity())


func get_combat_reserve_capacity() -> float:
	_update_combat_reserve_capacity_from_match_time()
	return _get_combat_reserve_capacity()


func get_combat_reserve_maximum() -> float:
	return _get_combat_reserve_maximum()


func get_combat_reserve_minimum_after_cast() -> float:
	return _get_combat_reserve_minimum_after_cast()


func get_next_combat_reserve_capacity_tick_minute() -> int:
	return maxi(
		next_combat_reserve_capacity_tick_minute,
		_get_first_combat_reserve_capacity_tick_minute()
	)


func get_next_combat_reserve_capacity_gain() -> float:
	return _get_combat_reserve_capacity_gain_for_tick(
		get_next_combat_reserve_capacity_tick_minute()
	)


func get_seconds_until_next_combat_reserve_capacity_tick() -> float:
	var next_tick_seconds := float(
		get_next_combat_reserve_capacity_tick_minute()
	) * 60.0
	return maxf(next_tick_seconds - _get_enemy_elapsed_simulation_seconds(), 0.0)


func is_combat_reserve_unlocked() -> bool:
	return _get_enemy_elapsed_simulation_seconds() >= (
		float(maxi(combat_reserve_unlock_minutes, 0)) * 60.0
	)


func can_spend_combat_reserve(amount: float) -> bool:
	_update_combat_reserve_capacity_from_match_time()
	var safe_cost := maxf(amount, 0.0)
	return combat_reserve + 0.001 >= safe_cost


# Call this only after a combat spell has applied successfully. Stored reserve
# energy pays the exact cost and may reach zero. The capacity loses the same
# amount but keeps its configured floor, then resumes normal minute growth.


func spend_combat_reserve_after_success(amount: float) -> bool:
	var safe_cost := maxf(amount, 0.0)

	if safe_cost <= 0.0 or not can_spend_combat_reserve(safe_cost):
		return false

	combat_reserve = maxf(combat_reserve - safe_cost, 0.0)
	combat_reserve_capacity = clampf(
		maxf(
			combat_reserve_capacity - safe_cost,
			_get_combat_reserve_minimum_after_cast()
		),
		0.0,
		_get_combat_reserve_maximum()
	)
	combat_reserve = minf(combat_reserve, combat_reserve_capacity)
	PerformanceStats.add_counter("enemy_combat_reserve_spent", roundi(safe_cost))
	PerformanceStats.add_counter("enemy_combat_reserve_capacity_spent", roundi(safe_cost))
	PerformanceStats.add_counter("enemy_combat_spell_casts")
	return true


func _get_enemy_energy_debug_value(method_name: StringName) -> float:
	if (
		enemy_energy != null
		and is_instance_valid(enemy_energy)
		and enemy_energy.has_method(method_name)
	):
		return maxf(float(enemy_energy.call(method_name)), 0.0)
	return 0.0


func _merge_debug_data(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source.keys():
		target[key] = source[key]


func get_rain_debug_data() -> Dictionary:
	_update_combat_reserve_capacity_from_match_time()
	var result: Dictionary = {}

	if rain_spell != null and rain_spell.has_method("get_debug_data"):
		var rain_variant: Variant = rain_spell.call("get_debug_data")
		if rain_variant is Dictionary:
			_merge_debug_data(result, rain_variant as Dictionary)

	if lightning_spell != null and lightning_spell.has_method("get_debug_data"):
		var lightning_variant: Variant = lightning_spell.call("get_debug_data")
		if lightning_variant is Dictionary:
			_merge_debug_data(result, lightning_variant as Dictionary)

	if earthquake_spell != null and earthquake_spell.has_method("get_debug_data"):
		var earthquake_variant: Variant = earthquake_spell.call("get_debug_data")
		if earthquake_variant is Dictionary:
			_merge_debug_data(result, earthquake_variant as Dictionary)

	result["combat_reserve"] = get_combat_reserve()
	result["combat_reserve_capacity"] = get_combat_reserve_capacity()
	result["combat_reserve_maximum"] = get_combat_reserve_maximum()
	result["combat_reserve_minimum_after_cast"] = get_combat_reserve_minimum_after_cast()
	result["combat_reserve_unlocked"] = is_combat_reserve_unlocked()
	result["combat_reserve_next_capacity_tick_minute"] = get_next_combat_reserve_capacity_tick_minute()
	result["combat_reserve_next_capacity_gain"] = get_next_combat_reserve_capacity_gain()
	result["combat_reserve_seconds_until_next_capacity_tick"] = get_seconds_until_next_combat_reserve_capacity_tick()
	result["combat_reserve_last_income_deposit"] = last_combat_reserve_income_deposit
	result["enemy_income_per_second"] = _get_enemy_energy_debug_value("get_income_per_second")
	result["combat_reserve_income_threshold_per_second"] = _get_enemy_energy_debug_value(
		"get_combat_reserve_income_threshold_per_second"
	)
	result["combat_reserve_income_share"] = _get_enemy_energy_debug_value(
		"get_combat_reserve_income_share"
	)
	result["enemy_last_income_to_ordinary_energy"] = _get_enemy_energy_debug_value(
		"get_last_income_to_ordinary_energy"
	)
	return result


func get_last_action_text() -> String:
	if rain_spell != null and rain_spell.has_method("get_last_action_text"):
		return str(rain_spell.call("get_last_action_text"))
	return "ожидание первого решения по спеллам"


func get_last_rain_target_tile() -> Vector2i:
	if rain_spell != null and rain_spell.has_method("get_last_rain_target_tile"):
		var value: Variant = rain_spell.call("get_last_rain_target_tile")
		if value is Vector2i:
			return value
	return Vector2i(2147483647, 2147483647)


func get_last_grass_entries_scanned() -> int:
	return _get_rain_int("get_last_grass_entries_scanned")


func get_last_mature_grass_count() -> int:
	return _get_rain_int("get_last_mature_grass_count")


func get_last_spread_ready_grass_count() -> int:
	return _get_rain_int("get_last_spread_ready_grass_count")


func get_last_productive_grass_count() -> int:
	return _get_rain_int("get_last_productive_grass_count")


func get_last_unique_spawn_target_count() -> int:
	return _get_rain_int("get_last_unique_spawn_target_count")


func get_last_candidate_center_count() -> int:
	return _get_rain_int("get_last_candidate_center_count")


func get_last_best_predicted_new_grass() -> int:
	return _get_rain_int("get_last_best_predicted_new_grass")


func get_last_search_duration_msec() -> float:
	return _get_rain_float("get_last_search_duration_msec")


func get_max_search_duration_msec() -> float:
	return _get_rain_float("get_max_search_duration_msec")


func get_total_search_count() -> int:
	return _get_rain_int("get_total_search_count")


func get_rain_energy_cost() -> float:
	return maxf(rain_energy_cost, 0.0)


func _get_rain_int(method_name: StringName) -> int:
	if rain_spell != null and rain_spell.has_method(method_name):
		return int(rain_spell.call(method_name))
	return 0


func _get_rain_float(method_name: StringName) -> float:
	if rain_spell != null and rain_spell.has_method(method_name):
		return float(rain_spell.call(method_name))
	return 0.0
